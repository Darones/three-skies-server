extends Node3D

## Bush stealth probe.
##
## Covers the 2 m reveal radius and names in bushes for three cases:
##   * a local HeroUnit in a bush is hidden (name + half-faded model) while the
##     enemy is 2.1 m away and revealed at 1.9 m,
##   * an ally in a bush loses its nickname too (like the minimap dot), while
##     the local player's own nickname never hides,
##   * a RemotePlayer (no physics body) inside a bush is tracked by position:
##     far -> name/HP bar hidden, near (<=2 m) -> visible, attack or damage ->
##     revealed for 3 s. Network interpolation keeps running meanwhile.
##
## Prints PASS/FAIL and exits non-zero on any failure.

var failures := 0
var checks := 0
var game: Node = null
var player: HeroUnit = null


func _ready() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	game = packed.instantiate()
	add_child(game)
	for _i in 14:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	# start_match now opens the match behind the class-select panel and may wait
	# briefly for the first-clash warm (bounded, ~1.2 s at most) instead of
	# blocking for up to 10 s. Wait for the real state: the remote/bush checks
	# below only run from game._process while the match is live.
	var live_deadline := Time.get_ticks_msec() + 5000
	while String(game.get("state")) != "live" and Time.get_ticks_msec() < live_deadline:
		await get_tree().process_frame
	for _i in 6:
		await get_tree().process_frame
	player = game.get("player") as HeroUnit
	if player == null:
		print("FAIL: no local player")
		get_tree().quit(1)
		return

	_check(is_equal_approx(HeroUnit.BUSH_PROXIMITY_REVEAL, 2.0), "BUSH_PROXIMITY_REVEAL == 2.0")

	await _case_hero_in_bush()
	await _case_ally_name()
	await _case_remote_player()

	print("BUSH_STEALTH_CHECKS=%d FAILURES=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _case_hero_in_bush() -> void:
	print("--- hero in bush: 1.9 m vs 2.1 m ---")
	var zone := _bush_zone(0)
	var enemy := _enemy_bot()
	if zone == null or enemy == null:
		_check(false, "bush zone and enemy bot exist")
		return
	_park_everyone([enemy])
	enemy.bush_reveal_timer = 0.0
	enemy.global_position = zone.global_position + Vector3(0.0, 0.76, 0.0)
	player.global_position = zone.global_position + Vector3(6.5, 0.76, 0.0)
	await _settle()
	_check(enemy.in_bush, "enemy bot registered inside BushZone via body_entered")
	_check(enemy._is_bush_stealthed(), "enemy concealed at 6.5 m")
	enemy._refresh_bush_visibility()
	enemy._update_name_visibility()
	_check(not enemy.name_label.visible, "enemy name hidden while concealed in bush")
	_check(_mesh_transparency(enemy) >= 0.49, "enemy model half-faded while concealed (%.2f)" % _mesh_transparency(enemy))

	player.global_position = enemy.global_position + Vector3(1.9, 0.0, 0.0)
	enemy._update_name_visibility()
	_check(not enemy._is_bush_stealthed(), "enemy at 1.9 m sees through the bush")
	_check(enemy.name_label.visible, "enemy name visible at 1.9 m")

	player.global_position = enemy.global_position + Vector3(2.1, 0.0, 0.0)
	enemy._update_name_visibility()
	_check(enemy._is_bush_stealthed(), "enemy at 2.1 m does not see the hero")
	_check(not enemy.name_label.visible, "enemy name hidden again at 2.1 m")

	# A hit breaks the concealment for 3 s at any distance.
	player.global_position = zone.global_position + Vector3(6.5, 0.76, 0.0)
	enemy.take_damage(1.0, null)
	enemy._update_name_visibility()
	_check(enemy.bush_reveal_timer > 0.0, "taking damage starts the 3 s reveal timer")
	_check(not enemy._is_bush_stealthed(), "damaged hero is revealed in the bush")
	_check(enemy.name_label.visible, "damaged hero name is visible")


func _case_ally_name() -> void:
	print("--- ally name in bush ---")
	var zone := _bush_zone(1)
	var ally := _ally_bot()
	if zone == null or ally == null:
		_check(false, "bush zone and ally bot exist")
		return
	_park_everyone([ally])
	ally.bush_reveal_timer = 0.0
	ally.global_position = zone.global_position + Vector3(0.0, 0.76, 0.0)
	player.global_position = zone.global_position + Vector3(6.5, 0.76, 0.0)
	await _settle()
	_check(ally.in_bush, "ally bot registered inside the bush")
	ally._update_name_visibility()
	_check(not ally.name_label.visible, "ally name hidden in bush (minimap behaviour)")

	# The local player's own name stays visible even inside the bush.
	player.global_position = zone.global_position + Vector3(0.0, 0.76, 0.0)
	await _settle()
	player._update_name_visibility()
	_check(player.name_label.visible, "local player's own name stays visible in a bush")


func _case_remote_player() -> void:
	print("--- RemotePlayer in bush ---")
	var zone := _bush_zone(0)
	if zone == null:
		_check(false, "bush zone exists")
		return
	_park_everyone([])
	var bush_pos := zone.global_position + Vector3(0.0, 0.76, 0.0)
	var remote = preload("res://scripts/remote_player.gd").new()
	remote.name = "BushRemoteProbe"
	game.add_child(remote)
	remote.game = game
	remote.setup(9001, {
		"name": "RemoteGuest",
		"class": HeroUnit.Cls.WARRIOR,
		"team": 1,
		"has_state": true,
		"position": bush_pos,
		"rotation": 0.0,
		"hp": 1050.0,
		"max_hp": 1050.0,
	})
	await get_tree().process_frame
	game.remote_players[9001] = remote
	_check(remote._bush_meshes.size() > 0, "remote model meshes tracked for bush fading")

	player.global_position = zone.global_position + Vector3(7.0, 0.76, 0.0)
	await _settle()
	_check(remote.in_bush, "remote player tracked inside the bush by position")
	_check(remote.bush_hidden, "remote player flagged as hidden while far")
	_check(not remote._name_label.visible, "remote name hidden while far")
	_check(not _tag_bar_drawn(remote._name_label), "remote HP bar hidden while far")
	_check(_remote_transparency(remote) >= 0.49, "remote model half-faded while hidden (%.2f)" % _remote_transparency(remote))

	player.global_position = remote.global_position + Vector3(1.9, 0.0, 0.0)
	await _settle()
	_check(not remote.is_bush_concealed(), "remote revealed when the local player is 1.9 m away")
	_check(remote._name_label.visible, "remote name visible at 1.9 m")
	_check(_tag_bar_drawn(remote._name_label), "remote HP bar visible at 1.9 m")
	_check(_remote_transparency(remote) <= 0.01, "remote model opaque at 1.9 m")

	player.global_position = zone.global_position + Vector3(7.0, 0.76, 0.0)
	await _settle()
	_check(not remote._name_label.visible, "remote hidden again when the player walks away")

	remote.play_attack("attack")
	_check(remote.bush_reveal_timer > 0.0, "remote attack starts the 3 s reveal timer")
	_check(remote._name_label.visible, "remote attack reveals the name")

	remote.bush_reveal_timer = 0.0
	remote._refresh_bush_visuals()
	_check(not remote._name_label.visible, "remote hides again after the reveal timer")

	remote.apply_network_damage(10.0, false)
	_check(remote.bush_reveal_timer > 0.0, "remote damage starts the 3 s reveal timer")
	_check(remote._name_label.visible, "remote damage reveals the name")

	# Bush tracking must not freeze network interpolation.
	remote.bush_reveal_timer = 0.0
	remote._refresh_bush_visuals()
	var before: Vector3 = remote.global_position
	remote.apply_state(before + Vector3(1.0, 0.0, 0.0), 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(remote.global_position.distance_to(before) > 0.01, "remote interpolation still moves towards the new state")

	game.remote_players.erase(9001)
	remote.queue_free()


func _bush_zone(index: int) -> Area3D:
	var bushes := game.get_node_or_null("Arena/Bushes")
	if bushes == null:
		return null
	var zones: Array[Area3D] = []
	for child in bushes.get_children():
		if child is Area3D and String(child.name).begins_with("BushZone_"):
			zones.append(child as Area3D)
	if index < 0 or index >= zones.size():
		return null
	return zones[index]


func _enemy_bot() -> HeroUnit:
	for hero in game.get("heroes"):
		if hero is HeroUnit and not hero.is_player and int(hero.team) != int(player.team) and not hero.dead:
			return hero as HeroUnit
	return null


func _ally_bot() -> HeroUnit:
	for hero in game.get("heroes"):
		if hero is HeroUnit and not hero.is_player and int(hero.team) == int(player.team) and not hero.dead:
			return hero as HeroUnit
	return null


func _park_everyone(keep: Array) -> void:
	for hero in game.get("heroes"):
		if hero == null or not is_instance_valid(hero) or hero is not HeroUnit:
			continue
		var unit := hero as HeroUnit
		unit.set_physics_process(false)
		if unit in keep:
			continue
		var base_z := 26.0 if int(unit.team) == 0 else -26.0
		unit.global_position = Vector3(6.0, 0.76, base_z)
		unit.bush_zones.clear()
		unit.in_bush = false
		unit.bush_reveal_timer = 0.0


func _settle() -> void:
	for _i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame


func _mesh_transparency(hero: HeroUnit) -> float:
	var best := 0.0
	if hero.visual == null:
		return best
	for child in hero.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh != null:
			best = maxf(best, mesh.transparency)
	return best


func _remote_transparency(remote: Node) -> float:
	var best := 0.0
	var meshes: Array = remote.get("_bush_meshes")
	for mesh_instance in meshes:
		var mesh := mesh_instance as MeshInstance3D
		if mesh != null and is_instance_valid(mesh):
			best = maxf(best, mesh.transparency)
	return best


## The visible HP bar is the 2D one inside the screen-space nickname
## (WorldNameLayer.NameTag), not the hidden 3D compatibility quad. It is a child
## of the label, so it hides and shows exactly with the name.
func _tag_bar_drawn(tag_label) -> bool:
	if tag_label == null or not is_instance_valid(tag_label):
		return false
	var back := tag_label.get("bar_back") as ColorRect
	return back != null and is_instance_valid(back) and back.is_visible_in_tree()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
