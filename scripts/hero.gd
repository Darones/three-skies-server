class_name HeroUnit
extends CharacterBody3D

signal hero_died(hero: HeroUnit)

enum Cls { WARRIOR, MAGE, FAIRY }

const GRAVITY := 26.0

const CLASS_DATA := {
	Cls.WARRIOR: {
		"name": "Воин",
		"title": "Воин света",
		"hp": 240.0,
		"speed": 6.4,
		"range": 2.7,
		"damage": 22.0,
		"interval": 0.8,
		"ranged": false,
		"color": Color(1.0, 0.78, 0.4),
		"abilities": [
			{"name": "Рывок", "cd": 7.0, "type": "dash"},
			{"name": "Оглушение", "cd": 11.0, "type": "stun_aoe"},
			{"name": "Небесный клинок", "cd": 24.0, "type": "ult_aoe"},
		],
	},
	Cls.MAGE: {
		"name": "Маг",
		"title": "Маг-целитель",
		"hp": 175.0,
		"speed": 5.9,
		"range": 9.0,
		"damage": 13.0,
		"interval": 1.0,
		"ranged": true,
		"color": Color(0.6, 0.95, 1.0),
		"abilities": [
			{"name": "Исцеление", "cd": 8.0, "type": "heal"},
			{"name": "Лозы", "cd": 12.0, "type": "root_aoe"},
			{"name": "Свет небес", "cd": 26.0, "type": "ult_support"},
		],
	},
	Cls.FAIRY: {
		"name": "Фея",
		"title": "Фея-лучница",
		"hp": 160.0,
		"speed": 7.0,
		"range": 11.0,
		"damage": 15.0,
		"interval": 0.75,
		"ranged": true,
		"color": Color(0.72, 0.95, 0.55),
		"abilities": [
			{"name": "Залп", "cd": 6.0, "type": "volley"},
			{"name": "Оглушающая стрела", "cd": 12.0, "type": "stun_shot"},
			{"name": "Дождь стрел", "cd": 24.0, "type": "ult_rain"},
		],
	},
}

var game: Node = null
var team := 0
var hero_class: int = Cls.WARRIOR
var is_player := false
var display_name := ""

var max_health := 200.0
var health := 200.0
var move_speed := 6.0
var attack_range := 2.5
var attack_damage := 20.0
var attack_interval := 0.8
var ranged := false

var carrying := false
var dead := false
var stun_timer := 0.0
var attack_cd := 0.0
var attack_anim_time := 0.0
var respawn_timer := 0.0
var ability_cds: Array[float] = [0.0, 0.0, 0.0]
var cast_flash := 0.0

var ai_goal := Vector3.ZERO
var ai_think := 0.0
var ai_attack_target: Node3D = null
var ai_offset := Vector3.ZERO

var visual: Node3D
var anim_player: AnimationPlayer = null
var current_anim := ""
var health_fill: MeshInstance3D
var carry_light: OmniLight3D


func setup(p_game: Node, p_class: int, p_team: int, p_player: bool) -> void:
	game = p_game
	hero_class = p_class
	team = p_team
	is_player = p_player
	var data: Dictionary = CLASS_DATA[hero_class]
	max_health = data["hp"]
	health = max_health
	move_speed = data["speed"]
	attack_range = data["range"]
	attack_damage = data["damage"]
	attack_interval = data["interval"]
	ranged = data["ranged"]
	display_name = data["name"]
	ai_offset = Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	_build_body()
	_build_visual()


func _build_body() -> void:
	collision_layer = 1
	collision_mask = 1
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.7
	col.shape = shape
	col.position = Vector3(0.0, 0.85, 0.0)
	add_child(col)

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)

	var ring := MeshInstance3D.new()
	ring.name = "TeamRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.78
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	var ring_color := Color(0.45, 0.85, 1.0) if team == 0 else Color(0.8, 0.35, 1.0)
	ring_mat.albedo_color = ring_color
	ring_mat.emission_enabled = true
	ring_mat.emission = ring_color
	ring_mat.emission_energy_multiplier = 1.4
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 0.05, 0.0)
	add_child(ring)

	_build_health_bar()

	carry_light = OmniLight3D.new()
	carry_light.light_color = Color(0.7, 0.9, 1.0)
	carry_light.light_energy = 0.0
	carry_light.omni_range = 5.0
	carry_light.position = Vector3(0.0, 2.4, 0.0)
	add_child(carry_light)


func _build_health_bar() -> void:
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.25, 0.15)
	back.mesh = quad
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.05, 0.05, 0.08, 0.85)
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	back_mat.no_depth_test = false
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back.material_override = back_mat
	back.position = Vector3(0.0, 2.35, 0.0)
	add_child(back)

	health_fill = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(1.18, 0.09)
	health_fill.mesh = fill_quad
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.9, 0.25, 0.3) if team == 1 else Color(0.35, 0.95, 0.55)
	fill_mat.emission_enabled = true
	fill_mat.emission = fill_mat.albedo_color
	fill_mat.emission_energy_multiplier = 0.6
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	health_fill.material_override = fill_mat
	health_fill.position = Vector3(0.0, 2.35, 0.01)
	add_child(health_fill)


func _build_visual() -> void:
	var model := _load_model()
	if model != null:
		var holder := Node3D.new()
		holder.name = "Model"
		holder.add_child(model)
		visual.add_child(holder)
		_fit_model(holder)
		anim_player = _find_animation_player(holder)
		_play_anim("idle")
		return
	_build_placeholder()


func _load_model() -> Node3D:
	var folder := ""
	match hero_class:
		Cls.WARRIOR:
			folder = "res://art/generated/warrior"
		Cls.MAGE:
			folder = "res://art/generated/mage"
		Cls.FAIRY:
			folder = "res://art/generated/fairy"
	var dir := DirAccess.open(folder)
	if dir == null:
		return null
	var chosen := ""
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			if chosen == "" or file.to_lower().contains("character"):
				chosen = file
	if chosen == "":
		for file in dir.get_files():
			if file.ends_with(".glb") and (file.to_lower().contains("idle") or chosen == ""):
				chosen = file
	if chosen == "":
		return null
	var packed := load(folder + "/" + chosen) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	return node


func _fit_model(holder: Node3D) -> void:
	var aabb := _node_aabb(holder)
	if aabb.size.y <= 0.01:
		return
	var target := 2.15
	var factor := target / aabb.size.y
	holder.scale = Vector3.ONE * factor
	holder.position.y = -aabb.position.y * factor


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


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found := _find_animation_player(c)
		if found != null:
			return found
	return null


func _play_anim(key: String) -> void:
	if anim_player == null or current_anim == key:
		return
	var target := ""
	for name in anim_player.get_animation_list():
		var low := String(name).to_lower()
		if low.contains(key):
			target = String(name)
			break
	if target == "":
		return
	current_anim = key
	anim_player.play(target)


func _build_placeholder() -> void:
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.6
	body.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CLASS_DATA[hero_class]["color"]
	body.material_override = mat
	body.position = Vector3(0.0, 0.9, 0.0)
	visual.add_child(body)


func _physics_process(delta: float) -> void:
	if dead:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return

	stun_timer = maxf(0.0, stun_timer - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	cast_flash = maxf(0.0, cast_flash - delta)
	attack_anim_time = maxf(0.0, attack_anim_time - delta)
	for i in ability_cds.size():
		ability_cds[i] = maxf(0.0, ability_cds[i] - delta)

	var dir := Vector3.ZERO
	if stun_timer <= 0.0:
		if is_player:
			dir = _player_dir()
		else:
			dir = _ai_dir(delta)
		_try_auto_attack(delta)

	var speed := move_speed * (0.5 if carrying else 1.0)
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, target_v.z, 40.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.2
	move_and_slide()

	if dir.length_squared() > 0.01:
		_face(dir, delta)
	if global_position.y < -8.0:
		global_position = _base_position()
		velocity = Vector3.ZERO

	_update_look(delta)


func _player_dir() -> Vector3:
	var x := 0.0
	var y := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		y -= 1.0
	var input := Vector2(x, y)
	if input.length() < 0.1:
		return Vector3.ZERO
	input = input.normalized()
	var cam: Camera3D = game.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var dir := right * input.x + fwd * input.y
	return dir.normalized()


func _ai_dir(delta: float) -> Vector3:
	ai_think -= delta
	if ai_think <= 0.0:
		ai_think = 0.3
		_ai_pick_goal()
		_ai_abilities()
	var to_goal := ai_goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	var dir := Vector3.ZERO
	if dist > 0.8:
		dir = to_goal / dist
	var enemy := ai_attack_target
	if enemy != null and is_instance_valid(enemy) and ranged:
		var away := global_position - enemy.global_position
		away.y = 0.0
		var d := away.length()
		if d < attack_range * 0.65 and d > 0.1:
			dir = away.normalized()
	var sep := Vector3.ZERO
	for other in game.heroes:
		if other == self or other.dead:
			continue
		var delta_pos: Vector3 = global_position - other.global_position
		delta_pos.y = 0.0
		var dd := delta_pos.length()
		if dd > 0.01 and dd < 1.7:
			sep += delta_pos.normalized() * (1.7 - dd)
	dir += sep * 0.8
	if stun_timer > 0.0:
		return Vector3.ZERO
	return dir.normalized() if dir.length() > 0.01 else Vector3.ZERO


func _ai_abilities() -> void:
	if dead or stun_timer > 0.0:
		return
	var enemy: HeroUnit = game.nearest_enemy(global_position, team, 13.0)
	var dist := global_position.distance_to(enemy.global_position) if enemy != null else 99.0
	var shell_target: SkyShell = game.shell
	var near_shell: bool = shell_target != null and is_instance_valid(shell_target) and shell_target.alive and global_position.distance_to(shell_target.global_position) < 8.0
	match hero_class:
		Cls.WARRIOR:
			if enemy != null and dist < 3.8 and ability_ready(1):
				use_ability(1)
			elif enemy != null and dist < 8.0 and dist > 3.0 and ability_ready(0):
				use_ability(0)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.5:
				use_ability(2)
		Cls.MAGE:
			var ally: HeroUnit = game.lowest_ally(global_position, team, 12.0)
			if ally != null and ally.health < ally.max_health * 0.62 and ability_ready(0):
				use_ability(0)
			elif enemy != null and dist < 6.0 and ability_ready(1):
				use_ability(1)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.4:
				use_ability(2)
		Cls.FAIRY:
			if enemy != null and dist < 12.0 and dist > 5.5 and ability_ready(1):
				use_ability(1)
			elif enemy != null and dist < 9.0 and ability_ready(0):
				use_ability(0)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.45:
				use_ability(2)


func _ai_pick_goal() -> void:
	var enemy: HeroUnit = game.nearest_enemy(global_position, team, 30.0)
	ai_attack_target = enemy
	if carrying:
		ai_goal = _base_position()
		return
	if health < max_health * 0.28:
		ai_goal = _base_position()
		return
	var crystal_node: Node3D = game.crystal_node
	if game.crystal_state == "ground" and crystal_node != null and is_instance_valid(crystal_node):
		ai_goal = crystal_node.global_position
		return
	var shell = game.shell
	if shell != null and is_instance_valid(shell) and shell.alive:
		ai_goal = shell.global_position
		return
	if enemy != null:
		var enemy_base := Vector3(0.0, 0.0, 12.0 if team == 0 else -12.0)
		var goal := enemy.global_position
		var from_base := goal - enemy_base
		from_base.y = 0.0
		if from_base.length() < 9.0:
			goal = enemy_base + from_base.normalized() * 9.0
		ai_goal = goal + ai_offset
	else:
		ai_goal = Vector3(0.0, 0.0, 0.0)


func _base_position() -> Vector3:
	var z := -12.0 if team == 0 else 12.0
	return Vector3(ai_offset.x, 0.0, z)


func _try_auto_attack(delta: float) -> void:
	if attack_cd > 0.0:
		return
	var target := _attack_target()
	if target == null:
		return
	var d := global_position.distance_to(target.global_position)
	if d > attack_range + 0.5:
		return
	attack_cd = attack_interval
	attack_anim_time = 0.35
	_face((target.global_position - global_position), 1.0)
	_play_anim("attack")
	if ranged:
		var color: Color = CLASS_DATA[hero_class]["color"]
		game.spawn_projectile(global_position + Vector3(0.0, 1.2, 0.0), target, attack_damage, color, self)
	else:
		target.take_damage(attack_damage, self)
		game.melee_fx(global_position + Vector3(0.0, 1.0, 0.0), target.global_position)


func _attack_target() -> Node3D:
	var best: Node3D = null
	var best_d := attack_range + 0.6
	for h in game.enemies_of(team):
		if h.dead:
			continue
		var d := global_position.distance_to(h.global_position)
		if d < best_d:
			best_d = d
			best = h
	if best != null:
		return best
	var shell = game.shell
	if shell != null and is_instance_valid(shell) and shell.alive:
		var ds := global_position.distance_to(shell.global_position)
		if ds < best_d + 0.8:
			return shell
	return null


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.001:
		return
	var target_y := atan2(dir.x, dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_y, minf(1.0, 12.0 * delta))


func _update_look(delta: float) -> void:
	if health_fill == null:
		return
	var frac := clampf(health / max_health, 0.0, 1.0)
	health_fill.scale.x = maxf(0.001, frac)
	health_fill.position.x = (frac - 1.0) * 0.59
	health_fill.visible = not dead
	if carry_light != null:
		carry_light.light_energy = 2.0 if carrying else 0.0
	if visual != null and visual.visible:
		var horizontal := Vector2(velocity.x, velocity.z).length()
		if not dead and attack_anim_time <= 0.0:
			_play_anim("run" if horizontal > move_speed * 0.55 else "walk" if horizontal > 0.4 else "idle")


func take_damage(amount: float, source: Node = null) -> void:
	if dead:
		return
	health -= amount
	game.damage_number(global_position + Vector3(0.0, 2.0, 0.0), amount, team)
	if health <= 0.0:
		health = 0.0
		_die()


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(max_health, health + amount)
	game.heal_number(global_position + Vector3(0.0, 2.2, 0.0), amount)


func stun(duration: float) -> void:
	if dead:
		return
	stun_timer = maxf(stun_timer, duration)


func _die() -> void:
	dead = true
	respawn_timer = 8.0
	velocity = Vector3.ZERO
	carrying = false
	stun_timer = 0.0
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	visual.visible = false
	if health_fill != null:
		health_fill.visible = false
	game.on_hero_died(self)
	hero_died.emit(self)


func _respawn() -> void:
	dead = false
	health = max_health
	global_position = _base_position() + Vector3(0.0, 0.4, 0.0)
	velocity = Vector3.ZERO
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	visual.visible = true
	current_anim = ""
	if health_fill != null:
		health_fill.visible = true
	game.on_hero_respawned(self)


func use_ability(index: int) -> bool:
	if dead or stun_timer > 0.0:
		return false
	if index < 0 or index >= 3:
		return false
	if ability_cds[index] > 0.0:
		return false
	var data: Dictionary = CLASS_DATA[hero_class]["abilities"][index]
	ability_cds[index] = data["cd"]
	cast_flash = 0.35
	_play_anim("cast")
	var color: Color = CLASS_DATA[hero_class]["color"]
	var origin := global_position
	match String(data["type"]):
		"dash":
			var dir := Vector3(sin(visual.rotation.y), 0.0, cos(visual.rotation.y))
			var start := global_position
			for step in 6:
				var moved := move_and_collide(dir * 0.9)
				if moved != null:
					break
			game.aoe(global_position, 2.4, 26.0, team, 0.0, true)
			game.burst(global_position, color, 20)
			game.ring_fx(start, color, 3.0)
		"stun_aoe":
			game.aoe(origin, 4.0, 18.0, team, 1.6, true)
			game.burst(origin, color, 26)
			game.ring_fx(origin, color, 4.2)
		"ult_aoe":
			game.aoe(origin, 6.5, 60.0, team, 0.6, true)
			game.burst(origin, color, 46)
			game.ring_fx(origin, color, 6.6)
			game.shake(0.4)
		"heal":
			game.heal_area(origin, 12.0, 55.0, team, 1)
			game.burst(origin, Color(0.65, 1.0, 0.75), 18)
		"root_aoe":
			game.aoe(origin, 6.0, 16.0, team, 2.0, true)
			game.burst(origin, color, 24)
			game.ring_fx(origin, color, 6.0)
		"ult_support":
			game.heal_area(origin, 14.0, 55.0, team, 99)
			game.aoe(origin, 14.0, 34.0, team, 0.0, true)
			game.burst(origin, color, 40)
			game.ring_fx(origin, color, 14.0)
		"volley":
			var target: HeroUnit = game.nearest_enemy(origin, team, 14.0)
			if target != null:
				game.spawn_projectile(origin + Vector3(0.0, 1.2, 0.0), target, 15.0, color, self)
				game.spawn_projectile(origin + Vector3(0.6, 1.2, 0.0), target, 15.0, color, self)
				game.spawn_projectile(origin + Vector3(-0.6, 1.2, 0.0), target, 15.0, color, self)
		"stun_shot":
			var target2: HeroUnit = game.nearest_enemy(origin, team, 16.0)
			if target2 != null:
				game.spawn_projectile(origin + Vector3(0.0, 1.3, 0.0), target2, 24.0, color, self, 1.8)
		"ult_rain":
			var target3: HeroUnit = game.nearest_enemy(origin, team, 18.0)
			var center: Vector3 = target3.global_position if target3 != null else origin + Vector3(0.0, 0.0, 4.0)
			game.aoe(center, 5.0, 62.0, team, 0.0, true)
			game.burst(center, color, 50)
			game.ring_fx(center, color, 5.0)
			game.shake(0.25)
	return true


func ability_data(index: int) -> Dictionary:
	return CLASS_DATA[hero_class]["abilities"][index]


func ability_ready(index: int) -> bool:
	return ability_cds[index] <= 0.01
