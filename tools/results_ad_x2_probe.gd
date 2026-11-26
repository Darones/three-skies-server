extends Node

## Results x2 contract for the rewarded ad and the server bonus:
##  (a) rewarded success, base confirmed -> one bonus with the doubled total;
##  (b) base not confirmed / failed -> the bonus waits, then is queued behind
##      the base in MetaProgression's outbox and is not lost;
##  (c) rewarded fail -> no x2, no local payout and no interstitial in the
##      same results screen;
##  (d) rewarded watched -> no interstitial in the same results screen;
##  (e) a second click pays nothing twice.
##
## The probe never talks to the real server: the reward outbox points at a
## closed local port, so every request fails fast and the entries stay in
## MetaProgression where the assertions can read them.

const PROFILE_PATHS := ["user://meta_save.cfg", "user://stats.cfg", "user://loadout.cfg"]
const ROOM := 987654321
const DEAD_API := "http://127.0.0.1:9"


class AdStub extends PlatformAdapter:
	var rewarded_result := true
	var rewarded_calls := 0
	var interstitial_calls := 0
	var interstitial_result := false

	func _init() -> void:
		platform_id = "vk"
		display_name = "ResultsX2Stub"

	func is_rewarded_available() -> bool:
		return true

	func is_interstitial_available() -> bool:
		return true

	func show_rewarded_ad(_placement: String) -> bool:
		rewarded_calls += 1
		last_ad_error = "" if rewarded_result else "not_completed"
		last_ad_detail = "stub"
		return rewarded_result

	func show_interstitial(_placement: String) -> bool:
		interstitial_calls += 1
		return interstitial_result


var failures := 0
var _profile_backup: Dictionary = {}
var stub: AdStub
var screen: Control


func _ready() -> void:
	var target := Vector2i(1440, 734)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
	if target.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
	get_tree().root.content_scale_size = target
	DisplayServer.window_set_size(target)
	for i in 3:
		await get_tree().process_frame
	_snapshot_profile()

	var original_adapter: Variant = Platform.adapter
	var original_id := Platform.platform_id
	var original_api := NetworkClient.api_base_url
	stub = AdStub.new()
	Platform.adapter = stub
	Platform.platform_id = "vk"
	NetworkClient.api_base_url = DEAD_API
	get_tree().set_meta("last_match_room", ROOM)

	# Build the screen without a profile request; the reward identity is set
	# afterwards so the probe owns every request it makes.
	var saved_player_id := int(MetaProgression.player_id)
	MetaProgression.player_id = 0
	screen = (load("res://scenes/ResultsScreen.tscn") as PackedScene).instantiate()
	add_child(screen)
	for i in 6:
		await get_tree().process_frame
	MetaProgression.player_id = maxi(saved_player_id, 7)
	MetaProgression.session_token = "probe"
	MetaProgression.profile_loaded = true
	MetaProgression.matches_played = 9
	MetaProgression.novice = false
	MetaProgression.last_interstitial_at = 0
	MetaProgression.pending_match_rewards.clear()

	await _check_waits_for_base()
	await _check_bonus_before_base()
	await _check_failed_rewarded()
	await _check_watched_rewarded()
	await _check_double_click()

	MetaProgression.pending_match_rewards.clear()
	Platform.adapter = original_adapter
	Platform.platform_id = original_id
	NetworkClient.api_base_url = original_api
	print("RESULTS_AD_X2_FAILURES=%d" % failures)
	_restore_profile()
	# Free the built screen before quitting: its tweens and the stub keep
	# references that Godot would otherwise report as leaked at exit.
	if is_instance_valid(screen):
		screen.queue_free()
	stub = null
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)


# (a) and (e) on the server path.
func _check_waits_for_base() -> void:
	_prepare(true, 3, 100, true)
	await screen.call("_double_rewards_for_ad")
	_check(bool(screen.get("rewards_doubled")), "(a) rewarded success doubles the totals")
	_check(int(screen.get("final_shards")) == 6, "(a) the screen shows exactly x2 shards")
	_check(bool(screen.get("pending_bonus")), "(a) the bonus waits for the base answer")
	_check(_count(false) == 0 and _count(true) == 0, "(a) no request is sent before the base answer")

	NetworkClient.match_reward_settled.emit(true, {"room_id": ROOM, "bonus": false, "amount": 3}, 200, "", {})
	var bonus := _first(true)
	_check(not bonus.is_empty(), "(a) the bonus is sent after the base is confirmed")
	_check(int(bonus.get("amount", 0)) == 6, "(a) the bonus carries the doubled total")
	_check(String(bonus.get("character", "")) == "warrior", "(a) the bonus keeps the character")
	_check(not bool(screen.get("pending_bonus")), "(a) nothing stays pending")

	# (e) the same click again must not request a second ad or a second payout.
	screen.set("ad_in_progress", false)
	var calls_before := stub.rewarded_calls
	await screen.call("_double_rewards_for_ad")
	_check(stub.rewarded_calls == calls_before, "(e) the x2 button requests no second ad")
	_check(_count(true) == 1, "(e) exactly one bonus request exists for the match")
	_check(int(screen.get("final_shards")) == 6, "(e) the doubled total is applied once")


# (b) the base answer fails while the x2 is already earned.
func _check_bonus_before_base() -> void:
	_prepare(true, 3, 100, true)
	# A realistic outbox state: the base reward is recorded but unanswered.
	MetaProgression.call("_remember_pending_match_reward", ROOM, 3, false, 100, "warrior")
	_check(_count(false) == 1, "(b) the base reward is in the outbox")

	await screen.call("_double_rewards_for_ad")
	_check(bool(screen.get("pending_bonus")), "(b) the bonus waits while the base is unconfirmed")
	_check(_count(true) == 0, "(b) the bonus is not sent before the base")

	NetworkClient.match_reward_settled.emit(false, {"room_id": ROOM, "bonus": false, "amount": 3}, 0, "Нет связи с сервером", {})
	var bonus := _first(true)
	_check(not bonus.is_empty(), "(b) the x2 is queued after the base failed")
	_check(int(bonus.get("amount", 0)) == 6, "(b) the queued bonus keeps the doubled total")
	var base_index := _index_of(false)
	var bonus_index := _index_of(true)
	_check(base_index >= 0 and bonus_index > base_index, "(b) the outbox keeps the base before the bonus")


# (c) a rewarded ad that was not completed.
func _check_failed_rewarded() -> void:
	_prepare(true, 3, 100, false)
	var shards_before := int(screen.get("final_shards"))
	var bonus_before := _count(true)
	await screen.call("_double_rewards_for_ad")
	_check(not bool(screen.get("rewards_doubled")), "(c) a failed rewarded does not double")
	_check(int(screen.get("final_shards")) == shards_before, "(c) a failed rewarded pays nothing")
	_check(not bool(screen.get("pending_bonus")), "(c) a failed rewarded queues no bonus")
	_check(_count(true) == bonus_before, "(c) the outbox gains no bonus")
	_check(AdManager.rewarded_attempted_this_results, "(c) the attempt is recorded")
	_check(not AdManager.can_show_interstitial_after_results(), "(c) no interstitial after a failed rewarded")
	_check(not bool(screen.call("_can_show_results_interstitial")), "(c) the results screen refuses it")
	var calls_before := stub.interstitial_calls
	await AdManager.maybe_show_interstitial_after_results()
	_check(stub.interstitial_calls == calls_before, "(c) no second ad screen is opened")

	# Control: the same policy still allows one interstitial when no rewarded
	# was attempted, so the checks above prove the gate and not a dead policy.
	AdManager.begin_results()
	_check(AdManager.can_show_interstitial_after_results(), "(c) control: a fresh results screen may show one")


# (d) a rewarded ad that was watched.
func _check_watched_rewarded() -> void:
	_prepare(true, 3, 100, true)
	await screen.call("_double_rewards_for_ad")
	_check(AdManager.rewarded_watched_this_results, "(d) the watched rewarded is recorded")
	_check(not AdManager.can_show_interstitial_after_results(), "(d) no interstitial after a watched rewarded")
	_check(not bool(screen.call("_can_show_results_interstitial")), "(d) the results screen refuses it")
	var calls_before := stub.interstitial_calls
	await AdManager.maybe_show_interstitial_after_results()
	_check(stub.interstitial_calls == calls_before, "(d) no second ad screen is opened")


# (e) two clicks in the same frame, offline match.
func _check_double_click() -> void:
	_prepare(false, 100, 10, true)
	var calls_before := stub.rewarded_calls
	screen.call("_double_rewards_for_ad")
	screen.call("_double_rewards_for_ad")
	for i in 4:
		await get_tree().process_frame
	_check(stub.rewarded_calls == calls_before + 1, "(e) a double click opens one ad")
	_check(int(screen.get("final_shards")) == 200, "(e) offline x2 is applied once")
	_check(int(screen.get("final_xp")) == 20, "(e) offline x2 xp is applied once")


func _prepare(server: bool, shards: int, xp: int, rewarded: bool) -> void:
	stub.rewarded_result = rewarded
	screen.set("match_aborted", false)
	screen.set("server_match", server)
	screen.set("rewards_doubled", false)
	screen.set("rewards_committed", true)
	screen.set("final_shards", shards)
	screen.set("final_xp", xp)
	screen.set("ad_in_progress", false)
	screen.set("base_reward_settled", false)
	screen.set("base_reward_ok", false)
	screen.set("pending_bonus", false)
	screen.set("reward_room", ROOM)
	screen.set("leaving_results", false)
	MetaProgression.pending_match_rewards.clear()
	AdManager.begin_results()
	var hint: Label = screen.get("ad_error_label")
	if hint != null:
		hint.visible = false
	var banner: Label = screen.get("reward_banner")
	if banner != null:
		banner.visible = false
	screen.call("_refresh_reward_ui")


func _entries(bonus: bool) -> Array:
	var found: Array = []
	for entry in MetaProgression.pending_match_rewards:
		if entry is Dictionary and bool(entry.get("bonus", false)) == bonus:
			found.append(entry)
	return found


func _count(bonus: bool) -> int:
	return _entries(bonus).size()


func _first(bonus: bool) -> Dictionary:
	var found := _entries(bonus)
	return found[0] if not found.is_empty() else {}


func _index_of(bonus: bool) -> int:
	for index in range(MetaProgression.pending_match_rewards.size()):
		var entry: Variant = MetaProgression.pending_match_rewards[index]
		if entry is Dictionary and bool(entry.get("bonus", false)) == bonus:
			return index
	return -1


## The x2 case writes shards/XP and the outbox, so put the save files back.
func _snapshot_profile() -> void:
	_profile_backup.clear()
	for path in PROFILE_PATHS:
		if FileAccess.file_exists(path):
			_profile_backup[path] = FileAccess.get_file_as_bytes(path)


func _restore_profile() -> void:
	for path in PROFILE_PATHS:
		if not _profile_backup.has(path):
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_profile_backup[path])
			file.close()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
