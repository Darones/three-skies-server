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
const CLASS_MAX_HP := [550.0, 500.0, 450.0]
const HEALTH_BAR_WIDTH := 1.3

var peer_id := 0
var display_name := ""
var hero_class := 0
var team := 0
var health := 0.0
var max_health := 0.0
var attack_damage := 0.0
var dead := false
var game: Node = null
var target_position := Vector3.ZERO
var target_rotation := 0.0
var _has_target := false
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
	target_position = position
	target_rotation = rotation_y
	if not _has_target:
		global_position = position
		rotation.y = rotation_y
		_has_target = true


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
	_model_root = holder
	_fit_model(holder)
	_play_idle(holder)


func _load_model() -> Node3D:
	var folder: String = MODEL_DIRS[hero_class]
	var directory := DirAccess.open(folder)
	if directory == null:
		return null
	var chosen := ""
	for file in directory.get_files():
		if file.ends_with(".tscn"):
			chosen = file
			break
	if chosen.is_empty():
		for file in directory.get_files():
			if file.ends_with(".glb"):
				chosen = file
				break
	if chosen.is_empty():
		return null
	var packed := load(folder + "/" + chosen) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


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
			_animation_player.play(animation_name)
			return
	if not animations.is_empty():
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
	_name_label.font = FONT
	_name_label.font_size = 30
	_name_label.pixel_size = 0.0048
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.modulate = Color(0.55, 0.85, 1.0) if team == 0 else Color(0.86, 0.62, 1.0)
	_name_label.outline_size = 6
	_name_label.outline_modulate = Color(0.02, 0.03, 0.06, 0.95)
	_name_label.position = Vector3(0.0, 2.9, 0.0)
	add_child(_name_label)


func _build_health_bar() -> void:
	_health_back = _make_bar_quad("HealthBarBack", Vector2(HEALTH_BAR_WIDTH, 0.18), Color(0.02, 0.03, 0.05, 0.9), 2.48, 0.0)
	_health_fill = _make_bar_quad("HealthBarFill", Vector2(HEALTH_BAR_WIDTH - 0.06, 0.1), Color(0.35, 0.95, 0.48, 1.0), 2.48, 0.01)
	_update_health_bar()


func _make_bar_quad(node_name: String, size: Vector2, color: Color, y: float, z: float) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	bar.name = node_name
	var quad := QuadMesh.new()
	quad.size = size
	bar.mesh = quad
	bar.position = Vector3(0.0, y, z)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_receive_shadows = true
	bar.material_override = material
	add_child(bar)
	return bar


func _update_health_bar() -> void:
	if _health_fill == null or _health_back == null:
		return
	var ratio := clampf(health / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0
	_health_fill.scale.x = ratio
	_health_fill.position.x = -(HEALTH_BAR_WIDTH - 0.06) * (1.0 - ratio) * 0.5
	_health_back.visible = not dead
	_health_fill.visible = not dead


func take_damage(amount: float, source: Node = null, _damage_type := "physical", skill := "auto") -> void:
	if dead:
		return
	if source is HeroUnit and game != null and bool(game.get("network_play")):
		NetworkManager.send_attack_intent(peer_id, skill)
		return
	var applied := minf(maxf(amount, 0.0), health)
	health = maxf(0.0, health - maxf(amount, 0.0))
	_update_health_bar()
	if game != null and game.has_method("damage_number"):
		game.call("damage_number", global_position + Vector3(0.0, 2.0, 0.0), applied, team)


func apply_network_damage(amount: float) -> void:
	if dead:
		return
	health = maxf(0.0, health - maxf(amount, 0.0))
	_update_health_bar()
	if game != null and game.has_method("damage_number"):
		game.call("damage_number", global_position + Vector3(0.0, 2.0, 0.0), amount, team)


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
	if _animation_player != null:
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
