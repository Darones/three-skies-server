extends RefCounted

## Weapon shop catalogue shared by the lobby and HeroUnit.
## IDs 1-3 are the old built-in legendary gear (kept, now with a glow).
## IDs 4-9 are external low-poly models attached to the hand bone.

const ITEMS := {
	1: {
		"id": 1, "class": 0, "name": "Двуручное оружие",
		"rarity": "Легендарное", "price": 1500,
		"icon": "res://ui/icons/legendary_greatsword.png",
		"builtin": true, "glow": Color(0.68, 0.32, 1.0), "glow_energy": 1.6,
		"description": "Клинок, светящийся фиолетовым.",
	},
	2: {
		"id": 2, "class": 2, "name": "Тяжёлый арбалет",
		"rarity": "Легендарное", "price": 1500,
		"icon": "res://assets/ui/shop/weapon_crossbow_2d.png",
		"builtin": true, "glow": Color(0.62, 0.38, 1.0), "glow_energy": 1.5,
		"description": "Арбалет с фиолетовым сиянием.",
	},
	3: {
		"id": 3, "class": 1, "name": "Посох волшебника",
		"rarity": "Легендарное", "price": 1500,
		"icon": "res://ui/icons/legendary_staff.png",
		"builtin": true, "glow": Color(1.0, 0.82, 0.35), "glow_energy": 1.6,
		"description": "Посох, светящийся тёплым золотом.",
	},
	4: {
		"id": 4, "class": 0, "name": "Боевой топор",
		"rarity": "Редкое", "price": 100,
		"icon": "res://addons/low_poly_rpg_items/icons/battle_axe.png",
		"builtin": false,
		"shop_enabled": true,
		"model": "res://addons/low_poly_rpg_items/models/battle_axe_model.glb",
		"hand": "handslot.r", "scale": 1.0,
		"rotation": Vector3(45.6, 27.7, 60.8), "offset": Vector3(0.0, 0.0, 0.05),
		"tip": Vector3(0.0, 0.5, 0.0), "roll": 90.0, "lean": 8.0,
		"glow": Color(1.0, 0.28, 0.22), "glow_energy": 0.9,
		"description": "Красное пламя по лезвию.",
	},
	5: {
		"id": 5, "class": 2, "name": "Короткий лук",
		"rarity": "Редкое", "price": 100,
		"icon": "res://addons/low_poly_rpg_items/icons/short_bow.png",
		"builtin": false,
		"shop_enabled": false,
		"model": "res://addons/low_poly_rpg_items/models/short_bow_model.glb",
		"hand": "handslot.l", "scale": 1.0,
		"rotation": Vector3(-52.83, 9.05, -15.1), "offset": Vector3(-0.6, -0.05, -0.09),
		"tip": Vector3(0.0, 0.0, 0.5), "roll": -80.0,
		"glow": Color(1.0, 0.35, 0.3), "glow_energy": 1.4,
		"description": "Алый свет и белая тетива.",
	},
	6: {
		"id": 6, "class": 1, "name": "Посох ученика",
		"rarity": "Редкое", "price": 100,
		"icon": "res://addons/low_poly_rpg_items/icons/staff_wizard.png",
		"builtin": false,
		"shop_enabled": true,
		"model": "res://addons/low_poly_rpg_items/models/staff_wizard_model.glb",
		"hand": "handslot.r", "scale": 0.75,
		"rotation": Vector3(45.0, 26.9, 60.1), "offset": Vector3(0.0, 0.0, 0.05),
		"tip": Vector3(0.0, 0.5, 0.0), "lean": 10.0,
		"glow": Color(1.0, 0.32, 0.28), "glow_energy": 0.9,
		"description": "Красный кристалл на конце.",
	},
	7: {
		"id": 7, "class": 0, "name": "Стальной меч",
		"rarity": "Обычное", "price": 400,
		"icon": "res://addons/low_poly_rpg_items/icons/longsword.png",
		"builtin": false,
		"shop_enabled": false,
		"model": "res://addons/low_poly_rpg_items/models/longsword_model.glb",
		"hand": "handslot.r", "scale": 1.0,
		"rotation": Vector3(45.6, 27.7, 60.8), "offset": Vector3(0.0, 0.0, 0.05),
		"tip": Vector3(0.0, 0.5, 0.0), "roll": 90.0, "lean": 6.0,
		"glow": Color(0.0, 0.0, 0.0), "glow_energy": 0.0,
		"description": "Чистая сталь без магии.",
	},
	8: {
		"id": 8, "class": 2, "name": "Эльфийский лук",
		"rarity": "Легендарное", "price": 800,
		"icon": "res://ui/icons/legendary_bow.png",
		"builtin": false,
		"shop_enabled": false,
		"model": "res://scenes/LegendaryBow.tscn",
		"hand": "handslot.l", "scale": 1.43,
		"rotation": Vector3(-47.4, 6.4, -3.39), "offset": Vector3(0.06, -0.02, -0.04),
		"tip": Vector3(0.0, 0.5, 0.0), "roll": -16.98,
		"glow": Color(0.62, 0.26, 1.0), "glow_energy": 1.2,
		"description": "Фиолетовое сияние эльфов.",
	},
	9: {
		"id": 9, "class": 1, "name": "Кристальный посох",
		"rarity": "Обычное", "price": 400,
		"icon": "res://ui/icons/crystal_staff.png",
		"builtin": false,
		"shop_enabled": true,
		"model": "res://assets/weapons/wizards_staff_low.glb",
		"hand": "handslot.r", "scale": 0.65,
		"rotation": Vector3(45.0, 26.9, 60.1), "offset": Vector3(0.0, 0.0, 0.05),
		"tip": Vector3(0.0, 0.0, 1.0),
		"glow": Color(0.0, 0.0, 0.0), "glow_energy": 0.0,
		"description": "Тяжёлый кристалл без свечения.",
	},
}

const ORDER := [1, 2, 3, 4, 5, 6, 7, 8, 9]
const CLASS_KEYS := ["warrior", "mage", "fairy"]

# Local transform of the built-in fairy crossbows under handslot_l. Tuned in
# tools/WeaponTuner.tscn; the values are mirrored from the original right-hand
# attachment so the crossbow points forward in the left hand.
const CROSSBOW_TUNING := {
	"1H_Crossbow": {
		"position": Vector3(0.104628, -0.010374, 0.0),
		"rotation": Vector3(0.0, -90.0, 0.0),
		"roll": 0.0,
		"scale": 1.0,
	},
	"2H_Crossbow": {
		"position": Vector3(0.104628, -0.010374, 0.0),
		"rotation": Vector3(0.0, -90.0, 0.0),
		"roll": 0.0,
		"scale": 1.0,
	},
}


static func crossbow_tuning(mesh_name: String) -> Dictionary:
	return CROSSBOW_TUNING.get(mesh_name, {})


static func get_item(item_id: int) -> Dictionary:
	return ITEMS.get(item_id, {})


static func items_for_class(hero_class: int) -> Array:
	var result: Array = []
	for item_id in ORDER:
		var item: Dictionary = ITEMS[item_id]
		if int(item["class"]) != hero_class:
			continue
		if not bool(item.get("shop_enabled", true)):
			continue
		result.append(item)
	return result


static func class_key(hero_class: int) -> String:
	if hero_class < 0 or hero_class >= CLASS_KEYS.size():
		return ""
	return String(CLASS_KEYS[hero_class])


static func item_ids_for_class(hero_class: int) -> Array[int]:
	var result: Array[int] = []
	for item_id in ORDER:
		var item: Dictionary = ITEMS[item_id]
		if int(item["class"]) != hero_class:
			continue
		if not bool(item.get("shop_enabled", true)):
			continue
		result.append(item_id)
	return result


static func all_item_ids_for_class(hero_class: int) -> Array[int]:
	var result: Array[int] = []
	for item_id in ORDER:
		var item: Dictionary = ITEMS[item_id]
		if int(item["class"]) != hero_class:
			continue
		result.append(item_id)
	return result
