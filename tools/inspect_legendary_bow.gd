extends SceneTree


func _init() -> void:
	var scene := load("res://assets/models/legendary_bow/Elven_Recurve_Bow_legendary.glb") as PackedScene
	if scene == null:
		print("LOAD FAILED")
		quit()
		return
	var inst := scene.instantiate()
	_dump(inst, 0)
	quit()


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	print(pad, node.name, " [", node.get_class(), "]")
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		print(pad, "  aabb=", mi.get_aabb(), " surfaces=", mi.mesh.get_surface_count() if mi.mesh else -1,
			" blend_shapes=", mi.mesh.blend_shape_count if mi.mesh else -1)
		for i in range(mi.mesh.get_surface_count() if mi.mesh else 0):
			var mat := mi.mesh.surface_get_material(i)
			print(pad, "    surface ", i, " -> ", mat, " name=", mat.resource_name if mat else "none")
	elif node is AnimationPlayer:
		var ap := node as AnimationPlayer
		print(pad, "  animations=", ap.get_animation_list())
		for anim_name in ap.get_animation_list():
			var anim := ap.get_animation(anim_name)
			print(pad, "    ", anim_name, " length=", anim.length, " tracks=", anim.get_track_count())
			for t in range(anim.get_track_count()):
				print(pad, "      track ", t, " ", anim.track_get_path(t), " type=", anim.track_get_type(t))
	for child in node.get_children():
		_dump(child, depth + 1)
