extends Node3D

## D1 lobby checks: rules entry point, first-play tutorial routing, the novice
## status plate, welcome-card gating and the still-clean standalone shop.
## Restores tutorial.cfg and every MetaProgression value it touches afterwards.

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

	# --- Novice status plate ------------------------------------------------
	# Visible while the server profile is in the novice pool, hidden for a
	# returning profile and after ten matches. It must never cover the cards.
	var old_novice: bool = MetaProgression.novice
	var old_played: int = MetaProgression.matches_played
	var novice_status := lobby.get("novice_status") as Control
	_check(novice_status != null, "lobby novice status exists")
	if novice_status != null:
		MetaProgression.novice = true
		MetaProgression.matches_played = 0
		MetaProgression.tutorial_completed = true
		lobby.call("_refresh_novice_status")
		await get_tree().process_frame
		_check(novice_status.visible, "novice status shows on the first lobby after the tutorial")
		var novice_title := novice_status.find_child("NoviceStatusTitle", true, false) as Label
		_check(novice_title != null and novice_title.text.contains("0 из 10"), "novice status shows progress 0 of 10")
		MetaProgression.tutorial_completed = false
		MetaProgression.tutorial_skipped = true
		lobby.call("_refresh_novice_status")
		_check(novice_status.visible, "novice status shows after skipping the tutorial")
		MetaProgression.tutorial_skipped = false
		MetaProgression.novice = true
		MetaProgression.matches_played = 3
		lobby.call("_refresh_novice_status")
		_check(novice_title != null and novice_title.text.contains("3 из 10"), "novice status counts played matches")
		var covers_cards := false
		for card in lobby.get("cards"):
			if novice_status.get_global_rect().intersects((card as Control).get_global_rect()):
				covers_cards = true
		_check(not covers_cards, "novice status does not cover the hero cards")
		MetaProgression.novice = false
		lobby.call("_refresh_novice_status")
		_check(not novice_status.visible, "novice status hides for a non-novice profile")
		MetaProgression.novice = true
		MetaProgression.matches_played = 10
		lobby.call("_refresh_novice_status")
		_check(not novice_status.visible, "novice status hides after 10 matches")
		MetaProgression.novice = old_novice
		MetaProgression.matches_played = old_played
		lobby.call("_refresh_novice_status")

	# --- Welcome card gating ------------------------------------------------
	# The card is enabled only for a lobby that is the scene root, so reparent
	# for these checks and put the lobby back afterwards.
	var old_loaded: bool = MetaProgression.profile_loaded
	var old_seen: bool = MetaProgression.welcome_seen
	var old_completed: bool = MetaProgression.tutorial_completed
	var old_skipped: bool = MetaProgression.tutorial_skipped
	var old_matches: int = MetaProgression.matches_played
	var old_api: String = NetworkClient.api_base_url
	NetworkClient.api_base_url = "http://127.0.0.1:9"
	MetaProgression.profile_loaded = true
	MetaProgression.welcome_seen = false
	MetaProgression.matches_played = 0
	MetaProgression.tutorial_completed = false
	MetaProgression.tutorial_skipped = false
	lobby.reparent(get_tree().root)
	lobby.call("_refresh_welcome_overlay")
	await get_tree().process_frame
	var welcome := lobby.get("welcome_overlay") as Control
	_check(welcome != null and bool(welcome.call("is_welcome_visible")), "welcome card shows for a new player")
	MetaProgression.tutorial_completed = true
	lobby.call("_refresh_welcome_overlay")
	_check(not bool(welcome.call("is_welcome_visible")), "welcome stays hidden after the tutorial")
	MetaProgression.tutorial_completed = false
	MetaProgression.tutorial_skipped = true
	lobby.call("_refresh_welcome_overlay")
	_check(not bool(welcome.call("is_welcome_visible")), "welcome stays hidden after skipping the tutorial")
	MetaProgression.tutorial_skipped = false
	MetaProgression.matches_played = 1
	MetaProgression.welcome_seen = true
	lobby.call("_refresh_welcome_overlay")
	_check(not bool(welcome.call("is_welcome_visible")), "returning player does not see the welcome card")
	lobby.reparent(self)
	lobby.call("_refresh_welcome_overlay")
	if welcome != null:
		welcome.call("hide_overlay")
	MetaProgression.profile_loaded = old_loaded
	MetaProgression.welcome_seen = old_seen
	MetaProgression.matches_played = old_matches
	MetaProgression.tutorial_completed = old_completed
	MetaProgression.tutorial_skipped = old_skipped
	NetworkClient.api_base_url = old_api
	await get_tree().process_frame

	var old_completed_now: bool = MetaProgression.tutorial_completed
	var old_skipped_now: bool = MetaProgression.tutorial_skipped
	MetaProgression.tutorial_completed = false
	MetaProgression.tutorial_skipped = false

	var old_matches_now: int = MetaProgression.matches_played
	var old_stats: int = int(MetaProgression.stats_all.get("matches", 0))
	MetaProgression.matches_played = 0
	MetaProgression.stats_all["matches"] = 0
	_check(lobby.call("_should_force_tutorial"), "new player is sent to the tutorial")
	MetaProgression.stats_all["matches"] = 1
	_check(not lobby.call("_should_force_tutorial"), "existing player is not forced into the tutorial")
	MetaProgression.matches_played = old_matches_now
	MetaProgression.stats_all["matches"] = old_stats
	MetaProgression.tutorial_completed = old_completed_now
	MetaProgression.tutorial_skipped = old_skipped_now
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
