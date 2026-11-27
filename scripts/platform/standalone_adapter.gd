extends "res://scripts/platform/platform_adapter.gd"

## Local/self-hosted build: no SDK, no ads, no payments. Cloud saves are a
## local JSON file until a real platform adapter provides them.

const CLOUD_PATH := "user://platform_cloud.json"


func _init() -> void:
	platform_id = "standalone"
	display_name = "Standalone"


func get_user() -> Dictionary:
	return {
		"id": "local",
		"name": "",
		"avatar": "",
		"platform": platform_id,
	}


func get_currency() -> String:
	return ""


## Standalone has no community group, so the real support contact is the
## e-mail. It stays non-empty on purpose: any UI that shows the adapter link
## directly gets a working address instead of a dead button. The e-mail is the
## same as SUPPORT_EMAIL in scripts/support_links.gd.
func get_support_url() -> String:
	return "mailto:daroness@ya.ru"


func is_rewarded_available() -> bool:
	return false


func is_interstitial_available() -> bool:
	return false


func is_purchase_available() -> bool:
	return false


func load_cloud() -> Dictionary:
	if not FileAccess.file_exists(CLOUD_PATH):
		return {}
	var file := FileAccess.open(CLOUD_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func save_cloud(data: Dictionary) -> bool:
	var file := FileAccess.open(CLOUD_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true
