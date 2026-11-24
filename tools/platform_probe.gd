extends Node

## Headless M1 smoke test. It proves that a standalone build has no ad/payment
## entry points and that AdManager cannot grant a reward without an adapter.

var failures := 0


func _ready() -> void:
	_check(Platform.platform_id == "standalone", "platform_id is standalone")
	_check(Platform.is_ready(), "adapter initialized")
	_check(Platform.get_currency().is_empty(), "standalone currency is empty")
	_check(not Platform.is_rewarded_available(), "rewarded ads unavailable")
	_check(not Platform.is_interstitial_available(), "interstitial ads unavailable")
	_check(not Platform.is_purchase_available(), "purchases unavailable")

	var purchase: Dictionary = await Platform.purchase("shards_100")
	_check(not bool(purchase.get("success", false)), "standalone purchase returns failure")

	var vk_adapter := preload("res://scripts/platform/vk_adapter.gd").new()
	_check(vk_adapter.platform_id == "vk", "VK stub reports vk id")
	_check(not vk_adapter.is_purchase_available(), "VK stub has no purchases yet")
	_check(not vk_adapter.is_rewarded_available(), "VK stub has no rewarded ads yet")
	_check(not vk_adapter.show_rewarded_ad("probe"), "VK stub grants no ad reward")

	var reward_emitted := false
	AdManager.rewarded_ad_completed.connect(func() -> void: reward_emitted = true)
	var rewarded: bool = await AdManager.show_rewarded_ad()
	_check(not rewarded, "AdManager refuses a rewarded ad without adapter")
	_check(not reward_emitted, "AdManager emits no completion without adapter")
	_check(not AdManager.can_show_interstitial_after_results(), "interstitial gated by adapter")

	var lobby_scene := load("res://scenes/Lobby.tscn") as PackedScene
	_check(lobby_scene != null, "Lobby.tscn loads")
	if lobby_scene != null:
		var lobby := lobby_scene.instantiate()
		add_child(lobby)
		await get_tree().process_frame
		await get_tree().process_frame
		var topup_button := lobby.find_child("TopupButton", true, false) as Button
		_check(topup_button != null, "shop topup button exists")
		if topup_button != null:
			_check(not topup_button.visible, "shop topup button hidden in standalone")
		var pay_button := lobby.find_child("PayButton", true, false) as Button
		_check(pay_button != null, "topup pay button exists")
		if pay_button != null:
			_check(not pay_button.visible, "topup pay button hidden in standalone")

	var results_scene := load("res://scenes/ResultsScreen.tscn") as PackedScene
	_check(results_scene != null, "ResultsScreen.tscn loads")
	if results_scene != null:
		var results := results_scene.instantiate()
		add_child(results)
		await get_tree().process_frame
		await get_tree().process_frame
		var ad_button := results.find_child("DoubleRewardsButton", true, false) as Button
		_check(ad_button != null, "results x2 button exists")
		if ad_button != null:
			_check(not ad_button.visible, "results x2 button hidden without rewarded adapter")

	print("PLATFORM_PROBE_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
