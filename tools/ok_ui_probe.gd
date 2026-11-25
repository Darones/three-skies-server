extends Node

## Headless OK moderation probe: the OK adapter must report OK currency and
## an ok.ru app link, the top-up panel must say "ОКов", and the OK credits
## screen must not contain external URLs. VK credits keep their URLs.

var failures := 0


func _ready() -> void:
	var original_id := Platform.platform_id
	var original_adapter: Variant = Platform.adapter

	var ok_adapter: PlatformAdapter = preload("res://scripts/platform/ok_adapter.gd").new()
	_check(ok_adapter.platform_id == "ok", "OK adapter reports ok id")
	_check(ok_adapter.get_currency() == "oki", "OK currency is oki")
	_check(
		ok_adapter.get_app_link() == "https://ok.ru/game/512005268801",
		"OK app link points to ok.ru/game/512005268801"
	)

	Platform.adapter = ok_adapter
	Platform.platform_id = "ok"

	var panel := preload("res://scenes/ShardTopupPanel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame
	_check(String(panel.call("_price_currency_name")) == "ОКов", "top-up price uses ОКов")
	_check(String(panel.call("_payment_currency_name")) == "ОКами", "top-up payment uses ОКами")
	panel.queue_free()

	var settings := preload("res://scripts/settings_panel.gd").new()
	add_child(settings)
	await get_tree().process_frame
	var ok_credits := String(settings.call("_credits_text"))
	_check(not ok_credits.contains("http"), "OK credits contain no external links")
	_check(ok_credits.contains("Low Poly RPG Items Free"), "OK credits keep the authors")
	_check(ok_credits.contains("CC BY 4.0"), "OK credits keep the licenses")
	_check(not ok_credits.contains("kenney.nl"), "OK credits drop license domains")

	Platform.platform_id = "vk"
	var vk_credits := String(settings.call("_credits_text"))
	_check(vk_credits.contains("https://kenney.nl"), "VK credits keep their URLs")
	settings.queue_free()

	Platform.platform_id = original_id
	Platform.adapter = original_adapter

	print("OK_UI_PROBE_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
