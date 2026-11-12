extends SceneTree


func _init() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	var main := scene.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	await process_frame

	var arena := main.get_node_or_null("Arena") as Node3D
	if arena == null:
		print("NO ARENA")
		quit()
		return

	for child in arena.get_children():
		print("ARENA CHILD: ", child.name, " (", child.get_class(), ") children=", child.get_child_count())

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
		print("DECOR trees=", trees, " rocks=", rocks, " crystals=", crystals)

	var bushes := arena.get_node_or_null("Bushes") as Node3D
	if bushes != null:
		print("BUSHES children=", bushes.get_child_count())
	quit()
