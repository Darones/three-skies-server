extends Node3D

# РђРІС‚РѕРјР°С‚РёС‡РµСЃРєРёР№ РїСЂРѕРіРѕРЅ РјР°С‚С‡Р° СЃ Р±РѕС‚Р°РјРё: СЃРѕР±РёСЂР°РµС‚ СЃС‚Р°С‚РёСЃС‚РёРєСѓ РїРѕ РїРµСЂРµРјРµС‰РµРЅРёСЋ,
# РїСЂРѕСЃС‚РѕСЏРј, СЃРјРµСЂС‚СЏРј Рё РїРѕРєСѓРїРєР°Рј. РќРёС‡РµРіРѕ РІ РёРіСЂРµ РЅРµ РјРµРЅСЏРµС‚.

var game: Node = null
var samples := {}
var stuck_events := []
var deaths := {}
var kills := {}
var travelled := {}
var last_score := [0, 0]
var score_events := []
var run_seconds := 40.0
var time_scale := 3.0


func _ready() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	game = scene.instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame

	if not game.has_method("start_match"):
		print("PROBE: no start_match")
		get_tree().quit()
		return
	game.call("start_match", HeroUnit.Cls.WARRIOR, 0)
	print("PROBE: match started, heroes=", game.heroes.size())
	Engine.time_scale = time_scale

	var start_ms := Time.get_ticks_msec()
	var next_sample := 0
	while Time.get_ticks_msec() - start_ms < int(run_seconds * 1000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_msec() - start_ms
		if now >= next_sample:
			next_sample += 500
			_sample(now)
		_track_score()

	Engine.time_scale = 1.0
	_report()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://bot_probe.png")
	get_tree().quit()


func _sample(now_ms: int) -> void:
	for hero in game.heroes:
		if hero == null or not is_instance_valid(hero):
			continue
		var key: String = String(hero.display_name)
		var pos: Vector3 = hero.global_position
		if not samples.has(key):
			samples[key] = {"pos": pos, "stuck": 0.0, "was_dead": hero.dead}
			travelled[key] = 0.0
			deaths[key] = 0
			continue
		var data: Dictionary = samples[key]
		if hero.dead and not bool(data["was_dead"]):
			deaths[key] = int(deaths.get(key, 0)) + 1
		data["was_dead"] = hero.dead
		if hero.dead:
			data["pos"] = pos
			continue
		var step := pos.distance_to(data["pos"])
		travelled[key] = float(travelled.get(key, 0.0)) + step
		if step < 0.35:
			data["stuck"] = float(data["stuck"]) + 0.5
		else:
			if float(data["stuck"]) >= 4.0:
				stuck_events.append({
					"who": key,
					"seconds": float(data["stuck"]),
					"at": pos,
				})
			data["stuck"] = 0.0
		data["pos"] = pos


func _track_score() -> void:
	var score: Array = game.score
	if score[0] != last_score[0] or score[1] != last_score[1]:
		score_events.append("%d:%d" % [score[0], score[1]])
		last_score = [score[0], score[1]]


func _report() -> void:
	print("=== BOT REPORT ===")
	print("state=", game.state, " score=", game.score, " time_left=", int(game.match_time))
	print("score_events=", score_events)
	for key in samples.keys():
		var data: Dictionary = samples[key]
		print("%-16s travelled=%5.1f m  stuck_now=%4.1f s  deaths=%d" % [
			key, float(travelled.get(key, 0.0)), float(data["stuck"]),
			int(deaths.get(key, 0)),
		])
	print("STUCK_EVENTS=", stuck_events.size())
	for event in stuck_events:
		print("  stuck ", event["who"], " ", event["seconds"], "s at ", event["at"])
	print("=== END ===")

