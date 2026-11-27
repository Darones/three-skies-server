extends "res://scripts/platform/vk_adapter.gd"

## Odnoklassniki adapter. OK uses the same VK Bridge shell. Identity comes from
## the signed `local_access_token` in the launch URL: the server verifies it
## through the OK API. The bridge (`VKWebAppGetUserInfo(use_local: true)`) is
## only the fallback for launches without a token.

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
	# OK has its own sign-in: the launch URL carries a signed
	# `local_access_token` that the server verifies through the OK API. While a
	# token is present, the unsigned bridge identity below must stay unused.
	var local_token := _local_access_token()
	if not local_token.is_empty():
		var token_auth: Dictionary = await NetworkClient.auth_ok(local_token)
		if not _apply_auth(token_auth):
			# Do not hide a real OK problem (bad token, OK not configured) behind
			# the uid fallback: the player must decide after a working OK login.
			_last_error = _token_auth_error(String(token_auth.get("error", "")))
			_auth_in_progress = false
			return false
		if _ok_user_id.is_empty():
			_ok_user_id = _ok_user_id_from_url()
		_authenticated = true
		_auth_in_progress = false
		_refresh_ad_availability()
		# Never log the token itself: only which path signed the player in.
		print("[OK] auth via local_access_token")
		return true
	# The OK launcher does not put `local_access_token` in the URL. Per the VK
	# docs for OK, VKWebAppGetAuthToken with append_local:true returns it in
	# `local_access_token`; the server then verifies it through the OK API.
	var bridge_token := await _request_bridge_access_token()
	if not bridge_token.is_empty():
		var bridge_auth: Dictionary = await NetworkClient.auth_ok(bridge_token)
		if _apply_auth(bridge_auth):
			if _ok_user_id.is_empty():
				_ok_user_id = _ok_user_id_from_url()
			_authenticated = true
			_auth_in_progress = false
			_refresh_ad_availability()
			print("[OK] auth via bridge local_access_token")
			return true
		# TEMPORARY: keep the working UID fallback until the OK cabinet/token
		# path is confirmed. Remove after a successful live token login.
		print("[OK] bridge local_access_token rejected: %s; falling back to identity" % String(bridge_auth.get("error", "")))
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
	print("[OK] auth via bridge identity (no token)")
	return true


## Token path failures keep their own names instead of the generic VK ones, so
## the entry screen says "OK is temporarily unavailable" and never "wrong
## password". `_apply_auth` already set a mapped error; this only renames it.
func _token_auth_error(server_error: String) -> String:
	match server_error:
		"ok_auth_not_configured":
			return "ok_auth_not_configured"
		"invalid_ok_auth", "invalid_server_profile", "ok_auth_denied":
			return "invalid_ok_auth"
		"rate_limited":
			return "ok_rate_limited"
		"timeout", "auth_in_progress":
			return "ok_auth_failed"
		_:
			return "ok_auth_failed"


func _local_access_token() -> String:
	return Platform.get_local_access_token()


## OK gives the signed token to the VK Bridge, not to the launch URL:
## VKWebAppGetAuthToken with `append_local` returns it for the OK app. Bridge
## errors and a missing token are not fatal here: the caller falls back to the
## bridge identity path. The token itself is never logged.
func _request_bridge_access_token() -> String:
	# The launcher requires app_id; `append_local` is not part of its validator
	# and made the call fail, so only the two documented fields are sent.
	# app_id must be a number: the bridge validator rejects a string as missing.
	var result := await _call_ad_bridge(
		"VKWebAppGetAuthToken",
		{"app_id": 54906713, "scope": "", "append_local": true},
		30.0
	)
	if not bool(result.get("ok", false)):
		var bridge_error := String(result.get("error", ""))
		if not bridge_error.is_empty():
			print("[OK] bridge access token request failed: %s" % bridge_error)
		return ""
	var data: Variant = result.get("data", {})
	if not data is Dictionary:
		return ""
	# OK wraps the answer as {type: "...", data: {...}}; VK resolves the token
	# object directly. Accept both shapes.
	var nested: Variant = (data as Dictionary).get("data")
	if nested is Dictionary:
		data = nested
	for key in ["local_access_token", "access_token", "token"]:
		var value := String((data as Dictionary).get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""


func _ok_url_param(param_name: String) -> String:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var prefix := param_name + "="
	for raw in [
		String(bridge.call("eval", "window.location.search", true)),
		String(bridge.call("eval", "window.location.hash", true)),
	]:
		var text := String(raw).strip_edges().trim_prefix("?").trim_prefix("#")
		var question := text.find("?")
		if question >= 0:
			text = text.substr(question + 1)
		for pair in text.split("&", false):
			if pair.begins_with(prefix):
				return pair.substr(prefix.length()).uri_decode().strip_edges()
	return ""


func _ok_user_id_from_url() -> String:
	# OK's uid arrives under different names depending on the launcher shell.
	for key in ["vk_ok_user_id", "ok_user_id", "user_id"]:
		var value := _ok_url_param(key)
		if not value.is_empty():
			return value
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


## OK group from the moderation brief. Direct link, own platform only: VK
## players must never be sent to the OK group or the other way round.
func get_support_url() -> String:
	return "https://ok.ru/group/70000062043632"


func get_currency() -> String:
	return "oki"
