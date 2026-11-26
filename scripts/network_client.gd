extends Node

# REST-клиент профиля, покупок и наград. Игровой мультиплеер идёт только
# через NetworkManager (WebSocket); старый протокол матчмейкинга удалён.

signal registration_completed(success: bool, player_id: int)
signal profile_loaded(success: bool, player_id: int, sky_shards: int, unlocked_wings: Array, unlocked_weapons: Array, nickname: String, nickname_custom: bool, matches_played: int, novice: bool)
signal purchase_completed(success: bool, purchase_type: String, item_id: int, new_shards: int)
signal match_reward_completed(success: bool, amount: int, new_shards: int, profile: Dictionary)
# Same event as match_reward_completed plus the exact request payload and the
# HTTP status, so MetaProgression can keep a failed reward and retry it once on
# the next profile/lobby without paying twice (the server is idempotent).
signal match_reward_settled(success: bool, payload: Dictionary, response_code: int, error: String, profile: Dictionary)
signal compensation_completed(success: bool, new_shards: int, error: String)
signal rename_completed(success: bool, nickname: String, error: String, charged: bool, cost: int, new_shards: int)
signal report_completed(success: bool, error: String)
signal session_ready(token: String)
signal vk_auth_completed(success: bool, profile: Dictionary, error: String)
signal ok_auth_completed(success: bool, profile: Dictionary, error: String)
signal progress_loaded(success: bool, progress: Dictionary)
signal progress_saved(success: bool, progress: Dictionary)
signal interstitial_recorded(success: bool, last_interstitial_at: int)
signal account_deleted(success: bool, error: String)
# Moderation state from the server. No UI is built here: screens subscribe.
signal account_ban_updated(banned: bool, reason: String)
signal warnings_updated(count: int, reason: String, at: int)

const API_BASE_URL := "https://three-skies-server.relaxdev.ru"

var api_base_url := API_BASE_URL
var session_token := ""
var last_purchase_error := ""
var account_banned := false
var account_ban_reason := ""
var warning_count := 0
var last_warning_reason := ""
var last_warning_at := 0
var http_request: HTTPRequest
var http_request_busy := false
var current_http_request: Dictionary = {}
var http_request_queue: Array[Dictionary] = []
var _vk_auth_waiting := false
var _vk_auth_result: Dictionary = {}
var _ok_auth_waiting := false
var _ok_auth_result: Dictionary = {}


func _ready() -> void:
	var env_url := OS.get_environment("THREE_SKIES_API_BASE_URL").strip_edges()
	if not env_url.is_empty():
		api_base_url = env_url
	else:
		var setting_url := String(ProjectSettings.get_setting("network/api_base_url", API_BASE_URL)).strip_edges()
		api_base_url = setting_url if not setting_url.is_empty() else API_BASE_URL
	api_base_url = api_base_url.trim_suffix("/")
	print("[NET] REST URL: ", api_base_url)
	http_request = HTTPRequest.new()
	http_request.name = "NetworkHTTPRequest"
	http_request.timeout = 10.0
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)


func register_player(nickname: String) -> void:
	_send_post("/register", {"nickname": nickname}, "register")


func buy_wing_server(player_id: int, wing_id: int, cost: int) -> void:
	_send_post("/buy_wing", {
		"player_id": player_id,
		"wing_id": wing_id,
		"cost": cost,
	}, "purchase", "wing", wing_id)


func buy_weapon_server(player_id: int, weapon_id: int, cost: int) -> void:
	_send_post("/buy_weapon", {
		"player_id": player_id,
		"weapon_id": weapon_id,
		"cost": cost,
	}, "purchase", "weapon", weapon_id)


func grant_match_reward(player_id: int, amount: int, room_id: int, xp: int, character: String, bonus := false) -> void:
	var payload := {
		"player_id": player_id,
		"room_id": room_id,
		"amount": amount,
		"xp": maxi(0, xp),
		"character": character,
	}
	if bonus:
		payload["bonus"] = true
	if player_id <= 0 or amount <= 0 or room_id <= 0:
		match_reward_completed.emit(false, amount, 0, {})
		match_reward_settled.emit(false, payload, 0, "invalid_reward", {})
		return
	_send_post("/match_reward", payload, "match_reward")


# Deprecated: the server answers 410 compensation_disabled (it used to pay
# shards without proof of an interrupted match). No current screen calls this;
# the route is kept only so an old build gets a clean machine-readable answer.
func claim_compensation(player_id: int) -> void:
	if player_id <= 0:
		compensation_completed.emit(false, 0, "invalid")
		return
	_send_post("/compensation", {
		"player_id": player_id,
		"reason": "match_aborted",
	}, "compensation")


func rename_player(player_id: int, nickname: String) -> void:
	var clean_nickname := nickname.strip_edges()
	if player_id <= 0 or clean_nickname.is_empty():
		rename_completed.emit(false, clean_nickname, "Некорректный ник", false, 0, 0)
		return
	_send_post("/rename", {
		"player_id": player_id,
		"nickname": clean_nickname,
	}, "rename")


func report_player(player_id: int, nickname: String, reason: String) -> void:
	var clean_nickname := nickname.strip_edges()
	var clean_reason := reason.strip_edges()
	if player_id <= 0 or clean_nickname.is_empty() or clean_reason.is_empty():
		report_completed.emit(false, "Некорректная жалоба")
		return
	_send_post("/report", {
		"player_id": player_id,
		"nickname": clean_nickname,
		"reason": clean_reason,
	}, "report")


func load_player_profile(player_id: int) -> void:
	if player_id <= 0:
		profile_loaded.emit(false, player_id, 0, [], [], "", false, 0, false)
		return
	http_request_queue.append({
		"path": "/profile?player_id=%d" % player_id,
		"payload": {},
		"method": HTTPClient.METHOD_GET,
		"request_type": "profile",
		"purchase_type": "",
		"item_id": 0,
		"player_id": player_id,
	})
	_start_next_http_request()


func auth_vk(params: Dictionary, display_name := "", avatar := "") -> Dictionary:
	if _vk_auth_waiting:
		return {"success": false, "profile": {}, "error": "auth_in_progress"}
	var payload := params.duplicate(true)
	if not display_name.strip_edges().is_empty():
		payload["name"] = display_name.strip_edges()
	if not avatar.is_empty():
		payload["avatar"] = avatar
	_vk_auth_waiting = true
	_vk_auth_result = {}
	_send_post("/auth/vk", payload, "vk_auth")
	var waited := 0.0
	while _vk_auth_waiting and waited < 15.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	if _vk_auth_waiting:
		_vk_auth_waiting = false
		return {"success": false, "profile": {}, "error": "timeout"}
	return _vk_auth_result


func auth_ok(local_access_token: String) -> Dictionary:
	if _ok_auth_waiting:
		return {"success": false, "profile": {}, "error": "auth_in_progress"}
	_ok_auth_waiting = true
	_ok_auth_result = {}
	_send_post("/auth/ok", {"local_access_token": local_access_token}, "ok_auth")
	var waited := 0.0
	while _ok_auth_waiting and waited < 15.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	if _ok_auth_waiting:
		_ok_auth_waiting = false
		return {"success": false, "profile": {}, "error": "timeout"}
	return _ok_auth_result


func auth_ok_identity(ok_user_id: String, name: String, avatar: String) -> Dictionary:
	if _ok_auth_waiting:
		return {"success": false, "profile": {}, "error": "auth_in_progress"}
	_ok_auth_waiting = true
	_ok_auth_result = {}
	_send_post("/auth/ok", {
		"ok_user_id": ok_user_id,
		"name": name,
		"avatar": avatar,
	}, "ok_auth")
	var waited := 0.0
	while _ok_auth_waiting and waited < 15.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	if _ok_auth_waiting:
		_ok_auth_waiting = false
		return {"success": false, "profile": {}, "error": "timeout"}
	return _ok_auth_result


func save_progress(player_id: int, levels: Dictionary, xps: Dictionary, tutorial_completed: bool, tutorial_skipped: bool, tutorial_battles_used: int) -> void:
	if player_id <= 0:
		progress_saved.emit(false, {})
		return
	_send_post("/progress", {
		"player_id": player_id,
		"char_levels": levels,
		"char_xps": xps,
		"tutorial_completed": tutorial_completed,
		"tutorial_skipped": tutorial_skipped,
		"tutorial_battles_used": tutorial_battles_used,
	}, "progress")


func _progress_from_profile(data: Dictionary) -> Dictionary:
	var levels: Variant = data.get("char_levels", {})
	var xps: Variant = data.get("char_xps", {})
	return {
		"progress_initialized": bool(data.get("progress_initialized", false)),
		"char_levels": levels if levels is Dictionary else {},
		"char_xps": xps if xps is Dictionary else {},
		"tutorial_completed": bool(data.get("tutorial_completed", false)),
		"tutorial_skipped": bool(data.get("tutorial_skipped", false)),
		"tutorial_battles_used": maxi(0, int(data.get("tutorial_battles_used", 0))),
		"last_interstitial_at": maxi(0, int(data.get("last_interstitial_at", 0))),
	}


# Reads the moderation fields the server puts into /profile. The ban reason
# and warning text are stored here only; UI belongs to the screens.
func _apply_moderation_state(data: Dictionary) -> void:
	var banned := bool(data.get("banned", false)) or String(data.get("error", "")) == "account_banned"
	var reason := String(data.get("ban_reason", ""))
	if banned != account_banned or reason != account_ban_reason:
		account_banned = banned
		account_ban_reason = reason if banned else ""
		print("[NET] account ban state: ", account_banned, " reason=", account_ban_reason)
		account_ban_updated.emit(account_banned, account_ban_reason)
	if data.has("warning_count"):
		warning_count = maxi(0, int(data.get("warning_count", 0)))
		last_warning_reason = String(data.get("last_warning_reason", ""))
		last_warning_at = maxi(0, int(data.get("last_warning_at", 0)))
		warnings_updated.emit(warning_count, last_warning_reason, last_warning_at)


func _send_post(path: String, payload: Dictionary, request_type: String, purchase_type := "", item_id := 0) -> void:
	http_request_queue.append({
		"path": path,
		"payload": payload,
		"method": HTTPClient.METHOD_POST,
		"request_type": request_type,
		"purchase_type": purchase_type,
		"item_id": item_id,
		"player_id": int(payload.get("player_id", 0)),
	})
	_start_next_http_request()


func record_interstitial_shown(player_id: int) -> void:
	if player_id <= 0:
		interstitial_recorded.emit(false, 0)
		return
	_send_post("/ad_interstitial", {"player_id": player_id}, "interstitial")


func delete_account(player_id: int) -> void:
	if player_id <= 0:
		account_deleted.emit(false, "no_player")
		return
	_send_post("/account/delete", {"player_id": player_id}, "delete_account")


func _start_next_http_request() -> void:
	if http_request_busy or http_request_queue.is_empty():
		return
	current_http_request = http_request_queue.pop_front()
	http_request_busy = true
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not session_token.is_empty():
		headers.append("X-Session-Token: " + session_token)
	elif String(current_http_request["path"]).begins_with("/profile"):
		headers.append("X-Claim-Session: 1")
	var request_method := int(current_http_request["method"])
	var request_body := "" if request_method == HTTPClient.METHOD_GET else JSON.stringify(current_http_request["payload"])
	var error := http_request.request(api_base_url + String(current_http_request["path"]), headers, request_method, request_body)
	if error != OK:
		http_request_busy = false
		_emit_http_failure(current_http_request)
		current_http_request.clear()
		_start_next_http_request()


func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var request := current_http_request
	http_request_busy = false
	current_http_request = {}
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if not response is Dictionary or not bool(response.get("success", false)):
		success = false
	if request["request_type"] == "register":
		var player_id := int(response.get("player_id", 0)) if response is Dictionary else 0
		if success and response is Dictionary:
			var token := String(response.get("token", ""))
			if not token.is_empty():
				session_token = token
				session_ready.emit(token)
		registration_completed.emit(success and player_id > 0, player_id if success else 0)
	elif request["request_type"] == "profile":
		var player_id := int(request["player_id"])
		_apply_moderation_state(response if response is Dictionary else {})
		if success and response is Dictionary:
			var profile_token := String(response.get("session_token", ""))
			if not profile_token.is_empty() and profile_token != session_token:
				session_token = profile_token
				session_ready.emit(profile_token)
		var sky_shards := int(response.get("sky_shards", 0)) if response is Dictionary else 0
		var wings_value: Variant = response.get("unlocked_wings", []) if response is Dictionary else []
		var weapons_value: Variant = response.get("unlocked_weapons", []) if response is Dictionary else []
		var unlocked_wings: Array = wings_value if wings_value is Array else []
		var unlocked_weapons: Array = weapons_value if weapons_value is Array else []
		var nickname := String(response.get("nickname", "")) if response is Dictionary else ""
		var nickname_custom := bool(response.get("nickname_custom", false)) if response is Dictionary else false
		var matches_played := int(response.get("matches_played", 0)) if response is Dictionary else 0
		var novice := bool(response.get("novice", false)) if response is Dictionary else false
		profile_loaded.emit(
			success,
			player_id,
			sky_shards if success else 0,
			unlocked_wings if success else [],
			unlocked_weapons if success else [],
			nickname if success else "",
			nickname_custom if success else false,
			matches_played if success else 0,
			novice if success else false
		)
		progress_loaded.emit(success, _progress_from_profile(response if success and response is Dictionary else {}))
	elif request["request_type"] == "progress":
		var saved := _progress_from_profile(response if success and response is Dictionary else {})
		progress_saved.emit(success, saved if success else {})
	elif request["request_type"] == "interstitial":
		var shown_at := int(response.get("last_interstitial_at", 0)) if response is Dictionary else 0
		interstitial_recorded.emit(success, shown_at if success else 0)
	elif request["request_type"] == "vk_auth":
		var profile: Dictionary = response if response is Dictionary else {}
		var error_text := String(profile.get("error", "")) if response is Dictionary else "Нет связи с сервером"
		_vk_auth_result = {"success": success, "profile": profile, "error": error_text}
		_vk_auth_waiting = false
		vk_auth_completed.emit(success, profile, error_text)
	elif request["request_type"] == "ok_auth":
		var profile: Dictionary = response if response is Dictionary else {}
		var error_text := String(profile.get("error", "")) if response is Dictionary else "Нет связи с сервером"
		_ok_auth_result = {"success": success, "profile": profile, "error": error_text}
		_ok_auth_waiting = false
		ok_auth_completed.emit(success, profile, error_text)
	elif request["request_type"] == "purchase":
		var new_shards := int(response.get("new_shards", 0)) if response is Dictionary else 0
		last_purchase_error = ""
		if not success:
			last_purchase_error = String(response.get("error", "")) if response is Dictionary else "Нет связи с сервером"
		purchase_completed.emit(success, String(request["purchase_type"]), int(request["item_id"]), new_shards if success else 0)
	elif request["request_type"] == "match_reward":
		var awarded := int(request["payload"].get("amount", 0))
		var new_shards := int(response.get("new_shards", 0)) if response is Dictionary else 0
		var error_text := String(response.get("error", "")) if response is Dictionary else "Нет связи с сервером"
		var reward_profile: Dictionary = {}
		if success and response is Dictionary:
			reward_profile = {
				"char_levels": response.get("char_levels", {}),
				"char_xps": response.get("char_xps", {}),
				"leveled_up": bool(response.get("leveled_up", false)),
				"level_up_shards": int(response.get("level_up_shards", 0)),
				"bonus": bool(response.get("bonus", false)),
				"character": String(request["payload"].get("character", "")),
			}
		match_reward_completed.emit(success, awarded, new_shards if success else 0, reward_profile)
		match_reward_settled.emit(success, request["payload"].duplicate(true), response_code, "" if success else error_text, reward_profile)
	elif request["request_type"] == "compensation":
		var error_text := String(response.get("error", "")) if response is Dictionary else "Нет связи с сервером"
		var new_shards := int(response.get("new_shards", 0)) if response is Dictionary else 0
		compensation_completed.emit(success, new_shards if success else 0, "" if success else error_text)
	elif request["request_type"] == "rename":
		var nickname := String(request["payload"].get("nickname", ""))
		var error_text := String(response.get("error", "")) if response is Dictionary else "Нет связи с сервером"
		var charged := bool(response.get("charged", false)) if response is Dictionary else false
		var cost := int(response.get("cost", 0)) if response is Dictionary else 0
		var new_shards := int(response.get("new_shards", 0)) if response is Dictionary else 0
		var saved_nickname := String(response.get("nickname", nickname)) if response is Dictionary else nickname
		rename_completed.emit(success, saved_nickname if success else nickname, "" if success else error_text, charged if success else false, cost if success else 0, new_shards if success else 0)
	elif request["request_type"] == "report":
		var error_text := String(response.get("error", "")) if response is Dictionary else "Нет связи с сервером"
		report_completed.emit(success, "" if success else error_text)
	elif request["request_type"] == "delete_account":
		var error_text := String(response.get("error", "")) if response is Dictionary else "Нет связи с сервером"
		account_deleted.emit(success, "" if success else error_text)
	_start_next_http_request()


func _emit_http_failure(request: Dictionary) -> void:
	if request["request_type"] == "register":
		registration_completed.emit(false, 0)
	elif request["request_type"] == "profile":
		profile_loaded.emit(false, int(request["player_id"]), 0, [], [], "", false, 0, false)
		progress_loaded.emit(false, {})
	elif request["request_type"] == "progress":
		progress_saved.emit(false, {})
	elif request["request_type"] == "interstitial":
		interstitial_recorded.emit(false, 0)
	elif request["request_type"] == "vk_auth":
		_vk_auth_result = {"success": false, "profile": {}, "error": "Нет связи с сервером"}
		_vk_auth_waiting = false
		vk_auth_completed.emit(false, {}, "Нет связи с сервером")
	elif request["request_type"] == "ok_auth":
		_ok_auth_result = {"success": false, "profile": {}, "error": "Нет связи с сервером"}
		_ok_auth_waiting = false
		ok_auth_completed.emit(false, {}, "Нет связи с сервером")
	elif request["request_type"] == "purchase":
		last_purchase_error = "Нет связи с сервером"
		purchase_completed.emit(false, String(request["purchase_type"]), int(request["item_id"]), 0)
	elif request["request_type"] == "match_reward":
		match_reward_completed.emit(false, int(request["payload"].get("amount", 0)), 0, {})
		match_reward_settled.emit(false, request["payload"].duplicate(true), 0, "Нет связи с сервером", {})
	elif request["request_type"] == "compensation":
		compensation_completed.emit(false, 0, "Нет связи с сервером")
	elif request["request_type"] == "rename":
		rename_completed.emit(false, String(request["payload"].get("nickname", "")), "Нет связи с сервером", false, 0, 0)
	elif request["request_type"] == "report":
		report_completed.emit(false, "Нет связи с сервером")
	elif request["request_type"] == "delete_account":
		account_deleted.emit(false, "Нет связи с сервером")
