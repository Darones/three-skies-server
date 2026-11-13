class_name ArenaKit
extends RefCounted

const FLOOR_LIGHT_TEX := "res://art/textures/temple_floor/img-6adcd384-a1c6-4d03-ab8f-2885c6220fd5-1793744216285-0_1793744216285_y4vdgmr5.png"
const FLOOR_DARK_TEX := "res://art/textures/obsidian_rock/img-6adcd384-a1c6-4d03-ab8f-2885c6220fd5-1793744225681-0_1793744225682_zroihsmf.png"
const SLATE_DIR := "res://art/textures/slate_floor"
const GLOWING_TREE_SCENE := preload("res://scenes/GlowingFantasyTree.tscn")
const BUSH_SCENE: PackedScene = preload("res://assets/models/small_stylised_bush.glb")
const BUSH_TARGET_HEIGHT := 3.6
const BUSH_PAIR_HALF_SPACING := 1.5
const NAVIGATION_SOURCE_GROUP := "navigation_mesh_source_group"

const HALF_X := 27.0
const HALF_Z := 19.5
const PERIMETER_RIDGE_SEGMENTS := 96

static func _first_texture(folder: String, fallback: String) -> Texture2D:
	var dir := DirAccess.open(folder)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".png") or file.ends_with(".jpg"):
				var tex := load(folder + "/" + file) as Texture2D
				if tex != null:
					return tex
	return load(fallback) as Texture2D


static func floor_light_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := _first_texture(SLATE_DIR, FLOOR_LIGHT_TEX)
	if tex != null:
		mat.albedo_texture = tex
	mat.albedo_color = Color(0.82, 0.81, 0.76)
	mat.roughness = 0.88
	mat.emission_enabled = true
	mat.emission = Color(0.08, 0.075, 0.06)
	mat.emission_energy_multiplier = 0.35
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

static func floor_dark_material() -> StandardMaterial3D:
	return floor_light_material()

static func rock_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := load(FLOOR_DARK_TEX) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
	mat.albedo_color = Color(0.52, 0.49, 0.56)
	mat.roughness = 0.95
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

static func gold_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.42)
	mat.metallic = 0.25
	mat.roughness = 0.32
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.32)
	mat.emission_energy_multiplier = 0.18
	return mat

static func marble_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.53, 0.6)
	mat.roughness = 0.72
	return mat

static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.25
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func crystal_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.65
	mat.roughness = 0.12
	mat.metallic = 0.35
	return mat

static func _is_inside(x: float, z: float) -> bool:
	var nx := x / HALF_X
	var nz := z / HALF_Z
	var ang := atan2(nz, nx)
	var wobble := 1.0 + 0.05 * sin(ang * 3.0) + 0.04 * sin(ang * 5.0 + 1.2) + 0.025 * sin(ang * 9.0 + 2.4)
	return nx * nx + nz * nz <= 0.97 * 0.97 * wobble

static func _shape_point(ang: float, scale: float) -> Vector2:
	var wobble := 1.0 + 0.06 * sin(ang * 3.0 + 0.4) + 0.045 * sin(ang * 5.0 + 1.2) + 0.03 * sin(ang * 9.0 + 2.4)
	return Vector2(cos(ang) * HALF_X * scale * wobble, sin(ang) * HALF_Z * scale * wobble)


static func _floor_height(x: float, z: float) -> float:
	return -0.02 * sin(x * 0.7) - 0.02 * cos(z * 0.6)


static func build_floor_mesh(mat_light: StandardMaterial3D, mat_dark: StandardMaterial3D) -> ArrayMesh:
	var st_light := SurfaceTool.new()
	var st_dark := SurfaceTool.new()
	st_light.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_light.set_material(mat_light)
	st_dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_dark.set_material(mat_dark)
	var step := 1.5
	var x := -HALF_X
	while x < HALF_X - 0.01:
		var z := -HALF_Z
		while z < HALF_Z - 0.01:
			var x1 := x + step
			var z1 := z + step
			if _is_inside((x + x1) * 0.5, (z + z1) * 0.5):
				var surface := st_light if (z + z1) * 0.5 < 0.0 else st_dark
				var a := Vector3(x, _floor_height(x, z), z)
				var b := Vector3(x1, _floor_height(x1, z), z)
				var c := Vector3(x1, _floor_height(x1, z1), z1)
				var d := Vector3(x, _floor_height(x, z1), z1)
				_add_quad(surface, a, b, c, d)
			z += step
		x += step
	st_light.index()
	st_light.generate_normals()
	var mesh := ArrayMesh.new()
	st_light.commit(mesh)
	st_dark.index()
	st_dark.generate_normals()
	st_dark.commit(mesh)
	return mesh


static func build(root: Node3D) -> void:
	var mat_light := floor_light_material()
	var mat_dark := floor_dark_material()
	var mat_rock := rock_material()
	var mat_gold := gold_material()
	var mat_marble := marble_material()

	var stage := Node3D.new()
	stage.name = "Stage"
	root.add_child(stage)
	_add_environment(stage)

	var island := Node3D.new()
	island.name = "Island"
	root.add_child(island)
	_add_island(island, mat_light, mat_dark, mat_rock)

	var altar := Node3D.new()
	altar.name = "Altar"
	root.add_child(altar)
	_add_altar(altar, mat_marble, mat_gold, mat_rock)

	var ruins := Node3D.new()
	ruins.name = "Ruins"
	root.add_child(ruins)
	_add_ruins(ruins, mat_marble, mat_gold, mat_rock)

	var bases := Node3D.new()
	bases.name = "Bases"
	root.add_child(bases)
	_add_base(bases, 28.0, Color(0.55, 0.85, 1.0), mat_rock, "LightBase")
	_add_base(bases, -28.0, Color(0.68, 0.32, 1.0), mat_rock, "DarkBase")

	var decor := Node3D.new()
	decor.name = "Decor"
	root.add_child(decor)
	_add_braziers(decor, mat_gold, mat_rock)
	add_crystal_scatter(decor)
	add_bushes(root)
	ensure_perimeter_ridge(root)
	ensure_arena_features(root)


static func ensure_arena_features(arena_root: Node3D) -> void:
	var island := arena_root.get_node_or_null("Island") as Node3D
	var ruins := arena_root.get_node_or_null("Ruins") as Node3D
	if island != null:
		_ensure_light_floor(island)
		_ensure_visible_boundary_walls(island)
		_ensure_fence_collision(island)
		island.add_to_group("navigation_mesh_source_group", true)
	if ruins != null:
		_ensure_ruin_columns(ruins)
	_rebuild_decor(arena_root)
	_ensure_decor_collisions(arena_root)
	_ensure_navigation_region(arena_root)


static var _occupied: Array = []


static func _is_free(p: Vector3, radius: float, extra: float) -> bool:
	for entry in _occupied:
		var other: Vector3 = entry["pos"]
		var other_radius: float = entry["radius"]
		if Vector2(p.x, p.z).distance_to(Vector2(other.x, other.z)) < radius + other_radius + extra:
			return false
	return true


static func _occupy(p: Vector3, radius: float) -> void:
	_occupied.append({"pos": p, "radius": radius})


static func _rebuild_decor(arena_root: Node3D) -> void:
	# Запечённый в сцену декор больше не используется: арена целиком
	# строится из кода, иначе правки в раскладке не доезжают до игры.
	_occupied.clear()
	for node_name in ["Decor", "Bushes"]:
		var old := arena_root.get_node_or_null(node_name)
		if old != null:
			arena_root.remove_child(old)
			old.queue_free()
	# кусты первыми: остальной декор потом обходит их стороной
	add_bushes(arena_root)
	var decor := Node3D.new()
	decor.name = "Decor"
	arena_root.add_child(decor)
	_add_decor(decor, rock_material())
	add_bushes(arena_root)


static func _ensure_light_floor(island: Node3D) -> void:
	var floor_node := island.get_node_or_null("Floor") as MeshInstance3D
	if floor_node == null or floor_node.mesh == null or floor_node.mesh.get_surface_count() == 0:
		return
	var source_material := floor_node.mesh.surface_get_material(0) as StandardMaterial3D
	if source_material == null:
		return
	var material := source_material.duplicate() as StandardMaterial3D
	material.albedo_color = Color(0.82, 0.81, 0.76, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.075, 0.06)
	material.emission_energy_multiplier = 0.35
	material.roughness = 0.88
	floor_node.mesh.surface_set_material(0, material)


static func _ensure_visible_boundary_walls(island: Node3D) -> void:
	if island.get_node_or_null("BoundaryWall_North") != null:
		return
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.46, 0.49, 0.54)
	wall_material.roughness = 0.92
	var wall_specs := [
		["BoundaryWall_North", Vector3(0.0, 0.7, HALF_Z - 1.0), Vector3(HALF_X * 2.0 - 2.0, 1.4, 1.0)],
		["BoundaryWall_South", Vector3(0.0, 0.7, -HALF_Z + 1.0), Vector3(HALF_X * 2.0 - 2.0, 1.4, 1.0)],
		["BoundaryWall_East", Vector3(HALF_X - 1.0, 0.7, 0.0), Vector3(1.0, 1.4, HALF_Z * 2.0 - 2.0)],
		["BoundaryWall_West", Vector3(-HALF_X + 1.0, 0.7, 0.0), Vector3(1.0, 1.4, HALF_Z * 2.0 - 2.0)],
	]
	for wall_spec in wall_specs:
		var wall := MeshInstance3D.new()
		wall.name = wall_spec[0]
		var box := BoxMesh.new()
		box.size = wall_spec[2]
		wall.mesh = box
		wall.material_override = wall_material
		wall.position = wall_spec[1]
		island.add_child(wall)
		if island.owner != null:
			wall.owner = island.owner


static func _ensure_fence_collision(island: Node3D) -> void:
	var fence := island.get_node_or_null("FenceCollision") as StaticBody3D
	if fence != null and fence.get_child_count() == 4:
		return
	if fence == null:
		fence = island.get_node_or_null("Walls") as StaticBody3D
	if fence == null:
		fence = StaticBody3D.new()
		island.add_child(fence)
	else:
		for old_shape in fence.get_children():
			fence.remove_child(old_shape)
			old_shape.free()
	fence.name = "FenceCollision"
	fence.collision_layer = 1
	fence.collision_mask = 1
	var wall_specs := [
		[Vector3(0.0, 0.7, HALF_Z - 1.0), Vector3(HALF_X * 2.0 - 2.0, 1.4, 1.0)],
		[Vector3(0.0, 0.7, -HALF_Z + 1.0), Vector3(HALF_X * 2.0 - 2.0, 1.4, 1.0)],
		[Vector3(HALF_X - 1.0, 0.7, 0.0), Vector3(1.0, 1.4, HALF_Z * 2.0 - 2.0)],
		[Vector3(-HALF_X + 1.0, 0.7, 0.0), Vector3(1.0, 1.4, HALF_Z * 2.0 - 2.0)],
	]
	for wall_spec in wall_specs:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = wall_spec[1]
		collider.shape = shape
		collider.position = wall_spec[0]
		fence.add_child(collider)
	if island.owner != null:
		fence.owner = island.owner
		for collider in fence.get_children():
			collider.owner = island.owner


static func _ensure_ruin_columns(ruins: Node3D) -> void:
	if ruins.get_node_or_null("RuinColumn_WestRear") != null:
		return
	var column_material := StandardMaterial3D.new()
	column_material.albedo_color = Color(0.58, 0.57, 0.54)
	column_material.roughness = 0.9
	var column_specs := [
		["RuinColumn_WestRear", Vector3(-15.0, 0.85, -1.1), 1.7, -5.0],
		["RuinColumn_WestFront", Vector3(-15.0, 0.6, 5.0), 1.2, 7.0],
		["RuinColumn_EastRear", Vector3(15.0, 1.1, -1.1), 2.2, 4.0],
		["RuinColumn_EastFront", Vector3(15.0, 0.8, 5.0), 1.6, -8.0],
	]
	for column_spec in column_specs:
		var column := MeshInstance3D.new()
		column.name = column_spec[0]
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.34
		mesh.bottom_radius = 0.48
		mesh.height = column_spec[2]
		mesh.radial_segments = 8
		column.mesh = mesh
		column.material_override = column_material
		column.position = column_spec[1]
		column.rotation_degrees.z = column_spec[3]
		ruins.add_child(column)
		if ruins.owner != null:
			column.owner = ruins.owner


static func _ensure_decor_collisions(arena_root: Node3D) -> void:
	var ruins := arena_root.get_node_or_null("Ruins") as Node3D
	if ruins != null:
		for child in ruins.get_children():
			if child is MeshInstance3D:
				_ensure_mesh_collision(child as MeshInstance3D)
	var decor := arena_root.get_node_or_null("Decor") as Node3D
	if decor != null:
		for child in decor.get_children():
			if child is Node3D and child.name.begins_with("CrystalCluster_"):
				_ensure_crystal_collision(child as Node3D)
			elif child is MeshInstance3D and (child as MeshInstance3D).mesh is SphereMesh and not child.has_meta("floating_decor"):
				_ensure_rock_collision(decor, child as MeshInstance3D)
	_ensure_shell_navigation_blocker(arena_root)
	arena_root.add_to_group(NAVIGATION_SOURCE_GROUP, true)


static func _ensure_mesh_collision(mesh_node: MeshInstance3D) -> void:
	for child in mesh_node.get_children():
		if child is StaticBody3D:
			return
	var mesh := mesh_node.mesh
	if mesh == null:
		return
	var shape_resource: Shape3D = null
	if mesh is BoxMesh:
		var box := BoxShape3D.new()
		box.size = (mesh as BoxMesh).size
		shape_resource = box
	elif mesh is CylinderMesh:
		var cylinder_mesh := mesh as CylinderMesh
		var cylinder := CylinderShape3D.new()
		cylinder.radius = maxf(cylinder_mesh.top_radius, cylinder_mesh.bottom_radius)
		cylinder.height = cylinder_mesh.height
		shape_resource = cylinder
	if shape_resource == null:
		return
	var body := StaticBody3D.new()
	body.name = mesh_node.name + "Collision"
	body.collision_layer = 1
	body.collision_mask = 1
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape_resource
	body.add_child(collider)
	mesh_node.add_child(body)
	if mesh_node.owner != null:
		body.owner = mesh_node.owner
		collider.owner = mesh_node.owner


static func _ensure_crystal_collision(cluster: Node3D) -> void:
	for child in cluster.get_children():
		if child is StaticBody3D:
			return
	var bounds := AABB()
	var found_shard := false
	for child in cluster.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var shard := child as MeshInstance3D
			var shard_bounds := _transform_aabb(shard.mesh.get_aabb(), shard.transform)
			bounds = shard_bounds if not found_shard else bounds.merge(shard_bounds)
			found_shard = true
	if not found_shard:
		return
	var body := StaticBody3D.new()
	body.name = "CrystalCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	var crystal := CylinderShape3D.new()
	crystal.radius = maxf(0.55, maxf(bounds.size.x, bounds.size.z) * 0.46)
	crystal.height = maxf(0.9, bounds.size.y)
	collider.shape = crystal
	collider.position = Vector3(bounds.get_center().x, crystal.height * 0.5, bounds.get_center().z)
	body.add_child(collider)
	cluster.add_child(body)
	if cluster.owner != null:
		body.owner = cluster.owner
		collider.owner = cluster.owner


static func _ensure_rock_collision(parent: Node3D, rock: MeshInstance3D) -> void:
	var body_name := String(rock.name) + "Collision"
	if parent.get_node_or_null(body_name) != null:
		return
	var sphere := rock.mesh as SphereMesh
	if sphere == null:
		return
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 1
	body.transform = rock.transform
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	var rock_shape := SphereShape3D.new()
	rock_shape.radius = sphere.radius * 0.9
	collider.shape = rock_shape
	body.add_child(collider)
	parent.add_child(body)
	if parent.owner != null:
		body.owner = parent.owner
		collider.owner = parent.owner


static func _ensure_shell_navigation_blocker(arena_root: Node3D) -> void:
	var existing := arena_root.get_node_or_null("ShellNavBlocker") as StaticBody3D
	if existing != null:
		existing.collision_layer = 2
		existing.collision_mask = 0
		var existing_shape := existing.get_child(0) as CollisionShape3D if existing.get_child_count() > 0 else null
		if existing_shape != null and existing_shape.shape is CylinderShape3D:
			var blocker_shape := existing_shape.shape as CylinderShape3D
			blocker_shape.radius = 1.8
			blocker_shape.height = 5.0
			existing_shape.position = Vector3(0.0, 2.5, 0.0)
		return
	var body := StaticBody3D.new()
	body.name = "ShellNavBlocker"
	body.collision_layer = 2
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	var blocker := CylinderShape3D.new()
	blocker.radius = 1.8
	blocker.height = 5.0
	collider.shape = blocker
	collider.position = Vector3(0.0, 2.5, 0.0)
	body.add_child(collider)
	arena_root.add_child(body)
	if arena_root.owner != null:
		body.owner = arena_root.owner
		collider.owner = arena_root.owner


static func _ensure_navigation_region(arena_root: Node3D) -> void:
	var region := arena_root.get_node_or_null("ArenaNavigation") as NavigationRegion3D
	if region == null:
		region = NavigationRegion3D.new()
		region.name = "ArenaNavigation"
		arena_root.add_child(region)
		if arena_root.owner != null:
			region.owner = arena_root.owner
	var navigation_mesh := region.navigation_mesh
	if navigation_mesh == null:
		navigation_mesh = NavigationMesh.new()
		region.navigation_mesh = navigation_mesh
	navigation_mesh.agent_radius = 0.75
	navigation_mesh.agent_height = 1.75
	navigation_mesh.agent_max_climb = 0.25
	navigation_mesh.agent_max_slope = 40.0
	navigation_mesh.cell_size = 0.25
	navigation_mesh.cell_height = 0.25
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navigation_mesh.geometry_source_group_name = NAVIGATION_SOURCE_GROUP
	navigation_mesh.geometry_collision_mask = 0xFFFFFFFF
	navigation_mesh.filter_baking_aabb = AABB(Vector3(-51.0, -0.2, -36.0), Vector3(102.0, 3.2, 72.0))
	region.bake_navigation_mesh(false)
	_remove_navmesh_disc(navigation_mesh, Vector3.ZERO, 2.2)
	region.navigation_mesh = navigation_mesh
	if navigation_mesh.get_polygon_count() == 0:
		push_warning("Arena navigation bake produced no walkable polygons")


static func _remove_navmesh_disc(navigation_mesh: NavigationMesh, center: Vector3, radius: float) -> void:
	var vertices := navigation_mesh.get_vertices()
	var kept: Array[PackedInt32Array] = []
	var center_2d := Vector2(center.x, center.z)
	for polygon_index in navigation_mesh.get_polygon_count():
		var polygon := navigation_mesh.get_polygon(polygon_index)
		var centroid := Vector2.ZERO
		for vertex_index in polygon:
			var vertex := vertices[vertex_index]
			centroid += Vector2(vertex.x, vertex.z)
		centroid /= float(polygon.size())
		if centroid.distance_to(center_2d) > radius:
			kept.append(polygon)
	navigation_mesh.clear_polygons()
	for polygon in kept:
		navigation_mesh.add_polygon(polygon)


static func _place_inside(pos: Vector3) -> Vector3:
	var p := pos
	var guard := 0
	while not _is_inside(p.x, p.z) and guard < 14:
		p.x *= 0.92
		p.z *= 0.92
		guard += 1
	return p


static func _add_environment(stage: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.025, 0.09, 0.24)
	sky_mat.sky_horizon_color = Color(0.13, 0.62, 0.69)
	sky_mat.sky_curve = 0.15
	sky_mat.ground_horizon_color = Color(0.1, 0.46, 0.55)
	sky_mat.ground_bottom_color = Color(0.02, 0.055, 0.13)
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.1

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	# Previous background: BG_SKY (2); sky top (0.025, 0.09, 0.24), sky horizon (0.13, 0.62, 0.69), ground horizon (0.1, 0.46, 0.55), ground bottom (0.02, 0.055, 0.13).
	# Previous fog: Color(0.075, 0.06, 0.18), depth begin 48.0, depth end 78.0.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.02)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.0, 0.0, 0.02)
	env.fog_light_energy = 0.9
	env.fog_density = 0.16
	env.fog_depth_begin = 10.0
	env.fog_depth_end = 55.0
	env.fog_depth_curve = 1.15
	env.fog_sky_affect = 0.25
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	stage.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, 34.0, 0.0)
	sun.light_color = Color(0.78, 0.86, 1.0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	stage.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "DarkFill"
	fill.rotation_degrees = Vector3(-26.0, 205.0, 0.0)
	fill.light_color = Color(0.55, 0.42, 0.95)
	fill.light_energy = 0.38
	stage.add_child(fill)

	var altar_glow := OmniLight3D.new()
	altar_glow.name = "AltarGlow"
	altar_glow.position = Vector3(0.0, 5.0, 0.0)
	altar_glow.light_color = Color(0.68, 0.45, 1.0)
	altar_glow.light_energy = 2.6
	altar_glow.omni_range = 20.0
	stage.add_child(altar_glow)

	var rim := OmniLight3D.new()
	rim.name = "WarmRim"
	rim.position = Vector3(-12.0, 6.0, -14.0)
	rim.light_color = Color(1.0, 0.82, 0.55)
	rim.light_energy = 1.6
	rim.omni_range = 26.0
	stage.add_child(rim)

	var light_half := OmniLight3D.new()
	light_half.name = "LightHalfGlow"
	light_half.position = Vector3(0.0, 7.0, -9.0)
	light_half.light_color = Color(0.55, 0.78, 1.0)
	light_half.light_energy = 1.5
	light_half.omni_range = 22.0
	stage.add_child(light_half)

	var dark_half := OmniLight3D.new()
	dark_half.name = "DarkHalfGlow"
	dark_half.position = Vector3(0.0, 7.0, 9.0)
	dark_half.light_color = Color(0.6, 0.34, 1.0)
	dark_half.light_energy = 1.7
	dark_half.omni_range = 22.0
	stage.add_child(dark_half)


static func _add_island(island: Node3D, mat_light: StandardMaterial3D, mat_dark: StandardMaterial3D, mat_rock: StandardMaterial3D) -> void:
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = build_floor_mesh(mat_light, mat_dark)
	island.add_child(floor_node)

	var skirt := SurfaceTool.new()
	var skirt_mesh := ArrayMesh.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	skirt.set_material(mat_rock)
	var segments := 64
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := _shape_point(a0, 1.0)
		var p1 := _shape_point(a1, 1.0)
		var deep0 := -7.0 - 2.5 * (0.5 + 0.5 * sin(a0 * 4.0 + 0.7))
		var deep1 := -7.0 - 2.5 * (0.5 + 0.5 * sin(a1 * 4.0 + 0.7))
		_add_quad(skirt, Vector3(p0.x, 0.0, p0.y), Vector3(p1.x, 0.0, p1.y), Vector3(p1.x, deep1, p1.y), Vector3(p0.x, deep0, p0.y))
		for k in 3:
			var t0 := float(k) / 3.0
			var t1 := float(k + 1) / 3.0
			var r0 := 1.0 - 0.55 * t0
			var r1 := 1.0 - 0.55 * t1
			var y0 := deep0 - 3.2 * t0
			var y1 := deep1 - 3.2 * t1
			_add_quad(skirt,
				Vector3(p0.x * r0, y0, p0.y * r0),
				Vector3(p1.x * r0, y0, p1.y * r0),
				Vector3(p1.x * r1, y1, p1.y * r1),
				Vector3(p0.x * r1, y1, p0.y * r1))
	skirt.generate_normals()
	skirt.commit(skirt_mesh)
	var skirt_node := MeshInstance3D.new()
	skirt_node.name = "Cliffs"
	skirt_node.mesh = skirt_mesh
	island.add_child(skirt_node)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	island.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_X * 2.0 - 2.0, 3.0, HALF_Z * 2.0 - 2.0)
	col.shape = shape
	col.position = Vector3(0.0, -1.5, 0.0)
	body.add_child(col)

	var walls := StaticBody3D.new()
	walls.name = "FenceCollision"
	island.add_child(walls)
	var wall_specs := [
		[Vector3(HALF_X - 1.0, 0.7, 0.0), Vector3(1.0, 1.4, HALF_Z * 2.0 - 2.0)],
		[Vector3(-HALF_X + 1.0, 0.7, 0.0), Vector3(1.0, 1.4, HALF_Z * 2.0 - 2.0)],
		[Vector3(0.0, 0.7, HALF_Z - 1.0), Vector3(HALF_X * 2.0 - 2.0, 1.4, 1.0)],
		[Vector3(0.0, 0.7, -HALF_Z + 1.0), Vector3(HALF_X * 2.0 - 2.0, 1.4, 1.0)],
	]
	for spec in wall_specs:
		var wc := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = spec[1]
		wc.shape = ws
		wc.position = spec[0]
		walls.add_child(wc)


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var uv_scale := 1.0 / 10.0
	st.set_uv(Vector2(a.x, a.z) * uv_scale)
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z) * uv_scale)
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z) * uv_scale)
	st.add_vertex(c)
	st.set_uv(Vector2(a.x, a.z) * uv_scale)
	st.add_vertex(a)
	st.set_uv(Vector2(c.x, c.z) * uv_scale)
	st.add_vertex(c)
	st.set_uv(Vector2(d.x, d.z) * uv_scale)
	st.add_vertex(d)


static func _add_altar(altar: Node3D, mat_marble: StandardMaterial3D, mat_gold: StandardMaterial3D, mat_rock: StandardMaterial3D) -> void:
	var disc := MeshInstance3D.new()
	disc.name = "AltarDisc"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 5.9
	cylinder.bottom_radius = 6.1
	cylinder.height = 0.16
	cylinder.radial_segments = 48
	disc.mesh = cylinder
	disc.material_override = mat_rock
	disc.position = Vector3(0.0, 0.06, 0.0)
	altar.add_child(disc)

	var pedestal := MeshInstance3D.new()
	pedestal.name = "Pedestal"
	var ped_mesh := CylinderMesh.new()
	ped_mesh.top_radius = 1.55
	ped_mesh.bottom_radius = 1.75
	ped_mesh.height = 0.45
	ped_mesh.radial_segments = 12
	pedestal.mesh = ped_mesh
	pedestal.material_override = mat_rock
	pedestal.position = Vector3(0.0, 0.22, 0.0)
	altar.add_child(pedestal)

	var crown := MeshInstance3D.new()
	crown.name = "PedestalCrown"
	var crown_mesh := TorusMesh.new()
	crown_mesh.inner_radius = 0.95
	crown_mesh.outer_radius = 1.15
	crown_mesh.rings = 32
	crown_mesh.ring_segments = 8
	crown.mesh = crown_mesh
	crown.material_override = mat_gold
	crown.position = Vector3(0.0, 0.5, 0.0)
	altar.add_child(crown)



static func _add_ruins(ruins: Node3D, mat_marble: StandardMaterial3D, mat_gold: StandardMaterial3D, mat_rock: StandardMaterial3D) -> void:
	for side in [-1.0, 1.0]:
		var block := MeshInstance3D.new()
		var block_mesh := BoxMesh.new()
		block_mesh.size = Vector3(2.6, 0.9, 1.4)
		block.mesh = block_mesh
		block.material_override = mat_rock
		block.position = Vector3(15.0 * side, 0.45, 2.0)
		block.rotation_degrees = Vector3(0.0, 24.0 * side, 6.0 * side)
		ruins.add_child(block)


static func _add_base(bases: Node3D, z: float, color: Color, mat_rock: StandardMaterial3D, node_name: String) -> void:
	var base := Node3D.new()
	base.name = node_name
	base.position = Vector3(0.0, 0.0, z)
	bases.add_child(base)

	var platform := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 4.8
	mesh.bottom_radius = 5.05
	mesh.height = 0.18
	mesh.radial_segments = 40
	platform.mesh = mesh
	platform.material_override = mat_rock
	platform.position = Vector3(0.0, 0.09, 0.0)
	base.add_child(platform)

	var ring := FxUtils.soft_ground_glow(9.0, Color(color.r, color.g, color.b, 0.45), 0.0, 0.22)
	ring.name = "BaseGlow"
	ring.position = Vector3(0.0, 0.2, 0.0)
	base.add_child(ring)


	for i in 5:
		var ang := TAU * float(i) / 5.0
		var pylon := MeshInstance3D.new()
		var pylon_mesh := CylinderMesh.new()
		pylon_mesh.top_radius = 0.0
		pylon_mesh.bottom_radius = 0.32
		pylon_mesh.height = 1.9
		pylon_mesh.radial_segments = 6
		pylon.mesh = pylon_mesh
		pylon.material_override = crystal_material(color)
		pylon.position = Vector3(cos(ang) * 4.45, 0.95, sin(ang) * 4.45)
		base.add_child(pylon)

	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 2.4, 0.0)
	light.light_color = color
	light.light_energy = 2.2
	light.omni_range = 12.0
	base.add_child(light)


static func _add_decor(decor: Node3D, mat_rock: StandardMaterial3D) -> void:
	var light_green := StandardMaterial3D.new()
	light_green.albedo_color = Color(0.26, 0.42, 0.34)
	light_green.roughness = 0.9
	var light_green2 := StandardMaterial3D.new()
	light_green2.albedo_color = Color(0.42, 0.5, 0.3)
	light_green2.roughness = 0.9
	var dark_foliage := StandardMaterial3D.new()
	dark_foliage.albedo_color = Color(0.2, 0.13, 0.3)
	dark_foliage.roughness = 0.95
	var trunk := StandardMaterial3D.new()
	trunk.albedo_color = Color(0.16, 0.13, 0.14)
	trunk.roughness = 0.95

	# деревья по самому краю арены, ровным шагом
	var tree_count := 12
	for i in tree_count:
		var ang := TAU * float(i) / float(tree_count) + 0.17
		var radius := 0.90 + 0.03 * sin(float(i) * 2.1)
		var p := _shape_point(ang, radius)
		var pos := Vector3(p.x, -0.9, p.y)
		var scale_factor := 0.88 + 0.18 * sin(float(i) * 1.7)
		if not _is_free(pos, 1.6 * scale_factor, 4.0):
			continue
		if p.y > 0.0:
			_add_glowing_tree(decor, pos, scale_factor, i)
		else:
			_add_tree(decor, pos, scale_factor, true, trunk, light_green, light_green2, dark_foliage)
		_occupy(pos, 1.6 * scale_factor)

	# камни средним кольцом
	var rock_count := 9
	for i in rock_count:
		var ang := TAU * float(i) / float(rock_count) + 0.42
		var radius := 0.58 + 0.13 * sin(float(i) * 2.7)
		var p := _shape_point(ang, radius)
		var pos := Vector3(p.x, 0.28, p.y)
		var rock_scale := 1.05 + 0.22 * sin(float(i) * 1.3)
		if not _is_free(pos, rock_scale * 0.9, 4.0):
			continue
		_add_rock(decor, pos, rock_scale, mat_rock)
		_occupy(pos, rock_scale * 0.9)

	# кристаллы между камнями
	var crystal_count := 6
	var crystal_colors := [Color(0.68, 0.34, 1.0), Color(0.4, 0.75, 1.0), Color(0.5, 0.3, 1.0)]
	for i in crystal_count:
		var ang := TAU * float(i) / float(crystal_count) + 0.95
		var radius := 0.44 + 0.10 * cos(float(i) * 1.9)
		var p := _shape_point(ang, radius)
		var pos := Vector3(p.x, 0.0, p.y)
		var crystal_scale := 1.15 + 0.18 * sin(float(i))
		if not _is_free(pos, crystal_scale, 4.0):
			continue
		_add_crystal_cluster(decor, pos, crystal_colors[i % crystal_colors.size()], crystal_scale)
		_occupy(pos, crystal_scale)

	# плавающие камни убраны: в игре они читались как летающие глыбы


static func _add_tree(parent: Node3D, pos: Vector3, scale_factor: float, dark: bool, trunk_mat: StandardMaterial3D, green_mat: StandardMaterial3D, gold_mat: StandardMaterial3D, dark_mat: StandardMaterial3D) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * scale_factor
	parent.add_child(tree)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 3.2
	trunk_mesh.radial_segments = 6
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_mat
	trunk.position = Vector3(0.0, 1.6, 0.0)
	trunk.rotation_degrees = Vector3(0.0, 0.0, 5.0 if dark else 0.0)
	tree.add_child(trunk)

	for i in 3:
		var leaves := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.5 - float(i) * 0.32
		cone.height = 1.7
		cone.radial_segments = 7
		leaves.mesh = cone
		leaves.material_override = dark_mat if dark else (green_mat if i % 2 == 0 else gold_mat)
		leaves.position = Vector3(0.0, 2.6 + float(i) * 0.85, 0.0)
		tree.add_child(leaves)

	var visibility_body := StaticBody3D.new()
	visibility_body.name = "VisibilityOccluder"
	visibility_body.collision_layer = 2
	visibility_body.collision_mask = 0
	var visibility_shape := CollisionShape3D.new()
	var visibility_capsule := CapsuleShape3D.new()
	visibility_capsule.radius = 1.35
	visibility_capsule.height = 5.4
	visibility_shape.shape = visibility_capsule
	visibility_shape.position = Vector3(0.0, 2.7, 0.0)
	visibility_body.add_child(visibility_shape)
	tree.add_child(visibility_body)
	_add_tree_body(tree, 0.5, 4.0)


static func _add_tree_body(tree: Node3D, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "TreeCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shape)
	tree.add_child(body)


static func _add_glowing_tree(parent: Node3D, pos: Vector3, scale_factor: float, tree_index: int) -> void:
	var tree := GLOWING_TREE_SCENE.instantiate() as Node3D
	if tree == null:
		return
	tree.name = "GlowingLightTree_%02d" % tree_index
	tree.position = pos
	tree.scale = Vector3.ONE * 4.8 * scale_factor
	parent.add_child(tree)

	var visibility_body := StaticBody3D.new()
	visibility_body.name = "VisibilityOccluder"
	visibility_body.collision_layer = 2
	visibility_body.collision_mask = 0
	var visibility_shape := CollisionShape3D.new()
	var visibility_capsule := CapsuleShape3D.new()
	visibility_capsule.radius = 0.17
	visibility_capsule.height = 0.9
	visibility_shape.shape = visibility_capsule
	visibility_shape.position = Vector3(0.0, 0.5, 0.0)
	visibility_body.add_child(visibility_shape)
	tree.add_child(visibility_body)
	_add_tree_body(tree, 0.22, 1.0)


static func _add_rock(parent: Node3D, pos: Vector3, size: float, mat: StandardMaterial3D, floating := false) -> void:
	var rock := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 1.4
	mesh.radial_segments = 6
	mesh.rings = 3
	rock.mesh = mesh
	rock.material_override = mat
	rock.position = pos
	rock.scale = Vector3(1.0, 0.7 + 0.3 * sin(pos.x), 1.0)
	rock.rotation = Vector3(pos.x * 0.3, pos.z * 0.2, pos.y * 0.4)
	if floating:
		rock.rotation_degrees = Vector3(20.0 * sin(pos.x), pos.y * 12.0, 15.0 * cos(pos.z))
		rock.set_meta("floating_decor", true)
	parent.add_child(rock)


static func _add_crystal_cluster(parent: Node3D, pos: Vector3, color: Color, size: float, cluster_name := "CrystalCluster") -> void:
	var cluster := Node3D.new()
	cluster.name = cluster_name
	cluster.position = pos
	parent.add_child(cluster)
	var mat := crystal_material(color)
	for i in 4:
		var shard := MeshInstance3D.new()
		shard.name = "Shard_%d" % (i + 1)
		var mesh := PrismMesh.new()
		mesh.left_to_right = 0.5
		mesh.size = Vector3(0.45, size * (0.6 + 0.3 * float(i % 2)), 0.45)
		shard.mesh = mesh
		shard.material_override = mat
		shard.position = Vector3(cos(i * 1.7) * 0.5, size * 0.3, sin(i * 1.7) * 0.5)
		shard.rotation_degrees = Vector3(18.0 * cos(i * 1.2), i * 42.0, 12.0 * sin(i * 2.0))
		cluster.add_child(shard)
	var light := OmniLight3D.new()
	light.name = "CrystalGlow"
	light.position = Vector3(0.0, size * 0.7, 0.0)
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 4.5
	cluster.add_child(light)


static func add_crystal_scatter(parent: Node3D) -> void:
	if parent == null or parent.get_node_or_null("CrystalCluster_01") != null:
		return
	var spots := [
		[Vector3(-34.0, 0.0, 20.0), Color(0.68, 0.34, 1.0), 2.0],
		[Vector3(34.0, 0.0, 20.0), Color(0.68, 0.34, 1.0), 1.8],
		[Vector3(-34.0, 0.0, -20.0), Color(0.5, 0.3, 1.0), 1.6],
		[Vector3(34.0, 0.0, -20.0), Color(0.4, 0.75, 1.0), 1.4],
	]
	for index in spots.size():
		var spot: Array = spots[index]
		_add_crystal_cluster(parent, _place_inside(spot[0]), spot[1], spot[2], "CrystalCluster_%02d" % (index + 1))


static func add_bushes(arena: Node3D) -> void:
	if arena == null or arena.get_node_or_null("Bushes") != null:
		return
	var bushes := Node3D.new()
	bushes.name = "Bushes"
	arena.add_child(bushes)
	var spots: Array[Vector3] = []
	var bush_zones := 5
	for i in bush_zones:
		var ang := TAU * float(i) / float(bush_zones) + 0.6
		var p := _shape_point(ang, 0.52)
		spots.append(Vector3(p.x, 0.0, p.y))
	for index in spots.size():
		var zone := Area3D.new()
		zone.name = "BushZone_%02d" % (index + 1)
		zone.position = _place_inside(spots[index])
		_occupy(zone.position, 3.4)
		zone.collision_layer = 0
		zone.collision_mask = 1
		bushes.add_child(zone)
		var detection := CollisionShape3D.new()
		detection.name = "StealthRange"
		detection.position = Vector3(0.0, 1.5, 0.0)
		var shape := SphereShape3D.new()
		shape.radius = 3.4
		detection.shape = shape
		zone.add_child(detection)
	rebuild_bush_visuals(bushes)


static func rebuild_bush_visuals(bushes_root: Node3D) -> void:
	var old_visuals := bushes_root.get_node_or_null("BushVisuals")
	if old_visuals != null:
		bushes_root.remove_child(old_visuals)
		old_visuals.free()
	var zones: Array[Area3D] = []
	for child in bushes_root.get_children():
		if child is Area3D and child.name.begins_with("BushZone_"):
			var zone := child as Area3D
			zones.append(zone)
			var old_visual := zone.get_node_or_null("BushVisual")
			if old_visual != null:
				zone.remove_child(old_visual)
				old_visual.free()
	if zones.is_empty():
		return
	var source_root := BUSH_SCENE.instantiate() as Node3D
	if source_root == null:
		return
	bushes_root.add_child(source_root)
	var mesh_specs: Array[Dictionary] = []
	var model_bounds := AABB()
	var found_mesh := false
	var pending: Array[Node] = [source_root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D:
			var mesh_instance := current as MeshInstance3D
			if mesh_instance.mesh != null:
				var local_transform := source_root.global_transform.affine_inverse() * mesh_instance.global_transform
				var mesh_bounds := _transform_aabb(mesh_instance.get_aabb(), local_transform)
				model_bounds = mesh_bounds if not found_mesh else model_bounds.merge(mesh_bounds)
				found_mesh = true
				mesh_specs.append({"mesh": mesh_instance.mesh, "transform": local_transform, "name": mesh_instance.name})
		for child in current.get_children():
			pending.append(child)
	bushes_root.remove_child(source_root)
	source_root.free()
	if not found_mesh or model_bounds.size.y <= 0.0:
		return
	var visual_scale := BUSH_TARGET_HEIGHT / model_bounds.size.y
	var visual_root := Node3D.new()
	visual_root.name = "BushVisuals"
	bushes_root.add_child(visual_root)
	if bushes_root.owner != null:
		_assign_owner_recursive(visual_root, bushes_root.owner)
	var instance_count := zones.size() * 2
	for mesh_spec in mesh_specs:
		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.mesh = mesh_spec["mesh"]
		multi_mesh.instance_count = instance_count
		var mesh_batch := MultiMeshInstance3D.new()
		mesh_batch.name = "%sBatch" % mesh_spec["name"]
		mesh_batch.multimesh = multi_mesh
		visual_root.add_child(mesh_batch)
		var instance_index := 0
		for zone in zones:
			var radial := Vector3(zone.position.x, 0.0, zone.position.z).normalized()
			var tangent := Vector3(-radial.z, 0.0, radial.x)
			var pair_sides: Array[float] = [-1.0, 1.0]
			for side in pair_sides:
				var plant_position: Vector3 = zone.position + tangent * BUSH_PAIR_HALF_SPACING * side
				plant_position.y = -model_bounds.position.y * visual_scale
				var placement := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * visual_scale), plant_position)
				multi_mesh.set_instance_transform(instance_index, placement * mesh_spec["transform"])
				instance_index += 1
	if bushes_root.owner != null:
		_assign_owner_recursive(visual_root, bushes_root.owner)


static func _assign_owner_recursive(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	for child in node.get_children():
		_assign_owner_recursive(child, scene_owner)


static func _combined_model_aabb(model_root: Node3D) -> AABB:
	var bounds := AABB()
	var found_mesh := false
	var pending: Array[Dictionary] = [{"node": model_root, "transform": Transform3D.IDENTITY}]
	while not pending.is_empty():
		var entry: Dictionary = pending.pop_back()
		var current := entry["node"] as Node3D
		var current_transform: Transform3D = entry["transform"]
		if current is MeshInstance3D:
			var mesh_instance := current as MeshInstance3D
			if mesh_instance.mesh != null:
				var mesh_bounds := _transform_aabb(mesh_instance.get_aabb(), current_transform)
				bounds = mesh_bounds if not found_mesh else bounds.merge(mesh_bounds)
				found_mesh = true
		for child in current.get_children():
			if child is Node3D:
				pending.append({"node": child, "transform": current_transform * (child as Node3D).transform})
	return bounds


static func _transform_aabb(source: AABB, transform: Transform3D) -> AABB:
	var result := AABB()
	var found_point := false
	for x in [source.position.x, source.end.x]:
		for y in [source.position.y, source.end.y]:
			for z in [source.position.z, source.end.z]:
				var point := transform * Vector3(x, y, z)
				result = AABB(point, Vector3.ZERO) if not found_point else result.expand(point)
				found_point = true
	return result


static func _add_braziers(parent: Node3D, mat_gold: StandardMaterial3D, mat_rock: StandardMaterial3D) -> void:
	var spots := [
		Vector3(-24.0, 0.0, -16.0), Vector3(24.0, 0.0, -16.0),
		Vector3(-24.0, 0.0, 16.0), Vector3(24.0, 0.0, 16.0),
	]
	var flame_mat := glow_material(Color(1.0, 0.62, 0.24), 3.4)
	for spot in spots:
		var brazier := Node3D.new()
		brazier.position = _place_inside(spot)
		parent.add_child(brazier)
		var post := MeshInstance3D.new()
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.16
		post_mesh.bottom_radius = 0.28
		post_mesh.height = 1.5
		post_mesh.radial_segments = 6
		post.mesh = post_mesh
		post.material_override = mat_rock
		post.position = Vector3(0.0, 0.75, 0.0)
		brazier.add_child(post)
		var bowl := MeshInstance3D.new()
		var bowl_mesh := CylinderMesh.new()
		bowl_mesh.top_radius = 0.42
		bowl_mesh.bottom_radius = 0.24
		bowl_mesh.height = 0.28
		bowl_mesh.radial_segments = 8
		bowl.mesh = bowl_mesh
		bowl.material_override = mat_gold
		bowl.position = Vector3(0.0, 1.62, 0.0)
		brazier.add_child(bowl)
		var flame := MeshInstance3D.new()
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.26
		flame_mesh.height = 0.72
		flame_mesh.radial_segments = 6
		flame_mesh.rings = 3
		flame.mesh = flame_mesh
		flame.material_override = flame_mat
		flame.position = Vector3(0.0, 1.95, 0.0)
		brazier.add_child(flame)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.66, 0.34)
		light.light_energy = 2.4
		light.omni_range = 9.0
		light.position = Vector3(0.0, 2.1, 0.0)
		brazier.add_child(light)


static func _add_rim(parent: Node3D, mat_rock: StandardMaterial3D) -> void:
	var segments := 46
	for i in segments:
		var ang := TAU * float(i) / float(segments)
		var p := _shape_point(ang, 0.985)
		var stone := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var size := 1.0 + 0.35 * sin(float(i) * 2.3)
		mesh.radius = size
		mesh.height = size * 1.2
		mesh.radial_segments = 5
		mesh.rings = 2
		stone.mesh = mesh
		stone.material_override = mat_rock
		stone.position = Vector3(p.x, -0.25 + 0.15 * sin(float(i) * 1.7), p.y)
		stone.rotation = Vector3(0.2 * sin(float(i)), ang, 0.15 * cos(float(i) * 0.7))
		stone.scale = Vector3(1.0, 0.55, 1.0)
		parent.add_child(stone)


static func ensure_perimeter_ridge(arena: Node3D) -> void:
	if arena == null or arena.get_node_or_null("PerimeterRidge") != null:
		return

	var island := arena.get_node_or_null("Island") as Node3D
	var island_scale := island.scale if island != null else Vector3.ONE
	var ridge := Node3D.new()
	ridge.name = "PerimeterRidge"
	arena.add_child(ridge)

	var void_surface := SurfaceTool.new()
	void_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var void_segments := 128
	var void_outer_scale := 100.0
	for index in void_segments:
		var angle0 := TAU * float(index) / float(void_segments)
		var angle1 := TAU * float(index + 1) / float(void_segments)
		var inner0 := _shape_point(angle0, 0.985)
		var inner1 := _shape_point(angle1, 0.985)
		var outer0 := Vector2(cos(angle0) * HALF_X * void_outer_scale, sin(angle0) * HALF_Z * void_outer_scale)
		var outer1 := Vector2(cos(angle1) * HALF_X * void_outer_scale, sin(angle1) * HALF_Z * void_outer_scale)
		_add_quad(void_surface,
			Vector3(inner0.x * island_scale.x, 0.0, inner0.y * island_scale.z),
			Vector3(outer0.x * island_scale.x, 0.0, outer0.y * island_scale.z),
			Vector3(outer1.x * island_scale.x, 0.0, outer1.y * island_scale.z),
			Vector3(inner1.x * island_scale.x, 0.0, inner1.y * island_scale.z))
	void_surface.generate_normals()
	var void_mesh := ArrayMesh.new()
	void_surface.commit(void_mesh)
	var void_backdrop := MeshInstance3D.new()
	void_backdrop.name = "VoidBlackout"
	void_backdrop.mesh = void_mesh
	void_backdrop.position.y = -0.18
	void_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var void_material := StandardMaterial3D.new()
	void_material.albedo_color = Color.BLACK
	void_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	void_material.disable_fog = true
	void_backdrop.material_override = void_material
	ridge.add_child(void_backdrop)

	var barrier := StaticBody3D.new()
	barrier.name = "CollisionBarrier"
	barrier.collision_layer = 0
	barrier.collision_mask = 0
	ridge.add_child(barrier)

	for index in PERIMETER_RIDGE_SEGMENTS:
		var angle := TAU * float(index) / float(PERIMETER_RIDGE_SEGMENTS)
		var point := _shape_point(angle, 0.955)
		var position := Vector3(point.x * island_scale.x, 0.52, point.y * island_scale.z)
		var collider := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 1.9
		shape.height = 1.6
		collider.shape = shape
		collider.position = position + Vector3.UP * 0.25
		barrier.add_child(collider)


