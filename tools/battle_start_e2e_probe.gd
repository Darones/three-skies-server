extends Node

## End-to-end battle-start probe (read-only QA tool).
##
## Runs the real flow — LoadingScreen (match search + WarmupFlow) → Main — and
## measures what the player actually gets at the start of the match:
##  * per-frame wall time from the moment Main opens through live + 3 s,
##  * when the loading screen handed its preloaded assets to the keeper and how
##    much it holds (the fix for the ~300 ms fighter-spawn frame),
##  * when music/ambient/battle-start SFX start playing and when the Master bus
##    first carries sound.
##
## Run windowed:
##   godot_console --path . tools/BattleStartE2EProbe.tscn -- --layout=1440x734 --tag=e2e-desktop
##   godot_console --path . --rendering-method gl_compatibility tools/BattleStartE2EProbe.tscn -- --mobile --layout=844x390 --quality=low --tag=e2e-mobile-compat
##   ... --no-keep-battle-assets   (pre-fix control)
##
## Writes res://docs/qa-battle-start/e2e_<tag>.json + .png and prints
## BATTLE_START_E2E=...

const OUT_DIR := "res://docs/qa-battle-start"
const AUDIBLE_DB := -45.0
const OBSERVE_LIVE_MS := 5000.0

var target := Vector2i(1440, 734)
var force_mobile := false
var quality := "high"
var tag := "e2e"
var no_vsync := true
var keeper_check := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout="):
			var parts := arg.trim_prefix("--layout=").split("x")
			if parts.size() == 2:
				target = Vector2i(int(parts[0]), int(parts[1]))
		elif arg == "--mobile":
			force_mobile = true
		elif arg.begins_with("--quality="):
			quality = arg.trim_prefix("--quality=")
		elif arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
		elif arg == "--vsync":
			no_vsync = false
		elif arg == "--keeper-check":
			keeper_check = true
	if force_mobile or target.x < 500:
		DeviceProfile.mobile_ui = true
		DeviceProfile.touch_controls = true
		get_tree().root.content_scale_size = Vector2i(960, 540)
	else:
		DeviceProfile.mobile_ui = false
		get_tree().root.content_scale_size = target
	if not quality.is_empty() and DeviceProfile.QUALITY_VALUES.has(quality):
		DeviceProfile.graphics_quality = quality
		DeviceProfile.quality_override = ""
	DeviceProfile.apply_graphics_quality()
	DisplayServer.window_set_size(target)
	if no_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for _i in 3:
		await get_tree().process_frame

	# The normal bot-flow match: no server, no tutorial.
	get_tree().set_meta("tutorial_mode", false)
	get_tree().set_meta("network_play", false)
	get_tree().set_meta("selected_class", 0)
	get_tree().set_meta("selected_team", 0)
	get_tree().set_meta("battle_prewarmed", false)
	get_tree().set_meta("fill_with_bots", false)

	var watcher := Watcher.new()
	watcher.name = "BattleStartE2EWatcher"
	watcher.tag = tag
	watcher.target = target
	get_tree().root.add_child(watcher)
	get_tree().change_scene_to_file.call_deferred("res://scenes/LoadingScreen.tscn")


## Lives on the SceneTree root, so it survives the switch to Main.
class Watcher extends Node:
	var tag := "e2e"
	var target := Vector2i(1440, 734)
	var phase := "boot"
	var loading: Node = null
	var game: Node = null

	var search_done_at := -1
	var main_at_usec := 0
	var live_at_usec := 0
	var prev_usec := 0
	var prev_audio := {}
	var prev_state := ""
	var frames: Array = []
	var events: Array = []

	var keeper_held := -1
	var keeper_seen := false
	var audio_stats := {
		"first_audible_at_ms": -1.0,
		"first_audible_db": 0.0,
		"first_sfx_at_ms": -1.0,
		"music_playing_at_live": false,
		"music_position_at_live_ms": -1.0,
		"music_restarts": 0,
	}
	var done := false
	var failures := 0
	var shot := ""


	func _ready() -> void:
		process_priority = 1000
		_started = Time.get_ticks_msec()

	var _started := 0


	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var wall_ms := 0.0
		if prev_usec > 0:
			wall_ms = float(now - prev_usec) / 1000.0
		prev_usec = now
		# Watchdog: never leave the probe (and the machine) running if the flow
		# or the match stalls; the report then says where it stopped.
		if not done and Time.get_ticks_msec() - _started > 120000:
			_event("timeout", phase, now)
			_finish()
			return
		if phase == "boot":
			var scene := get_tree().current_scene
			if scene != null and scene.name == "LoadingScreen":
				loading = scene
				phase = "search"
			return
		if phase == "search":
			_watch_search()
			return
		if phase == "main" and not done:
			_record_frame(now, wall_ms)
			_poll_game(now)


	func _watch_search() -> void:
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Main":
			game = scene
			main_at_usec = Time.get_ticks_usec()
			frames.clear()
			prev_usec = main_at_usec
			prev_state = ""
			phase = "main"
			_event("main_open", "", main_at_usec)
			_detect_keeper()
			return
		if not is_instance_valid(loading):
			return
		var flow := loading.get_node_or_null("WarmupFlow")
		if flow != null and search_done_at < 0:
			var percent := float(flow.get("_progress"))
			# Shorten the 15 s bot search so the run stays quick; the flow keeps
			# pacing itself, the transition waits for it exactly as in the game.
			if percent >= 55.0 or (percent >= 20.0 and Time.get_ticks_msec() - _started > 20000):
				search_done_at = Time.get_ticks_msec()
				loading.call("_complete_match_search")
		if search_done_at < 0 and Time.get_ticks_msec() - _started > 45000:
			# Safety: never hang the probe on the search screen.
			search_done_at = Time.get_ticks_msec()
			loading.call("_complete_match_search")


	func _detect_keeper() -> void:
		for child in get_tree().root.get_children():
			if String(child.name).begins_with("BattleAssetKeeper"):
				keeper_seen = true
				var held: Variant = child.get("held")
				if held is Array:
					keeper_held = (held as Array).size()
				_event("keeper", "held=%d" % keeper_held, Time.get_ticks_usec())
				return
		_event("keeper", "none", Time.get_ticks_usec())


	func _record_frame(now: int, wall_ms: float) -> void:
		var state := ""
		if game != null and is_instance_valid(game):
			state = String(game.get("state"))
			if state != prev_state:
				prev_state = state
				_event("state", state, now)
				if state == "live" and live_at_usec == 0:
					live_at_usec = now
					var music = game.get("music")
					if music is AudioStreamPlayer:
						audio_stats["music_playing_at_live"] = (music as AudioStreamPlayer).playing
						audio_stats["music_position_at_live_ms"] = snappedf(
							float((music as AudioStreamPlayer).get_playback_position()) * 1000.0, 0.1
						)
					_event("live", "", now)
		var master := AudioServer.get_bus_index("Master")
		var db := -80.0
		if master >= 0:
			db = float(AudioServer.get_bus_peak_volume_left_db(master, 0))
		if live_at_usec > 0 and db > AUDIBLE_DB and float(audio_stats["first_audible_at_ms"]) < 0.0:
			audio_stats["first_audible_at_ms"] = snappedf(float(now - live_at_usec) / 1000.0, 1.0)
			audio_stats["first_audible_db"] = snappedf(db, 0.1)
			_event("audible", "%.1f dB" % db, now)
		frames.append({
			"t_ms": snappedf(float(now - main_at_usec) / 1000.0, 1.0),
			"since_live_ms": snappedf(float(now - live_at_usec) / 1000.0, 1.0) if live_at_usec > 0 else -1.0,
			"frame_ms": snappedf(wall_ms, 0.01),
			"master_db": snappedf(db, 0.1),
			"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"video_mb": snappedf(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 0.1),
		})
		if live_at_usec > 0 and float(now - live_at_usec) / 1000.0 > OBSERVE_LIVE_MS:
			_finish()


	func _poll_game(now: int) -> void:
		if game == null or not is_instance_valid(game):
			return
		var music = game.get("music")
		if music is AudioStreamPlayer:
			_poll_player(music, "music", now)
		var ambient: Variant = game.get("ambient")
		if ambient is AudioStreamPlayer:
			_poll_player(ambient as AudioStreamPlayer, "ambient", now)
		for player in game.get("sfx_players"):
			_poll_player(player, "game_sfx", now)


	func _poll_player(player: Node, label: String, now: int) -> void:
		var stream_player := player as AudioStreamPlayer
		if stream_player == null:
			return
		var id := stream_player.get_instance_id()
		var playing := stream_player.playing
		if playing and not bool(prev_audio.get(id, false)):
			var file := ""
			if stream_player.stream != null:
				file = stream_player.stream.resource_path.get_file()
			_event("audio_play", "%s %s" % [label, file], now)
			if label == "music":
				audio_stats["music_restarts"] = int(audio_stats["music_restarts"]) + 1
			elif label == "game_sfx" and float(audio_stats["first_sfx_at_ms"]) < 0.0 and live_at_usec > 0:
				audio_stats["first_sfx_at_ms"] = snappedf(float(now - live_at_usec) / 1000.0, 1.0)
		prev_audio[id] = playing


	func _event(kind: String, detail: String, at_usec: int) -> void:
		events.append({
			"t_ms": snappedf(float(at_usec - main_at_usec) / 1000.0, 1.0) if main_at_usec > 0 else 0.0,
			"kind": kind,
			"detail": detail,
		})


	func _window(from_ms: float, to_ms: float) -> Dictionary:
		var values: Array[float] = []
		for frame in frames:
			var at := float(frame["t_ms"])
			if at >= from_ms and at < to_ms:
				values.append(float(frame["frame_ms"]))
		if values.is_empty():
			return {}
		values.sort()
		var total := 0.0
		var over_16 := 0
		var over_33 := 0
		var over_50 := 0
		for value in values:
			total += value
			if value > 16.67:
				over_16 += 1
			if value > 33.34:
				over_33 += 1
			if value > 50.0:
				over_50 += 1
		return {
			"frames": values.size(),
			"avg_ms": snappedf(total / float(values.size()), 0.01),
			"p95_ms": snappedf(values[mini(values.size() - 1, int(float(values.size()) * 0.95))], 0.01),
			"max_ms": snappedf(values[values.size() - 1], 0.01),
			"over_16": over_16,
			"over_33": over_33,
			"over_50": over_50,
		}


	func _finish() -> void:
		if done:
			return
		done = true
		_save_shot()
		var live_t := float(live_at_usec - main_at_usec) / 1000.0 if live_at_usec > 0 else -1.0
		var summary := {
			"tag": tag,
			"window": [target.x, target.y],
			"mobile": DeviceProfile.mobile_ui,
			"quality": DeviceProfile.effective_quality(),
			"keeper_seen": keeper_seen,
			"keeper_held": keeper_held,
			"main_to_live_ms": snappedf(live_t, 1.0),
			"audio": audio_stats,
			"frames": {
				"prelive": _window(0.0, maxf(0.1, live_t)),
				"live_0_3000": _window(live_t, live_t + 3000.0),
				"live_0_5000": _window(live_t, live_t + OBSERVE_LIVE_MS),
				"all": _window(0.0, 1.0e9),
			},
			"events": events,
			"screenshot": shot,
		}
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
		var path := "%s/e2e_%s.json" % [OUT_DIR, tag]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(summary, "  "))
			file.close()
		print("BATTLE_START_E2E=", JSON.stringify({
			"tag": tag,
			"keeper_seen": keeper_seen,
			"keeper_held": keeper_held,
			"main_to_live_ms": summary["main_to_live_ms"],
			"prelive": summary["frames"]["prelive"],
			"live_0_3000": summary["frames"]["live_0_3000"],
			"live_0_5000": summary["frames"]["live_0_5000"],
			"audio": audio_stats,
			"source": path,
		}))
		print("BATTLE_START_E2E_FAILURES=%d" % failures)
		if OS.get_cmdline_user_args().has("--keeper-check"):
			await _wait_for_keeper_release()
		get_tree().quit(0)


	## Proves the keeper does not leak: after its keep window it frees itself and
	## drops the references, and static memory comes back down.
	func _wait_for_keeper_release() -> void:
		var before_mb := float(OS.get_static_memory_usage()) / 1048576.0
		var deadline := Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < deadline:
			var found := false
			for child in get_tree().root.get_children():
				if String(child.name).begins_with("BattleAssetKeeper"):
					found = true
					break
			if not found:
				break
			await get_tree().process_frame
		await get_tree().process_frame
		var after_mb := float(OS.get_static_memory_usage()) / 1048576.0
		print("BATTLE_START_KEEPER_RELEASED={\"before_mb\":%.1f,\"after_mb\":%.1f}" % [before_mb, after_mb])


	func _save_shot() -> void:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image == null:
			return
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
		var path := "%s/e2e_%s.png" % [OUT_DIR, tag]
		image.save_png(path)
		shot = ProjectSettings.globalize_path(path)
		print("BATTLE_START_E2E_SHOT=", shot)
