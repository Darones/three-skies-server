extends Node3D

const MATCH_LENGTH := 300.0
const RESPAWN_TIME := 8.0
const SHELL_WINDOW := 45.0
const CRYSTALS_TO_WIN := 3

const MUSIC_PATH := "res://audio/music/dread/6adcd384-a1c6-4d03-ab8f-2885c6220fd5_music_dark_fantasy_arena_battle_them__1793744175999.mp3"
const SFX_PATHS := {
	"hit": "res://audio/sfx/sword_hit.wav",
	"magic": "res://audio/sfx/magic_burst.wav",
	"thunder": "res://audio/sfx/shell_thunder.wav",
}

var camera: Camera3D
var hud: Node
var heroes: Array[HeroUnit] = []
var player: HeroUnit = null
var shell: SkyShell = null
var crystal_node: Node3D = null
var carrier: HeroUnit = null

var state := "select"
var match_time := MATCH_LENGTH
var score: Array[int] = [0, 0]
var p_kills := 0
var p_deaths := 0
var p_damage := 0.0
var p_crystals := 0
var shell_phase := "idle"
var shell_timer := 8.0
var shell_window := SHELL_WINDOW
var crystal_state := "none"
var crystal_timer := 0.0
var pickup_delay := 0.0
var sudden_death := false
var player_won := false
var result_text := ""
var last_announce := ""

var projectiles: Array = []
var shake_amount := 0.0
var select_angle := 0.6
var camera_pos := Vector3.ZERO
var camera_distance := 16.0
var zoom_speed := 1.0
var min_zoom_distance := 12.0
var max_zoom_distance := 42.0

var music: AudioStreamPlayer
var sfx_streams := {}
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_index := 0


func _ready() -> void:
	randomize()
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.fov = 46.0
	camera_pos = camera.global_position
	if get_node_or_null("Arena") == null:
		var arena := Node3D.new()
		arena.name = "Arena"
		add_child(arena)
		ArenaKit.build(arena)
	_setup_audio()
	hud = preload("res://scripts/hud.gd").new()
	add_child(hud)
	hud.game = self
	hud.name = "HUD"
	var bushes_root := get_node_or_null("Arena/Bushes")
	if bushes_root != null:
		for bush_node in bushes_root.get_children():
			if bush_node is Area3D:
				var bush := bush_node as Area3D
				bush.body_entered.connect(_on_bush_body_entered.bind(bush))
				bush.body_exited.connect(_on_bush_body_exited.bind(bush))
	state = "select"
	if get_tree().has_meta("selected_class"):
		var selected_class := int(get_tree().get_meta("selected_class"))
		if selected_class >= 0 and selected_class <= 2:
			var selected_team := clampi(int(get_tree().get_meta("selected_team", get_meta("selected_team", 0))), 0, 1)
			call_deferred("start_match", selected_class, selected_team)


func _setup_audio() -> void:
	music = AudioStreamPlayer.new()
	music.name = "Music"
	var stream := load(MUSIC_PATH) as AudioStream
	if stream != null:
		music.stream = stream
		music.volume_db = -10.0
		add_child(music)
		music.play()
	for key in SFX_PATHS.keys():
		var s := load(SFX_PATHS[key]) as AudioStream
		if s != null:
			sfx_streams[key] = s
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)


func play_sfx(key: String, volume_db := -4.0) -> void:
	if not sfx_streams.has(key) or sfx_players.is_empty():
		return
	var p := sfx_players[sfx_index]
	sfx_index = (sfx_index + 1) % sfx_players.size()
	p.stream = sfx_streams[key]
	p.volume_db = volume_db
	p.play()


func start_match(player_class: int, requested_team: int = -1) -> void:
	if state != "select":
		return
	p_kills = 0
	p_deaths = 0
	p_damage = 0.0
	p_crystals = 0
	var player_team := requested_team
	if player_team < 0:
		player_team = int(get_tree().get_meta("selected_team", get_meta("selected_team", 0)))
	player_team = clampi(player_team, 0, 1)
	var classes: Array[int] = [HeroUnit.Cls.WARRIOR, HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY]
	var ally_classes: Array[int] = []
	for c in classes:
		if c != player_class:
			ally_classes.append(c)
	var light_spots: Array[Vector3] = [Vector3(-3.0, 0.4, 32.5), Vector3(0.0, 0.4, 32.0), Vector3(3.0, 0.4, 32.5)]
	var dark_spots: Array[Vector3] = [Vector3(3.0, 0.4, -32.5), Vector3(0.0, 0.4, -32.0), Vector3(-3.0, 0.4, -32.5)]
	var own_spots: Array[Vector3] = light_spots if player_team == 0 else dark_spots
	var enemy_spots: Array[Vector3] = dark_spots if player_team == 0 else light_spots
	var enemy_team := 1 - player_team
	player = _spawn_hero(player_class, player_team, true, own_spots[0])
	var ai_index := 1
	for c in ally_classes:
		_spawn_hero(c, player_team, false, own_spots[mini(ai_index, 2)])
		ai_index += 1
	for i in classes.size():
		_spawn_hero(classes[i], enemy_team, false, enemy_spots[mini(i, 2)])
	state = "live"
	match_time = MATCH_LENGTH
	shell_phase = "idle"
	shell_timer = 8.0
	if hud != null:
		hud.hide_class_select()
		announce("Бой за осколки!", Color(1.0, 0.86, 0.55), 2.6)


func _spawn_hero(cls: int, team: int, is_player: bool, pos: Vector3) -> HeroUnit:
	var h := HeroUnit.new()
	h.name = ("Player" if is_player else "%s_%d_%d" % [HeroUnit.CLASS_DATA[cls]["name"], team, heroes.size()])
	add_child(h)
	h.setup(self, cls, team, is_player)
	h.global_position = pos
	h.rotation.y = 0.0 if team == 0 else PI
	heroes.append(h)
	return h


func _process(delta: float) -> void:
	if state == "select":
		select_angle += delta * 0.12
		var focus := Vector3(0.0, 1.5, 0.0)
		var target_pos := focus + Vector3(cos(select_angle) * 27.0, 21.0, sin(select_angle) * 27.0)
		camera_pos = camera_pos.lerp(target_pos, 1.0 - exp(-3.0 * delta))
		camera.global_position = camera_pos
		camera.look_at(focus, Vector3.UP)
	else:
		_update_camera(delta)

	if state == "live":
		_update_match(delta)

	_update_projectiles(delta)
	_update_shake(delta)
	_update_crystal(delta)


func _update_camera(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var focus := player.global_position + Vector3(0.0, 1.0, 0.0)
	if player.dead:
		focus = Vector3(0.0, 1.0, 0.0)
	var camera_side := 1.0 if player.team == 0 else -1.0
	var camera_axis := Vector3(0.0, 22.0, 16.0 * camera_side).normalized()
	var target_pos := focus + camera_axis * camera_distance
	camera_pos = camera_pos.lerp(target_pos, 1.0 - exp(-5.0 * delta))
	camera.global_position = camera_pos
	camera.look_at(focus, Vector3.UP)


func _update_shake(delta: float) -> void:
	shake_amount = maxf(0.0, shake_amount - delta * 2.2)
	if shake_amount > 0.01:
		camera.h_offset = randf_range(-1.0, 1.0) * shake_amount * 0.5
		camera.v_offset = randf_range(-1.0, 1.0) * shake_amount * 0.5
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _update_match(delta: float) -> void:
	if sudden_death:
		match_time = 0.0
	else:
		match_time = maxf(0.0, match_time - delta)
		if match_time <= 0.0:
			if score[0] == score[1]:
				sudden_death = true
				announce("Решающий осколок!", Color(1.0, 0.75, 0.35), 3.0)
			else:
				end_match(score[0] > score[1])
				return

	match shell_phase:
		"idle":
			shell_timer -= delta
			if shell_timer <= 0.0:
				shell_phase = "warning"
				shell_timer = 10.0
				announce("Оболочка пробуждается — 10 секунд!", Color(0.78, 0.6, 1.0), 2.4)
		"warning":
			shell_timer -= delta
			if shell_timer <= 0.0:
				_spawn_shell()
		"active":
			shell_window -= delta
			if shell_window <= 0.0 and shell != null and is_instance_valid(shell) and shell.alive:
				shell.despawn()
				shell = null
				shell_phase = "idle"
				shell_timer = 18.0
				announce("Оболочка ушла в тень", Color(0.7, 0.7, 0.8), 1.6)


func _spawn_shell() -> void:
	var s := SkyShell.new()
	s.name = "Shell"
	add_child(s)
	s.setup(self)
	s.global_position = Vector3(0.0, 0.16, 0.0)
	shell = s
	shell_phase = "active"
	shell_window = SHELL_WINDOW
	announce("Оболочка здесь! Разбейте её — 45 секунд", Color(0.85, 0.62, 1.0), 2.6)
	play_sfx("thunder", -3.0)
	shake(0.6)
	burst(Vector3(0.0, 1.2, 0.0), Color(0.8, 0.5, 1.0), 44)
	ring_fx(Vector3(0.0, 0.2, 0.0), Color(0.8, 0.5, 1.0), 8.0)


func on_shell_died(s: SkyShell) -> void:
	if s != shell:
		return
	var pos := s.global_position
	burst(pos, Color(0.75, 0.9, 1.0), 60)
	ring_fx(Vector3(pos.x, 0.25, pos.z), Color(0.8, 0.95, 1.0), 9.0)
	play_sfx("thunder", -2.0)
	shake(0.8)
	spawn_crystal(pos)
	announce("Оболочка пала! Осколок свободен", Color(0.8, 0.95, 1.0), 2.4)
	var tween := create_tween()
	tween.tween_property(s, "scale", Vector3(0.02, 0.02, 0.02), 0.5)
	tween.tween_callback(s.queue_free)
	shell = null
	shell_phase = "idle"
	shell_timer = 25.0


func spawn_crystal(pos: Vector3) -> void:
	if crystal_node != null and is_instance_valid(crystal_node):
		crystal_node.queue_free()
	var c := Node3D.new()
	c.name = "Crystal"
	add_child(c)
	var mesh_node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.15
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh_node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.9, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.roughness = 0.1
	mat.metallic = 0.4
	mesh_node.material_override = mat
	c.add_child(mesh_node)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.9, 1.0)
	light.light_energy = 3.0
	light.omni_range = 9.0
	c.add_child(light)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.05
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.7, 0.95, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.7, 0.95, 1.0)
	ring_mat.emission_energy_multiplier = 2.2
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.position.y = -0.6
	c.add_child(ring)
	c.global_position = Vector3(pos.x, 1.1, pos.z)
	c.set_meta("spin", 0.0)
	crystal_node = c
	crystal_state = "ground"
	crystal_timer = 0.0
	carrier = null


func _update_crystal(delta: float) -> void:
	if crystal_node == null or not is_instance_valid(crystal_node):
		return
	if crystal_state == "ground":
		crystal_timer += delta
		pickup_delay = maxf(0.0, pickup_delay - delta)
		crystal_node.rotation.y += delta * 1.8
		crystal_node.position.y = 1.1 + sin(crystal_timer * 2.4) * 0.12
		if crystal_timer > 35.0:
			crystal_node.global_position = Vector3(0.0, 1.1, 0.0)
			crystal_timer = 0.0
			announce("Осколок вернулся к алтарю", Color(0.75, 0.9, 1.0), 1.8)
		if state == "live" and pickup_delay <= 0.0:
			_try_pickup()
	elif crystal_state == "carried" and carrier != null and is_instance_valid(carrier):
		crystal_node.global_position = carrier.global_position + Vector3(0.0, 2.9, 0.0)
		if not is_instance_valid(crystal_node):
			crystal_state = "none"
			carrier.carrying = false
			carrier = null
		crystal_node.rotation.y += delta * 2.4
		var base_z := 35.0 if carrier.team == 0 else -35.0
		if Vector2(carrier.global_position.x, carrier.global_position.z - base_z).length() < 4.8:
			_deliver(carrier)


func _try_pickup() -> void:
	var best: HeroUnit = null
	var best_d := 2.1
	for h in heroes:
		if h.dead or h.carrying:
			continue
		var d := h.global_position.distance_to(crystal_node.global_position)
		if d < best_d:
			best_d = d
			best = h
	if best != null:
		best.carrying = true
		carrier = best
		crystal_state = "carried"
		play_sfx("magic", -8.0)
		if best == player:
			announce("Осколок у тебя! Неси на базу", Color(0.75, 1.0, 0.85), 2.0)
		else:
			announce("%s несёт осколок %s" % [best.display_name, "к свету" if best.team == 0 else "во тьму"], Color(0.85, 0.85, 0.95), 1.6)


func _deliver(h: HeroUnit) -> void:
	h.carrying = false
	score[h.team] += 1
	if h == player:
		p_crystals += 1
	carrier = null
	crystal_state = "none"
	if crystal_node != null and is_instance_valid(crystal_node):
		burst(crystal_node.global_position, Color(0.7, 0.95, 1.0), 40)
		crystal_node.queue_free()
		crystal_node = null
	play_sfx("magic", -2.0)
	var team_name := "Свет" if h.team == 0 else "Тьма"
	announce("Осколок на базе: %s  %d : %d" % [team_name, score[0], score[1]], Color(1.0, 0.9, 0.6), 2.6)
	if sudden_death or score[h.team] >= CRYSTALS_TO_WIN:
		end_match(h.team == 0)
	else:
		shell_phase = "idle"
		shell_timer = 30.0


func drop_crystal(pos: Vector3) -> void:
	if crystal_node == null or not is_instance_valid(crystal_node):
		return
	crystal_state = "ground"
	crystal_timer = 0.0
	pickup_delay = 0.5
	carrier = null
	crystal_node.global_position = Vector3(pos.x, 0.5, pos.z)


func on_hero_died(h: HeroUnit) -> void:
	burst(h.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.45, 0.4), 22)
	play_sfx("hit", -6.0)
	if h == player:
		p_deaths += 1
	if h.carrying:
		drop_crystal(h.global_position)
		announce("Осколок выбит!", Color(1.0, 0.7, 0.4), 1.8)
	if h == player:
		announce("Ты пал. Возрождение через 8 с", Color(1.0, 0.5, 0.45), 2.2)


func record_hero_damage(target: HeroUnit, source: Node, damage: float, killed: bool) -> void:
	if player == null or source != player or target == player or target.team == player.team or damage <= 0.0:
		return
	p_damage += damage
	if killed:
		p_kills += 1


func on_hero_respawned(h: HeroUnit) -> void:
	burst(h.global_position + Vector3(0.0, 0.6, 0.0), Color(0.6, 0.9, 1.0), 18)


func end_match(team_zero_won: bool) -> void:
	if state != "live":
		return
	state = "over"
	var player_team := 0
	if player != null and is_instance_valid(player):
		player_team = player.team
	player_won = team_zero_won if player_team == 0 else not team_zero_won
	result_text = "ПОБЕДА" if player_won else "ПОРАЖЕНИЕ"
	get_tree().set_meta("last_match_won", player_won)
	get_tree().set_meta("last_match_score", score.duplicate())
	get_tree().set_meta("last_match_stats", {
		"p_kills": p_kills,
		"p_deaths": p_deaths,
		"p_damage": p_damage,
		"p_crystals": p_crystals,
	})
	if player != null and is_instance_valid(player):
		get_tree().set_meta("selected_class", player.hero_class)
		player.is_player = false
	announce(result_text, Color(0.85, 1.0, 0.7) if player_won else Color(1.0, 0.5, 0.45), 6.0)
	var transition_timer := get_tree().create_timer(2.8)
	transition_timer.timeout.connect(_open_results_screen)


func _open_results_screen() -> void:
	if state != "over":
		return
	var error := get_tree().change_scene_to_file("res://scenes/ResultsScreen.tscn")
	if error != OK:
		push_error("Failed to open ResultsScreen: %s" % error_string(error))


func announce(text: String, color: Color, duration := 2.0) -> void:
	last_announce = text
	if hud != null:
		hud.show_announcement(text, color, duration)


func enemies_of(team: int, observer: HeroUnit = null) -> Array[HeroUnit]:
	var out: Array[HeroUnit] = []
	for h in heroes:
		if h.team == team or h.dead:
			continue
		if observer != null and h.is_hidden_from(observer):
			continue
		out.append(h)
	return out


func nearest_enemy(from: Vector3, team: int, max_dist: float, observer: HeroUnit = null) -> HeroUnit:
	var best: HeroUnit = null
	var best_d := max_dist
	for h in heroes:
		if h.team == team or h.dead:
			continue
		if observer != null and h.is_hidden_from(observer):
			continue
		var d := from.distance_to(h.global_position)
		if d < best_d:
			best_d = d
			best = h
	return best


func _on_bush_body_entered(body: Node3D, bush: Area3D) -> void:
	if body is HeroUnit:
		(body as HeroUnit).set_bush_presence(bush, true)


func _on_bush_body_exited(body: Node3D, bush: Area3D) -> void:
	if body is HeroUnit:
		(body as HeroUnit).set_bush_presence(bush, false)


func lowest_ally(from: Vector3, team: int, max_dist: float) -> HeroUnit:
	var best: HeroUnit = null
	var best_frac := 1.0
	for h in heroes:
		if h.team != team or h.dead:
			continue
		if from.distance_to(h.global_position) > max_dist:
			continue
		var frac := h.health / h.max_health
		if frac < best_frac:
			best_frac = frac
			best = h
	return best


func alive_heroes_near(center: Vector3, radius: float) -> int:
	var count := 0
	for h in heroes:
		if not h.dead and center.distance_to(h.global_position) <= radius:
			count += 1
	return count


func pick_shell_target() -> HeroUnit:
	var options: Array[HeroUnit] = []
	for h in heroes:
		if not h.dead and h.global_position.distance_to(Vector3.ZERO) < 14.5:
			options.append(h)
	if options.is_empty():
		return null
	if carrier != null and not carrier.dead and randf() < 0.55:
		return carrier
	return options[randi() % options.size()]


func aoe(center: Vector3, radius: float, amount: float, source_team: int, stun_time: float, hurt_shell: bool, source: HeroUnit = null) -> void:
	for h in enemies_of(source_team):
		if h.global_position.distance_to(center) <= radius:
			h.take_damage(amount, source)
			if stun_time > 0.0:
				h.stun(stun_time)
	if hurt_shell and shell != null and is_instance_valid(shell) and shell.alive:
		if shell.global_position.distance_to(center) <= radius + 1.0:
			shell.take_damage(amount * 0.8, null)


func heal_area(center: Vector3, radius: float, amount: float, team: int, max_targets: int) -> void:
	var targets: Array[HeroUnit] = []
	for h in heroes:
		if h.team != team or h.dead:
			continue
		if h.global_position.distance_to(center) <= radius and h.health < h.max_health:
			targets.append(h)
	targets.sort_custom(func(a, b): return a.health / a.max_health < b.health / b.max_health)
	var count := 0
	for h in targets:
		if count >= max_targets:
			break
		h.heal(amount)
		heal_number(h.global_position + Vector3(0.0, 2.2, 0.0), amount)
		count += 1


func spawn_projectile(from: Vector3, target: Node3D, damage: float, color: Color, source: HeroUnit, stun_time := 0.0) -> void:
	if target == null or not is_instance_valid(target):
		return
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	mesh.radial_segments = 6
	mesh.rings = 3
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	add_child(node)
	node.global_position = from
	projectiles.append({
		"node": node,
		"target": target,
		"damage": damage,
		"color": color,
		"source": source,
		"stun": stun_time,
		"life": 2.5,
	})


func _update_projectiles(delta: float) -> void:
	var keep: Array = []
	for p in projectiles:
		var node: Node3D = p["node"]
		var target = p["target"]
		if not is_instance_valid(node):
			continue
		p["life"] = float(p["life"]) - delta
		if p["life"] <= 0.0:
			node.queue_free()
			continue
		if p.get("black_hole", false):
			var bh_dir: Vector3 = p.get("bh_dir", Vector3.FORWARD)
			node.global_position += bh_dir * 5.0 * delta
			for h in enemies_of(p["source"].team if p.has("source") else 0):
				if not h.dead and h.global_position.distance_to(node.global_position) <= float(p.get("radius", 3.5)):
					h.take_damage(float(p["damage"]) * delta * 0.5, p["source"])
			if randf() < 0.3:
				burst(node.global_position, p["color"], 3)
			keep.append(p)
			continue
		if not is_instance_valid(target) or (target is HeroUnit and (target as HeroUnit).dead):
			node.queue_free()
			continue
		var goal: Vector3 = target.global_position + Vector3(0.0, 1.1, 0.0)
		var to_goal: Vector3 = goal - node.global_position
		var dist := to_goal.length()
		if dist < 0.6:
			if target.has_method("take_damage"):
				target.take_damage(p["damage"], p["source"])
				if float(p["stun"]) > 0.0 and target is HeroUnit:
					(target as HeroUnit).stun(float(p["stun"]))
			burst(node.global_position, p["color"], 10)
			play_sfx("magic", -12.0)
			node.queue_free()
			continue
		node.global_position += to_goal.normalized() * minf(dist, 26.0 * delta)
		keep.append(p)
	projectiles = keep


func melee_fx(_from: Vector3, to: Vector3) -> void:
	play_sfx("hit", -10.0)
	burst(to + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.85, 0.5), 10)


func shell_bolt(pos: Vector3, radius: float, damage: float) -> void:
	play_sfx("thunder", -2.0)
	shake(0.7)
	var beam := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.5
	mesh.height = 16.0
	mesh.radial_segments = 8
	beam.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.7, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.6, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material_override = mat
	add_child(beam)
	beam.global_position = pos + Vector3(0.0, 8.0, 0.0)
	var tween := create_tween()
	tween.tween_method(func(a: float): mat.albedo_color.a = a, 0.95, 0.0, 0.35)
	tween.tween_callback(beam.queue_free)
	burst(pos + Vector3(0.0, 0.6, 0.0), Color(0.85, 0.65, 1.0), 34)
	ring_fx(Vector3(pos.x, 0.2, pos.z), Color(0.85, 0.65, 1.0), radius)
	for h in heroes:
		if not h.dead and h.global_position.distance_to(pos) <= radius:
			h.take_damage(damage, null)
			h.stun(1.0)


func telegraph(pos: Vector3, radius: float, duration: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.25
	torus.outer_radius = radius
	torus.rings = 40
	torus.ring_segments = 8
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.55, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.5)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	add_child(ring)
	ring.global_position = Vector3(pos.x, 0.25, pos.z)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3(1.15, 1.0, 1.15), duration)
	tween.tween_callback(ring.queue_free)


func burst(pos: Vector3, color: Color, count := 16) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = count
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 180.0
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 8.0
	particles.gravity = Vector3(0.0, -14.0, 0.0)
	particles.scale_amount_min = 0.4
	particles.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	particles.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	particles.material_override = mat
	add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)


func ring_fx(pos: Vector3, color: Color, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 8
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	add_child(ring)
	ring.global_position = Vector3(pos.x, 0.35, pos.z)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.4)
	tween.parallel().tween_method(func(a: float): mat.albedo_color.a = a, 0.8, 0.0, 0.4)
	tween.tween_callback(ring.queue_free)


func damage_number(pos: Vector3, amount: float, _team: int, is_shell := false) -> void:
	var label := Label3D.new()
	label.text = str(int(round(amount)))
	label.font_size = 64
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.85, 0.9, 1.0) if is_shell else Color(1.0, 0.55, 0.45)
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.03, 0.08, 0.9)
	add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	var tween := create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector3(0.0, 1.1, 0.0), 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)


func heal_number(pos: Vector3, amount: float) -> void:
	var label := Label3D.new()
	label.text = "+" + str(int(round(amount)))
	label.font_size = 56
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.6, 1.0, 0.7)
	label.outline_size = 12
	label.outline_modulate = Color(0.03, 0.08, 0.05, 0.9)
	add_child(label)
	label.global_position = pos
	var tween := create_tween()
	tween.tween_property(label, "global_position", pos + Vector3(0.0, 1.0, 0.0), 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)


func shake(amount: float) -> void:
	shake_amount = maxf(shake_amount, amount)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and state == "live":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clampf(camera_distance - zoom_speed * 2.0, min_zoom_distance, max_zoom_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clampf(camera_distance + zoom_speed * 2.0, min_zoom_distance, max_zoom_distance)
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and not event.echo:
		if state == "select":
			if event.keycode == KEY_1:
				start_match(HeroUnit.Cls.WARRIOR)
			elif event.keycode == KEY_2:
				start_match(HeroUnit.Cls.MAGE)
			elif event.keycode == KEY_3:
				start_match(HeroUnit.Cls.FAIRY)
		elif state == "live" and player != null:
			if event.keycode == KEY_1:
				player.use_ability(0)
			elif event.keycode == KEY_2:
				player.use_ability(1)
			elif event.keycode == KEY_3:
				player.use_ability(2)
		elif state == "over":
			if event.keycode == KEY_R:
				get_tree().reload_current_scene()
	if event is InputEventMouseButton and event.pressed and state == "over":
		get_tree().reload_current_scene()


func objective_text() -> String:
	if state == "select":
		return "Выбери класс — 1 Воин · 2 Маг · 3 Фея"
	if state == "over":
		return "Нажми R, чтобы сыграть ещё раз"
	if crystal_state == "carried" and carrier != null and is_instance_valid(carrier):
		var who := "Ты несёшь осколок — на базу!" if carrier == player else "%s несёт осколок" % carrier.display_name
		return who
	if crystal_state == "ground":
		return "Осколок свободен — подбери его"
	match shell_phase:
		"warning":
			return "Оболочка пробуждается: %d" % int(ceil(shell_timer))
		"active":
			return "Разбей Оболочку: %d" % int(ceil(shell_window))
	return "Оболочка появится через %d" % int(ceil(shell_timer))


func debug_state() -> Dictionary:
	var info := {}
	info["state"] = state
	info["time"] = int(match_time)
	info["score"] = [score[0], score[1]]
	info["shell_phase"] = shell_phase
	info["shell_timer"] = int(ceil(shell_timer))
	info["shell_window"] = int(ceil(shell_window))
	info["crystal"] = crystal_state
	info["sudden_death"] = sudden_death
	var names: Array[String] = []
	for h in heroes:
		names.append("%s t%d hp%d%s" % [h.display_name, h.team, int(h.health), " C" if h.carrying else ""])
	info["heroes"] = names
	if shell != null and is_instance_valid(shell):
		info["shell_hp"] = int(shell.health)
	return info
