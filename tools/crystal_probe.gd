extends Node3D

# РС‰РµС‚ РІСЃРµ РѕР±СЉРµРєС‚С‹ РІРѕРєСЂСѓРі С†РµРЅС‚СЂР° Р°СЂРµРЅС‹: С‡С‚Рѕ СЌС‚Рѕ Р·Р° Р±РµР»С‹Рµ РєРѕРЅСѓСЃС‹.

func _ready() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	var main := scene.instantiate()
	add_child(main)
	for i in 8:
		await get_tree().process_frame

	var total := 0
	for node in main.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var pos := mi.global_position
		if Vector2(pos.x, pos.z).length() > 16.0:
			continue
		total += 1
		if total > 20:
			continue
		var mat := mi.get_active_material(0) as StandardMaterial3D
		var color := mat.albedo_color if mat != null else Color.MAGENTA
		var kind := "other"
		if mi.mesh is PrismMesh:
			kind = "prism"
		elif mi.mesh is CylinderMesh:
			kind = "cylinder"
		elif mi.mesh is SphereMesh:
			kind = "sphere"
		elif mi.mesh is BoxMesh:
			kind = "box"
		elif mi.mesh is QuadMesh:
			kind = "quad"
		print(kind, " ", mi.name, " parent=", mi.get_parent().name,
			" pos=", Vector3(round(pos.x), round(pos.y), round(pos.z)), " color=", color)
	var shell := main.get_node_or_null("Shell")
	if shell != null:
		print("SHELL visible=", shell.visible, " children=", shell.get_child_count())
		for c in shell.get_children():
			if c is MeshInstance3D:
				print("  shell mesh ", c.name, " vis=", c.visible, " pos=", c.global_position)
	print("NEAR_CENTER_TOTAL ", total)
	get_tree().quit()

