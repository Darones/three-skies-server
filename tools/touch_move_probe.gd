extends Node3D

# Проверяет, что виртуальный джойстик реально двигает героя.

var game: Node = null


func _ready() -> void:
	game = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	for i in 10:
		await get_tree().process_frame
	var joystick := get_tree().root.find_child("TouchJoystick", true, false) as Control
	if joystick == null:
		print("TOUCH_MOVE_FAIL no joystick")
		get_tree().quit()
		return
	var start: Vector3 = game.player.global_position
	joystick.call("_update_knob", joystick.size * 0.5 + Vector2(0.0, -70.0))
	await get_tree().create_timer(1.2).timeout
	var finish: Vector3 = game.player.global_position
	joystick.call("_reset")
	print("TOUCH_MOVE distance=", start.distance_to(finish))
	get_tree().quit()
