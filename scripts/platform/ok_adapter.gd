extends "res://scripts/platform/platform_adapter.gd"

## M1 stub for Odnoklassniki. The real adapter (M5) will use VK Bridge with
## VKWebAppGetAuthToken(append_local:true) and local_access_token. No OKи
## purchase is faked before that work is done.


func _init() -> void:
	platform_id = "ok"
	display_name = "OK"


func get_currency() -> String:
	return "oki"
