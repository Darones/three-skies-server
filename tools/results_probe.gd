extends Node3D

# РЎРЅРёРјР°РµС‚ СЌРєСЂР°РЅ СЂРµР·СѓР»СЊС‚Р°С‚РѕРІ Р±РѕСЏ СЃ Р·Р°РїРѕР»РЅРµРЅРЅРѕР№ СЃС‚Р°С‚РёСЃС‚РёРєРѕР№.

func _ready() -> void:
	get_tree().set_meta("last_match_won", true)
	get_tree().set_meta("last_match_score", [3, 1])
	get_tree().set_meta("last_match_team", 0)
	get_tree().set_meta("last_match_place", 1)
	get_tree().set_meta("last_match_is_mvp", true)
	get_tree().set_meta("selected_class", HeroUnit.Cls.FAIRY)
	get_tree().set_meta("last_match_stats", {
		"kills": 4, "deaths": 2, "damage": 3200, "crystals": 3, "shells": 1,
		"xp": 240, "shards": 150,
	})
	get_tree().set_meta("last_match_players", [
		{"name": "Даронес", "team": 0, "kills": 4, "deaths": 2, "damage": 3200, "crystals": 3, "is_player": true},
		{"name": "Тёмный Лис", "team": 0, "kills": 2, "deaths": 3, "damage": 1800, "crystals": 1, "is_player": false},
		{"name": "Искра", "team": 0, "kills": 1, "deaths": 4, "damage": 900, "crystals": 0, "is_player": false},
		{"name": "Северный Ветер", "team": 1, "kills": 3, "deaths": 2, "damage": 2400, "crystals": 1, "is_player": false},
		{"name": "Белый Ворон", "team": 1, "kills": 2, "deaths": 3, "damage": 1500, "crystals": 0, "is_player": false},
		{"name": "Пепел", "team": 1, "kills": 0, "deaths": 5, "damage": 600, "crystals": 0, "is_player": false},
	])

	var packed := load("res://scenes/ResultsScreen.tscn") as PackedScene
	var scene := packed.instantiate()
	add_child(scene)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/results_full.png")
	print("RESULTS_PROBE_DONE")
	get_tree().quit()

