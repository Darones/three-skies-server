extends Node3D

const HEROES := {
	"fairy": "res://art/generated/fairy/rig.glb",
	"mage": "res://art/generated/mage/rig.glb",
	"warrior": "res://art/generated/warrior/rig.glb",
}


func _ready() -> void:
	for hero_key in HEROES.keys():
		var scene := load(HEROES[hero_key]) as PackedScene
		var model := scene.instantiate() as Node3D
		add_child(model)
		await get_tree().process_frame
		var box := _aabb(model)
		print(hero_key, " aabb pos=", box.position, " size=", box.size)
		var skel := _find_skel(model)
		if skel != null:
			print("  skel scale=", skel.global_transform.basis.get_scale())
			print("  bones=", skel.get_bone_count())
			for i in range(mini(4, skel.get_bone_count())):
				print("   bone ", skel.get_bone_name(i), " pose=", skel.get_bone_global_pose(i).origin)
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).mesh != null:
			var mi := current as MeshInstance3D
			var box := mi.global_transform * mi.get_aabb()
			if first:
				result = box
				first = false
			else:
				result = result.merge(box)
		for child in current.get_children():
			stack.append(child)
	return result


func _find_skel(node: Node) -> Skeleton3D:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Skeleton3D:
			return current as Skeleton3D
		for child in current.get_children():
			stack.append(child)
	return null
