extends Control

# Тунер крыльев: один вид с переключением ракурсов (спереди/сбоку/сверху/3-4),
# ползунки положения, поворота и масштаба, сохранение в user://wings_tune.json.

const HEROES := {
	"warrior": "res://art/generated/warrior/rig.glb",
	"mage": "res://art/generated/mage/rig.glb",
	"fairy": "res://art/generated/fairy/rig.glb",
}
const WINGS := {
	1: "res://assets/wings/angel_wings_animated.glb",
	2: "res://assets/wings/angel_wings_animated.glb",
	3: "res://assets/wings/angel_wings_animated.glb",
	4: "res://assets/wings/low_poly_demon_wings_animated.glb",
}
const TINTS := {
	1: Color(1, 1, 1),
	2: Color(1.0, 0.78, 0.34),
	3: Color(0.10, 0.09, 0.13),
	4: Color(1, 1, 1),
}
const SAVE_PATH := "user://wings_tune.json"

const VIEWS := {
	"СПЕРЕДИ": [Vector3(0.0, 1.05, 3.4), Vector3(0.0, 1.05, 0.0)],
	"СЗАДИ": [Vector3(0.0, 1.05, -3.4), Vector3(0.0, 1.05, 0.0)],
	"СБОКУ": [Vector3(3.4, 1.05, 0.0), Vector3(0.0, 1.05, 0.0)],
	"СВЕРХУ": [Vector3(0.0, 4.2, 0.02), Vector3(0.0, 0.6, 0.0)],
	"3/4": [Vector3(2.4, 1.9, 2.4), Vector3(0.0, 1.0, 0.0)],
}

var hero_key := "warrior"
var wing_id := 1
var params := {
	"px": 0.0, "py": 0.0, "pz": -0.12,
	"rx": 0.0, "ry": 0.0, "rz": 0.0,
	"scale": 1.0,
}
var sliders := {}
var spins := {}

var viewport: SubViewport
var camera: Camera3D
var hero_root: Node3D = null
var skeleton: Skeleton3D = null
var bone_index := -1
var wing_model: Node3D = null

const RANGES := {
	"px": [-2.0, 2.0], "py": [-2.0, 2.0], "pz": [-2.0, 2.0],
	"rx": [-180.0, 180.0], "ry": [-180.0, 180.0], "rz": [-180.0, 180.0],
	"scale": [0.2, 2.0],
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_reload_hero()
	if OS.get_cmdline_user_args().has("--autoshot"):
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://tuner.png")
		print("TUNER_SHOT")
		get_tree().quit()


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(left)

	var view_buttons := HBoxContainer.new()
	view_buttons.add_theme_constant_override("separation", 6)
	left.add_child(view_buttons)
	for view_name in VIEWS.keys():
		var button := Button.new()
		button.text = String(view_name)
		button.custom_minimum_size = Vector2(120, 34)
		button.pressed.connect(_set_view.bind(String(view_name)))
		view_buttons.add_child(button)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(container)

	viewport = SubViewport.new()
	viewport.size = Vector2i(900, 700)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	viewport.add_child(camera)
	camera.current = true
	_set_view("СПЕРЕДИ")

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	panel.add_theme_constant_override("separation", 4)
	root.add_child(panel)

	panel.add_child(_make_label("ГЕРОЙ"))
	var hero_option := OptionButton.new()
	for key in HEROES.keys():
		hero_option.add_item(String(key))
	hero_option.item_selected.connect(func(index: int) -> void:
		hero_key = String(HEROES.keys()[index])
		_reload_hero())
	panel.add_child(hero_option)

	panel.add_child(_make_label("КРЫЛЬЯ"))
	var wing_option := OptionButton.new()
	for id in WINGS.keys():
		wing_option.add_item("Крылья %d" % int(id))
	wing_option.item_selected.connect(func(index: int) -> void:
		wing_id = int(WINGS.keys()[index])
		_apply_params(_wing_defaults(wing_id))
		_reload_wing())
	panel.add_child(wing_option)

	for key in ["px", "py", "pz", "rx", "ry", "rz", "scale"]:
		panel.add_child(_make_label(key.to_upper()))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		panel.add_child(row)
		var slider := HSlider.new()
		slider.min_value = RANGES[key][0]
		slider.max_value = RANGES[key][1]
		slider.step = 0.01
		slider.value = float(params[key])
		slider.custom_minimum_size = Vector2(0, 22)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var spin := SpinBox.new()
		spin.min_value = RANGES[key][0]
		spin.max_value = RANGES[key][1]
		spin.step = 0.01
		spin.value = float(params[key])
		spin.custom_minimum_size = Vector2(96, 0)
		row.add_child(spin)
		slider.value_changed.connect(func(value: float) -> void:
			spin.set_value_no_signal(value)
			params[key] = value
			_update_wing())
		spin.value_changed.connect(func(value: float) -> void:
			slider.set_value_no_signal(value)
			params[key] = value
			_update_wing())
		sliders[key] = slider
		spins[key] = spin

	var save_button := Button.new()
	save_button.text = "Сохранить JSON"
	save_button.custom_minimum_size = Vector2(0, 40)
	save_button.pressed.connect(_save_json)
	panel.add_child(save_button)

	var log_label := Label.new()
	log_label.name = "LogLabel"
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(0, 160)
	log_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(log_label)


func _set_view(view_name: String) -> void:
	if camera == null or not VIEWS.has(view_name):
		return
	camera.position = VIEWS[view_name][0]
	camera.look_at(VIEWS[view_name][1], Vector3.UP)
	camera.current = true


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(0.8, 0.84, 0.92)
	return label


func _reload_hero() -> void:
	if hero_root != null and is_instance_valid(hero_root):
		hero_root.queue_free()
	hero_root = load(HEROES[hero_key]).instantiate() as Node3D
	viewport.add_child(hero_root)
	_build_lights(hero_root)
	skeleton = _find_skeleton(hero_root)
	bone_index = -1
	for i in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(i)).to_lower().contains("spine02"):
			bone_index = i
			break
	_reload_wing()


func _build_lights(parent: Node3D) -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "TunerEnv"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.10, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.63, 0.75)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	parent.add_child(env_node)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, 150.0, 0.0)
	key.light_energy = 1.5
	parent.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -40.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.75, 0.8, 1.0)
	parent.add_child(fill)


func _reload_wing() -> void:
	if wing_model != null and is_instance_valid(wing_model):
		wing_model.queue_free()
		wing_model = null
	if skeleton == null or bone_index < 0:
		return
	var scene := load(String(WINGS[wing_id])) as PackedScene
	if scene == null:
		return
	wing_model = scene.instantiate() as Node3D
	viewport.add_child(wing_model)
	_apply_tint()
	_update_wing()


func _apply_tint() -> void:
	var tint: Color = TINTS[wing_id]
	if tint.is_equal_approx(Color.WHITE):
		return
	var shader: Shader = load("res://shaders/wing_tint.gdshader")
	for node in wing_model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s) as BaseMaterial3D
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("tint", tint)
			mat.set_shader_parameter("emission_strength", 0.15 if wing_id == 2 else 0.0)
			mat.set_shader_parameter("rim_strength", 0.30 if wing_id == 2 else 0.0)
			if src != null and src.albedo_texture != null:
				mat.set_shader_parameter("albedo_texture", src.albedo_texture)
			mi.set_surface_override_material(s, mat)


func _update_wing() -> void:
	if wing_model == null or skeleton == null or bone_index < 0:
		return
	var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	var skel_basis := skeleton.global_transform.basis
	var up := Vector3.UP
	var forward := -skel_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var basis := Basis(right, up, forward)
	basis = basis * Basis.from_euler(Vector3(
		deg_to_rad(float(params["rx"])),
		deg_to_rad(float(params["ry"])),
		deg_to_rad(float(params["rz"]))
	))
	basis = basis.scaled(Vector3.ONE * float(params["scale"]))
	var offset := Vector3(float(params["px"]), float(params["py"]), float(params["pz"]))
	wing_model.global_transform = Transform3D(basis, bone_world.origin + offset)


func _process(_delta: float) -> void:
	_update_wing()


func _wing_defaults(id: int) -> Dictionary:
	match id:
		4:
			return {"px": 0.0, "py": -0.85, "pz": -0.12, "rx": 0.0, "ry": 0.0, "rz": 0.0, "scale": 0.006}
		3:
			return {"px": 0.0, "py": 0.0, "pz": -0.12, "rx": 0.0, "ry": 0.0, "rz": 4.0, "scale": 1.06}
		_:
			return {"px": 0.0, "py": 0.0, "pz": -0.12, "rx": 0.0, "ry": 0.0, "rz": 0.0, "scale": 1.0}


func _apply_params(values: Dictionary) -> void:
	for key in values.keys():
		params[key] = values[key]
		if sliders.has(key):
			(sliders[key] as HSlider).set_value_no_signal(float(values[key]))
		if spins.has(key):
			(spins[key] as SpinBox).set_value_no_signal(float(values[key]))
	_update_wing()


func _save_json() -> void:
	var data := {
		"hero": hero_key,
		"wing": wing_id,
		"position": [float(params["px"]), float(params["py"]), float(params["pz"])],
		"rotation": [float(params["rx"]), float(params["ry"]), float(params["rz"])],
		"scale": float(params["scale"]),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()
	var log_label := find_child("LogLabel", true, false) as Label
	var text := JSON.stringify(data, "  ")
	if log_label != null:
		log_label.text = text
	print("WINGS_TUNE ", text)
	print("WINGS_TUNE_PATH ", ProjectSettings.globalize_path(SAVE_PATH))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
