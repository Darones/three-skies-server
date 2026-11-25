extends Node3D

## D1 Shell finale: separate from 3v3, only after the player leaves the centre,
## 3s telegraph, passive Shell, shard delivery completes the tutorial.

var failures := 0


func _ready() -> void:
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("selected_class", HeroUnit.Cls.WARRIOR)
	get_tree().set_meta("selected_team", 0)
	var game := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 4:
		await get_tree().process_frame
	var tutorial: Node = game.get("tutorial_controller")
	_check(tutorial != null, "tutorial controller created")
	if tutorial == null:
		_finish()
		return
	game.player.global_position = Vector3(0.0, 0.76, 0.0)
	tutorial.set("stage", "team_fight_final_done")
	tutorial.call("_start_shell_lesson")
	_check(String(tutorial.get("stage")) == "shell_intro", "finale card shown")
	tutorial.call("_begin_shell_prepare")
	_check(String(tutorial.get("stage")) == "shell_telegraph", "shell telegraph starts immediately")
	_check(game.shell == null, "no shell during the telegraph")
	await get_tree().create_timer(2.3).timeout
	_check(String(tutorial.get("stage")) == "destroy_shell", "telegraph spawns the shell")
	_check(game.shell != null and is_instance_valid(game.shell), "shell exists")
	if game.shell != null and is_instance_valid(game.shell):
		_check(game.shell.max_health == 1000.0, "shell starts at 1000 HP")
		game.shell.take_damage(99999.0, game.player)
	await get_tree().create_timer(0.6).timeout
	_check(String(tutorial.get("stage")) == "pick_crystal", "shell death starts pickup")
	if game.crystal_node != null and is_instance_valid(game.crystal_node):
		game.player.global_position = game.crystal_node.global_position
		await get_tree().create_timer(0.8).timeout
	_check(game.carrier == game.player, "player picks up the shard")
	game.player.global_position = Vector3(0.0, 0.76, float(game.BASE_POSITION_Z))
	await get_tree().create_timer(1.2).timeout
	_check(bool(tutorial.get("completed")), "tutorial completes after delivery")
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _finish() -> void:
	print("TUTORIAL_FINAL_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
