extends SceneTree


func _init() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	if scene == null:
		print("LOAD FAILED")
		quit()
		return
	var root := scene.instantiate()
	_report(root, 0)
	quit()


func _report(node: Node, depth: int) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var box := mi.get_aabb()
		var size := box.size
		if size.x > 2.0 or size.z > 2.0:
			print("%s%s  aabb_size=(%.1f, %.1f, %.1f) pos=(%.1f, %.1f, %.1f)" % [
				"  ".repeat(depth), node.name, size.x, size.y, size.z,
				mi.global_position.x, mi.global_position.y, mi.global_position.z])
	for child in node.get_children():
		_report(child, depth + 1)
