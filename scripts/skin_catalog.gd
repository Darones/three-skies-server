extends RefCounted

## Cosmetic hero skins. Unlocks are stored in the existing server weapons
## array as 100 + skin_id (101, 102), so no DB migration is needed.

const ITEMS := {
	1: {
		"id": 1, "class": 0, "name": "Варвар", "short_name": "Варвар",
		"rarity": "Скин", "price": 1000,
		"icon": "res://ui/icons/skin_barbarian.png",
		"model": "res://art/generated/warrior_barbarian/character.tscn",
		"default_gear": ["1H_Axe", "1H_Axe_Offhand"],
		"legendary_gear": ["2H_Axe"],
		"description": "Дикие топоры, меховая шапка и ярость севера.",
	},
	2: {
		"id": 2, "class": 2, "name": "Арбалетчица в капюшоне", "short_name": "Арбалетчица",
		"rarity": "Скин", "price": 1000,
		"icon": "res://ui/icons/skin_archer_hood.png",
		"model": "res://art/generated/fairy_hooded/character.tscn",
		"default_gear": ["1H_Crossbow"],
		"legendary_gear": ["2H_Crossbow"],
		"description": "Лесной капюшон и тёмный плащ.",
	},
}

const ORDER := [1, 2]
const UNLOCK_BASE := 100


static func get_item(skin_id: int) -> Dictionary:
	return ITEMS.get(skin_id, {})


static func items_for_class(hero_class: int) -> Array:
	var result: Array = []
	for skin_id in ORDER:
		if int(ITEMS[skin_id]["class"]) == hero_class:
			result.append(ITEMS[skin_id])
	return result


static func unlock_id(skin_id: int) -> int:
	return UNLOCK_BASE + skin_id
