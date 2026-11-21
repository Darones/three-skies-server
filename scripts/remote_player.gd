extends Node3D

const FONT: FontFile = preload("res://assets/fonts/Philosopher-Regular.ttf")
const MODEL_DIRS := [
	"res://art/generated/warrior",
	"res://art/generated/mage",
	"res://art/generated/fairy",
]
const CLASS_COLORS := [
	Color(1.0, 0.78, 0.4),
	Color(0.6, 0.95, 1.0),
	Color(0.72, 0.95, 0.55),
]
const CLASS_MAX_HP := [1050.0, 1000.0, 950.0]
const HEALTH_BAR_WIDTH := 1.7
const HEALTH_BAR_3D := preload("res://scripts/health_bar_3d.gd")

var peer_id := 0
var display_name := ""
var hero_class := 0
var team := 0
var health := 0.0
var max_health := 0.0
var attack_damage := 0.0
var dead := false
var carrying := false
var is_bot := false
var match_kills := 0
var match_deaths := 0
var match_damage_dealt := 0.0
var match_crystals := 0
var match_shells := 0
var game: Node = null
var target_position := Vector3.ZERO
var target_rotation := 0.0
var _has_target := false
var _last_bot_animation := ""
var _move_anim := ""
var _last_state_msec := 0
var _attack_lock_msec := 0
var last_damage_msec := 0
var _name_label: Label3D = null
var _health_back: MeshInstance3D = null
var _health_fill: MeshInstance3D = null
var _model_root: Node3D = null
var _animation_player: AnimationPlayer = null


func setup(player_id: int, info: Dictionary) -> void:
	peer_id = player_id
	display_name = String(info.get("name", "Игрок %d" % player_id))
	hero_class = clampi(int(info.get("class", 0)), 0, 2)
	team = clampi(int(info.get("team", 0)), 0, 1)
	is_bot = bool(info.get("bot", false))
	_last_bot_animation = String(info.get("animation", ""))
	var synced_max_hp := float(info.get("max_hp", 0.0))
	max_health = synced_max_hp if synced_max_hp > 0.0 else CLASS_MAX_HP[hero_class]
	var synced_hp := float(info.get("hp", 0.0))
	health = clampf(synced_hp if synced_hp > 0.0 else max_health, 0.0, max_health)
	attack_damage = maxf(float(info.get("attack_damage", 0.0)), 0.0)

	var spawn := Vector3(0.0, 0.76, 28.0 if team == 0 else -28.0)
	if bool(info.get("has_state", false)) and info.get("position") is Vector3:
		spawn = info["position"]
	global_position = spawn
	rotation.y = float(info.get("rotation", 0.0))
	target_position = spawn
	target_rotation = rotation.y
	_has_target = true

	_build_visual()
	_build_name_label()
	_build_health_bar()
	if not bool(info.get("alive", true)):
		apply_network_death()


func update_info(info: Dictionary) -> void:
	var updated_name := String(info.get("name", "")).strip_edges()
	if not updated_name.is_empty() and updated_name != display_name:
		display_name = updated_name
		if _name_label != null and is_instance_valid(_name_label):
			_name_label.text = display_name


func apply_stats(stats_max_hp: float, stats_hp: float, stats_attack_damage: float) -> void:
	if stats_max_hp > 0.0:
		max_health = stats_max_hp
	if not dead and stats_hp > 0.0:
		health = clampf(stats_hp, 0.0, max_health)
	attack_damage = maxf(stats_attack_damage, 0.0)
	_update_health_bar()


func apply_state(position: Vector3, rotation_y: float) -> void:
	var previous := target_position
	var moved := previous.distance_to(position) if _has_target else 0.0
	target_position = position
	target_rotation = rotation_y
	if not _has_target:
		global_position = position
		rotation.y = rotation_y
		_has_target = true
	# Human players do not send current_anim over the wire; infer locomotion
	# from the position delta so they do not slide on other clients.
	var now := Time.get_ticks_msec()
	if now >= _attack_lock_msec:
		if moved > 0.02:
			_last_state_msec = now
			var desired := "run" if moved > 0.22 else "walk"
			if desired != _move_anim:
				_move_anim = desired
				_play_bot_animation(desired)
		elif now - _last_state_msec > 220 and _move_anim != "idle":
			_move_anim = "idle"
			_play_bot_animation("idle")


func apply_bot_state(info: Dictionary) -> void:
	var synced_max := maxf(float(info.get("max_hp", 0.0)), 0.0)
	if synced_max > 0.0:
		max_health = synced_max
	var synced_hp := maxf(float(info.get("hp", 0.0)), 0.0)
	if max_health > 0.0:
		synced_hp = clampf(synced_hp, 0.0, max_health)
	if CombatProfiler.enabled and absf(synced_hp - health) > 1.0:
		print("[BOTHP] id=%d snapshot=%.0f/%.0f current=%.0f/%.0f" % [peer_id, synced_hp, max_health, health, max_health])
	if synced_hp > health and Time.get_ticks_msec() - last_damage_msec < 600:
		# The host sends snapshots at 12 Hz. A snapshot created just before
		# the host applied our confirmed hit can arrive after the damage and
		# raise the bar again. Hold the confirmed damage briefly so the hit
		# is visible; real heals after 600 ms still apply.
		synced_hp = health
	attack_damage = maxf(float(info.get("attack_damage", attack_damage)), 0.0)
	var alive := bool(info.get("alive", synced_hp > 0.0))
	var position: Vector3 = info.get("position", target_position)
	var rotation_y := float(info.get("rotation", target_rotation))
	if not alive:
		health = 0.0
		if not dead:
			apply_network_death()
		_update_health_bar()
		return
	if dead:
		apply_network_respawn(position, rotation_y)
	health = synced_hp if synced_hp > 0.0 else max_health
	target_position = position
	target_rotation = rotation_y
	if not _has_target:
		global_position = position
		rotation.y = rotation_y
		_has_target = true
	_update_health_bar()
	var animation := String(info.get("animation", ""))
	if animation != _last_bot_animation:
		_last_bot_animation = animation
		_play_bot_animation(animation)


func _play_bot_animation(anim_name: String) -> void:
	if anim_name.is_empty() or dead:
		return
	if anim_name == "attack" or anim_name == "cast":
		play_attack(anim_name)
		return
	if _animation_player == null:
		return
	var wanted := anim_name.to_lower()
	for animation_name in _animation_player.get_animation_list():
		var lower := String(animation_name).to_lower()
		if lower == wanted or lower.contains(wanted):
			var anim := _animation_player.get_animation(animation_name)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR if wanted in ["idle", "run", "walk"] else Animation.LOOP_NONE
			_animation_player.play(animation_name)
			return
	for animation_name in _animation_player.get_animation_list():
		if String(animation_name).to_lower().contains("idle"):
			var anim := _animation_player.get_animation(animation_name)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			_animation_player.play(animation_name)
			return


func _process(delta: float) -> void:
	if dead or not _has_target:
		return
	var weight := 1.0 - exp(-14.0 * delta)
	global_position = global_position.lerp(target_position, weight)
	rotation.y = lerp_angle(rotation.y, target_rotation, weight)


func _build_visual() -> void:
	var model := _load_model()
	if model == null:
		_build_placeholder()
		return
	var holder := Node3D.new()
	holder.name = "Model"
	add_child(holder)
	holder.add_child(model)
	_configure_gear(model)
	_model_root = holder
	_fit_model(holder)
	_play_idle(holder)


func _configure_gear(model: Node) -> void:
	# The rig ships every weapon mesh visible. Remote heroes must show only
	# the class default, otherwise the archer runs with daggers + crossbow.
	var selected: Array = HeroUnit.GEAR_DEFAULT.get(hero_class, [])
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var mesh_name := String(mesh.name)
		if mesh_name in HeroUnit.GEAR_NAMES:
			mesh.visible = mesh_name in selected


func _load_model() -> Node3D:
	var folder: String = MODEL_DIRS[hero_class]
	# Exported builds remap .tscn to .scn + .tscn.remap, so scan-free explicit
	# path first and only fall back to a directory listing if it is missing.
	var scene_path := folder + "/character.tscn"
	if not ResourceLoader.exists(scene_path):
		scene_path = _find_model_scene(folder)
	if scene_path.is_empty():
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


func _find_model_scene(folder: String) -> String:
	var directory := DirAccess.open(folder)
	if directory == null:
		return ""
	var files := directory.get_files()
	for suffix in [".tscn", ".scn", ".tscn.remap"]:
		for file in files:
			if file.to_lower().contains("character") and file.to_lower().ends_with(suffix):
				return folder + "/" + file.trim_suffix(".remap")
	for suffix in [".tscn", ".scn", ".tscn.remap"]:
		for file in files:
			if file.to_lower().ends_with(suffix):
				return folder + "/" + file.trim_suffix(".remap")
	for file in files:
		if file.to_lower().ends_with(".glb"):
			return folder + "/" + file
	return ""


func _fit_model(holder: Node3D) -> void:
	var bounds := _model_aabb(holder)
	if bounds.size.y <= 0.01:
		return
	var factor := 2.15 / bounds.size.y
	holder.scale = Vector3.ONE * factor
	holder.position.y = -bounds.position.y * factor


func _model_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.mesh.get_aabb()
		box.position += mesh_instance.global_position - root.global_position
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _play_idle(holder: Node3D) -> void:
	_animation_player = _find_animation_player(holder)
	if _animation_player == null:
		return
	var animations := _animation_player.get_animation_list()
	for animation_name in animations:
		if String(animation_name).to_lower().contains("idle"):
			var anim := _animation_player.get_animation(animation_name)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			_animation_player.play(animation_name)
			return
	if not animations.is_empty():
		var anim := _animation_player.get_animation(animations[0])
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		_animation_player.play(animations[0])


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _build_placeholder() -> void:
	var body := MeshInstance3D.new()
	body.name = "PlaceholderBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.6
	body.mesh = capsule
	body.position = Vector3(0.0, 0.9, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = CLASS_COLORS[hero_class]
	body.material_override = material
	add_child(body)


func _build_name_label() -> void:
	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = display_name
	_name_label.font = ThemeDB.fallback_font
	_name_label.font_size = 56
	_name_label.pixel_size = 0.0055
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.modulate = Color(0.62, 1.0, 0.62) if _is_ally() else Color(1.0, 0.32, 0.28)
	_name_label.outline_size = 10
	_name_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_name_label.position = Vector3(0.0, 3.02, 0.0)
	add_child(_name_label)


func _is_ally() -> bool:
	if game != null and is_instance_valid(game) and game.player != null and is_instance_valid(game.player):
		return team == int(game.player.team)
	return team == int(NetworkManager.assigned_team)


func _build_health_bar() -> void:
	var bar_color := Color(0.36, 0.95, 0.52, 1.0) if _is_ally() else Color(1.0, 0.3, 0.26, 1.0)
	_health_back = HEALTH_BAR_3D.create(HEALTH_BAR_WIDTH, 0.16, bar_color, 2.55)
	add_child(_health_back)
	_health_fill = _health_back
	_update_health_bar()


func _update_health_bar() -> void:
	if _health_back == null:
		return
	var ratio := clampf(health / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0
	HEALTH_BAR_3D.set_fill(_health_back, ratio)
	_health_back.visible = not dead
	if _health_fill != null and _health_fill != _health_back:
		_health_fill.visible = not dead


func take_damage(amount: float, source: Node = null, _damage_type := "physical", skill := "auto", is_crit := false) -> void:
	if dead:
		return
	if source is HeroUnit and game != null and bool(game.get("network_play")):
		var source_id := int(source.get("network_id"))
		if source_id == 0 and bool(source.get("is_player")):
			source_id = NetworkManager.local_peer_id
		# Same contract as HeroUnit: the intent carries the final hit, so the
		# outgoing multiplier and the crit flag must be included.
		var intent_damage := amount * HeroUnit.HERO_OUTGOING_DAMAGE_MULTIPLIER
		if CombatProfiler.enabled:
			print("[HIT] remote id=%d amount=%.0f skill=%s source=%d" % [peer_id, intent_damage, skill, source_id])
		NetworkManager.send_attack_intent(peer_id, skill, source_id, intent_damage, is_crit)
		return
	var applied := minf(maxf(amount, 0.0), health)
	health = maxf(0.0, health - maxf(amount, 0.0))
	_update_health_bar()
	if game != null and game.has_method("damage_number"):
		game.call("damage_number", global_position + Vector3(0.0, 2.0, 0.0), applied, team)


func apply_network_damage(amount: float, show_number := true, is_crit := false) -> bool:
	if dead:
		return false
	last_damage_msec = Time.get_ticks_msec()
	health = maxf(0.0, health - maxf(amount, 0.0))
	_update_health_bar()
	if show_number and game != null and game.has_method("damage_number"):
		game.call("damage_number", global_position + Vector3(0.0, 2.0, 0.0), amount, team, false, is_crit)
	if health <= 0.0:
		apply_network_death()
		return true
	return false


func receive_heal(amount: float, source: Node = null) -> void:
	if dead:
		return
	var applied := minf(maxf(amount, 0.0), max_health - health)
	if applied <= 0.0:
		return
	health = minf(max_health, health + applied)
	_update_health_bar()
	if game != null and game.has_method("heal_number"):
		game.call("heal_number", global_position + Vector3(0.0, 2.0, 0.0), applied)
	if source is HeroUnit and game != null and bool(game.get("network_play")):
		NetworkManager.send_heal(peer_id, applied)


func apply_network_heal(amount: float) -> void:
	if dead:
		return
	var applied := minf(maxf(amount, 0.0), max_health - health)
	if applied <= 0.0:
		return
	health = minf(max_health, health + applied)
	_update_health_bar()
	if game != null and game.has_method("heal_number"):
		game.call("heal_number", global_position + Vector3(0.0, 2.0, 0.0), applied)


func apply_network_death() -> void:
	if dead:
		return
	dead = true
	match_deaths += 1
	health = 0.0
	_update_health_bar()
	if game != null and game.has_method("burst"):
		game.call("burst", global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.45, 0.4), 20)
	visible = false


func apply_network_respawn(position: Vector3, rotation_y: float) -> void:
	dead = false
	health = max_health
	global_position = position
	target_position = position
	rotation.y = rotation_y
	target_rotation = rotation_y
	_has_target = true
	visible = true
	_update_health_bar()
	if _model_root != null:
		_play_idle(_model_root)


func play_attack(_attack_type: String) -> void:
	if dead:
		return
	_attack_lock_msec = Time.get_ticks_msec() + 450
	if _animation_player != null:
		var preferred: Array[String] = []
		match hero_class:
			1:
				preferred = ["spellcast", "cast", "ranged_shoot", "shoot"]
			2:
				preferred = ["1h_ranged_shoot", "ranged_shoot", "shoot", "attack"]
			_:
				preferred = ["1h_melee_attack", "attack", "cast"]
		for want in preferred:
			for animation_name in _animation_player.get_animation_list():
				if String(animation_name).to_lower().contains(want):
					var anim := _animation_player.get_animation(animation_name)
					if anim != null:
						anim.loop_mode = Animation.LOOP_NONE
					_animation_player.play(animation_name)
					return
		for animation_name in _animation_player.get_animation_list():
			var lower := String(animation_name).to_lower()
			if lower.contains("attack") or lower.contains("cast"):
				_animation_player.play(animation_name)
				return
	if _model_root != null:
		var base_scale := _model_root.scale
		var tween := create_tween()
		tween.tween_property(_model_root, "scale", base_scale * 1.06, 0.08)
		tween.tween_property(_model_root, "scale", base_scale, 0.12)


func stun(_duration: float) -> void:
	pass
