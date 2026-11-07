extends Node

const SAVE_PATH := "user://meta_save.cfg"

var sky_shards: int = 0
var char_levels: Dictionary = {"warrior": 1, "mage": 1, "fairy": 1}
var char_xps: Dictionary = {"warrior": 0, "mage": 0, "fairy": 0}
var just_leveled_up: bool = false
var just_leveled_up_character: String = ""
var equipped_wing: int = 0
var unlocked_wings: Array[int] = []


func _ready() -> void:
	load_game()


func save_game() -> void:
	var config := ConfigFile.new()
	config.set_value("progression", "sky_shards", sky_shards)
	config.set_value("progression", "char_levels", char_levels)
	config.set_value("progression", "char_xps", char_xps)
	config.set_value("progression", "equipped_wing", equipped_wing)
	config.set_value("progression", "unlocked_wings", unlocked_wings)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить прогресс: %s" % error_string(error))


func load_game() -> void:
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error != OK:
		sky_shards = 0
		char_levels = {"warrior": 1, "mage": 1, "fairy": 1}
		char_xps = {"warrior": 0, "mage": 0, "fairy": 0}
		just_leveled_up = false
		just_leveled_up_character = ""
		equipped_wing = 0
		unlocked_wings.clear()
		return
	sky_shards = maxi(0, int(config.get_value("progression", "sky_shards", 0)))
	char_levels = {"warrior": 1, "mage": 1, "fairy": 1}
	char_xps = {"warrior": 0, "mage": 0, "fairy": 0}
	var saved_levels: Variant = config.get_value("progression", "char_levels", {})
	var saved_xps: Variant = config.get_value("progression", "char_xps", {})
	if saved_levels is Dictionary:
		for char_name in char_levels.keys():
			char_levels[char_name] = maxi(1, int(saved_levels.get(char_name, 1)))
	if saved_xps is Dictionary:
		for char_name in char_xps.keys():
			char_xps[char_name] = maxi(0, int(saved_xps.get(char_name, 0)))
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
	if equipped_wing > 0 and equipped_wing not in unlocked_wings:
		equipped_wing = 0


func add_shards(shards_amount: int) -> void:
	sky_shards += maxi(0, shards_amount)
	save_game()


func add_character_xp(char_name: String, amount: int) -> void:
	if not char_levels.has(char_name) or amount <= 0:
		return
	just_leveled_up = false
	just_leveled_up_character = ""
	char_xps[char_name] = int(char_xps[char_name]) + amount
	while int(char_xps[char_name]) >= int(char_levels[char_name]) * 100:
		char_xps[char_name] = int(char_xps[char_name]) - int(char_levels[char_name]) * 100
		char_levels[char_name] = int(char_levels[char_name]) + 1
		just_leveled_up = true
		just_leveled_up_character = char_name
	save_game()


func consume_level_up_for(char_name: String) -> bool:
	if not just_leveled_up or just_leveled_up_character != char_name:
		return false
	just_leveled_up = false
	just_leveled_up_character = ""
	return true


func equip_wing(wing_id: int) -> bool:
	if wing_id < 0 or wing_id > 4 or (wing_id > 0 and wing_id not in unlocked_wings):
		return false
	equipped_wing = wing_id
	save_game()
	return true


func buy_wing(wing_id: int, cost: int) -> bool:
	if wing_id < 1 or wing_id > 4 or cost <= 0 or wing_id in unlocked_wings or sky_shards < cost:
		return false
	sky_shards -= cost
	unlocked_wings.append(wing_id)
	save_game()
	return true
