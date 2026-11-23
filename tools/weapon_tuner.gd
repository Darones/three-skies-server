extends Control

# Тунер оружия: выбираешь героя и оружие, крутишь положение/поворот/масштаб,
# сохраняешь в user://weapon_tune_all.json. Числа потом переносятся в hero.gd.

const HEROES := {
	"warrior": {"name": "Воин", "class": HeroUnit.Cls.WARRIOR},
	"mage": {"name": "Маг", "class": HeroUnit.Cls.MAGE},
	"fairy": {"name": "Арбалетчица", "class": HeroUnit.Cls.FAIRY},
}

const WEAPONS := {
	"warrior_axe": {
		"name": "Боевой топор",
		"hero": "warrior",
		"bone": "handslot.r",
		"path": "res://addons/low_poly_rpg_items/models/battle_axe_model.glb",
		"position": Vector3(0.0, 0.0, 0.05),
		"rotation": Vector3(45.6, 27.7, 60.8),
		"roll": 90.0,
		"scale": 1.1,
	},
	"warrior_longsword": {
		"name": "Стальной меч",
		"hero": "warrior",
		"bone": "handslot.r",
		"path": "res://addons/low_poly_rpg_items/models/longsword_model.glb",
		"position": Vector3(0.0, 0.0, 0.05),
		"rotation": Vector3(45.6, 27.7, 60.8),
		"roll": 90.0,
		"scale": 1.0,
	},
	"mage_wizard_staff": {
		"name": "Посох ученика",
		"hero": "mage",
		"bone": "handslot.r",
		"path": "res://addons/low_poly_rpg_items/models/staff_wizard_model.glb",
		"position": Vector3(0.0, 0.0, 0.05),
		"rotation": Vector3(45.0, 26.9, 60.1),
		"roll": 0.0,
		"scale": 0.8,
	},
	"mage_crystal_staff": {
		"name": "Кристальный посох",
		"hero": "mage",
		"bone": "handslot.r",
		"path": "res://assets/weapons/wizards_staff_low.glb",
		"position": Vector3(0.0, 0.0, 0.05),
		"rotation": Vector3(45.0, 26.9, 60.1),
		"roll": 0.0,
		"scale": 0.65,
	},
	"fairy_short_bow": {
		"name": "Короткий лук",
		"hero": "fairy",
		"bone": "handslot.l",
		"path": "res://addons/low_poly_rpg_items/models/short_bow_model.glb",
		"position": Vector3(0.0, 0.0, 0.05),
		"rotation": Vector3(-47.4, 6.4, -14.5),
		"roll": 0.0,
		"scale": 1.0,
	},
	"fairy_elven_bow": {
		"name": "Эльфийский лук",
		"hero": "fairy",
		"bone": "handslot.l",
		"path": "res://scenes/LegendaryBow.tscn",
		"position": Vector3(0.0, 0.0, 0.05),
		"rotation": Vector3(-47.4, 6.4, -14.5),
		"roll": 90.0,
		"scale": 1.0,
	},
	"fairy_crossbow": {
		"name": "Стандартный арбалет",
		"hero": "fairy",
		"bone": "handslot.l",
		"builtin_mesh": "1H_Crossbow",
		"weapon_id": 0,
		"position": Vector3(0.104628, -0.010374, 0.0),
		"rotation": Vector3(0.0, -90.0, 0.0),
		"roll": 0.0,
		"scale": 1.0,
	},
	"fairy_heavy_crossbow": {
		"name": "Тяжёлый арбалет",
		"hero": "fairy",
		"bone": "handslot.l",
		"builtin_mesh": "2H_Crossbow",
		"weapon_id": 2,
		"position": Vector3(0.104628, -0.010374, 0.0),
		"rotation": Vector3(0.0, -90.0, 0.0),
		"roll": 0.0,
		"scale": 1.0,
	},
}

const VIEWS := {
	"СПЕРЕДИ": [Vector3(0.0, 1.05, 3.4), Vector3(0.0, 1.05, 0.0)],
	"СЗАДИ": [Vector3(0.0, 1.05, -3.4), Vector3(0.0, 1.05, 0.0)],
	"СБОКУ": [Vector3(3.4, 1.05, 0.0), Vector3(0.0, 1.05, 0.0)],
	"СВЕРХУ": [Vector3(0.0, 4.2, 0.02), Vector3(0.0, 0.6, 0.0)],
	"3/4": [Vector3(2.4, 1.9, 2.4), Vector3(0.0, 1.0, 0.0)],
}

const SAVE_PATH := "user://weapon_tune_all.json"
const RANGES := {
	"px": [-2.0, 2.0], "py": [-2.0, 2.0], "pz": [-2.0, 2.0],
	"rx": [-180.0, 180.0], "ry": [-180.0, 180.0], "rz": [-180.0, 180.0],
	"roll": [-180.0, 180.0],
	"scale": [0.1, 3.0],
}

var hero_key := "warrior"
var weapon_key := "warrior_sword"
var params := {
	"px": 0.0, "py": 0.0, "pz": -0.12,
	"rx": 0.0, "ry": 0.0, "rz": 0.0,
	"roll": 0.0,
	"scale": 1.0,
}

var viewport: SubViewport
var camera: Camera3D
var hero_root: Node3D = null
var skeleton: Skeleton3D = null
var bone_index := -1
var weapon_model: Node3D = null
var weapon_is_builtin := false
var sliders := {}
var spins := {}
var saved_all := {}
var weapon_option: OptionButton
var hero_option: OptionButton
var requested_weapon := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon="):
			requested_weapon = arg.trim_prefix("--weapon=")
	if not requested_weapon.is_empty() and WEAPONS.has(requested_weapon):
		hero_key = String(WEAPONS[requested_weapon]["hero"])
	_load_saved()
	_build_ui()
	var hero_keys := HEROES.keys()
	var hero_index := hero_keys.find(hero_key)
	if hero_index >= 0:
		hero_option.select(hero_index)
	if not requested_weapon.is_empty():
		var keys := _weapon_keys_for_hero()
		var index := keys.find(requested_weapon)
		if index >= 0:
			weapon_key = requested_weapon
			weapon_option.select(index)
	_apply_params(_weapon_defaults(weapon_key))
	_reload_hero()
	if OS.get_cmdline_user_args().has("--autoshot"):
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://weapon_tuner.png")
		print("WEAPON_TUNER_SHOT")
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
	hero_option = OptionButton.new()
	for key in HEROES.keys():
		hero_option.add_item(String(HEROES[key]["name"]))
	hero_option.item_selected.connect(func(index: int) -> void:
		hero_key = String(HEROES.keys()[index])
		_rebuild_weapon_list()
		_reload_hero())
	panel.add_child(hero_option)

	panel.add_child(_make_label("ОРУЖИЕ"))
	weapon_option = OptionButton.new()
	panel.add_child(weapon_option)
	weapon_option.item_selected.connect(func(index: int) -> void:
		weapon_key = _weapon_keys_for_hero()[index]
		_apply_params(_weapon_defaults(weapon_key))
		_reload_weapon())
	_rebuild_weapon_list()

	for key in ["px", "py", "pz", "rx", "ry", "rz", "roll", "scale"]:
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
			_update_weapon())
		spin.value_changed.connect(func(value: float) -> void:
			slider.set_value_no_signal(value)
			params[key] = value
			_update_weapon())
		sliders[key] = slider
		spins[key] = spin

	var save_button := Button.new()
	save_button.text = "Сохранить JSON"
	save_button.custom_minimum_size = Vector2(0, 40)
	save_button.pressed.connect(_save_json)
	panel.add_child(save_button)
	var hint := _make_label("Сохрани JSON — агент перенесёт числа в игру. Файл:\n%s" % ProjectSettings.globalize_path(SAVE_PATH))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	panel.add_child(hint)

	var log_label := Label.new()
	log_label.name = "LogLabel"
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(0, 160)
	log_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(log_label)


func _weapon_keys_for_hero() -> Array:
	var keys := []
	for key in WEAPONS.keys():
		if String(WEAPONS[key]["hero"]) == hero_key:
			keys.append(String(key))
	return keys


func _rebuild_weapon_list() -> void:
	var keys := _weapon_keys_for_hero()
	weapon_option.clear()
	for key in keys:
		weapon_option.add_item(String(WEAPONS[key]["name"]))
	if not keys.is_empty():
		weapon_key = String(keys[0])
		weapon_option.select(0)


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


func _load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var reader := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if reader == null:
		return
	var parsed: Variant = JSON.parse_string(reader.get_as_text())
	reader.close()
	if parsed is Dictionary:
		saved_all = parsed


func _weapon_defaults(key: String) -> Dictionary:
	if saved_all.has(key):
		var saved: Dictionary = saved_all[key]
		var pos: Array = saved.get("position", [0.0, 0.0, 0.0])
		var rot: Array = saved.get("rotation", [0.0, 0.0, 0.0])
		return {
			"px": float(pos[0]), "py": float(pos[1]), "pz": float(pos[2]),
			"rx": float(rot[0]), "ry": float(rot[1]), "rz": float(rot[2]),
			"roll": float(saved.get("roll", 0.0)),
			"scale": float(saved.get("scale", 1.0)),
		}
	var preset: Dictionary = WEAPONS[key]
	var position: Vector3 = preset["position"]
	var rotation: Vector3 = preset["rotation"]
	return {
		"px": position.x, "py": position.y, "pz": position.z,
		"rx": rotation.x, "ry": rotation.y, "rz": rotation.z,
		"roll": float(preset.get("roll", 0.0)),
		"scale": float(preset["scale"]),
	}


func _apply_params(values: Dictionary) -> void:
	for key in values.keys():
		params[key] = values[key]
		if sliders.has(key):
			(sliders[key] as HSlider).set_value_no_signal(float(values[key]))
		if spins.has(key):
			(spins[key] as SpinBox).set_value_no_signal(float(values[key]))
	_update_weapon()


func _reload_hero() -> void:
	if hero_root != null and is_instance_valid(hero_root):
		hero_root.queue_free()
	var cls: int = int(HEROES[hero_key]["class"])
	# The tuner uses the real HeroUnit so scale, skeleton and idle pose match
	# the game exactly; the old raw rig was often at a different scale.
	var preset: Dictionary = WEAPONS[weapon_key]
	var builtin_mesh := String(preset.get("builtin_mesh", ""))
	var weapon_id := int(preset.get("weapon_id", 0))
	MetaProgression.equipped_weapons[hero_key] = weapon_id
	var hero := HeroUnit.new()
	viewport.add_child(hero)
	hero.setup(null, cls, 0, true)
	hero.set_physics_process(false)
	hero.position = Vector3.ZERO
	hero.set_preview_mode(true)
	hero.visual.rotation.y = PI
	for gear_name in hero.gear_nodes.keys():
		var gear := hero.gear_nodes[gear_name] as MeshInstance3D
		if gear != null:
			gear.visible = String(gear_name) == builtin_mesh
	hero_root = hero
	_build_lights(hero)
	_apply_idle_pose(hero)
	skeleton = _find_skeleton(hero)
	_reload_weapon()


func _apply_idle_pose(hero: Node3D) -> void:
	# в игре герой стоит в idle, а не в T-позе — настраивать надо по той же позе
	var player := hero.get("anim_player") as AnimationPlayer
	if player == null:
		player = _find_anim(hero)
	if player == null:
		return
	for anim_name in player.get_animation_list():
		if String(anim_name).to_lower().contains("idle"):
			player.play(anim_name)
			player.seek(0.6, true)
			player.pause()
			return


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


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


func _reload_weapon() -> void:
	if weapon_model != null and is_instance_valid(weapon_model):
		if weapon_is_builtin:
			weapon_model.visible = false
		else:
			weapon_model.queue_free()
		weapon_model = null
	weapon_is_builtin = false
	if hero_root != null:
		for gear_name in hero_root.gear_nodes.keys():
			var gear := hero_root.gear_nodes[gear_name] as MeshInstance3D
			if gear != null:
				gear.visible = false
	if skeleton == null:
		return
	var preset: Dictionary = WEAPONS[weapon_key]
	var builtin_mesh := String(preset.get("builtin_mesh", ""))
	if not builtin_mesh.is_empty():
		if hero_root == null:
			return
		weapon_model = hero_root.find_child(builtin_mesh, true, false) as Node3D
		if weapon_model == null:
			return
		weapon_model.visible = true
		weapon_is_builtin = true
		_update_weapon()
		return
	bone_index = -1
	var wanted := String(preset["bone"])
	for i in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(i)).to_lower() == wanted:
			bone_index = i
			break
	if bone_index < 0:
		return
	var scene := load(String(preset["path"])) as PackedScene
	if scene == null:
		return
	weapon_model = scene.instantiate() as Node3D
	viewport.add_child(weapon_model)
	_update_weapon()


func _update_weapon() -> void:
	if weapon_model == null:
		return
	var offset_basis := Basis.from_euler(Vector3(
		deg_to_rad(float(params["rx"])),
		deg_to_rad(float(params["ry"])),
		deg_to_rad(float(params["rz"]))
	))
	if absf(float(params["roll"])) > 0.01:
		offset_basis = offset_basis * Basis(Vector3.UP, deg_to_rad(float(params["roll"])))
	offset_basis = offset_basis.scaled(Vector3.ONE * float(params["scale"]))
	var offset := Vector3(float(params["px"]), float(params["py"]), float(params["pz"]))
	if weapon_is_builtin:
		# Built-in crossbows live under handslot_l. Tune the local transform so
		# the same numbers can be baked into WeaponCatalog.CROSSBOW_TUNING.
		weapon_model.transform = Transform3D(offset_basis, offset)
		return
	if skeleton == null or bone_index < 0:
		return
	var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	var base := bone_world.basis.orthonormalized()
	weapon_model.global_transform = Transform3D(base * offset_basis, bone_world.origin + offset)


func _process(_delta: float) -> void:
	_update_weapon()


func _save_json() -> void:
	var data := {
		"hero": hero_key,
		"weapon": weapon_key,
		"position": [float(params["px"]), float(params["py"]), float(params["pz"])],
		"rotation": [float(params["rx"]), float(params["ry"]), float(params["rz"])],
		"roll": float(params["roll"]),
		"scale": float(params["scale"]),
	}
	saved_all[weapon_key] = data
	var writer := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if writer != null:
		writer.store_string(JSON.stringify(saved_all, "  "))
		writer.close()
	var log_label := find_child("LogLabel", true, false) as Label
	if log_label != null:
		log_label.text = "%s\n\nSaved: %d" % [JSON.stringify(data, "  "), saved_all.size()]
	print("WEAPON_TUNE ", JSON.stringify(data))
	print("WEAPON_TUNE_PATH ", ProjectSettings.globalize_path(SAVE_PATH))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
