extends "res://scripts/platform/platform_adapter.gd"

## M1 stub. The web-vk HTML shell loads VK Bridge, but launch-param auth,
## VK Ads and VK Голоса are M2/M4 work. Until then every paid/rewarded action
## reports "unavailable" instead of faking a purchase or a reward.


func _init() -> void:
	platform_id = "vk"
	display_name = "VK"


func get_currency() -> String:
	return "votes"
