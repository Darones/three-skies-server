class_name ArenaKit
extends RefCounted

const FLOOR_LIGHT_TEX := "res://art/textures/temple_floor/img-6adcd384-a1c6-4d03-ab8f-2885c6220fd5-1793744216285-0_1793744216285_y4vdgmr5.png"
const FLOOR_DARK_TEX := "res://art/textures/obsidian_rock/img-6adcd384-a1c6-4d03-ab8f-2885c6220fd5-1793744225681-0_1793744225682_zroihsmf.png"
const SLATE_DIR := "res://art/textures/slate_floor"

const HALF_X := 27.0
const HALF_Z := 19.5

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
	mat.albedo_color = Color(0.76, 0.73, 0.68)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

static func floor_dark_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := _first_texture(SLATE_DIR, FLOOR_DARK_TEX)
	if tex != null:
		mat.albedo_texture = tex
	mat.albedo_color = Color(0.62, 0.5, 0.88)
	mat.roughness = 0.7
	mat.metallic = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

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
	mat.emission_energy_multiplier = 1.6
	mat.roughness = 0.15
	mat.metallic = 0.3
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
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
	_add_base(bases, -12.5, Color(0.55, 0.85, 1.0), mat_rock, "LightBase")
	_add_base(bases, 12.5, Color(0.68, 0.32, 1.0), mat_rock, "DarkBase")

	var decor := Node3D.new()
	decor.name = "Decor"
	root.add_child(decor)
	_add_decor(decor, mat_rock)
	_add_braziers(decor, mat_gold, mat_rock)
	_add_rim(decor, mat_rock)


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
	env.background_mode = Environment.BG_SKY
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
	env.fog_light_color = Color(0.52, 0.73, 0.84)
	env.fog_light_energy = 0.8
	env.fog_density = 0.55
	env.fog_depth_begin = 42.0
	env.fog_depth_end = 82.0
	env.fog_depth_curve = 1.15
	env.fog_sky_affect = 0.35

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
	var st_light := SurfaceTool.new()
	var st_dark := SurfaceTool.new()
	st_light.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_light.set_material(mat_light)
	st_dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_dark.set_material(mat_dark)
	var mesh := ArrayMesh.new()
	var step := 1.5
	var x := -HALF_X
	while x < HALF_X - 0.01:
		var z := -HALF_Z
		while z < HALF_Z - 0.01:
			var x1 := x + step
			var z1 := z + step
			if _is_inside((x + x1) * 0.5, (z + z1) * 0.5):
				var st := st_light if (z + z1) * 0.5 < 0.0 else st_dark
				var y0 := -0.02 * sin(x * 0.7) - 0.02 * cos(z * 0.6)
				_add_quad(st, Vector3(x, y0, z), Vector3(x1, y0, z), Vector3(x1, y0, z1), Vector3(x, y0, z1))
			z += step
		x += step
	st_light.generate_normals()
	st_light.commit(mesh)
	st_dark.generate_normals()
	st_dark.commit(mesh)

	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = mesh
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
	walls.name = "Walls"
	island.add_child(walls)
	var wall_specs := [
		[Vector3(HALF_X - 1.0, 2.0, 0.0), Vector3(1.0, 6.0, HALF_Z * 2.0)],
		[Vector3(-HALF_X + 1.0, 2.0, 0.0), Vector3(1.0, 6.0, HALF_Z * 2.0)],
		[Vector3(0.0, 2.0, HALF_Z - 1.0), Vector3(HALF_X * 2.0, 6.0, 1.0)],
		[Vector3(0.0, 2.0, -HALF_Z + 1.0), Vector3(HALF_X * 2.0, 6.0, 1.0)],
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

	var rune_ring := MeshInstance3D.new()
	rune_ring.name = "RuneRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 5.8
	torus.outer_radius = 6.15
	torus.rings = 64
	torus.ring_segments = 12
	rune_ring.mesh = torus
	rune_ring.material_override = glow_material(Color(0.62, 0.82, 1.0), 2.4)
	rune_ring.position = Vector3(0.0, 0.16, 0.0)
	altar.add_child(rune_ring)

	var inner_ring := MeshInstance3D.new()
	inner_ring.name = "InnerRing"
	var torus2 := TorusMesh.new()
	torus2.inner_radius = 2.2
	torus2.outer_radius = 2.4
	torus2.rings = 48
	torus2.ring_segments = 10
	inner_ring.mesh = torus2
	inner_ring.material_override = glow_material(Color(0.75, 0.5, 1.0), 2.0)
	inner_ring.position = Vector3(0.0, 0.17, 0.0)
	altar.add_child(inner_ring)

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

	for i in 4:
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		var pos := Vector3(cos(ang) * 6.6, 0.0, sin(ang) * 6.6)
		_add_pillar(altar, pos, 4.6, false, mat_marble, mat_gold, mat_rock)


static func _add_pillar(parent: Node3D, pos: Vector3, height: float, broken: bool, mat_marble: StandardMaterial3D, mat_gold: StandardMaterial3D, mat_rock: StandardMaterial3D) -> void:
	var node := Node3D.new()
	node.position = pos
	if broken:
		var tilt := 7.0 + 5.0 * sin(pos.x * 1.3 + pos.z)
		node.rotation_degrees = Vector3(tilt, pos.x * 9.0, 4.0 * cos(pos.z + pos.x))
	parent.add_child(node)

	var shaft := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.74
	mesh.height = height
	mesh.radial_segments = 12
	shaft.mesh = mesh
	shaft.material_override = mat_marble
	shaft.position = Vector3(0.0, height * 0.5, 0.0)
	node.add_child(shaft)

	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(1.65, 0.28, 1.65)
	plinth.mesh = plinth_mesh
	plinth.material_override = mat_marble
	plinth.position = Vector3(0.0, 0.14, 0.0)
	node.add_child(plinth)

	if not broken:
		var collar := MeshInstance3D.new()
		var collar_mesh := CylinderMesh.new()
		collar_mesh.top_radius = 0.78
		collar_mesh.bottom_radius = 0.66
		collar_mesh.height = 0.16
		collar_mesh.radial_segments = 12
		collar.mesh = collar_mesh
		collar.material_override = mat_gold
		collar.position = Vector3(0.0, height - 0.08, 0.0)
		node.add_child(collar)
		var capital := MeshInstance3D.new()
		var capital_mesh := BoxMesh.new()
		capital_mesh.size = Vector3(1.42, 0.24, 1.42)
		capital.mesh = capital_mesh
		capital.material_override = mat_marble
		capital.position = Vector3(0.0, height + 0.12, 0.0)
		node.add_child(capital)
	else:
		var chip := MeshInstance3D.new()
		var chip_mesh := CylinderMesh.new()
		chip_mesh.top_radius = 0.3
		chip_mesh.bottom_radius = 0.55
		chip_mesh.height = 0.7
		chip_mesh.radial_segments = 7
		chip.mesh = chip_mesh
		chip.material_override = mat_rock
		chip.position = Vector3(0.12, height + 0.3, -0.1)
		chip.rotation_degrees = Vector3(12.0, 0.0, 18.0)
		node.add_child(chip)

	var body := StaticBody3D.new()
	body.name = "Body"
	node.add_child(body)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.68
	shape.height = height
	col.shape = shape
	col.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(col)


static func _add_ruins(ruins: Node3D, mat_marble: StandardMaterial3D, mat_gold: StandardMaterial3D, mat_rock: StandardMaterial3D) -> void:
	var specs := [
		[Vector3(-10.0, 0.0, -6.5), 5.0, false],
		[Vector3(10.0, 0.0, -6.5), 5.0, false],
		[Vector3(-10.0, 0.0, 6.5), 3.2, true],
		[Vector3(10.0, 0.0, 6.5), 4.4, false],
	]
	for spec in specs:
		_add_pillar(ruins, spec[0], spec[1], spec[2], mat_marble, mat_gold, mat_rock)

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

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.9
	torus.outer_radius = 4.2
	torus.rings = 48
	torus.ring_segments = 10
	ring.mesh = torus
	ring.material_override = glow_material(color, 2.6)
	ring.position = Vector3(0.0, 0.22, 0.0)
	base.add_child(ring)

	var shield_dome := MeshInstance3D.new()
	shield_dome.name = "BaseShieldDome"
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 5.25
	dome_mesh.height = 5.25
	dome_mesh.is_hemisphere = true
	dome_mesh.radial_segments = 40
	dome_mesh.rings = 20
	shield_dome.mesh = dome_mesh
	var dome_material := StandardMaterial3D.new()
	dome_material.albedo_color = Color(color.r, color.g, color.b, 0.08)
	dome_material.emission_enabled = true
	dome_material.emission = color
	dome_material.emission_energy_multiplier = 0.2
	dome_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dome_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dome_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_dome.material_override = dome_material
	shield_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(shield_dome)

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

	for i in 16:
		var ang := TAU * float(i) / 16.0 + 0.22
		var p := _shape_point(ang, 1.045)
		var dark := sin(ang) > 0.0
		_add_tree(decor, Vector3(p.x, -0.9, p.y), 0.95 + 0.25 * sin(float(i) * 1.7), dark, trunk, light_green, light_green2, dark_foliage)

	var bush_spots := [
		Vector3(-20.0, 0.0, -6.0), Vector3(20.0, 0.0, -6.5),
		Vector3(-19.0, 0.0, 8.0), Vector3(19.5, 0.0, 8.5),
		Vector3(-8.5, 0.0, 15.0), Vector3(8.5, 0.0, -15.0),
	]
	for spot in bush_spots:
		_add_bush(decor, _place_inside(spot), light_green if spot.z < 0.0 else dark_foliage)

	var rock_spots := [
		[Vector3(-25.0, 0.3, 0.0), 1.7],
		[Vector3(25.0, 0.3, 2.0), 1.5],
		[Vector3(-6.0, 0.25, 18.0), 1.3],
		[Vector3(7.0, 0.25, -18.0), 1.2],
		[Vector3(-13.0, 0.25, 3.0), 0.9],
		[Vector3(13.5, 0.25, -3.0), 0.85],
	]
	for spot in rock_spots:
		_add_rock(decor, _place_inside(spot[0]), spot[1], mat_rock)

	var crystal_spots := [
		[Vector3(-18.0, 0.0, 13.0), Color(0.68, 0.34, 1.0), 2.2],
		[Vector3(18.5, 0.0, 14.5), Color(0.68, 0.34, 1.0), 1.8],
		[Vector3(-12.0, 0.0, -13.0), Color(0.5, 0.3, 1.0), 1.4],
		[Vector3(12.0, 0.0, -13.0), Color(0.4, 0.75, 1.0), 1.2],
	]
	for spot in crystal_spots:
		_add_crystal_cluster(decor, _place_inside(spot[0]), spot[1], spot[2])

	var float_spots := [
		Vector3(-30.0, -3.0, -6.0), Vector3(30.0, -5.0, 8.0), Vector3(-24.0, 3.0, 22.0),
		Vector3(26.0, 2.0, -21.0), Vector3(0.0, -12.0, -26.0), Vector3(6.0, -16.0, 24.0),
	]
	for p in float_spots:
		_add_rock(decor, p, 1.6, mat_rock, true)


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
	parent.add_child(rock)


static func _add_crystal_cluster(parent: Node3D, pos: Vector3, color: Color, size: float) -> void:
	var cluster := Node3D.new()
	cluster.position = pos
	parent.add_child(cluster)
	var mat := crystal_material(color)
	for i in 4:
		var shard := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.left_to_right = 0.5
		mesh.size = Vector3(0.45, size * (0.6 + 0.3 * float(i % 2)), 0.45)
		shard.mesh = mesh
		shard.material_override = mat
		shard.position = Vector3(cos(i * 1.7) * 0.5, size * 0.3, sin(i * 1.7) * 0.5)
		shard.rotation_degrees = Vector3(18.0 * cos(i * 1.2), i * 42.0, 12.0 * sin(i * 2.0))
		cluster.add_child(shard)
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, size * 0.7, 0.0)
	light.light_color = color
	light.light_energy = 1.1
	light.omni_range = 6.0
	cluster.add_child(light)


static func _add_braziers(parent: Node3D, mat_gold: StandardMaterial3D, mat_rock: StandardMaterial3D) -> void:
	var spots := [
		Vector3(-7.0, 0.0, -13.0), Vector3(7.0, 0.0, -13.0),
		Vector3(-7.0, 0.0, 13.0), Vector3(7.0, 0.0, 13.0),
		Vector3(-15.0, 0.0, -4.0), Vector3(15.0, 0.0, -4.0),
		Vector3(-15.0, 0.0, 5.0), Vector3(15.0, 0.0, 5.0),
		Vector3(-9.5, 0.0, 1.5), Vector3(9.5, 0.0, -1.5),
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


static func _add_bush(parent: Node3D, pos: Vector3, mat: StandardMaterial3D) -> void:
	var bush := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.75
	mesh.height = 0.9
	mesh.radial_segments = 6
	mesh.rings = 3
	bush.mesh = mesh
	bush.material_override = mat
	bush.position = Vector3(pos.x, 0.22, pos.z)
	bush.scale = Vector3(1.0, 0.62, 1.0)
	parent.add_child(bush)
