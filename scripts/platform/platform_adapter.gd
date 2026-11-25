class_name PlatformAdapter
extends RefCounted

## Stable platform contract. The game core talks only to the Platform autoload,
## never to VK/OK/Yandex SDKs directly. A concrete adapter may await real SDK
## callbacks; the base implementation is deliberately safe and does nothing.

var platform_id := "standalone"
var display_name := "Standalone"
var last_ad_error := ""
var last_ad_detail := ""


func initialize(_host: Node) -> void:
	pass


func is_ready() -> bool:
	return true


func authenticate() -> bool:
	return true


func is_authenticated() -> bool:
	return true


func get_auth_error() -> String:
	return ""


func get_last_ad_error() -> String:
	return last_ad_error


func get_last_ad_detail() -> String:
	return last_ad_detail


func get_user() -> Dictionary:
	return {
		"id": "",
		"name": "",
		"avatar": "",
		"platform": platform_id,
	}


func get_launch_token() -> String:
	return ""


func get_app_link() -> String:
	return ""


func get_currency() -> String:
	return ""


func is_rewarded_available() -> bool:
	return false


func is_interstitial_available() -> bool:
	return false


func is_purchase_available() -> bool:
	return false


func show_rewarded_ad(_placement: String) -> bool:
	return false


func show_interstitial(_placement: String) -> bool:
	return false


func purchase(_sku: String) -> Dictionary:
	return {
		"success": false,
		"receipt": "",
		"error": "unavailable",
	}


func load_cloud() -> Dictionary:
	return {}


func save_cloud(_data: Dictionary) -> bool:
	return false


func track(_event: String, _payload: Dictionary) -> void:
	pass
