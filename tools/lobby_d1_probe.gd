extends Node3D

## D1 lobby checks: rules entry point, first-play tutorial routing, and the
## still-clean standalone shop. Restores tutorial.cfg afterwards.

var failures := 0
var backup := ""
var had_backup := false


func _ready() -> void:
	if FileAccess.file_exists("user://tutorial.cfg"):
		had_backup = true
		backup = FileAccess.get_file_as_string("user://tutorial.cfg")
	var config := ConfigFile.new()
	config.set_value("tutorial", "completed", false)
	config.set_value("tutorial", "skipped", false)
	config.save("user://tutorial.cfg")

	var lobby := (load("res://scenes/Lobby.tscn") as PackedScene).instantiate()
	add_child(lobby)
	for i in 10:
		await get_tree().process_frame
	_check(lobby.get("rules_button") != null, "lobby rules button exists")
	_check(lobby.get("rules_panel") != null, "lobby rules panel exists")
	if lobby.get("rules_panel") != null:
		_check(not lobby.get("rules_panel").visible, "rules panel starts hidden")
		lobby.call("_open_rules")
		await get_tree().process_frame
		_check(lobby.get("rules_panel").visible, "rules panel opens")
		lobby.call("_close_rules")
		_check(not lobby.get("rules_panel").visible, "rules panel closes")
	var topup := lobby.find_child("TopupButton", true, false) as Button
	_check(topup != null and topup.visible, "standalone shop shows the topup placeholder")
	var old_completed: bool = MetaProgression.tutorial_completed
	var old_skipped: bool = MetaProgression.tutorial_skipped
	MetaProgression.tutorial_completed = false
	MetaProgression.tutorial_skipped = false

	var old_matches: int = MetaProgression.matches_played
	var old_stats: int = int(MetaProgression.stats_all.get("matches", 0))
	MetaProgression.matches_played = 0
	MetaProgression.stats_all["matches"] = 0
	_check(lobby.call("_should_force_tutorial"), "new player is sent to the tutorial")
	MetaProgression.stats_all["matches"] = 1
	_check(not lobby.call("_should_force_tutorial"), "existing player is not forced into the tutorial")
	MetaProgression.matches_played = old_matches
	MetaProgression.stats_all["matches"] = old_stats
	MetaProgression.tutorial_completed = old_completed
	MetaProgression.tutorial_skipped = old_skipped
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
	print("LOBBY_D1_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
