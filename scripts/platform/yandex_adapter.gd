extends "res://scripts/platform/platform_adapter.gd"

## M1 stub for Yandex Games. The real adapter (M6) will own ysdk init, player,
## cloud saves, payments and ads. Nothing is faked before that work is done.


func _init() -> void:
	platform_id = "yandex"
	display_name = "Yandex"


func get_currency() -> String:
	return "yandex"


## Yandex Games support channel is not configured yet. No fake community link
## before the real adapter (M6) owns ysdk; an empty URL means "no channel".
func get_support_url() -> String:
	return ""
