extends Node

signal purchase_updated(success: bool, purchase_type: String, item_id: int, new_shards: int)
signal profile_updated

const MAX_CHARACTER_LEVEL := 15
const LEVEL_UP_SHARD_REWARDS: Dictionary = {
	1: 50, 2: 75, 3: 100, 4: 125, 5: 150,
	6: 175, 7: 200, 8: 225, 9: 250, 10: 300,
	11: 325, 12: 350, 13: 375, 14: 400, 15: 450,
}

var sky_shards: int = 0
var player_nickname: String = ""
var player_id: int = 0
var profile_loaded: bool = false
var char_levels: Dictionary = {"warrior": 1, "mage": 1, "fairy": 1}
var char_xps: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var just_leveled_up: bool = false
var just_leveled_up_character: String = ""
var equipped_wing: int = 0
var equipped_wings: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var unlocked_wings: Array[int] = []
var unlocked_weapons: Array[int] = []
var pending_purchase_type := ""
var pending_purchase_id := 0


func _ready() -> void:
	if not NetworkClient.registration_completed.is_connected(_on_registration_completed):
		NetworkClient.registration_completed.connect(_on_registration_completed)
	if not NetworkClient.profile_loaded.is_connected(_on_profile_loaded):
		NetworkClient.profile_loaded.connect(_on_profile_loaded)
	if not NetworkClient.purchase_completed.is_connected(_on_purchase_completed):
		NetworkClient.purchase_completed.connect(_on_purchase_completed)
	if not NetworkClient.match_reward_completed.is_connected(_on_match_reward_completed):
		NetworkClient.match_reward_completed.connect(_on_match_reward_completed)


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


func grant_match_reward(amount: int) -> bool:
	if amount <= 0:
		return false
	if player_id <= 0:
		add_shards(amount)
		return false
	NetworkClient.grant_match_reward(player_id, amount)
	return true


func _on_match_reward_completed(success: bool, amount: int, new_shards: int) -> void:
	if success:
		sky_shards = maxi(0, new_shards)
	else:
		# Keep the reward if the server is unreachable so offline play still
		# progresses.
		add_shards(amount)
	profile_updated.emit()


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
	if weapon_id != 1 or cost <= 0 or weapon_id in unlocked_weapons:
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


func _on_profile_loaded(success: bool, loaded_player_id: int, server_shards: int, server_wings: Array, server_weapons: Array) -> void:
	if loaded_player_id != player_id:
		return
	profile_loaded = success
	if not success:
		return
	sky_shards = maxi(0, server_shards)
	unlocked_wings.clear()
	unlocked_weapons.clear()
	for wing_id in server_wings:
		var parsed_wing_id := int(wing_id)
		if parsed_wing_id >= 1 and parsed_wing_id <= 4 and parsed_wing_id not in unlocked_wings:
			unlocked_wings.append(parsed_wing_id)
	for weapon_id in server_weapons:
		var parsed_weapon_id := int(weapon_id)
		if parsed_weapon_id == 1 and parsed_weapon_id not in unlocked_weapons:
			unlocked_weapons.append(parsed_weapon_id)
	profile_updated.emit()


func _on_purchase_completed(success: bool, purchase_type: String, item_id: int, new_shards: int) -> void:
	if pending_purchase_type != purchase_type or pending_purchase_id != item_id:
		return
	pending_purchase_type = ""
	pending_purchase_id = 0
	if success:
		sky_shards = maxi(0, new_shards)
		if purchase_type == "wing" and item_id not in unlocked_wings:
			unlocked_wings.append(item_id)
		elif purchase_type == "weapon" and item_id not in unlocked_weapons:
			unlocked_weapons.append(item_id)
	purchase_updated.emit(success, purchase_type, item_id, sky_shards)
