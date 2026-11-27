extends Node

## Single entry point for platform services. The core calls Platform.* only;
## concrete SDK code lives in adapters selected by export feature tags.

signal app_paused
signal app_resumed

const StandaloneAdapterScript := preload("res://scripts/platform/standalone_adapter.gd")
const VKAdapterScript := preload("res://scripts/platform/vk_adapter.gd")
const OKAdapterScript := preload("res://scripts/platform/ok_adapter.gd")
const YandexAdapterScript := preload("res://scripts/platform/yandex_adapter.gd")

var adapter: RefCounted
var platform_id := "standalone"
var initialized := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_select_adapter()
	adapter.initialize(self)
	initialized = true
	print("[Platform] id=%s adapter=%s" % [platform_id, adapter.display_name])


func _web_location() -> Dictionary:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return {}
	var bridge := Engine.get_singleton("JavaScriptBridge")
	return {
		"search": String(bridge.call("eval", "window.location.search", true)),
		"hash": String(bridge.call("eval", "window.location.hash", true)),
		"referrer": String(bridge.call("eval", "document.referrer", true)),
	}


## Reads one parameter out of a URL query or hash fragment ("a=1&b=2").
func _url_param(source: String, param_name: String) -> String:
	var text := source.strip_edges().trim_prefix("?").trim_prefix("#")
	var question := text.find("?")
	if question >= 0:
		# Hash routers keep their query after a second "?".
		text = text.substr(question + 1)
	var prefix := param_name + "="
	for pair in text.split("&", false):
		if pair.begins_with(prefix):
			return pair.substr(prefix.length()).uri_decode().strip_edges()
	return ""


## OK marks the player with a signed `local_access_token` in the launch URL,
## in the query or in the hash. The server verifies it through the OK API; the
## client only passes it on. Empty means "no OK token", so the caller keeps its
## own fallback path.
func get_local_access_token() -> String:
	var location := _web_location()
	if location.is_empty():
		return ""
	var token := _url_param(String(location["search"]), "local_access_token")
	if token.is_empty():
		token = _url_param(String(location["hash"]), "local_access_token")
	return token


func _url_platform_hint() -> String:
	# One PCK serves every platform: the adapter is chosen at runtime from the
	# launcher URL, not from export feature tags. OK is checked first because
	# it also runs through VK Bridge and can carry vk_* names.
	var location := _web_location()
	if location.is_empty():
		return ""
	var launch := (String(location["search"]) + "&" + String(location["hash"])).to_lower()
	var referrer := String(location["referrer"]).to_lower()
	if launch.contains("vk_client=ok") or launch.contains("ok_client") \
			or launch.contains("platform=ok") or launch.contains("local_access_token="):
		return "ok"
	# In OK the game runs inside an ok.ru iframe. The referrer is readable even
	# when the launch query does not repeat the client name.
	if referrer.contains("ok.ru"):
		return "ok"
	# VK launch params live in the query or in the hash. They are the signed
	# identity source, so their presence is the reliable runtime VK marker.
	if launch.contains("vk_user_id=") or launch.contains("vk_app_id=") \
			or launch.contains("vk_ts=") or launch.contains("vk_platform="):
		return "vk"
	return ""


func _detect_platform_id() -> String:
	var hint := _url_platform_hint()
	if not hint.is_empty():
		return hint
	# Legacy platform-specific PCKs still select by feature tag. The single
	# build has no vk/ok tags and reaches this only as standalone.
	# Custom export feature tags win over URL sniffing. `web-vk` is the preset
	# tag; `vk` is kept for future native/hosted builds and matches the docs.
	if OS.has_feature("vk") or OS.has_feature("web-vk"):
		return "vk"
	if OS.has_feature("ok") or OS.has_feature("web-ok"):
		return "ok"
	if OS.has_feature("yandex") or OS.has_feature("web-yandex"):
		return "yandex"
	return "standalone"


func _select_adapter() -> void:
	match _detect_platform_id():
		"vk":
			adapter = VKAdapterScript.new()
		"ok":
			adapter = OKAdapterScript.new()
		"yandex":
			adapter = YandexAdapterScript.new()
		_:
			adapter = StandaloneAdapterScript.new()
	platform_id = String(adapter.platform_id)


func is_ready() -> bool:
	return initialized and adapter != null


func authenticate() -> bool:
	if adapter == null:
		return false
	@warning_ignore("redundant_await")
	return await adapter.authenticate()


## Stops waiting for the current sign-in attempt. Used by the entry screen
## watchdog: a bridge promise that never settles must not block the retry
## button. Adapters without an override stay as they are.
func abort_auth() -> void:
	if adapter != null and adapter.has_method("abort_auth"):
		adapter.abort_auth()


func is_authenticated() -> bool:
	return adapter != null and adapter.is_authenticated()


func get_auth_error() -> String:
	if adapter == null:
		return "adapter_unavailable"
	return String(adapter.get_auth_error())


func get_last_ad_error() -> String:
	if adapter == null:
		return "adapter_unavailable"
	return String(adapter.get_last_ad_error())


func get_last_ad_detail() -> String:
	if adapter == null:
		return ""
	return String(adapter.get_last_ad_detail())


func get_user() -> Dictionary:
	if adapter == null:
		return {}
	return adapter.get_user()


func get_launch_token() -> String:
	if adapter == null:
		return ""
	return String(adapter.get_launch_token())


func get_app_link() -> String:
	if adapter == null:
		return ""
	return String(adapter.get_app_link())


func get_support_url() -> String:
	# Support/community link of the active platform; "" when it has no channel.
	if adapter == null:
		return ""
	return String(adapter.get_support_url())


func get_currency() -> String:
	if adapter == null:
		return ""
	return String(adapter.get_currency())


func is_rewarded_available() -> bool:
	return adapter != null and adapter.is_rewarded_available()


func is_interstitial_available() -> bool:
	return adapter != null and adapter.is_interstitial_available()


func is_purchase_available() -> bool:
	return adapter != null and adapter.is_purchase_available()


func show_rewarded_ad(placement: String = "default") -> bool:
	if adapter == null:
		return false
	@warning_ignore("redundant_await")
	return await adapter.show_rewarded_ad(placement)


func show_interstitial(placement: String = "default") -> bool:
	if adapter == null:
		return false
	@warning_ignore("redundant_await")
	return await adapter.show_interstitial(placement)


func purchase(sku: String) -> Dictionary:
	if adapter == null:
		return {"success": false, "receipt": "", "error": "unavailable"}
	@warning_ignore("redundant_await")
	return await adapter.purchase(sku)


func load_cloud() -> Dictionary:
	if adapter == null:
		return {}
	return adapter.load_cloud()


func save_cloud(data: Dictionary) -> bool:
	if adapter == null:
		return false
	return adapter.save_cloud(data)


func track(event: String, payload: Dictionary = {}) -> void:
	if adapter != null:
		adapter.track(event, payload)


func notify_paused() -> void:
	app_paused.emit()


func notify_resumed() -> void:
	app_resumed.emit()
