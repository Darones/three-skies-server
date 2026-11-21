class_name SkyShell
extends CharacterBody3D

const SHELL_MODEL: PackedScene = preload("res://art/generated/shell/3d_1793744338028.glb")
const HEALTH_BAR_3D := preload("res://scripts/health_bar_3d.gd")

var game: Node
var alive := false
var max_health := 1080.0
var health := 1080.0
var attack_timer := 3.0
var bob_time := 0.0
var visual: Node3D
var collision_shape: CollisionShape3D
var health_fill: MeshInstance3D
var health_name: Label3D
var core_light: OmniLight3D
var base_y := 0.16
var retiring := false


func setup(p_game: Node) -> void:
	game = p_game


func activate(p_game: Node, spawn_position: Vector3) -> void:
	game = p_game
	retiring = false
	alive = true
	health = max_health
	attack_timer = 3.0
	bob_time = 0.0
	scale = Vector3.ONE
	global_position = spawn_position
	if visual != null:
		visual.rotation = Vector3.ZERO
		visual.position = Vector3.ZERO
	if health_fill != null:
		health_fill.visible = true
	_refresh_health_bar()
	collision_layer = 1
	collision_mask = 1
	if collision_shape != null:
		collision_shape.set_deferred("disabled", false)
	visible = true
	set_physics_process(true)


func deactivate() -> void:
	alive = false
	retiring = false
	collision_layer = 0
	collision_mask = 0
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	set_physics_process(false)
	visible = false
	scale = Vector3.ONE


func retire(duration: float) -> void:
	if retiring:
		return
	retiring = true
	alive = false
	collision_layer = 0
	collision_mask = 0
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), duration)
	tween.tween_callback(deactivate)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	collision_shape = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = 2.2
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, 1.1, 0.0)
	collision_shape.disabled = true
	add_child(collision_shape)

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_build_visual()
	_build_health_bar()

	core_light = OmniLight3D.new()
	core_light.light_color = Color(0.68, 0.35, 1.0)
	core_light.light_energy = 3.5
	core_light.omni_range = 5.0
	core_light.position = Vector3(0.0, 1.1, 0.0)
	add_child(core_light)

	var pulse := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.05
	torus.outer_radius = 1.13
	torus.rings = 40
	torus.ring_segments = 8
	pulse.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.4, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.4, 1.0)
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pulse.material_override = mat
	pulse.name = "AuraRing"
	pulse.position = Vector3(0.0, 0.06, 0.0)
	add_child(pulse)
	visible = false
	set_physics_process(false)


func _build_visual() -> void:
	if SHELL_MODEL != null:
		var model := SHELL_MODEL.instantiate() as Node3D
		visual.add_child(model)
		var aabb := _node_aabb(model)
		if aabb.size.y > 0.01:
			var factor := 2.4 / aabb.size.y
			model.scale = Vector3.ONE * factor
			model.position.y = -aabb.position.y * factor
		return
	var placeholder := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.9
	mesh.height = 2.4
	placeholder.mesh = mesh
	placeholder.position.y = 1.2
	visual.add_child(placeholder)


func _node_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and n.mesh != null:
			var mi := n as MeshInstance3D
			var box := mi.mesh.get_aabb()
			box.position += mi.global_position - global_position
			if first:
				result = box
				first = false
			else:
				result = result.merge(box)
	return result


func _build_health_bar() -> void:
	health_fill = HEALTH_BAR_3D.create(1.7, 0.16, Color(0.85, 0.4, 1.0, 1.0), 2.7)
	add_child(health_fill)

	health_name = Label3D.new()
	health_name.name = "ShellName"
	health_name.text = "ОБОЛОЧКА"
	health_name.font = ThemeDB.fallback_font
	health_name.font_size = 48
	health_name.pixel_size = 0.006
	health_name.outline_size = 10
	health_name.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	health_name.modulate = Color(0.95, 0.75, 1.0)
	health_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_name.no_depth_test = true
	health_name.position = Vector3(0.0, 3.12, 0.0)
	add_child(health_name)


func _refresh_health_bar() -> void:
	if health_fill == null:
		return
	var frac := clampf(health / max_health, 0.0, 1.0)
	HEALTH_BAR_3D.set_fill(health_fill, frac)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	bob_time += delta
	if visual != null:
		visual.rotation.y += delta * 0.35
		visual.position.y = sin(bob_time * 1.6) * 0.08
	if game == null or not bool(game.get("tutorial_mode")):
		attack_timer -= delta
		if attack_timer <= 0.0:
			attack_timer = 3.4
			_strike()
	var frac := clampf(health / max_health, 0.0, 1.0)
	HEALTH_BAR_3D.set_fill(health_fill, frac)
	if core_light != null:
		core_light.light_energy = 3.0 + sin(bob_time * 3.0) * 0.8


func _strike() -> void:
	var target = game.pick_shell_target()
	if target == null:
		return
	var pos: Vector3 = target.global_position
	game.telegraph(pos, 2.8, 0.85)
	await get_tree().create_timer(0.85).timeout
	if not is_instance_valid(self) or not alive:
		return
	game.shell_bolt(pos, 2.7, 44.0)


func take_damage(amount: float, source: Node = null, _damage_type: String = "physical", _skill: String = "", _is_crit: bool = false) -> void:
	if not alive:
		return
	if game != null and bool(game.get("network_play")) and NetworkManager.server_protocol >= 2:
		var source_id := 0
		if source is HeroUnit:
			source_id = int((source as HeroUnit).network_id)
			if source_id == 0 and (source as HeroUnit).is_player:
				source_id = NetworkManager.local_peer_id
		# The server applies the intent as-is, so include the same outgoing
		# multiplier the offline branch applies below.
		var source_multiplier := HeroUnit.HERO_OUTGOING_DAMAGE_MULTIPLIER if source is HeroUnit else 1.0
		var intent_damage := maxf(amount, 0.0) * source_multiplier
		if CombatProfiler.enabled:
			print("[SHELL] intent amount=%.0f source=%d hp_local=%.0f" % [intent_damage, source_id, health])
		NetworkManager.send_shell_attack(intent_damage, source_id)
		return
	if CombatProfiler.enabled:
		print("[SHELL] dmg=%.0f hp_before=%.0f/%.0f source=%s" % [amount, health, max_health, str(source.name) if source != null else "?"])
	var source_multiplier := HeroUnit.HERO_OUTGOING_DAMAGE_MULTIPLIER if source is HeroUnit else 1.0
	var applied_damage := minf(maxf(amount, 0.0) * source_multiplier, health)
	health -= applied_damage
	_refresh_health_bar()
	if source is HeroUnit and (source as HeroUnit).is_player:
		game.damage_number(global_position + Vector3(0.0, 3.4, 0.0), applied_damage, 1, true)
	if applied_damage > 0.0 and health > 0.0:
		game.play_sfx("shell_hit", -4.0)
	if source is HeroUnit:
		(source as HeroUnit).on_damage_dealt(applied_damage)
	if health <= 0.0:
		health = 0.0
		alive = false
		collision_layer = 0
		collision_mask = 0
		if collision_shape != null:
			collision_shape.set_deferred("disabled", true)
		set_physics_process(false)
		game.on_shell_died(self, source)


func despawn() -> void:
	retire(0.6)

