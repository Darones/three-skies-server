extends "res://scripts/platform/platform_adapter.gd"

## VK launch-param authentication. The bridge/SDK lives only in this adapter;
## the core receives a server profile and never talks to VK directly.

var _host: Node
var _launch_params: Dictionary = {}
var _profile: Dictionary = {}
var _avatar := ""
var _session_token := ""
var _authenticated := false
var _auth_in_progress := false
var _last_error := ""
var _js_launch_cb = null
var _js_user_cb = null
var _launch_ready := false
var _launch_result: Dictionary = {}
var _user_ready := false
var _user_result: Dictionary = {}


func _init() -> void:
	platform_id = "vk"
	display_name = "VK"


func initialize(host: Node) -> void:
	_host = host


func authenticate() -> bool:
	if _authenticated:
		return true
	if _auth_in_progress:
		return false
	_auth_in_progress = true
	_last_error = ""
	var launch: Dictionary = await _get_launch_params()
	if not bool(launch.get("ok", false)):
		_fail(String(launch.get("error", "vk_launch_params")))
		return false
	_launch_params = launch.get("params", {})
	var auth: Dictionary = await NetworkClient.auth_vk(_launch_params)
	if not _apply_auth(auth):
		_auth_in_progress = false
		return false
	# The display name is cosmetic; identity already comes from the signed
	# vk_user_id. Fetch it after the server has verified the launch params.
	var user: Dictionary = await _get_user_info()
	if bool(user.get("ok", false)):
		var data: Dictionary = user.get("data", {})
		var display_name_text := _display_name(data)
		_avatar = String(data.get("photo_200", data.get("photo_100", "")))
		if not display_name_text.is_empty():
			var updated: Dictionary = await NetworkClient.auth_vk(_launch_params, display_name_text, _avatar)
			if bool(updated.get("success", false)):
				_apply_auth(updated)
	_authenticated = true
	_auth_in_progress = false
	return true


func is_ready() -> bool:
	return _authenticated


func is_authenticated() -> bool:
	return _authenticated


func get_auth_error() -> String:
	return _last_error


func get_user() -> Dictionary:
	return {
		"id": String(_launch_params.get("vk_user_id", "")),
		"name": String(_profile.get("nickname", "")),
		"avatar": _avatar,
		"platform": platform_id,
	}


func get_launch_token() -> String:
	return JSON.stringify(_launch_params)


func get_app_link() -> String:
	return "https://vk.com/app54906713"


func get_currency() -> String:
	return "votes"


func _fail(error: String) -> void:
	_last_error = _map_error(error)
	_auth_in_progress = false


func _apply_auth(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		_last_error = _map_error(String(result.get("error", "")))
		return false
	var profile: Dictionary = result.get("profile", {})
	var player_id := int(profile.get("player_id", 0))
	var token := String(profile.get("session_token", ""))
	if player_id <= 0 or token.is_empty():
		_last_error = "invalid_server_profile"
		return false
	_profile = profile
	_session_token = token
	_avatar = String(profile.get("avatar", _avatar))
	MetaProgression.player_id = player_id
	MetaProgression.session_token = token
	MetaProgression.account_level = maxi(1, int(profile.get("level", 1)))
	NetworkClient.session_token = token
	var wings: Array = profile.get("unlocked_wings", [])
	var weapons: Array = profile.get("unlocked_weapons", [])
	var nickname := String(profile.get("nickname", ""))
	var nickname_custom := bool(profile.get("nickname_custom", false))
	MetaProgression.apply_server_profile(
		player_id,
		int(profile.get("sky_shards", 0)),
		wings,
		weapons,
		nickname,
		nickname_custom,
		int(profile.get("matches_played", 0)),
		bool(profile.get("novice", false))
	)
	MetaProgression.persist_local()
	return true


func _map_error(error: String) -> String:
	match error:
		"invalid_vk_auth", "invalid_server_profile":
			return "vk_invalid_auth"
		"rate_limited":
			return "vk_rate_limited"
		"vk_auth_not_configured":
			return "vk_server_not_configured"
		"timeout", "vk_timeout":
			return "vk_network_timeout"
		"vk_missing_params":
			return "vk_missing_params"
		"vk_bridge_unavailable":
			return "vk_bridge_unavailable"
		_:
			return "vk_auth_failed"


func _get_launch_params() -> Dictionary:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return {"ok": false, "error": "vk_bridge_unavailable"}
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var window = bridge.call("get_interface", "window")
	if window == null:
		return {"ok": false, "error": "vk_bridge_unavailable"}
	_js_launch_cb = bridge.call("create_callback", Callable(self, "_on_launch_params_js"))
	if _js_launch_cb == null:
		return {"ok": false, "error": "vk_bridge_unavailable"}
	window.__tsVKLaunchCB = _js_launch_cb
	_launch_ready = false
	_launch_result = {}
	var script := """
	(function(){
		var settled = false;
		function done(payload) {
			if (settled) return;
			settled = true;
			try { window.__tsVKLaunchCB(JSON.stringify(payload)); } catch (e) {}
		}
		function urlParams() {
			var out = {};
			try {
				var query = new URLSearchParams(window.location.search);
				query.forEach(function(value, key) {
					if (key === 'sign' || key.indexOf('vk_') === 0) out[key] = value;
				});
			} catch (e) {}
			return out;
		}
		// A VK webview normally answers in well under a second. If the bridge
		// hangs (opened outside VK, blocked script), fall back to the launch
		// params VK put in the URL instead of waiting forever.
		setTimeout(function() {
			done({ok: true, params: urlParams(), source: 'url', bridge_timeout: true});
		}, 5000);
		if (typeof window.vkBridge === 'undefined' || !window.vkBridge || !window.vkBridge.send) {
			done({ok: true, params: urlParams(), source: 'url'});
			return;
		}
		window.vkBridge.send('VKWebAppGetLaunchParams').then(function(data) {
			done({ok: true, params: data || {}, source: 'bridge'});
		}).catch(function(err) {
			done({ok: true, params: urlParams(), source: 'url', bridge_error: String(err)});
		});
	})();
	"""
	bridge.call("eval", script, true)
	var waited := 0.0
	while not _launch_ready and waited < 8.0:
		await _host.get_tree().create_timer(0.05).timeout
		waited += 0.05
	if not _launch_ready:
		return {"ok": false, "error": "vk_timeout"}
	if not bool(_launch_result.get("ok", false)):
		return {"ok": false, "error": String(_launch_result.get("error", "vk_bridge_error"))}
	var params: Dictionary = _launch_result.get("params", {})
	for required in ["vk_user_id", "vk_app_id", "vk_ts", "sign"]:
		if String(params.get(required, "")).strip_edges().is_empty():
			return {"ok": false, "error": "vk_missing_params"}
	return {"ok": true, "params": params}


func _on_launch_params_js(args: Array) -> void:
	_launch_ready = true
	if args.is_empty():
		_launch_result = {"ok": false, "error": "vk_bridge_error"}
		return
	var parsed: Variant = JSON.parse_string(String(args[0]))
	if parsed is Dictionary:
		_launch_result = parsed
	else:
		_launch_result = {"ok": false, "error": "vk_bridge_error"}


func _get_user_info() -> Dictionary:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return {"ok": false}
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var window = bridge.call("get_interface", "window")
	if window == null:
		return {"ok": false}
	_js_user_cb = bridge.call("create_callback", Callable(self, "_on_user_info_js"))
	if _js_user_cb == null:
		return {"ok": false}
	window.__tsVKUserCB = _js_user_cb
	_user_ready = false
	_user_result = {}
	var script := """
	(function(){
		function done(payload) {
			try { window.__tsVKUserCB(JSON.stringify(payload)); } catch (e) {}
		}
		if (typeof window.vkBridge === 'undefined' || !window.vkBridge || !window.vkBridge.send) {
			done({ok: false, error: 'bridge_unavailable'});
			return;
		}
		window.vkBridge.send('VKWebAppGetUserInfo').then(function(data) {
			done({ok: true, data: data || {}});
		}).catch(function(err) {
			done({ok: false, error: String(err)});
		});
	})();
	"""
	bridge.call("eval", script, true)
	var waited := 0.0
	while not _user_ready and waited < 6.0:
		await _host.get_tree().create_timer(0.05).timeout
		waited += 0.05
	if not _user_ready:
		return {"ok": false, "error": "timeout"}
	return _user_result


func _on_user_info_js(args: Array) -> void:
	_user_ready = true
	if args.is_empty():
		_user_result = {"ok": false, "error": "vk_bridge_error"}
		return
	var parsed: Variant = JSON.parse_string(String(args[0]))
	if parsed is Dictionary:
		_user_result = parsed
	else:
		_user_result = {"ok": false, "error": "vk_bridge_error"}


func _display_name(data: Dictionary) -> String:
	var first := String(data.get("first_name", "")).strip_edges()
	var last := String(data.get("last_name", "")).strip_edges()
	var name := (first + " " + last).strip_edges()
	if name.is_empty():
		name = String(data.get("screen_name", "")).strip_edges()
	return name
