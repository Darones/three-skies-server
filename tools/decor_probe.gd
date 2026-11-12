extends Node3D

# Диагностика арены в реальном запуске: считает, что реально попало в сцену
# после ensure_arena_features / _rebuild_decor.

func _ready() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	if scene == null:
		print("PROBE: Main.tscn load failed")
		get_tree().quit()
		return
	var main := scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var arena := main.get_node_or_null("Arena") as Node3D
	if arena == null:
		print("PROBE: no Arena")
		get_tree().quit()
		return

	print("PROBE: Arena children = ", arena.get_child_count())
	for child in arena.get_children():
		print("PROBE:   ", child.name, " (", child.get_class(), ") children=", child.get_child_count())

	var decor := arena.get_node_or_null("Decor") as Node3D
	if decor != null:
		var trees := 0
		var rocks := 0
		var crystals := 0
		for sub in decor.get_children():
			var low := sub.name.to_lower()
			if low.contains("crystal"):
				crystals += 1
			elif low.contains("rock"):
				rocks += 1
			else:
				trees += 1
		print("PROBE: DECOR trees=", trees, " rocks=", rocks, " crystals=", crystals)

	var bushes := arena.get_node_or_null("Bushes") as Node3D
	if bushes != null:
		print("PROBE: BUSHES children=", bushes.get_child_count())

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 62.0
	cam.position = Vector3(0.0, 60.0, 0.01)
	cam.look_at(Vector3.ZERO, Vector3.FORWARD)
	add_child(cam)
	cam.current = true
	_hide_ui(main)
	for node in main.find_children("*", "MeshInstance3D", true, false):
		if String(node.name).to_lower().contains("fog"):
			(node as MeshInstance3D).visible = false
	var game_camera := main.get_node_or_null("Camera3D") as Camera3D
	if game_camera != null:
		game_camera.current = false
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.9)
	e.ambient_light_energy = 1.4
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70.0, 30.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)

	await get_tree().process_frame
	await get_tree().process_frame
	cam.current = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://decor_top.png")
	print("PROBE: saved user://decor_top.png")

	get_tree().quit()


func _hide_ui(node: Node) -> void:
	if node is CanvasLayer or node is Control:
		if node is CanvasItem:
			(node as CanvasItem).visible = false
	for child in node.get_children():
		_hide_ui(child)
