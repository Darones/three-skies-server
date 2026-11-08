extends Node

signal wing_purchase_updated(success: bool, wing_id: int, new_shards: int)

const SAVE_PATH := "user://meta_save.cfg"

const MAX_CHARACTER_LEVEL := 15
const LEVEL_UP_SHARD_REWARDS: Dictionary = {
	1: 50, 2: 75, 3: 100, 4: 125, 5: 150,
	6: 175, 7: 200, 8: 225, 9: 250, 10: 300,
	11: 325, 12: 350, 13: 375, 14: 400, 15: 450,
}

var sky_shards: int = 0
var player_nickname: String = ""
var player_id: int = 0
var char_levels: Dictionary = {"warrior": 1, "mage": 1, "fairy": 1}
var char_xps: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var just_leveled_up: bool = false
var just_leveled_up_character: String = ""
var equipped_wing: int = 0
var equipped_wings: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var unlocked_wings: Array[int] = []
var pending_wing_id: int = 0


func _ready() -> void:
	load_game()
	if not NetworkClient.registration_completed.is_connected(_on_registration_completed):
		NetworkClient.registration_completed.connect(_on_registration_completed)
	if not NetworkClient.purchase_completed.is_connected(_on_purchase_completed):
		NetworkClient.purchase_completed.connect(_on_purchase_completed)


func register_player(nickname: String) -> void:
	var clean_nickname := nickname.strip_edges()
	if player_id > 0 or clean_nickname.is_empty():
		return
	NetworkClient.register_player(clean_nickname)


func save_game() -> void:
	var config := ConfigFile.new()
	config.set_value("progression", "sky_shards", sky_shards)
	config.set_value("progression", "player_nickname", player_nickname)
	config.set_value("progression", "player_id", player_id)
	config.set_value("progression", "char_levels", char_levels)
	config.set_value("progression", "char_xps", char_xps)
	config.set_value("progression", "equipped_wing", equipped_wing)
	config.set_value("progression", "equipped_wings", equipped_wings)
	config.set_value("progression", "unlocked_wings", unlocked_wings)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить прогресс: %s" % error_string(error))


func load_game() -> void:
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error != OK:
		sky_shards = 0
		player_nickname = ""
		player_id = 0
		char_levels = {"warrior": 1, "mage": 1, "fairy": 1}
		char_xps = {"warrior": 0, "mage": 0, "fairy": 0}
		just_leveled_up = false
		just_leveled_up_character = ""
		equipped_wing = 0
		equipped_wings = {"warrior": 0, "mage": 0, "fairy": 0}
		unlocked_wings.clear()
		return
	sky_shards = maxi(0, int(config.get_value("progression", "sky_shards", 0)))
	player_nickname = String(config.get_value("progression", "player_nickname", ""))
	player_id = maxi(0, int(config.get_value("progression", "player_id", 0)))
	char_levels = {"warrior": 1, "mage": 1, "fairy": 1}
	char_xps = {"warrior": 0, "mage": 0, "fairy": 0}
	var saved_levels: Variant = config.get_value("progression", "char_levels", {})
	var saved_xps: Variant = config.get_value("progression", "char_xps", {})
	if saved_levels is Dictionary:
		for char_name in char_levels.keys():
			char_levels[char_name] = clampi(int(saved_levels.get(char_name, 1)), 1, MAX_CHARACTER_LEVEL)
	if saved_xps is Dictionary:
		for char_name in char_xps.keys():
			char_xps[char_name] = maxi(0, int(saved_xps.get(char_name, 0)))
	for char_name in char_levels.keys():
		if int(char_levels[char_name]) >= MAX_CHARACTER_LEVEL:
			char_xps[char_name] = 0
	just_leveled_up = false
	just_leveled_up_character = ""
	unlocked_wings.clear()
	var saved_wings: Variant = config.get_value("progression", "unlocked_wings", [])
	if saved_wings is Array:
		for saved_id in saved_wings:
			var wing_id := int(saved_id)
			if wing_id >= 1 and wing_id <= 4 and wing_id not in unlocked_wings:
				unlocked_wings.append(wing_id)
	equipped_wing = clampi(int(config.get_value("progression", "equipped_wing", 0)), 0, 4)
	equipped_wings = {"warrior": equipped_wing, "mage": equipped_wing, "fairy": equipped_wing}
	var saved_equipped_wings: Variant = config.get_value("progression", "equipped_wings", {})
	if saved_equipped_wings is Dictionary:
		for character_key in equipped_wings.keys():
			var wing_id := clampi(int(saved_equipped_wings.get(character_key, equipped_wing)), 0, 4)
			equipped_wings[character_key] = wing_id if wing_id == 0 or wing_id in unlocked_wings else 0
	if equipped_wing > 0 and equipped_wing not in unlocked_wings:
		equipped_wing = 0


func add_shards(shards_amount: int) -> void:
	sky_shards += maxi(0, shards_amount)
	save_game()


func get_xp_for_next_level(char_name: String) -> int:
	if not char_levels.has(char_name):
		return 1000
	return int(char_levels[char_name]) * 1000


func get_shard_reward_for_level(level: int) -> int:
	return int(LEVEL_UP_SHARD_REWARDS.get(level, 0))


func add_character_xp(char_name: String, amount: int) -> void:
	if not char_levels.has(char_name) or amount <= 0:
		return
	just_leveled_up = false
	just_leveled_up_character = ""
	if int(char_levels[char_name]) >= MAX_CHARACTER_LEVEL:
		char_xps[char_name] = 0
		return
	char_xps[char_name] = int(char_xps[char_name]) + amount
	while int(char_levels[char_name]) < MAX_CHARACTER_LEVEL and int(char_xps[char_name]) >= get_xp_for_next_level(char_name):
		char_xps[char_name] = int(char_xps[char_name]) - get_xp_for_next_level(char_name)
		char_levels[char_name] = int(char_levels[char_name]) + 1
		sky_shards += int(LEVEL_UP_SHARD_REWARDS.get(int(char_levels[char_name]), 0))
		just_leveled_up = true
		just_leveled_up_character = char_name
	if int(char_levels[char_name]) >= MAX_CHARACTER_LEVEL:
		char_xps[char_name] = 0
	save_game()


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
	save_game()
	return true


func buy_wing(wing_id: int, cost: int) -> bool:
	if wing_id < 1 or wing_id > 4 or cost <= 0 or wing_id in unlocked_wings:
		return false
	if player_id <= 0 or pending_wing_id != 0:
		return false
	pending_wing_id = wing_id
	NetworkClient.buy_wing_server(player_id, wing_id, cost)
	return true


func _on_registration_completed(success: bool, registered_player_id: int) -> void:
	if not success or registered_player_id <= 0 or player_id > 0:
		return
	player_id = registered_player_id
	save_game()


func _on_purchase_completed(success: bool, new_shards: int) -> void:
	if pending_wing_id <= 0:
		return
	var completed_wing_id := pending_wing_id
	pending_wing_id = 0
	if success:
		sky_shards = maxi(0, new_shards)
		if completed_wing_id not in unlocked_wings:
			unlocked_wings.append(completed_wing_id)
		save_game()
	wing_purchase_updated.emit(success, completed_wing_id, sky_shards)
