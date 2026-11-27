extends Node

const WeaponCatalog = preload("res://scripts/weapon_catalog.gd")
const SkinCatalog = preload("res://scripts/skin_catalog.gd")

signal purchase_updated(success: bool, purchase_type: String, item_id: int, new_shards: int)
signal profile_updated
signal profile_failed

const MAX_CHARACTER_LEVEL := 15
const STATS_PATH := "user://stats.cfg"
const LOADOUT_PATH := "user://loadout.cfg"
const META_PATH := "user://meta_save.cfg"
const LEGACY_TUTORIAL_PATH := "user://tutorial.cfg"
const LEVEL_UP_SHARD_REWARDS: Dictionary = {
	1: 50, 2: 75, 3: 100, 4: 125, 5: 150,
	6: 175, 7: 200, 8: 225, 9: 250, 10: 300,
	11: 325, 12: 350, 13: 375, 14: 400, 15: 450,
}

var sky_shards: int = 0
var pending_compensation: int = 0
var compensation_in_flight := false
var compensation_retries := 0
var player_nickname: String = ""
var player_id: int = 0
var session_token: String = ""
var profile_loaded: bool = false
var nickname_custom: bool = false
var matches_played: int = 0
var novice: bool = false
var account_level: int = 1
var char_levels: Dictionary = {"warrior": 1, "mage": 1, "fairy": 1}
var char_xps: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var tutorial_completed := false
var tutorial_skipped := false
var tutorial_battles_used := 0
# Local-only flag: the first-launch welcome card is shown once per device.
var welcome_seen := false
var progress_initialized := false
var last_interstitial_at := 0
var just_leveled_up: bool = false
var just_leveled_up_character: String = ""
var last_xp_gain := 0
var last_xp_gain_character := ""
var equipped_wing: int = 0
var equipped_wings: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var weapons_enabled: Dictionary = {"warrior": true, "mage": true, "fairy": true}
var equipped_weapons: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var equipped_skins: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var unlocked_wings: Array[int] = []
var unlocked_weapons: Array[int] = []
var pending_purchase_type := ""
var pending_purchase_id := 0
var pending_level_shards := 0
# Rewards the server has not confirmed yet. They survive a restart in
# meta_save.cfg and are retried once on the next profile/lobby. /match_reward is
# idempotent per room, so a retry can never pay the same match twice.
var pending_match_rewards: Array = []
var _reward_in_flight: Dictionary = {}
# One automatic retry per pending payload per launch: a profile poll loop must
# not turn a failing retry into a retry storm.
var _reward_flush_attempted: Dictionary = {}
var match_reward_retry_count := 0
var stats_all := {
	"matches": 0, "wins": 0, "kills": 0, "deaths": 0,
	"damage": 0, "shells": 0, "crystals": 0, "xp": 0, "shards": 0,
}
var stats_session := {
	"matches": 0, "wins": 0, "kills": 0, "deaths": 0,
	"damage": 0, "shells": 0, "crystals": 0, "xp": 0, "shards": 0,
}
var stats_last := {
	"won": false, "place": 0, "kills": 0, "deaths": 0,
	"damage": 0, "shells": 0, "crystals": 0, "xp": 0, "shards": 0,
}


func _ready() -> void:
	_load_loadout()
	_load_meta()
	NetworkClient.session_token = session_token
	if not NetworkClient.session_ready.is_connected(_on_session_ready):
		NetworkClient.session_ready.connect(_on_session_ready)
	var stats_config := ConfigFile.new()
	if stats_config.load(STATS_PATH) == OK:
		for key in stats_all.keys():
			stats_all[key] = int(stats_config.get_value("all", key, 0))
	if not NetworkClient.registration_completed.is_connected(_on_registration_completed):
		NetworkClient.registration_completed.connect(_on_registration_completed)
	if not NetworkClient.profile_loaded.is_connected(_on_profile_loaded):
		NetworkClient.profile_loaded.connect(_on_profile_loaded)
	if not NetworkClient.progress_loaded.is_connected(_on_progress_loaded):
		NetworkClient.progress_loaded.connect(_on_progress_loaded)
	if not NetworkClient.progress_saved.is_connected(_on_progress_saved):
		NetworkClient.progress_saved.connect(_on_progress_saved)
	if not NetworkClient.interstitial_recorded.is_connected(_on_interstitial_recorded):
		NetworkClient.interstitial_recorded.connect(_on_interstitial_recorded)
	if not NetworkClient.purchase_completed.is_connected(_on_purchase_completed):
		NetworkClient.purchase_completed.connect(_on_purchase_completed)
	if not NetworkClient.match_reward_completed.is_connected(_on_match_reward_completed):
		NetworkClient.match_reward_completed.connect(_on_match_reward_completed)
	if not NetworkClient.match_reward_settled.is_connected(_on_match_reward_settled):
		NetworkClient.match_reward_settled.connect(_on_match_reward_settled)
	if not NetworkClient.compensation_completed.is_connected(_on_compensation_completed):
		NetworkClient.compensation_completed.connect(_on_compensation_completed)
	if not NetworkClient.quests_rerolled.is_connected(_on_quests_rerolled):
		NetworkClient.quests_rerolled.connect(_on_quests_rerolled)
	if not NetworkClient.weekly_claimed.is_connected(_on_weekly_claimed):
		NetworkClient.weekly_claimed.connect(_on_weekly_claimed)
	# DailyQuests is autoloaded after MetaProgression, so it does not exist yet
	# during this _ready; connect on the next idle frame instead of at parse time.
	call_deferred("_connect_daily_quests")


func _load_meta() -> void:
	var config := ConfigFile.new()
	if config.load(META_PATH) != OK:
		return
	player_id = int(config.get_value("progression", "player_id", 0))
	player_nickname = String(config.get_value("progression", "player_nickname", ""))
	session_token = String(config.get_value("progression", "session_token", ""))
	sky_shards = maxi(0, int(config.get_value("progression", "sky_shards", 0)))
	# Interrupted matches no longer pay compensation; drop any stale queue from
	# an older build so it cannot be claimed after this update.
	pending_compensation = 0
	matches_played = maxi(0, int(config.get_value("progression", "matches_played", 0)))
	novice = bool(config.get_value("progression", "novice", false))
	welcome_seen = bool(config.get_value("progression", "welcome_seen", false))
	account_level = maxi(1, int(config.get_value("progression", "account_level", 1)))
	var levels: Variant = config.get_value("progression", "char_levels", {})
	if levels is Dictionary:
		for key in char_levels.keys():
			char_levels[key] = clampi(int(levels.get(key, 1)), 1, MAX_CHARACTER_LEVEL)
	var xps: Variant = config.get_value("progression", "char_xps", {})
	if xps is Dictionary:
		for key in char_xps.keys():
			char_xps[key] = maxi(0, int(xps.get(key, 0)))
	# One-time source for players who finished the tutorial before M2. The
	# server profile replaces these values as soon as it is loaded.
	var tutorial := ConfigFile.new()
	if tutorial.load(LEGACY_TUTORIAL_PATH) == OK:
		tutorial_completed = bool(tutorial.get_value("tutorial", "completed", false))
		tutorial_skipped = bool(tutorial.get_value("tutorial", "skipped", false))
		tutorial_battles_used = maxi(0, int(tutorial.get_value("tutorial", "battles_used", 0)))
	_load_pending_match_rewards(config)


func _load_pending_match_rewards(config: ConfigFile) -> void:
	pending_match_rewards.clear()
	var stored: Variant = config.get_value("pending", "match_rewards", [])
	if not stored is Array:
		return
	for item in stored:
		if not item is Dictionary:
			continue
		var room_id := int(item.get("room_id", 0))
		var amount := int(item.get("amount", 0))
		if room_id <= 0 or amount <= 0:
			continue
		var bonus := bool(item.get("bonus", false))
		pending_match_rewards.append({
			"key": _reward_key(room_id, bonus),
			"room_id": room_id,
			"amount": amount,
			"xp": maxi(0, int(item.get("xp", 0))),
			"character": String(item.get("character", "")),
			"bonus": bonus,
			"attempts": maxi(0, int(item.get("attempts", 0))),
		})
	if not pending_match_rewards.is_empty():
		print("[REWARD] restored pending rewards: ", pending_match_rewards.size())


func _on_session_ready(token: String) -> void:
	session_token = token
	_save_meta()
	_flush_compensation()
	_flush_pending_match_rewards()


func persist_local() -> void:
	_save_meta()


func mark_welcome_seen() -> void:
	# The welcome card is device-local: it must not touch the server profile.
	if welcome_seen:
		return
	welcome_seen = true
	_save_meta()


func known_matches() -> int:
	# matches_played is server-owned. Local stats are only a fallback while
	# the profile request is still in flight; they must not override VK data
	# with an unrelated standalone history.
	if profile_loaded:
		return matches_played
	return maxi(matches_played, int(stats_all.get("matches", 0)))


func save_progress() -> void:
	if player_id <= 0:
		return
	NetworkClient.save_progress(
		player_id,
		char_levels,
		char_xps,
		tutorial_completed,
		tutorial_skipped,
		tutorial_battles_used
	)


func _on_progress_loaded(success: bool, progress: Dictionary) -> void:
	if not success:
		return
	apply_server_progress(progress)


func _on_interstitial_recorded(success: bool, last_interstitial_at_server: int) -> void:
	if success and last_interstitial_at_server > 0:
		last_interstitial_at = last_interstitial_at_server


func _on_progress_saved(success: bool, progress: Dictionary) -> void:
	if not success:
		return
	progress_initialized = true
	if not progress.is_empty():
		_apply_progress_values(progress)
	_save_meta()
	profile_updated.emit()


func apply_server_progress(progress: Dictionary, notify := true) -> void:
	var initialized := bool(progress.get("progress_initialized", false))
	progress_initialized = initialized
	if not initialized:
		if Platform.platform_id == "standalone":
			# One-time import of the pre-server local XP/tutorial state.
			save_progress()
			return
		# Never copy an unrelated device-local standalone save into a VK/OK
		# profile. A platform profile starts with clean defaults.
		char_levels = {"warrior": 1, "mage": 1, "fairy": 1}
		char_xps = {"warrior": 0, "mage": 0, "fairy": 0}
		tutorial_completed = false
		tutorial_skipped = false
		tutorial_battles_used = 0
		save_progress()
		return
	_apply_progress_values(progress)
	_save_meta()
	if notify:
		profile_updated.emit()


func _apply_progress_values(progress: Dictionary) -> void:
	var levels: Variant = progress.get("char_levels", {})
	if levels is Dictionary:
		for key in char_levels.keys():
			char_levels[key] = clampi(int(levels.get(key, 1)), 1, MAX_CHARACTER_LEVEL)
	var xps: Variant = progress.get("char_xps", {})
	if xps is Dictionary:
		for key in char_xps.keys():
			char_xps[key] = maxi(0, int(xps.get(key, 0)))
	tutorial_completed = bool(progress.get("tutorial_completed", false))
	tutorial_skipped = bool(progress.get("tutorial_skipped", false))
	tutorial_battles_used = maxi(0, int(progress.get("tutorial_battles_used", 0)))
	last_interstitial_at = maxi(0, int(progress.get("last_interstitial_at", last_interstitial_at)))


func _save_meta() -> void:
	var config := ConfigFile.new()
	config.set_value("progression", "player_id", player_id)
	config.set_value("progression", "player_nickname", player_nickname)
	config.set_value("progression", "session_token", session_token)
	config.set_value("progression", "sky_shards", sky_shards)
	config.set_value("progression", "pending_compensation", pending_compensation)
	config.set_value("progression", "matches_played", matches_played)
	config.set_value("progression", "novice", novice)
	config.set_value("progression", "welcome_seen", welcome_seen)
	config.set_value("progression", "account_level", account_level)
	config.set_value("pending", "match_rewards", pending_match_rewards)
	# Before the first successful server save, keep the legacy local values so
	# a failed upload does not lose them. Once the server owns progress they
	# are not written to user:// anymore.
	if not progress_initialized:
		config.set_value("progression", "char_levels", char_levels)
		config.set_value("progression", "char_xps", char_xps)
	config.save(META_PATH)


func reset_all() -> void:
	player_id = 0
	player_nickname = ""
	profile_loaded = false
	nickname_custom = false
	session_token = ""
	NetworkClient.session_token = ""
	NetworkClient.last_purchase_error = ""
	NetworkClient.account_banned = false
	NetworkClient.account_ban_reason = ""
	NetworkClient.warning_count = 0
	NetworkClient.last_warning_reason = ""
	NetworkClient.last_warning_at = 0
	pending_compensation = 0
	compensation_in_flight = false
	compensation_retries = 0
	matches_played = 0
	novice = false
	account_level = 1
	sky_shards = 0
	char_levels = {"warrior": 1, "mage": 1, "fairy": 1}
	char_xps = {"warrior": 0, "mage": 0, "fairy": 0}
	tutorial_completed = false
	tutorial_skipped = false
	tutorial_battles_used = 0
	welcome_seen = false
	progress_initialized = false
	just_leveled_up = false
	just_leveled_up_character = ""
	equipped_wing = 0
	equipped_wings = {"warrior": 0, "mage": 0, "fairy": 0}
	equipped_weapons = {"warrior": 0, "mage": 0, "fairy": 0}
	equipped_skins = {"warrior": 0, "mage": 0, "fairy": 0}
	unlocked_wings.clear()
	unlocked_weapons.clear()
	pending_purchase_type = ""
	pending_purchase_id = 0
	pending_level_shards = 0
	pending_match_rewards.clear()
	_reward_in_flight.clear()
	_reward_flush_attempted.clear()
	match_reward_retry_count = 0
	var daily := get_node_or_null("/root/DailyQuests")
	if daily != null and daily.has_method("clear"):
		daily.clear()
	stats_all = {
		"matches": 0, "wins": 0, "kills": 0, "deaths": 0,
		"damage": 0, "shells": 0, "crystals": 0, "xp": 0, "shards": 0,
	}
	stats_session = {
		"matches": 0, "wins": 0, "kills": 0, "deaths": 0,
		"damage": 0, "shells": 0, "crystals": 0, "xp": 0, "shards": 0,
	}
	stats_last = {
		"won": false, "place": 0, "kills": 0, "deaths": 0,
		"damage": 0, "shells": 0, "crystals": 0, "xp": 0, "shards": 0,
	}
	_save_loadout()


func _load_loadout() -> void:
	var config := ConfigFile.new()
	if config.load(LOADOUT_PATH) != OK:
		return
	for key in equipped_wings.keys():
		equipped_wings[key] = clampi(int(config.get_value("wings", String(key), 0)), 0, 4)
	equipped_wing = clampi(int(config.get_value("wings", "last", 0)), 0, 4)
	for key in weapons_enabled.keys():
		weapons_enabled[key] = bool(config.get_value("weapons", String(key), true))
	for key in equipped_weapons.keys():
		var fallback := 0
		if config.has_section_key("weapons", String(key)):
			# Old saves stored only "use the legendary variant" as a bool.
			if bool(config.get_value("weapons", String(key), false)):
				fallback = 1 if String(key) == "warrior" else (3 if String(key) == "mage" else 2)
		equipped_weapons[key] = clampi(int(config.get_value("equipped", String(key), fallback)), 0, 13)
	for key in equipped_skins.keys():
		equipped_skins[key] = clampi(int(config.get_value("skin", String(key), 0)), 0, 2)


func _save_loadout() -> void:
	var config := ConfigFile.new()
	for key in equipped_wings.keys():
		config.set_value("wings", String(key), int(equipped_wings[key]))
	config.set_value("wings", "last", equipped_wing)
	for key in equipped_weapons.keys():
		config.set_value("equipped", String(key), int(equipped_weapons[key]))
		config.set_value("weapons", String(key), int(equipped_weapons[key]) != 0)
	for key in equipped_skins.keys():
		config.set_value("skin", String(key), int(equipped_skins[key]))
	config.save(LOADOUT_PATH)


func is_weapon_enabled(character_key: String) -> bool:
	return get_equipped_weapon(character_key) != 0


func get_equipped_weapon(character_key: String) -> int:
	return clampi(int(equipped_weapons.get(character_key, 0)), 0, 13)


func set_equipped_weapon(character_key: String, weapon_id: int) -> bool:
	if not equipped_weapons.has(character_key):
		return false
	if weapon_id != 0:
		if weapon_id not in unlocked_weapons:
			return false
		var item := WeaponCatalog.get_item(weapon_id)
		if item.is_empty() or WeaponCatalog.class_key(int(item["class"])) != character_key:
			return false
	equipped_weapons[character_key] = weapon_id
	_save_loadout()
	return true


func toggle_weapon(character_key: String) -> void:
	var variant_id := 1 if character_key == "warrior" else (3 if character_key == "mage" else 2)
	set_equipped_weapon(character_key, 0 if get_equipped_weapon(character_key) != 0 else variant_id)


func is_skin_unlocked(skin_id: int) -> bool:
	if SkinCatalog.get_item(skin_id).is_empty():
		return false
	return SkinCatalog.unlock_id(skin_id) in unlocked_weapons


func buy_skin(skin_id: int, cost: int) -> bool:
	if SkinCatalog.get_item(skin_id).is_empty():
		return false
	return buy_weapon(SkinCatalog.unlock_id(skin_id), cost)


func get_equipped_skin(character_key: String) -> int:
	return clampi(int(equipped_skins.get(character_key, 0)), 0, 2)


func set_equipped_skin(character_key: String, skin_id: int) -> bool:
	if not equipped_skins.has(character_key):
		return false
	if skin_id != 0:
		if not is_skin_unlocked(skin_id):
			return false
		var item := SkinCatalog.get_item(skin_id)
		if item.is_empty() or WeaponCatalog.class_key(int(item["class"])) != character_key:
			return false
	equipped_skins[character_key] = skin_id
	_save_loadout()
	return true


func set_weapon_enabled(character_key: String, enabled: bool) -> void:
	var variant_id := 1 if character_key == "warrior" else (3 if character_key == "mage" else 2)
	set_equipped_weapon(character_key, variant_id if enabled else 0)


func register_player(nickname: String) -> void:
	var clean_nickname := nickname.strip_edges()
	if player_id > 0 or clean_nickname.is_empty():
		return
	NetworkClient.register_player(clean_nickname)


func load_profile(saved_player_id: int) -> void:
	if saved_player_id <= 0:
		return
	player_id = saved_player_id
	profile_loaded = false
	NetworkClient.load_player_profile(player_id)


func add_shards(shards_amount: int) -> void:
	sky_shards += maxi(0, shards_amount)


func grant_match_reward(amount: int, bonus := false, xp := 0, character := "") -> bool:
	if amount <= 0 or player_id <= 0:
		return false
	var room_id := int(NetworkManager.room_id)
	if room_id <= 0:
		room_id = int(get_tree().get_meta("last_match_room", 0))
	if room_id <= 0:
		# Offline match (or a tutorial): no server room to claim against.
		add_shards(amount)
		_save_meta()
		profile_updated.emit()
		return true
	_remember_pending_match_reward(room_id, amount, bonus, xp, character)
	_reward_in_flight[_reward_key(room_id, bonus)] = true
	NetworkClient.grant_match_reward(player_id, amount, room_id, xp, character, bonus)
	return true


func _reward_key(room_id: int, bonus: bool) -> String:
	return "%d:%s" % [room_id, "bonus" if bonus else "base"]


# Stores the exact payload before sending it. If the app closes or the network
# drops before the server confirms, the next profile/lobby retries it once.
func _remember_pending_match_reward(room_id: int, amount: int, bonus: bool, xp: int, character: String) -> void:
	if room_id <= 0 or amount <= 0:
		return
	var key := _reward_key(room_id, bonus)
	for entry in pending_match_rewards:
		if entry is Dictionary and String(entry.get("key", "")) == key:
			return
	pending_match_rewards.append({
		"key": key,
		"room_id": room_id,
		"amount": amount,
		"xp": maxi(0, xp),
		"character": character,
		"bonus": bonus,
		"attempts": 0,
	})
	_save_meta()


func _remove_pending_match_reward(key: String) -> void:
	var changed := false
	for index in range(pending_match_rewards.size() - 1, -1, -1):
		var entry: Variant = pending_match_rewards[index]
		if entry is Dictionary and String(entry.get("key", "")) == key:
			pending_match_rewards.remove_at(index)
			changed = true
	if changed:
		_save_meta()


# One retry per pending payload per launch, on the next profile/lobby. The
# server claim is idempotent per room, so a retry can never pay twice.
func _flush_pending_match_rewards() -> void:
	if pending_match_rewards.is_empty():
		return
	if player_id <= 0 or session_token.is_empty():
		return
	var to_send: Array = []
	var cleaned: Array = []
	# Keep chronological order: the base reward must reach the server before
	# the separate x2 bonus, otherwise the bonus is rejected as unclaimed.
	for entry in pending_match_rewards:
		if not entry is Dictionary:
			continue
		var room_id := int(entry.get("room_id", 0))
		var amount := int(entry.get("amount", 0))
		var key := String(entry.get("key", _reward_key(room_id, bool(entry.get("bonus", false)))))
		if room_id <= 0 or amount <= 0:
			continue
		cleaned.append(entry)
		if bool(_reward_in_flight.get(key, false)):
			continue
		if bool(_reward_flush_attempted.get(key, false)):
			continue
		var attempts := int(entry.get("attempts", 0)) + 1
		entry["attempts"] = attempts
		_reward_in_flight[key] = true
		_reward_flush_attempted[key] = true
		match_reward_retry_count += 1
		print("[REWARD] retry room=%d bonus=%s amount=%d attempt=%d (total retries=%d)" % [
			room_id, String(entry.get("bonus", false)), amount, attempts, match_reward_retry_count,
		])
		to_send.append(entry)
	if cleaned.size() != pending_match_rewards.size():
		pending_match_rewards = cleaned
	for entry in to_send:
		NetworkClient.grant_match_reward(
			player_id,
			int(entry.get("amount", 0)),
			int(entry.get("room_id", 0)),
			maxi(0, int(entry.get("xp", 0))),
			String(entry.get("character", "")),
			bool(entry.get("bonus", false))
		)
	_save_meta()


func _on_match_reward_settled(success: bool, payload: Dictionary, _response_code: int, error: String, _profile: Dictionary) -> void:
	var room_id := int(payload.get("room_id", 0))
	var bonus := bool(payload.get("bonus", false))
	var key := _reward_key(room_id, bonus)
	_reward_in_flight.erase(key)
	if success:
		_remove_pending_match_reward(key)
		print("[REWARD] confirmed room=%d bonus=%s" % [room_id, bonus])
		return
	# These answers cannot be fixed by retrying; anything else (network, 5xx)
	# stays in meta_save.cfg for the next launch. A bonus "already claimed" may
	# simply mean the base reward has not been paid yet, so the bonus keeps
	# waiting for the next profile instead of being dropped.
	var terminal_errors := [
		"Invalid reward", "Invalid character",
		"Conflicting reward amount", "Player not found", "invalid_reward",
	]
	if error == "Reward already claimed" and not bonus:
		terminal_errors.append(error)
	if error in terminal_errors:
		_remove_pending_match_reward(key)
		print("[REWARD] terminal room=%d bonus=%s error=%s; cleared" % [room_id, bonus, error])
		return
	_save_meta()
	print("[REWARD] not confirmed room=%d bonus=%s error=%s; kept for next profile" % [room_id, bonus, error])


func _on_match_reward_completed(success: bool, _amount: int, new_shards: int, profile: Dictionary) -> void:
	# The server owns the balance and match XP: a failed request must not
	# create shards or levels.
	if success:
		sky_shards = maxi(0, new_shards)
		var levels: Variant = profile.get("char_levels", {})
		if levels is Dictionary:
			for key in char_levels.keys():
				char_levels[key] = clampi(int(levels.get(key, char_levels[key])), 1, MAX_CHARACTER_LEVEL)
		var xps: Variant = profile.get("char_xps", {})
		if xps is Dictionary:
			for key in char_xps.keys():
				char_xps[key] = maxi(0, int(xps.get(key, char_xps[key])))
		if bool(profile.get("leveled_up", false)):
			var character := String(profile.get("character", ""))
			if character in char_levels:
				just_leveled_up = true
				just_leveled_up_character = character
		_save_meta()
	profile_updated.emit()


func queue_compensation(amount: int) -> void:
	if amount <= 0:
		return
	# One interrupted-match payout is pending at a time; the server also has a
	# cooldown, so stacking claims would only make the player wait longer.
	pending_compensation = mini(20, pending_compensation + amount)
	_save_meta()
	_flush_compensation()


func _flush_compensation() -> void:
	if compensation_in_flight or pending_compensation <= 0:
		return
	if player_id <= 0 or session_token.is_empty():
		return
	compensation_in_flight = true
	NetworkClient.claim_compensation(player_id)


func _on_compensation_completed(success: bool, new_shards: int, error: String) -> void:
	compensation_in_flight = false
	if success:
		pending_compensation = 0
		compensation_retries = 0
		sky_shards = maxi(0, new_shards)
		_save_meta()
		profile_updated.emit()
		return
	_save_meta()
	if error == "cooldown":
		# The next match/session will try again; a retry now cannot succeed.
		return
	compensation_retries += 1
	if compensation_retries <= 6:
		var timer := get_tree().create_timer(5.0)
		timer.timeout.connect(_flush_compensation)


func get_xp_for_next_level(char_name: String) -> int:
	if not char_levels.has(char_name):
		return 1000
	return int(char_levels[char_name]) * 1000


func get_shard_reward_for_level(level: int) -> int:
	return int(LEVEL_UP_SHARD_REWARDS.get(level, 0))


func add_character_xp(char_name: String, amount: int) -> void:
	if not char_levels.has(char_name) or amount <= 0:
		return
	# Doubling rewards adds XP in a second call. Keep a level-up that the
	# first call already earned instead of silently clearing the flag.
	var had_pending_level_up := just_leveled_up and just_leveled_up_character == char_name
	last_xp_gain = amount
	last_xp_gain_character = char_name
	if not had_pending_level_up:
		just_leveled_up = false
		just_leveled_up_character = ""
	if int(char_levels[char_name]) >= MAX_CHARACTER_LEVEL:
		char_xps[char_name] = 0
		return
	char_xps[char_name] = int(char_xps[char_name]) + amount
	var level_reward := 0
	while int(char_levels[char_name]) < MAX_CHARACTER_LEVEL and int(char_xps[char_name]) >= get_xp_for_next_level(char_name):
		char_xps[char_name] = int(char_xps[char_name]) - get_xp_for_next_level(char_name)
		char_levels[char_name] = int(char_levels[char_name]) + 1
		level_reward += int(LEVEL_UP_SHARD_REWARDS.get(int(char_levels[char_name]), 0))
		just_leveled_up = true
		just_leveled_up_character = char_name
	if level_reward > 0:
		# The level-up bonus is still granted locally; only the XP/level state
		# is stored on the server.
		add_shards(level_reward)
	if int(char_levels[char_name]) >= MAX_CHARACTER_LEVEL:
		char_xps[char_name] = 0
	_save_meta()
	save_progress()


func consume_level_up_for(char_name: String) -> bool:
	if not just_leveled_up or just_leveled_up_character != char_name:
		return false
	just_leveled_up = false
	just_leveled_up_character = ""
	return true


func get_equipped_wing(character_key: String) -> int:
	return clampi(int(equipped_wings.get(character_key, 0)), 0, 4)


func equip_wing(wing_id: int, character_key: String) -> bool:
	if not equipped_wings.has(character_key) or wing_id < 0 or wing_id > 4 or (wing_id > 0 and wing_id not in unlocked_wings):
		return false
	equipped_wings[character_key] = wing_id
	equipped_wing = wing_id
	_save_loadout()
	return true


func buy_wing(wing_id: int, cost: int) -> bool:
	if wing_id < 1 or wing_id > 4 or cost <= 0 or wing_id in unlocked_wings:
		return false
	if player_id <= 0 or not profile_loaded or pending_purchase_type != "":
		return false
	pending_purchase_type = "wing"
	pending_purchase_id = wing_id
	NetworkClient.buy_wing_server(player_id, wing_id, cost)
	return true


func buy_weapon(weapon_id: int, cost: int) -> bool:
	var known_item := (weapon_id >= 1 and weapon_id <= 13) or (weapon_id >= 101 and weapon_id <= 102)
	if not known_item or cost <= 0 or weapon_id in unlocked_weapons:
		return false
	if player_id <= 0 or not profile_loaded or pending_purchase_type != "":
		return false
	pending_purchase_type = "weapon"
	pending_purchase_id = weapon_id
	NetworkClient.buy_weapon_server(player_id, weapon_id, cost)
	return true


func is_purchase_pending(purchase_type: String, item_id: int) -> bool:
	return pending_purchase_type == purchase_type and pending_purchase_id == item_id


func _on_registration_completed(success: bool, registered_player_id: int) -> void:
	if not success or registered_player_id <= 0 or player_id > 0:
		return
	player_id = registered_player_id
	load_profile(registered_player_id)


func apply_server_profile(loaded_player_id: int, server_shards: int, server_wings: Array, server_weapons: Array, server_nickname: String, server_nickname_custom: bool, server_matches_played: int, server_novice: bool) -> void:
	_on_profile_loaded(true, loaded_player_id, server_shards, server_wings, server_weapons, server_nickname, server_nickname_custom, server_matches_played, server_novice)


func _on_profile_loaded(success: bool, loaded_player_id: int, server_shards: int, server_wings: Array, server_weapons: Array, server_nickname: String, server_nickname_custom: bool, server_matches_played: int, server_novice: bool) -> void:
	if loaded_player_id != player_id:
		return
	profile_loaded = success
	if not success:
		# The lobby shows a small retry card instead of leaving the welcome
		# screen waiting forever.
		profile_failed.emit()
		return
	sky_shards = maxi(0, server_shards)
	matches_played = maxi(0, server_matches_played)
	novice = server_novice
	if not server_nickname.strip_edges().is_empty():
		player_nickname = server_nickname.strip_edges()
	nickname_custom = server_nickname_custom
	unlocked_wings.clear()
	unlocked_weapons.clear()
	for wing_id in server_wings:
		var parsed_wing_id := int(wing_id)
		if parsed_wing_id >= 1 and parsed_wing_id <= 4 and parsed_wing_id not in unlocked_wings:
			unlocked_wings.append(parsed_wing_id)
	for weapon_id in server_weapons:
		var parsed_weapon_id := int(weapon_id)
		var known_weapon := (parsed_weapon_id >= 1 and parsed_weapon_id <= 13) or (parsed_weapon_id >= 101 and parsed_weapon_id <= 102)
		if known_weapon and parsed_weapon_id not in unlocked_weapons:
			unlocked_weapons.append(parsed_weapon_id)
	var loadout_changed := false
	for key in equipped_wings.keys():
		var equipped_id := int(equipped_wings[key])
		if equipped_id > 0 and equipped_id not in unlocked_wings:
			equipped_wings[key] = 0
			loadout_changed = true
	if equipped_wing > 0 and equipped_wing not in unlocked_wings:
		equipped_wing = 0
		loadout_changed = true
	for key in equipped_weapons.keys():
		var equipped_weapon := int(equipped_weapons[key])
		if equipped_weapon != 0 and equipped_weapon not in unlocked_weapons:
			equipped_weapons[key] = 0
			loadout_changed = true
	for key in equipped_skins.keys():
		var equipped_skin := int(equipped_skins[key])
		if equipped_skin != 0 and not is_skin_unlocked(equipped_skin):
			equipped_skins[key] = 0
			loadout_changed = true
	if loadout_changed:
		_save_loadout()
	if pending_level_shards > 0:
		var pending := pending_level_shards
		pending_level_shards = 0
		grant_match_reward(pending)
	_save_meta()
	_flush_compensation()
	_flush_pending_match_rewards()
	profile_updated.emit()


func _on_purchase_completed(success: bool, purchase_type: String, item_id: int, new_shards: int) -> void:
	if pending_purchase_type != purchase_type or pending_purchase_id != item_id:
		return
	pending_purchase_type = ""
	pending_purchase_id = 0
	if success:
		sky_shards = maxi(0, new_shards)
		if purchase_type == "wing":
			if item_id not in unlocked_wings:
				unlocked_wings.append(item_id)
			for key in equipped_wings.keys():
				equipped_wings[key] = item_id
			equipped_wing = item_id
			_save_loadout()
		elif purchase_type == "weapon" and item_id not in unlocked_weapons:
			unlocked_weapons.append(item_id)
	purchase_updated.emit(success, purchase_type, item_id, sky_shards)


func _connect_daily_quests() -> void:
	var daily := get_node_or_null("/root/DailyQuests")
	if daily == null:
		return
	if daily.has_signal("changed") and not daily.is_connected("changed", _on_daily_quests_changed):
		daily.connect("changed", _on_daily_quests_changed)


func _on_daily_quests_changed() -> void:
	# The badge lives in DailyQuests; this only refreshes the shard counter and
	# the panels that cache profile data. DailyQuests itself blocks a forced
	# request from inside this signal, so the chain cannot loop on the network.
	profile_updated.emit()


# A reroll costs shards and a weekly claim grants them; both endpoints return
# the authoritative balance. Keep it even when the amount is unchanged.
func _on_quests_rerolled(success: bool, _slot: int, data: Dictionary, _error: String) -> void:
	if success:
		_apply_quest_shards(data)


func _on_weekly_claimed(success: bool, data: Dictionary, _error: String) -> void:
	if success:
		_apply_quest_shards(data)


func _apply_quest_shards(data: Dictionary) -> void:
	if not data.has("new_shards"):
		return
	sky_shards = maxi(0, int(data.get("new_shards", sky_shards)))
	_save_meta()
	profile_updated.emit()


func record_match_result(won: bool, place: int, match_stats: Dictionary, xp: int, shards: int) -> void:
	var kills := int(match_stats.get("p_kills", 0))
	var deaths := int(match_stats.get("p_deaths", 0))
	var damage := int(match_stats.get("p_damage", 0))
	var shells := int(match_stats.get("p_shells_destroyed", 0))
	var crystals := int(match_stats.get("p_crystals", 0))
	for stats in [stats_all, stats_session]:
		stats["matches"] = int(stats["matches"]) + 1
		if won:
			stats["wins"] = int(stats["wins"]) + 1
		stats["kills"] = int(stats["kills"]) + kills
		stats["deaths"] = int(stats["deaths"]) + deaths
		stats["damage"] = int(stats["damage"]) + damage
		stats["shells"] = int(stats["shells"]) + shells
		stats["crystals"] = int(stats["crystals"]) + crystals
		stats["xp"] = int(stats["xp"]) + xp
		stats["shards"] = int(stats["shards"]) + shards
	stats_last = {
		"won": won, "place": place, "kills": kills, "deaths": deaths,
		"damage": damage, "shells": shells, "crystals": crystals,
		"xp": xp, "shards": shards,
	}
	_save_stats()


func add_reward_delta(xp: int, shards: int) -> void:
	if xp <= 0 and shards <= 0:
		return
	for stats in [stats_all, stats_session]:
		stats["xp"] = int(stats["xp"]) + maxi(0, xp)
		stats["shards"] = int(stats["shards"]) + maxi(0, shards)
	stats_last["xp"] = int(stats_last["xp"]) + maxi(0, xp)
	stats_last["shards"] = int(stats_last["shards"]) + maxi(0, shards)
	_save_stats()


func stats_for(tab: String) -> Dictionary:
	match tab:
		"last":
			return stats_last
		"session":
			return stats_session
		_:
			return stats_all


func _save_stats() -> void:
	var config := ConfigFile.new()
	for key in stats_all.keys():
		config.set_value("all", key, int(stats_all[key]))
	var error := config.save(STATS_PATH)
	if error != OK:
		push_warning("Не удалось сохранить статистику: %s" % error_string(error))
