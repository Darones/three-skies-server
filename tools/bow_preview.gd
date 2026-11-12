extends Node3D

# Быстрый «фотоаппарат» для лука: рендерит несколько ракурсов в PNG,
# чтобы проверять материалы и свечение без запуска матча.
# Файл лежит в tools/, поэтому в сборку не попадает.

const BOW_SCENE := "res://scenes/LegendaryBow.tscn"
const OUT_DIR := "user://bow_preview"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.065, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.55)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.96, 0.90)
	key.rotation_degrees = Vector3(-28.0, -38.0, 0.0)
	add_child(key)

	var rim := OmniLight3D.new()
	rim.light_color = Color(0.62, 0.34, 1.0)
	rim.light_energy = 5.0
	rim.omni_range = 4.0
	rim.position = Vector3(0.5, 0.6, 0.9)
	add_child(rim)

	var bow := load(BOW_SCENE).instantiate() as Node3D
	add_child(bow)

	var cam := Camera3D.new()
	cam.fov = 34.0
	add_child(cam)
	cam.current = true

	await _shoot(cam, bow, "front", Vector3(0.0, 0.0, 2.6), 0.0)
	await _shoot(cam, bow, "tq", Vector3(1.45, 0.35, 2.05), 0.0)
	await _shoot(cam, bow, "draw", Vector3(0.0, 0.0, 2.6), 0.34)
	await _shoot(cam, bow, "side", Vector3(2.6, 0.0, 0.05), 0.0)

	print("BOW_PREVIEW_DONE ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shoot(cam: Camera3D, bow: Node3D, shot_name: String, cam_pos: Vector3, anim_time: float) -> void:
	cam.position = cam_pos
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var player := bow.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null and player.has_animation("shoot"):
		if anim_time > 0.0:
			player.play("shoot")
			player.seek(anim_time, true)
			player.pause()
		else:
			player.stop()
			player.play("shoot")
			player.seek(0.0, true)
			player.pause()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := OUT_DIR.path_join("%s.png" % shot_name)
	var err := image.save_png(path)
	print("SHOT ", shot_name, " err=", err, " size=", image.get_size())
