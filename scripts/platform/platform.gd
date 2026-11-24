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


func _detect_platform_id() -> String:
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
