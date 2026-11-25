extends "res://scripts/platform/vk_adapter.gd"

## Odnoklassniki adapter. OK uses the same VK Bridge shell. Identity comes from
## VKWebAppGetUserInfo(use_local: true): it works in OK without permissions and
## returns the OK UID, so no OK API token or application key is required.

var _ok_user_id := ""


func _init() -> void:
	platform_id = "ok"
	display_name = "OK"


func authenticate() -> bool:
	if _authenticated:
		return true
	if _auth_in_progress:
		return false
	_auth_in_progress = true
	_last_error = ""
	var user_result := await _call_ad_bridge("VKWebAppGetUserInfo", {"use_local": true})
	if not bool(user_result.get("ok", false)):
		var bridge_error := String(user_result.get("error", ""))
		_last_error = "ok_bridge_unavailable" if bridge_error == "bridge_unavailable" else "ok_auth_denied"
		_auth_in_progress = false
		return false
	var data: Variant = user_result.get("data", {})
	if not data is Dictionary:
		_last_error = "ok_auth_denied"
		_auth_in_progress = false
		return false
	var payload: Dictionary = data
	# OK wraps the bridge result as {type: "...", data: {...}} while VK
	# returns the user object directly. Accept both shapes.
	var nested: Variant = payload.get("data")
	if nested is Dictionary:
		payload = nested
	_ok_user_id = String(payload.get("id", "")).strip_edges()
	if _ok_user_id.is_empty():
		# The launcher URL always carries the OK uid; use it if the bridge
		# payload shape changes again.
		_ok_user_id = _ok_user_id_from_url()
	if _ok_user_id.is_empty():
		_last_error = "ok_auth_denied"
		_auth_in_progress = false
		return false
	var display_name := _display_name(payload)
	if display_name.is_empty():
		display_name = String(payload.get("name", ""))
	var avatar := String(payload.get("photo_200", payload.get("photo_100", "")))
	var auth: Dictionary = await NetworkClient.auth_ok_identity(_ok_user_id, display_name, avatar)
	if not _apply_auth(auth):
		_auth_in_progress = false
		return false
	_authenticated = true
	_auth_in_progress = false
	_refresh_ad_availability()
	return true


func _ok_user_id_from_url() -> String:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var search := String(bridge.call("eval", "window.location.search", true))
	for pair in search.trim_prefix("?").split("&"):
		if pair.begins_with("vk_ok_user_id="):
			return pair.substr("vk_ok_user_id=".length()).uri_decode().strip_edges()
	return ""


func get_user() -> Dictionary:
	return {
		"id": _ok_user_id,
		"name": String(_profile.get("nickname", "")),
		"avatar": "",
		"platform": platform_id,
	}


func get_launch_token() -> String:
	return _ok_user_id


func get_app_link() -> String:
	return String(ProjectSettings.get_setting("network/ok_app_url", "https://ok.ru/game/512005268801"))


func get_currency() -> String:
	return "oki"
