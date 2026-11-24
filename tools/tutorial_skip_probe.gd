extends Node3D

## Checks the skip dialog and the persisted skip flag without leaving the
## current scene. The original tutorial.cfg is restored afterwards.

var failures := 0
var backup := ""
var had_backup := false


func _ready() -> void:
	if FileAccess.file_exists("user://tutorial.cfg"):
		had_backup = true
		backup = FileAccess.get_file_as_string("user://tutorial.cfg")
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
	tutorial.call("request_skip")
	await get_tree().process_frame
	var overlay: Control = game.hud.get("tutorial_overlay")
	var secondary: Button = game.hud.get("tutorial_secondary_button")
	var skip_button: Button = game.hud.get("tutorial_skip_button")
	_check(overlay != null and overlay.visible, "skip choice card opens")
	_check(secondary != null and secondary.text == "Пропустить", "skip choice has the skip action")
	_check(skip_button != null and not skip_button.visible, "skip button hides behind the choice")
	tutorial.call("_cancel_skip")
	await get_tree().process_frame
	_check(overlay != null and not overlay.visible, "cancel closes the skip choice")
	_check(skip_button != null and skip_button.visible, "skip button returns after cancel")
	tutorial.call("_save_skip")
	var config := ConfigFile.new()
	_check(config.load("user://tutorial.cfg") == OK, "tutorial.cfg is readable")
	_check(bool(config.get_value("tutorial", "skipped", false)), "skip flag is saved")
	_check(not bool(config.get_value("tutorial", "completed", false)), "skip does not mark completion")
	_restore()
	_finish()


func _restore() -> void:
	if had_backup:
		var file := FileAccess.open("user://tutorial.cfg", FileAccess.WRITE)
		if file != null:
			file.store_string(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tutorial.cfg"))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _finish() -> void:
	print("TUTORIAL_SKIP_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
