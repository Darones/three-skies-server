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
