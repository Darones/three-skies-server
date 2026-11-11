extends Node3D

const MATCH_LENGTH := 600.0
const RESPAWN_TIME := 8.0
const RESPAWN_GOLD_STEP := 200
const RESPAWN_MAX_SECONDS := 16.0
const SHELL_WINDOW := 45.0
const SHELL_SPAWN_INTERVAL := 120.0
const SHELL_WARNING_TIME := 10.0
const CRYSTALS_TO_WIN := 3
const GROUND_CRYSTAL_LIFETIME := 30.0
const CRYSTAL_PICKUP_DELAY := 1.25
const CRYSTAL_PICKUP_RADIUS := 3.2
const CRYSTAL_DROP_SEARCH_RADII := [7.8, 9.0, 10.2, 11.4, 12.6]
const TEST_STARTING_GOLD := 500
const ARENA_SAFE_HALF_X := 52.0
const ARENA_SAFE_HALF_Z := 37.0
const VISIBILITY_COLLISION_MASK := 3
const VISIBILITY_REFRESH_INTERVAL := 0.12
const VFX_POOL_SIZE := 10
const SHELL_BEAM_POOL_SIZE := 5
const PROJECTILE_POOL_SIZE := 16
const ROOT_SPIKE_POOL_SIZE := 24
const GOLD_COIN_INTERVAL := 1.0
const GOLD_COIN_MAX_COUNT := 30
const GOLD_COIN_PULL_RADIUS := 4.0
const GOLD_COIN_PULL_SPEED := 7.5
const GOLD_COIN_SPAWN_BASE_RADIUS := 5.0
const GOLD_COIN_SPAWN_EXTRA_RADIUS := 1.2
const SHOP_INTERACTION_POINT := Vector3(-40.0, 0.0, 0.0)
const BASE_POSITION_Z := 28.0
const BASE_DELIVERY_RADIUS := 6.0
const SHOP_INTERACTION_RADIUS := 4.0
const CRYSTAL_SCENE: PackedScene = preload("res://assets/models/detail-crystal.glb")
const CRYSTAL_MODEL_SCALE := 2.7
const CRYSTAL_EMISSION_COLOR := Color(0.16, 0.68, 1.0)
const BOT_CALLSIGNS := ["ЛунныйЛис", "СеверныйВетер", "ТихийШторм", "Искра", "КаменныйПуть", "ЗвёздныйСлед", "СумрачныйКлинок", "БелыйВорон"]
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const CLOUD_WALL_SHADER: Shader = preload("res://shaders/cloud_wall.gdshader")
const FOG_OF_WAR_SHADER_PATH := "res://shaders/fog_of_war.gdshader"
const FOG_VIEW_RADIUS := 10.0
const SHOP_STALL_SCENE: PackedScene = preload("res://assets/shop_stall/3d_4f92fe433b084100af7a1d7f_1790958942025.glb")
const GOLD_FOUNTAIN_SCENE: PackedScene = preload("res://assets/gold_fountain/3d_aeb9c9ced6384164aff32ae5_1790300466128.glb")
const TUTORIAL_CONTROLLER_SCRIPT: Script = preload("res://scripts/tutorial_controller.gd")
const REMOTE_PLAYER_SCRIPT: Script = preload("res://scripts/remote_player.gd")
const SHOP_ITEMS := [
	{"id": "life_amulet", "name": "Амулет Жизни", "effect": "+150 Max HP", "price": 300, "icon": 0},
	{"id": "revival_talisman", "name": "Талисман Возрождения", "effect": "+10 HP/сек реген", "price": 350, "icon": 1},
	{"id": "titan_shell", "name": "Панцирь Титана", "effect": "−15% входящего урона", "price": 350, "icon": 2},
	{"id": "power_glove", "name": "Перчатка Силы", "effect": "+25 к урону атаки", "price": 300, "icon": 3},
	{"id": "vampire_fang", "name": "Клык Вампира", "effect": "15% вампиризма", "price": 350, "icon": 4},
	{"id": "agility_mark", "name": "Знак Ловкости", "effect": "+20% скорости атаки", "price": 300, "icon": 5},
	{"id": "wind_boots", "name": "Сапоги Ветра", "effect": "+15% скорости бега", "price": 250, "icon": 6},
	{"id": "hourglass", "name": "Песочные Часы", "effect": "−15% КД скиллов", "price": 350, "icon": 7},
	{"id": "cleansing_charm", "name": "Оберег Очищения", "effect": "−20% времени станов", "price": 300, "icon": 8},
]

const MUSIC_PATH := "res://audio/music/dread/6adcd384-a1c6-4d03-ab8f-2885c6220fd5_music_dark_fantasy_arena_battle_them__1793744175999.mp3"
const SFX_PATHS := {
	"fairy_ult": "res://audio/sfx/fairy_blessing_free/sfx_magical_fairy_chime_bell_brig_.wav",
	"hit": "res://audio/sfx/sword_hit.wav",
	"magic": "res://audio/sfx/magic_burst.wav",
	"thunder": "res://audio/sfx/shell_thunder.wav",
	"coin_pickup": "res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/bright_coin_pickup.wav",
	"shop_purchase": "res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/coins_1.wav",
	"shard_pickup": "res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/synth_power_up_ascending.wav",
	"shard_delivery": "res://assets/audio/Soundza_Game_SFX_Pack/jingles_stingers/level_clear.wav",
}

var camera: Camera3D
var hud: Node
var fog_of_war_plane: MeshInstance3D
var fog_of_war_material: ShaderMaterial
var heroes: Array[HeroUnit] = []
var player: HeroUnit = null
var shell: SkyShell = null
var shell_pool: SkyShell = null
var crystal_node: Node3D = null
var carrier: HeroUnit = null

var state := "select"
var match_time := MATCH_LENGTH
var score: Array[int] = [0, 0]
var p_kills := 0
var p_deaths := 0
var p_damage := 0.0
var p_crystals := 0
var p_shells_destroyed := 0
var gold := 0
var gold_earned_this_match := 0
var shop_open := false
var purchased_shop_items: Array[String] = []
var used_bot_callsigns: Array[String] = []
var gold_fountain: Node3D = null
var gold_coin_timer := GOLD_COIN_INTERVAL
var gold_coins: Array[Node3D] = []
var tutorial_mode := false
var tutorial_controller: Node = null
var tutorial_dummy: HeroUnit = null
var tutorial_arrow: MeshInstance3D = null
var tutorial_arrow_material: StandardMaterial3D = null
var tutorial_target_position := Vector3.ZERO
var tutorial_target_color := Color(1.0, 0.82, 0.32)
var tutorial_target_active := false
var tutorial_pulse_time := 0.0
var network_play := false
var network_host := false
var network_room_id := 0
var network_match_players: Array = []
var network_shutting_down := false
var network_bots: Dictionary = {}
var remote_players: Dictionary = {}
var remote_root: Node3D = null
var shell_phase := "idle"
var shell_cycle_timer := SHELL_SPAWN_INTERVAL
var shell_timer := SHELL_SPAWN_INTERVAL
var shell_window := SHELL_WINDOW
var crystal_state := "none"
var crystal_timer := 0.0
var pickup_delay := 0.0
var sudden_death := false
var player_won := false
var result_text := ""
var last_announce := ""

var projectiles: Array = []
var burst_pool: Array[Dictionary] = []
var ring_pool: Array[Dictionary] = []
var root_spike_pool: Array[Dictionary] = []
var shell_beam_pool: Array[Dictionary] = []
var projectile_pool: Array[Dictionary] = []
var shake_amount := 0.0
var earthquake_timer := 0.0
var earthquake_intensity := 0.0
var select_angle := 0.6
var camera_pos := Vector3.ZERO
var camera_distance := 16.0
var visibility_refresh_timer := 0.0
var death_camera_active := false
var death_camera_last_distance := 16.0
var zoom_speed := 1.0
var min_zoom_distance := 12.0
var max_zoom_distance := 42.0

var music: AudioStreamPlayer
var sfx_streams := {}
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_index := 0


func _ready() -> void:
	randomize()
	tutorial_mode = bool(get_tree().get_meta("tutorial_mode", false))
	network_play = bool(get_tree().get_meta("network_play", false))
	network_host = bool(get_tree().get_meta("network_host", false))
	network_room_id = int(get_tree().get_meta("network_room_id", 0))
	var configured_players: Variant = get_tree().get_meta("network_match_players", [])
	network_match_players = configured_players if configured_players is Array else []
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.fov = 46.0
	camera_pos = camera.global_position
	if get_node_or_null("Arena") == null:
		var arena := Node3D.new()
		arena.name = "Arena"
		add_child(arena)
		ArenaKit.build(arena)
	var arena_root := get_node_or_null("Arena") as Node3D
	if arena_root != null:
		ArenaKit.ensure_perimeter_ridge(arena_root)
		ArenaKit.ensure_arena_features(arena_root)
	_create_base_shield_domes()
	_create_fog_of_war()
	_create_shop_stall()
	_create_gold_fountain()
	_setup_audio()
	_prepare_effect_pools()
	hud = preload("res://scripts/hud.gd").new()
	hud.name = "HUD"
	hud.game = self
	add_child(hud)
	var bushes_root := get_node_or_null("Arena/Bushes")
	if bushes_root != null:
		for bush_node in bushes_root.get_children():
			if bush_node is Area3D:
				var bush := bush_node as Area3D
				bush.body_entered.connect(_on_bush_body_entered.bind(bush))
				bush.body_exited.connect(_on_bush_body_exited.bind(bush))
	state = "select"
	if get_tree().has_meta("selected_class"):
		var selected_class := int(get_tree().get_meta("selected_class"))
		if selected_class >= 0 and selected_class <= 2:
			var selected_team := clampi(int(get_tree().get_meta("selected_team", get_meta("selected_team", 0))), 0, 1)
			call_deferred("start_match", selected_class, selected_team)
	if network_play:
		_setup_network_play()


func _create_base_shield_domes() -> void:
	var shield_configs := [
		{"path": "Arena/Bases/LightBase", "color": Color(0.42, 0.72, 1.0, 0.065)},
		{"path": "Arena/Bases/DarkBase", "color": Color(0.72, 0.46, 0.92, 0.065)},
	]
	for shield_config in shield_configs:
		var base := get_node_or_null(String(shield_config["path"])) as Node3D
		if base == null or base.has_node("SpawnShieldDome"):
			continue
		var dome := MeshInstance3D.new()
		dome.name = "SpawnShieldDome"
		var sphere := SphereMesh.new()
		sphere.radius = 4.9
		sphere.height = 9.8
		sphere.radial_segments = 32
		sphere.rings = 16
		dome.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = shield_config["color"]
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.9
		dome.material_override = material
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dome.position.y = 0.15
		base.add_child(dome)


func _create_floating_clouds() -> void:
	var arena := get_node_or_null("Arena") as Node3D
	if arena == null or arena.get_node_or_null("FloatingClouds") != null:
		return
	var clouds := Node3D.new()
	clouds.name = "FloatingClouds"
	arena.add_child(clouds)
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = CLOUD_WALL_SHADER
	cloud_material.set_shader_parameter("cloud_tint", Color(0.78, 0.9, 0.97, 0.22))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segment_count := 64
	var ring_radius_x := 28.9
	var ring_radius_z := 20.9
	var wall_bottom := -14.0
	var wall_top := 3.0
	for index in segment_count:
		var u0 := float(index) / float(segment_count)
		var u1 := float(index + 1) / float(segment_count)
		var angle0 := TAU * u0
		var angle1 := TAU * u1
		var bottom0 := Vector3(cos(angle0) * ring_radius_x, wall_bottom, sin(angle0) * ring_radius_z)
		var bottom1 := Vector3(cos(angle1) * ring_radius_x, wall_bottom, sin(angle1) * ring_radius_z)
		var top0 := Vector3(bottom0.x, wall_top, bottom0.z)
		var top1 := Vector3(bottom1.x, wall_top, bottom1.z)
		surface.set_uv(Vector2(u0, 0.0))
		surface.add_vertex(bottom0)
		surface.set_uv(Vector2(u1, 0.0))
		surface.add_vertex(bottom1)
		surface.set_uv(Vector2(u1, 1.0))
		surface.add_vertex(top1)
		surface.set_uv(Vector2(u0, 0.0))
		surface.add_vertex(bottom0)
		surface.set_uv(Vector2(u1, 1.0))
		surface.add_vertex(top1)
		surface.set_uv(Vector2(u0, 1.0))
		surface.add_vertex(top0)
	var cloud_wall := MeshInstance3D.new()
	cloud_wall.name = "CloudWall"
	cloud_wall.mesh = surface.commit()
	cloud_wall.material_override = cloud_material
	cloud_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.add_child(cloud_wall)


func _create_shop_stall() -> void:
	var parent := get_node_or_null("Arena/Decor") as Node3D
	if parent == null:
		parent = get_node_or_null("Arena") as Node3D
	if parent == null or parent.get_node_or_null("ShopStall") != null:
		return

	var shop := Node3D.new()
	shop.name = "ShopStall"
	shop.position = Vector3(-40.0, 0.0, 0.0)
	shop.scale = Vector3.ONE * 5.0
	parent.add_child(shop)

	var stall_model := SHOP_STALL_SCENE.instantiate() as Node3D
	stall_model.name = "MarketStallModel"
	shop.add_child(stall_model)
	_add_shop_collision(shop)

	var sign := MeshInstance3D.new()
	sign.name = "ShopSign"
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(2.7, 0.65, 0.14)
	sign.mesh = sign_mesh
	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = Color(0.18, 0.085, 0.045)
	sign_material.roughness = 0.9
	sign.material_override = sign_material
	sign.position = Vector3(0.0, 3.65, 1.82)
	shop.add_child(sign)
	var title := Label3D.new()
	title.name = "ShopTitle"
	title.font = UI_FONT
	title.text = "МАГАЗИН"
	title.position = Vector3(0.0, 4.15, 1.9)
	title.font_size = 88
	title.pixel_size = 0.006
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color(1.0, 0.82, 0.48)
	title.outline_size = 9
	title.outline_modulate = Color(0.045, 0.03, 0.02, 0.95)
	shop.add_child(title)

func _add_shop_collision(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "ShopCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.9, 0.8)
	collision_shape.shape = box
	collision_shape.position = Vector3(0.0, 0.45, 0.0)
	body.add_child(collision_shape)
	parent.add_child(body)


func _create_gold_fountain() -> void:
	var parent := get_node_or_null("Arena/Decor") as Node3D
	if parent == null:
		parent = get_node_or_null("Arena") as Node3D
	if parent == null or parent.get_node_or_null("GoldFountain") != null:
		return

	gold_fountain = Node3D.new()
	gold_fountain.name = "GoldFountain"
	gold_fountain.position = Vector3(37.0, 0.0, 0.0)
	gold_fountain.scale = Vector3.ONE * 5.0
	parent.add_child(gold_fountain)

	var imported_model := GOLD_FOUNTAIN_SCENE.instantiate() as Node3D
	if imported_model != null:
		imported_model.name = "StoneFountainModel"
		gold_fountain.add_child(imported_model)
		_add_model_collision(gold_fountain, imported_model, "FountainCollision")
	else:
		_build_primitive_fountain(gold_fountain)
		_add_model_collision(gold_fountain, gold_fountain, "FountainCollision")

	var title := Label3D.new()
	title.name = "FountainTitle"
	title.font = UI_FONT
	title.text = "ФОНТАН"
	title.position = Vector3(0.0, 3.7, 0.0)
	title.font_size = 88
	title.pixel_size = 0.006
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color(1.0, 0.84, 0.38)
	title.outline_size = 9
	title.outline_modulate = Color(0.045, 0.03, 0.02, 0.95)
	gold_fountain.add_child(title)


func _build_primitive_fountain(parent: Node3D) -> void:
	var gold_material := StandardMaterial3D.new()
	gold_material.albedo_color = Color(0.72, 0.47, 0.12)
	gold_material.metallic = 0.72
	gold_material.roughness = 0.28
	gold_material.emission_enabled = true
	gold_material.emission = Color(0.7, 0.38, 0.06)
	gold_material.emission_energy_multiplier = 0.35

	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color(0.36, 0.35, 0.39)
	stone_material.roughness = 0.9

	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.08, 0.38, 0.48, 0.82)
	water_material.metallic = 0.28
	water_material.roughness = 0.18
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.emission_enabled = true
	water_material.emission = Color(0.04, 0.26, 0.38)
	water_material.emission_energy_multiplier = 0.8

	var base := MeshInstance3D.new()
	base.name = "StoneBase"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.35
	base_mesh.bottom_radius = 1.5
	base_mesh.height = 0.55
	base_mesh.radial_segments = 12
	base.mesh = base_mesh
	base.material_override = stone_material
	base.position.y = 0.28
	parent.add_child(base)

	var column := MeshInstance3D.new()
	column.name = "GoldColumn"
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.36
	column_mesh.bottom_radius = 0.58
	column_mesh.height = 1.45
	column_mesh.radial_segments = 10
	column.mesh = column_mesh
	column.material_override = gold_material
	column.position.y = 1.25
	parent.add_child(column)

	var basin := MeshInstance3D.new()
	basin.name = "StoneBasin"
	var basin_mesh := CylinderMesh.new()
	basin_mesh.top_radius = 1.45
	basin_mesh.bottom_radius = 0.75
	basin_mesh.height = 0.55
	basin_mesh.radial_segments = 12
	basin.mesh = basin_mesh
	basin.material_override = stone_material
	basin.position.y = 2.12
	parent.add_child(basin)

	var rim := MeshInstance3D.new()
	rim.name = "GoldBasinRim"
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 1.23
	rim_mesh.outer_radius = 1.5
	rim_mesh.rings = 24
	rim_mesh.ring_segments = 8
	rim.mesh = rim_mesh
	rim.material_override = gold_material
	rim.position.y = 2.42
	parent.add_child(rim)

	var water := MeshInstance3D.new()
	water.name = "BasinWater"
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 1.22
	water_mesh.bottom_radius = 1.22
	water_mesh.height = 0.04
	water_mesh.radial_segments = 16
	water.mesh = water_mesh
	water.material_override = water_material
	water.position.y = 2.34
	parent.add_child(water)



func _add_model_collision(parent: Node3D, model_root: Node3D, collision_name: String) -> void:
	var meshes: Array[MeshInstance3D] = []
	var stack: Array[Node] = [model_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).mesh != null:
			meshes.append(current as MeshInstance3D)
		for child in current.get_children():
			stack.append(child)

	for index in meshes.size():
		var mesh_instance := meshes[index]
		var mesh_parent := mesh_instance.get_parent() as Node3D
		if mesh_parent == null:
			mesh_parent = parent
		var body := StaticBody3D.new()
		body.name = "%s_%d" % [collision_name, index]
		body.collision_layer = 1
		body.collision_mask = 1
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()
		body.add_child(collision_shape)
		mesh_parent.add_child(body)
		body.transform = mesh_instance.transform



func _spawn_gold_coin(gold_value: int = 1, tutorial_spawn: bool = false) -> void:
	if gold_fountain == null or not is_instance_valid(gold_fountain):
		return
	if gold_coins.size() >= GOLD_COIN_MAX_COUNT:
		var oldest: Node3D = gold_coins.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var coin := MeshInstance3D.new()
	coin.name = "GoldCoin"
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = 0.22
	coin_mesh.bottom_radius = 0.22
	coin_mesh.height = 0.075
	coin_mesh.radial_segments = 12
	coin.mesh = coin_mesh
	var coin_material := StandardMaterial3D.new()
	coin_material.albedo_color = Color(1.0, 0.68, 0.12)
	coin_material.metallic = 0.78
	coin_material.roughness = 0.22
	coin_material.emission_enabled = true
	coin_material.emission = Color(1.0, 0.48, 0.04)
	coin_material.emission_energy_multiplier = 0.8
	coin.material_override = coin_material
	add_child(coin)
	var coin_angle := randf_range(0.0, TAU)
	var coin_radius := randf_range(0.35, 1.0) if tutorial_spawn else GOLD_COIN_SPAWN_BASE_RADIUS + randf_range(0.0, GOLD_COIN_SPAWN_EXTRA_RADIUS)
	var coin_center: Vector3 = player.global_position if tutorial_spawn and player != null else gold_fountain.global_position
	var spawn_position := coin_center + Vector3(cos(coin_angle) * coin_radius, 0.09, sin(coin_angle) * coin_radius)
	coin.global_position = clamp_to_arena(spawn_position)
	coin.set_meta("gold_value", gold_value)
	gold_coins.append(coin)


func _update_gold_fountain(delta: float) -> void:
	if not tutorial_mode:
		gold_coin_timer -= delta
		if gold_coin_timer <= 0.0:
			_spawn_gold_coin()
			gold_coin_timer = GOLD_COIN_INTERVAL

	for index in range(gold_coins.size() - 1, -1, -1):
		var coin := gold_coins[index]
		if not is_instance_valid(coin):
			gold_coins.remove_at(index)
			continue
		coin.rotation.y += delta * 2.0
		var collector: HeroUnit = null
		var closest_distance := GOLD_COIN_PULL_RADIUS
		for hero in heroes:
			if hero == null or not is_instance_valid(hero) or hero.dead:
				continue
			var distance := Vector2(hero.global_position.x - coin.global_position.x, hero.global_position.z - coin.global_position.z).length()
			if distance < closest_distance:
				closest_distance = distance
				collector = hero
		if collector == null:
			continue
		var collector_target := collector.global_position + Vector3(0.0, 0.8, 0.0)
		coin.global_position = coin.global_position.move_toward(collector_target, GOLD_COIN_PULL_SPEED * delta)
		if coin.global_position.distance_to(collector_target) <= 0.75:
			coin.queue_free()
			gold_coins.remove_at(index)
			collector.match_coins_collected += 1
			play_sfx("coin_pickup", -12.0)
			var coin_value := int(coin.get_meta("gold_value", 1))
			if collector.is_player:
				award_gold(coin_value)
				if tutorial_mode and tutorial_controller != null:
					tutorial_controller.call("on_coin_collected")
			else:
				collector.bot_gold += coin_value


func spawn_tutorial_coin_batch(count: int, gold_per_coin: int) -> void:
	if not tutorial_mode or player == null or gold_fountain == null:
		return
	for coin_index in range(count):
		_spawn_gold_coin(gold_per_coin, true)


func is_hero_near_shop(hero: HeroUnit) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	var hero_position := Vector2(hero.global_position.x, hero.global_position.z)
	var shop_point := Vector2(SHOP_INTERACTION_POINT.x, SHOP_INTERACTION_POINT.z)
	return hero_position.distance_to(shop_point) <= SHOP_INTERACTION_RADIUS


func _setup_audio() -> void:
	music = AudioStreamPlayer.new()
	music.name = "Music"
	var stream := load(MUSIC_PATH) as AudioStream
	if stream != null:
		music.stream = stream
		music.volume_db = -10.0
		add_child(music)
		music.play()
	for key in SFX_PATHS.keys():
		var s := load(SFX_PATHS[key]) as AudioStream
		if s != null:
			sfx_streams[key] = s
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.max_polyphony = 1
		add_child(p)
		sfx_players.append(p)


func _prepare_effect_pools() -> void:
	shell_pool = SkyShell.new()
	shell_pool.name = "Shell"
	add_child(shell_pool)
	shell_pool.setup(self)
	shell_pool.deactivate()

	var burst_texture := _create_soft_particle_texture()
	var burst_fade := _create_burst_fade_gradient()
	var burst_amounts := [3, 10, 14, 16, 18, 20, 28, 34, 44, 60]
	for amount in burst_amounts:
		var particles := CPUParticles3D.new()
		particles.name = "PooledBurst%d" % int(amount)
		particles.amount = int(amount)
		particles.lifetime = 0.6
		particles.one_shot = true
		particles.explosiveness = 0.95
		particles.direction = Vector3(0.0, 1.0, 0.0)
		particles.spread = 180.0
		particles.initial_velocity_min = 3.0
		particles.initial_velocity_max = 8.0
		particles.gravity = Vector3(0.0, -14.0, 0.0)
		particles.scale_amount_min = 0.4
		particles.scale_amount_max = 1.0
		var quad := QuadMesh.new()
		quad.size = Vector2(0.28, 0.28)
		particles.mesh = quad
		particles.color_ramp = burst_fade
		var material := StandardMaterial3D.new()
		material.albedo_texture = burst_texture
		material.emission_texture = burst_texture
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_enabled = true
		material.emission_energy_multiplier = 1.35
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.vertex_color_use_as_albedo = true
		particles.material_override = material
		particles.emitting = false
		particles.visible = false
		add_child(particles)
		burst_pool.append({"node": particles, "material": material, "count": int(amount), "busy": false, "remaining": 0.0})

	for index in VFX_POOL_SIZE:
		var ring := MeshInstance3D.new()
		ring.name = "PooledRing%d" % index
		var torus := TorusMesh.new()
		torus.inner_radius = 0.8
		torus.outer_radius = 1.0
		torus.rings = 40
		torus.ring_segments = 8
		ring.mesh = torus
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		material.emission_energy_multiplier = 3.0
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = material
		ring.visible = false
		add_child(ring)
		ring_pool.append({"node": ring, "material": material, "busy": false, "elapsed": 0.0, "duration": 0.0, "start_scale": Vector3.ONE, "target_scale": Vector3.ONE, "fade": false, "alpha": 0.8})

	var root_mesh := CylinderMesh.new()
	root_mesh.top_radius = 0.0
	root_mesh.bottom_radius = 0.22
	root_mesh.height = 1.0
	root_mesh.radial_segments = 6
	for index in ROOT_SPIKE_POOL_SIZE:
		var spike := MeshInstance3D.new()
		spike.name = "PooledRootSpike%d" % index
		spike.mesh = root_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.85, 0.46, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.12, 0.62, 0.3)
		material.emission_energy_multiplier = 1.4
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spike.material_override = material
		spike.visible = false
		add_child(spike)
		root_spike_pool.append({"node": spike, "material": material, "busy": false, "elapsed": 0.0, "duration": 0.0, "position": Vector3.ZERO, "height": 0.0, "color": Color.WHITE})

	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.22
	beam_mesh.bottom_radius = 0.5
	beam_mesh.height = 16.0
	beam_mesh.radial_segments = 8
	for index in SHELL_BEAM_POOL_SIZE:
		var beam := MeshInstance3D.new()
		beam.name = "PooledShellBeam%d" % index
		beam.mesh = beam_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.85, 0.7, 1.0, 0.95)
		material.emission_enabled = true
		material.emission = Color(0.8, 0.6, 1.0)
		material.emission_energy_multiplier = 4.0
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam.material_override = material
		beam.visible = false
		add_child(beam)
		shell_beam_pool.append({"node": beam, "material": material, "busy": false, "remaining": 0.0})

	var projectile_mesh := SphereMesh.new()
	projectile_mesh.radius = 0.18
	projectile_mesh.height = 0.36
	projectile_mesh.radial_segments = 6
	projectile_mesh.rings = 3
	for index in PROJECTILE_POOL_SIZE:
		var projectile := MeshInstance3D.new()
		projectile.name = "PooledProjectile%d" % index
		projectile.mesh = projectile_mesh
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		material.emission_energy_multiplier = 3.0
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		projectile.material_override = material
		projectile.visible = false
		add_child(projectile)
		projectile_pool.append({"node": projectile, "material": material, "busy": false})


func _create_soft_particle_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var uv := Vector2(x, y) / 63.0 * 2.0 - Vector2.ONE
			var radius := uv.length()
			var alpha := pow(maxf(1.0 - radius * radius, 0.0), 3.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _create_burst_fade_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.14, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.66, Color(1.0, 1.0, 1.0, 0.72))
	gradient.set_color(3, Color(1.0, 1.0, 1.0, 0.0))
	return gradient


func _update_effect_pools(delta: float) -> void:
	for index in burst_pool.size():
		var entry: Dictionary = burst_pool[index]
		if not bool(entry["busy"]):
			continue
		entry["remaining"] = float(entry["remaining"]) - delta
		if float(entry["remaining"]) <= 0.0:
			var particles := entry["node"] as CPUParticles3D
			particles.emitting = false
			particles.visible = false
			entry["busy"] = false
		burst_pool[index] = entry

	for index in ring_pool.size():
		var entry: Dictionary = ring_pool[index]
		if not bool(entry["busy"]):
			continue
		entry["elapsed"] = float(entry["elapsed"]) + delta
		var duration := maxf(float(entry["duration"]), 0.001)
		var progress := clampf(float(entry["elapsed"]) / duration, 0.0, 1.0)
		var ring := entry["node"] as MeshInstance3D
		var material := entry["material"] as StandardMaterial3D
		var start_scale: Vector3 = entry["start_scale"]
		var target_scale: Vector3 = entry["target_scale"]
		ring.scale = start_scale.lerp(target_scale, progress)
		if bool(entry["fade"]):
			var tint := material.albedo_color
			tint.a = float(entry["alpha"]) * (1.0 - progress)
			material.albedo_color = tint
			material.emission_energy_multiplier = 3.0 * (1.0 - progress)
		if progress >= 1.0:
			ring.visible = false
			entry["busy"] = false
		ring_pool[index] = entry

	for index in root_spike_pool.size():
		var entry: Dictionary = root_spike_pool[index]
		if not bool(entry["busy"]):
			continue
		entry["elapsed"] = float(entry["elapsed"]) + delta
		var duration := maxf(float(entry["duration"]), 0.001)
		var progress := clampf(float(entry["elapsed"]) / duration, 0.0, 1.0)
		var rise := clampf(progress / 0.22, 0.0, 1.0)
		var height := float(entry["height"])
		var spike := entry["node"] as MeshInstance3D
		var material := entry["material"] as StandardMaterial3D
		var spike_position: Vector3 = entry["position"]
		spike.global_position = spike_position + Vector3.UP * height * rise * 0.5
		spike.scale = Vector3(1.0, height * rise, 1.0)
		var tint: Color = entry["color"]
		if progress > 0.58:
			tint.a = 1.0 - clampf((progress - 0.58) / 0.42, 0.0, 1.0)
		material.albedo_color = tint
		material.emission_energy_multiplier = 1.4 * tint.a
		if progress >= 1.0:
			spike.visible = false
			spike.scale = Vector3.ONE
			entry["busy"] = false
		root_spike_pool[index] = entry

	for index in shell_beam_pool.size():
		var entry: Dictionary = shell_beam_pool[index]
		if not bool(entry["busy"]):
			continue
		entry["remaining"] = float(entry["remaining"]) - delta
		var beam := entry["node"] as MeshInstance3D
		var material := entry["material"] as StandardMaterial3D
		var tint := material.albedo_color
		tint.a = 0.95 * clampf(float(entry["remaining"]) / 0.35, 0.0, 1.0)
		material.albedo_color = tint
		if float(entry["remaining"]) <= 0.0:
			beam.visible = false
			entry["busy"] = false
		shell_beam_pool[index] = entry


func _acquire_burst(requested_count: int) -> Dictionary:
	var selected_index := -1
	var best_difference := INF
	for index in burst_pool.size():
		var entry: Dictionary = burst_pool[index]
		if bool(entry["busy"]):
			continue
		var difference := absf(float(entry["count"]) - float(requested_count))
		if difference < best_difference:
			best_difference = difference
			selected_index = index
	if selected_index < 0:
		return {}
	var selected: Dictionary = burst_pool[selected_index]
	selected["busy"] = true
	selected["remaining"] = 1.2
	burst_pool[selected_index] = selected
	return selected


func _activate_ring(pos: Vector3, color: Color, duration: float, start_scale: Vector3, target_scale: Vector3, fade: bool, alpha: float) -> void:
	for index in ring_pool.size():
		var entry: Dictionary = ring_pool[index]
		if bool(entry["busy"]):
			continue
		var ring := entry["node"] as MeshInstance3D
		var material := entry["material"] as StandardMaterial3D
		var tint := color
		tint.a = alpha
		material.albedo_color = tint
		material.emission = color
		material.emission_energy_multiplier = 3.0
		ring.global_position = pos
		ring.scale = start_scale
		ring.visible = true
		entry["busy"] = true
		entry["elapsed"] = 0.0
		entry["duration"] = duration
		entry["start_scale"] = start_scale
		entry["target_scale"] = target_scale
		entry["fade"] = fade
		entry["alpha"] = alpha
		ring_pool[index] = entry
		return


func _activate_shell_beam(pos: Vector3, beam_color := Color(0.85, 0.7, 1.0, 0.95)) -> void:
	for index in shell_beam_pool.size():
		var entry: Dictionary = shell_beam_pool[index]
		if bool(entry["busy"]):
			continue
		var beam := entry["node"] as MeshInstance3D
		var material := entry["material"] as StandardMaterial3D
		material.albedo_color = beam_color
		material.emission = Color(beam_color.r, beam_color.g, beam_color.b)
		beam.global_position = pos + Vector3(0.0, 8.0, 0.0)
		beam.scale = Vector3.ONE
		beam.visible = true
		entry["busy"] = true
		entry["remaining"] = 0.35
		shell_beam_pool[index] = entry
		return


func _acquire_projectile() -> MeshInstance3D:
	for index in projectile_pool.size():
		var entry: Dictionary = projectile_pool[index]
		if bool(entry["busy"]):
			continue
		entry["busy"] = true
		projectile_pool[index] = entry
		return entry["node"] as MeshInstance3D
	return null


func _release_projectile(node: Node3D, pooled: bool) -> void:
	if not pooled:
		node.queue_free()
		return
	node.visible = false
	for index in projectile_pool.size():
		var entry: Dictionary = projectile_pool[index]
		if entry["node"] == node:
			entry["busy"] = false
			projectile_pool[index] = entry
			return


func play_sfx(key: String, volume_db := -4.0) -> void:
	if not sfx_streams.has(key) or sfx_players.is_empty():
		return
	for offset in range(sfx_players.size()):
		var index := (sfx_index + offset) % sfx_players.size()
		var player := sfx_players[index]
		if player.is_playing():
			continue
		player.stream = sfx_streams[key]
		player.volume_db = volume_db
		player.play()
		sfx_index = (index + 1) % sfx_players.size()
		return


func start_match(player_class: int, requested_team: int = -1) -> void:
	if state != "select":
		return
	p_kills = 0
	p_deaths = 0
	p_damage = 0.0
	p_crystals = 0
	p_shells_destroyed = 0
	gold_earned_this_match = 0
	gold = 0 if tutorial_mode else TEST_STARTING_GOLD
	death_camera_active = false
	shop_open = false
	purchased_shop_items.clear()
	used_bot_callsigns.clear()
	network_bots.clear()
	if network_play:
		NetworkManager.clear_bots()
	var player_team := requested_team
	if player_team < 0:
		player_team = int(get_tree().get_meta("selected_team", get_meta("selected_team", 0)))
	player_team = clampi(player_team, 0, 1)
	var classes: Array[int] = [HeroUnit.Cls.WARRIOR, HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY]
	var ally_classes: Array[int] = []
	for c in classes:
		if c != player_class:
			ally_classes.append(c)
	var light_spots: Array[Vector3] = [Vector3(-2.0, 0.76, BASE_POSITION_Z - 1.5), Vector3(0.0, 0.76, BASE_POSITION_Z - 1.0), Vector3(2.0, 0.76, BASE_POSITION_Z - 1.5)]
	var dark_spots: Array[Vector3] = [Vector3(2.0, 0.76, -BASE_POSITION_Z + 1.5), Vector3(0.0, 0.76, -BASE_POSITION_Z + 1.0), Vector3(-2.0, 0.76, -BASE_POSITION_Z + 1.5)]
	var own_spots: Array[Vector3] = light_spots if player_team == 0 else dark_spots
	var enemy_spots: Array[Vector3] = dark_spots if player_team == 0 else light_spots
	var enemy_team := 1 - player_team
	player = _spawn_hero(player_class, player_team, true, own_spots[0])
	if not tutorial_mode:
		if network_play:
			if network_host:
				_spawn_network_bots(light_spots, dark_spots)
		else:
			var ai_index := 1
			for c in ally_classes:
				_spawn_hero(c, player_team, false, own_spots[mini(ai_index, 2)])
				ai_index += 1
			for i in classes.size():
				_spawn_hero(classes[i], enemy_team, false, enemy_spots[mini(i, 2)])
	state = "live"
	if network_play:
		_setup_network_play()
	match_time = MATCH_LENGTH
	shell_phase = "idle"
	shell_cycle_timer = SHELL_SPAWN_INTERVAL
	shell_timer = SHELL_SPAWN_INTERVAL
	if hud != null:
		hud.hide_class_select()
		if tutorial_mode:
			tutorial_controller = TUTORIAL_CONTROLLER_SCRIPT.new()
			tutorial_controller.name = "TutorialController"
			tutorial_controller.set("game", self)
			add_child(tutorial_controller)
			tutorial_controller.call("begin")
		else:
			announce("Бой за осколки!", Color(1.0, 0.86, 0.55), 2.6)


func _spawn_network_bots(light_spots: Array[Vector3], dark_spots: Array[Vector3]) -> void:
	var next_index := [0, 0]
	for entry in network_match_players:
		if not entry is Dictionary or not bool(entry.get("bot", false)):
			continue
		var bot_team := clampi(int(entry.get("team", 0)), 0, 1)
		var bot_class := clampi(int(entry.get("class", 0)), 0, 2)
		var spots: Array[Vector3] = light_spots if bot_team == 0 else dark_spots
		var spot_index: int = mini(next_index[bot_team], 2)
		next_index[bot_team] += 1
		var bot := _spawn_hero(bot_class, bot_team, false, spots[spot_index])
		bot.network_id = int(entry.get("id", 0))
		var bot_name := String(entry.get("name", "")).strip_edges()
		if not bot_name.is_empty():
			bot.display_name = bot_name
		network_bots[bot.network_id] = bot
		NetworkManager.register_bot(bot)


func _spawn_hero(cls: int, team: int, is_player: bool, pos: Vector3) -> HeroUnit:
	var h := HeroUnit.new()
	h.name = ("Player" if is_player else "%s_%d_%d" % [HeroUnit.CLASS_DATA[cls]["name"], team, heroes.size()])
	add_child(h)
	h.setup(self, cls, team, is_player)
	if not is_player:
		h.display_name = _next_bot_callsign()
	h.global_position = pos
	h.rotation.y = 0.0 if team == 0 else PI
	heroes.append(h)
	return h


func _next_bot_callsign() -> String:
	var available: Array[String] = []
	for callsign in BOT_CALLSIGNS:
		if not used_bot_callsigns.has(String(callsign)):
			available.append(String(callsign))
	if available.is_empty():
		return "Путник%d" % (used_bot_callsigns.size() + 1)
	var callsign := available[randi_range(0, available.size() - 1)]
	used_bot_callsigns.append(callsign)
	return callsign


func clamp_to_arena(position: Vector3) -> Vector3:
	var clamped_x := clampf(position.x, -ARENA_SAFE_HALF_X, ARENA_SAFE_HALF_X)
	var clamped_z := clampf(position.z, -ARENA_SAFE_HALF_Z, ARENA_SAFE_HALF_Z)
	return Vector3(clamped_x, position.y, clamped_z)


func get_shop_items() -> Array:
	return SHOP_ITEMS


func nearest_gold_coin(from_position: Vector3) -> Node3D:
	var closest_coin: Node3D = null
	var closest_distance := INF
	for coin in gold_coins:
		if coin == null or not is_instance_valid(coin):
			continue
		var distance := from_position.distance_squared_to(coin.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_coin = coin
	return closest_coin


func bot_has_affordable_shop_item(bot: HeroUnit) -> bool:
	if bot == null or not is_instance_valid(bot) or bot.is_player:
		return false
	for item in SHOP_ITEMS:
		if String(item["id"]) not in bot.bot_purchased_shop_items and bot.bot_gold >= int(item["price"]):
			return true
	return false


func bot_shop_goal() -> Vector3:
	return clamp_to_arena(SHOP_INTERACTION_POINT + Vector3(3.0, 0.0, 0.0))


func purchase_bot_shop_item(bot: HeroUnit) -> bool:
	if state != "live" or bot == null or not is_instance_valid(bot) or bot.is_player or bot.dead:
		return false
	if not is_hero_near_shop(bot):
		return false
	for item in SHOP_ITEMS:
		var item_id := String(item["id"])
		var price := int(item["price"])
		if item_id in bot.bot_purchased_shop_items or bot.bot_gold < price:
			continue
		if not bot.apply_shop_item(item_id):
			return false
		bot.bot_gold -= price
		bot.match_gold_spent += price
		bot.bot_purchased_shop_items.append(item_id)
		return true
	return false


func award_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_earned_this_match += amount
	if hud != null:
		hud.update_gold()
		if shop_open:
			hud.update_shop()


func respawn_delay_for(hero: HeroUnit) -> float:
	if hero != player:
		return RESPAWN_TIME
	var bonus_seconds := floori(float(gold_earned_this_match) / float(RESPAWN_GOLD_STEP))
	return minf(RESPAWN_MAX_SECONDS, RESPAWN_TIME + float(bonus_seconds))


func set_shop_open(open: bool) -> void:
	var next_state := open and state == "live" and player != null and not player.dead
	if shop_open == next_state:
		return
	shop_open = next_state
	if hud != null:
		hud.set_shop_open(shop_open)


func is_shop_item_available(item_id: String) -> bool:
	if not tutorial_mode or tutorial_controller == null:
		return true
	return bool(tutorial_controller.call("can_buy_item", item_id))


func buy_item(item_id: String) -> bool:
	if not shop_open or player == null or item_id in purchased_shop_items:
		return false
	if tutorial_mode and (tutorial_controller == null or not bool(tutorial_controller.call("can_buy_item", item_id))):
		return false
	for item in SHOP_ITEMS:
		if String(item["id"]) != item_id:
			continue
		var price := int(item["price"])
		if gold < price or not player.apply_shop_item(item_id):
			return false
		gold -= price
		player.match_gold_spent += price
		purchased_shop_items.append(item_id)
		if hud != null:
			hud.update_gold()
			hud.update_shop()
		play_sfx("shop_purchase", -10.0)
		if tutorial_mode and tutorial_controller != null:
			tutorial_controller.call("on_shop_item_bought", item_id)
		return true
	return false


func _process(delta: float) -> void:
	_update_effect_pools(delta)
	_update_tutorial_arrow(delta)
	if state == "select":
		select_angle += delta * 0.12
		var focus := Vector3(0.0, 1.5, 0.0)
		var target_pos := focus + Vector3(cos(select_angle) * 27.0, 21.0, sin(select_angle) * 27.0)
		camera_pos = camera_pos.lerp(target_pos, 1.0 - exp(-3.0 * delta))
		camera.global_position = camera_pos
		camera.look_at(focus, Vector3.UP)
	else:
		_update_camera(delta)
	_update_fog_of_war()

	if state == "live":
		if tutorial_mode:
			if tutorial_controller != null:
				tutorial_controller.call("process", delta)
				if tutorial_controller.get("stage") == "collect_coins":
					_update_gold_fountain(delta)
		else:
			_update_match(delta)
		if state == "live":
			if not tutorial_mode:
				_update_gold_fountain(delta)
			visibility_refresh_timer -= delta
			if visibility_refresh_timer <= 0.0:
				_update_enemy_visibility()
				visibility_refresh_timer = VISIBILITY_REFRESH_INTERVAL

	_update_projectiles(delta)
	if earthquake_timer > 0.0:
		earthquake_timer = maxf(0.0, earthquake_timer - delta)
		shake(earthquake_intensity)
	_update_shake(delta)
	_update_crystal(delta)


func _create_fog_of_war() -> void:
	var arena := get_node_or_null("Arena") as Node3D
	if arena == null or arena.get_node_or_null("FogOfWar") != null:
		return
	var fog_shader := load(FOG_OF_WAR_SHADER_PATH) as Shader
	if fog_shader == null:
		return

	fog_of_war_plane = MeshInstance3D.new()
	fog_of_war_plane.name = "FogOfWar"
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(ARENA_SAFE_HALF_X * 2.0, ARENA_SAFE_HALF_Z * 2.0)
	fog_of_war_plane.mesh = plane_mesh
	fog_of_war_plane.position = Vector3(0.0, 0.35, 0.0)
	fog_of_war_plane.visible = false
	fog_of_war_material = ShaderMaterial.new()
	fog_of_war_material.shader = fog_shader
	fog_of_war_material.set_shader_parameter("view_radius", FOG_VIEW_RADIUS)
	fog_of_war_material.set_shader_parameter("arena_half_extent", Vector2(ARENA_SAFE_HALF_X, ARENA_SAFE_HALF_Z))
	fog_of_war_plane.material_override = fog_of_war_material
	arena.add_child(fog_of_war_plane)


func _update_fog_of_war() -> void:
	if fog_of_war_plane == null or fog_of_war_material == null:
		return
	fog_of_war_plane.visible = state == "live"
	if state != "live":
		return
	if player == null or not is_instance_valid(player):
		return

	var vision_positions: Array[Vector3] = []
	for ally in heroes:
		if ally == null or not is_instance_valid(ally) or ally.dead or ally.team != player.team:
			continue
		vision_positions.append(ally.global_position)
		if vision_positions.size() >= 3:
			break

	var primary_position := player.global_position
	var ally_position_1 := Vector3(100000.0, 0.0, 100000.0)
	var ally_position_2 := Vector3(100000.0, 0.0, 100000.0)
	if not vision_positions.is_empty():
		primary_position = vision_positions[0]
	if vision_positions.size() > 1:
		ally_position_1 = vision_positions[1]
	if vision_positions.size() > 2:
		ally_position_2 = vision_positions[2]
	fog_of_war_material.set_shader_parameter("player_position", primary_position)
	fog_of_war_material.set_shader_parameter("ally_position_1", ally_position_1)
	fog_of_war_material.set_shader_parameter("ally_position_2", ally_position_2)
	fog_of_war_material.set_shader_parameter("vision_count", vision_positions.size())


func _update_camera(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return

	if player.dead:
		if not death_camera_active:
			death_camera_active = true
			camera_pos = camera.global_position
			death_camera_last_distance = camera_distance
			announce("Наблюдение: WASD — камера, колесико — зум", Color(0.82, 0.9, 1.0), 4.0)

		if not is_equal_approx(camera_distance, death_camera_last_distance):
			var zoom_delta := camera_distance - death_camera_last_distance
			camera.global_position -= -camera.global_transform.basis.z * zoom_delta
			camera_pos = camera.global_position
			death_camera_last_distance = camera_distance

		var pan_input := Vector2.ZERO
		if Input.is_action_pressed("move_left") or Input.is_action_pressed("move_left_2") or Input.is_key_pressed(KEY_LEFT):
			pan_input.x -= 1.0
		if Input.is_action_pressed("move_right") or Input.is_action_pressed("move_right_2") or Input.is_key_pressed(KEY_RIGHT):
			pan_input.x += 1.0
		if Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_forward_2") or Input.is_key_pressed(KEY_UP):
			pan_input.y += 1.0
		if Input.is_action_pressed("move_back") or Input.is_action_pressed("move_back_2") or Input.is_key_pressed(KEY_DOWN):
			pan_input.y -= 1.0

		if pan_input.length_squared() > 0.0:
			pan_input = pan_input.normalized()
			var team_orientation := 1.0 if player.team == 0 else -1.0
			var pan_direction := Vector3(pan_input.x * team_orientation, 0.0, -pan_input.y * team_orientation)
			camera_pos = camera.global_position + pan_direction * 16.0 * delta
			camera.global_position = camera_pos
		return

	death_camera_active = false
	var focus := player.global_position + Vector3(0.0, 1.0, 0.0)
	var camera_side := 1.0 if player.team == 0 else -1.0
	# Previous angle was approximately 33 degrees: Vector3(0.0, 13.0, 20.0 * camera_side).
	var camera_axis := Vector3(0.0, 20.0, 20.0 * camera_side).normalized()
	var target_pos := focus + camera_axis * camera_distance
	camera_pos = camera_pos.lerp(target_pos, 1.0 - exp(-5.0 * delta))
	camera.global_position = camera_pos
	camera.look_at(focus, Vector3.UP)


func _update_enemy_visibility() -> void:
	if player == null or not is_instance_valid(player):
		return
	var excluded_rids: Array[RID] = []
	var vision_allies: Array[HeroUnit] = []
	for hero in heroes:
		if hero != null and is_instance_valid(hero):
			excluded_rids.append(hero.get_rid())
			if hero.team == player.team and not hero.dead:
				vision_allies.append(hero)
	var space_state := get_world_3d().direct_space_state
	for hero in heroes:
		if hero == null or not is_instance_valid(hero):
			continue
		if hero == player or hero.team == player.team or hero.dead:
			hero.set_occluded_from_player(false)
			continue
		var seen_by_team := false
		var target_position := hero.global_position + Vector3(0.0, 1.15, 0.0)
		for ally in vision_allies:
			if not hero.is_within_view_distance(ally, FOG_VIEW_RADIUS) or hero.is_hidden_from(ally):
				continue
			var ray := PhysicsRayQueryParameters3D.create(
				ally.global_position + Vector3(0.0, 1.15, 0.0),
				target_position,
				VISIBILITY_COLLISION_MASK,
				excluded_rids
			)
			ray.collide_with_areas = false
			ray.collide_with_bodies = true
			if space_state.intersect_ray(ray).is_empty():
				seen_by_team = true
				break
		hero.set_occluded_from_player(not seen_by_team)

func _update_shake(delta: float) -> void:
	shake_amount = maxf(0.0, shake_amount - delta * 2.2)
	if shake_amount > 0.01:
		camera.h_offset = randf_range(-1.0, 1.0) * shake_amount * 0.5
		camera.v_offset = randf_range(-1.0, 1.0) * shake_amount * 0.5
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _update_match(delta: float) -> void:
	if sudden_death:
		match_time = 0.0
	else:
		match_time = maxf(0.0, match_time - delta)
		if match_time <= 0.0 and not network_play:
			if score[0] == score[1]:
				sudden_death = true
				announce("Решающий осколок!", Color(1.0, 0.75, 0.35), 3.0)
			else:
				end_match(score[0] > score[1])
				return

	shell_cycle_timer = maxf(0.0, shell_cycle_timer - delta)
	shell_timer = shell_cycle_timer
	if shell_phase == "idle" and shell_cycle_timer <= SHELL_WARNING_TIME:
		shell_phase = "warning"
		announce("Оболочка пробуждается — 10 секунд!", Color(0.78, 0.6, 1.0), 2.4)
	if shell_phase == "warning":
		if shell_cycle_timer <= 0.0:
			_spawn_shell()
	elif shell_phase == "active":
		shell_window -= delta
		if shell_window <= 0.0 and shell != null and is_instance_valid(shell) and shell.alive:
			shell.despawn()
			shell = null
			shell_phase = "idle"
			announce("Оболочка ушла в тень", Color(0.7, 0.7, 0.8), 1.6)


func _spawn_shell() -> void:
	var s := shell_pool
	if s == null or not is_instance_valid(s):
		s = SkyShell.new()
		s.name = "Shell"
		add_child(s)
		s.setup(self)
		shell_pool = s
	if tutorial_mode:
		s.max_health = 1000.0
	s.activate(self, Vector3(0.0, 0.16, 0.0))
	shell = s
	shell_phase = "active"
	shell_window = SHELL_WINDOW
	shell_cycle_timer = SHELL_SPAWN_INTERVAL
	shell_timer = shell_cycle_timer
	announce("Оболочка здесь", Color(0.85, 0.62, 1.0), 2.6)
	play_sfx("thunder", -3.0)
	shake(0.6)
	burst(Vector3(0.0, 1.2, 0.0), Color(0.8, 0.5, 1.0), 44)
	ring_fx(Vector3(0.0, 0.2, 0.0), Color(0.8, 0.5, 1.0), 8.0)


func on_shell_died(s: SkyShell, source: Node = null) -> void:
	if s != shell:
		return
	if source == player and not tutorial_mode:
		p_shells_destroyed += 1
	if not tutorial_mode and player != null and source is HeroUnit and (source as HeroUnit).team == player.team:
		award_gold(100)
	if not tutorial_mode and source is HeroUnit and not (source as HeroUnit).is_player:
		(source as HeroUnit).bot_gold += 100
	var pos := s.global_position
	var vfx_host := source as HeroUnit
	if vfx_host == null or not is_instance_valid(vfx_host):
		vfx_host = player
	if vfx_host != null and is_instance_valid(vfx_host):
		vfx_host.spawn_vfx_silent(HeroUnit.VFX_BIG_IMPACT_02_SCENE, pos, 1.8)
	burst(pos, Color(0.75, 0.9, 1.0), 60)
	ring_fx(Vector3(pos.x, 0.25, pos.z), Color(0.8, 0.95, 1.0), 9.0)
	play_sfx("thunder", -2.0)
	shake(0.8)
	spawn_crystal(pos, true)
	announce("Оболочка пала! Осколок свободен", Color(0.8, 0.95, 1.0), 2.4)
	s.retire(0.5)
	shell = null
	shell_phase = "idle"
	if network_play:
		var event_team := 0
		if source is HeroUnit:
			event_team = (source as HeroUnit).team
		elif player != null and is_instance_valid(player):
			event_team = player.team
		NetworkManager.send_match_event("shell_destroyed", event_team)
	if tutorial_mode and tutorial_controller != null:
		tutorial_controller.call("on_shell_destroyed")


func spawn_crystal(pos: Vector3, spawn_on_pedestal := false) -> void:
	if crystal_node != null and is_instance_valid(crystal_node):
		crystal_node.queue_free()
	if carrier != null and is_instance_valid(carrier):
		carrier.carrying = false
	var c := Node3D.new()
	c.name = "Crystal"
	add_child(c)
	var crystal_visual := CRYSTAL_SCENE.instantiate() as Node3D
	crystal_visual.name = "CrystalModel"
	crystal_visual.scale = Vector3.ONE * CRYSTAL_MODEL_SCALE
	crystal_visual.position.y = -0.572
	_apply_crystal_emission(crystal_visual)
	c.add_child(crystal_visual)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.9, 1.0)
	light.light_energy = 3.0
	light.omni_range = 9.0
	c.add_child(light)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.05
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.7, 0.95, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.7, 0.95, 1.0)
	ring_mat.emission_energy_multiplier = 2.2
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.position.y = -0.6
	c.add_child(ring)
	var drop_position := Vector3.ZERO if spawn_on_pedestal else _find_crystal_drop_position(pos)
	c.global_position = Vector3(drop_position.x, 1.3, drop_position.z)
	c.set_meta("spin", 0.0)
	crystal_node = c
	crystal_state = "ground"
	crystal_timer = 0.0
	pickup_delay = CRYSTAL_PICKUP_DELAY
	carrier = null


func _apply_crystal_emission(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var source_material := mesh_instance.get_active_material(0) as StandardMaterial3D
		var crystal_material := StandardMaterial3D.new()
		if source_material != null:
			crystal_material = source_material.duplicate() as StandardMaterial3D
		else:
			crystal_material.albedo_color = Color(0.45, 0.82, 1.0)
		crystal_material.roughness = 0.22
		crystal_material.metallic = 0.25
		crystal_material.emission_enabled = true
		crystal_material.emission = CRYSTAL_EMISSION_COLOR
		crystal_material.emission_energy_multiplier = 1.8
		mesh_instance.material_override = crystal_material
	for child in node.get_children():
		_apply_crystal_emission(child)


func _find_crystal_drop_position(origin: Vector3) -> Vector3:
	var best_position := Vector3(0.0, 0.0, 12.0)
	var best_clearance := -1.0
	var angle_offset := randf_range(0.0, TAU)
	for radius in CRYSTAL_DROP_SEARCH_RADII:
		for index in range(16):
			var angle := angle_offset + TAU * float(index) / 16.0
			var candidate := clamp_to_arena(Vector3(
				origin.x + cos(angle) * radius,
				0.0,
				origin.z + sin(angle) * radius
			))
			if not _is_crystal_drop_position_clear(candidate):
				continue
			var nearest_hero_distance := INF
			for hero in heroes:
				if hero == null or not is_instance_valid(hero) or hero.dead:
					continue
				var hero_position := Vector2(hero.global_position.x, hero.global_position.z)
				var candidate_position := Vector2(candidate.x, candidate.z)
				nearest_hero_distance = minf(nearest_hero_distance, candidate_position.distance_to(hero_position))
			if nearest_hero_distance > best_clearance:
				best_clearance = nearest_hero_distance
				best_position = candidate
			if nearest_hero_distance >= 2.4:
				return candidate
	return best_position


func _is_crystal_drop_position_clear(candidate: Vector3) -> bool:
	var point := Vector2(candidate.x, candidate.z)
	if point.length() < 7.6:
		return false
	var bushes := get_node_or_null("Arena/Bushes")
	if bushes != null:
		for bush in bushes.get_children():
			if bush is Area3D:
				var bush_position := Vector2(bush.global_position.x, bush.global_position.z)
				if point.distance_to(bush_position) < 3.4:
					return false
	for root_path in ["Arena/Altar", "Arena/Ruins", "Arena/Bases", "Arena/Decor"]:
		var obstacle_root := get_node_or_null(root_path) as Node3D
		if obstacle_root == null:
			continue
		for obstacle in obstacle_root.get_children():
			if not obstacle is Node3D:
				continue
			var obstacle_node := obstacle as Node3D
			var clearance_radius := _decoration_footprint_radius(obstacle_node) + 1.2
			if point.distance_to(Vector2(obstacle_node.global_position.x, obstacle_node.global_position.z)) < clearance_radius:
				return false
	return true


func _decoration_footprint_radius(root: Node3D) -> float:
	var radius := 0.0
	var root_inverse := root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mesh_instance := current as MeshInstance3D
			if mesh_instance.mesh != null:
				var local_position: Vector3 = root_inverse * mesh_instance.global_position
				var bounds := mesh_instance.mesh.get_aabb()
				var horizontal_scale := maxf(absf(mesh_instance.scale.x), absf(mesh_instance.scale.z))
				var extent := maxf(bounds.size.x, bounds.size.z) * horizontal_scale * 0.5
				radius = maxf(radius, Vector2(local_position.x, local_position.z).length() + extent)
		for child in current.get_children():
			stack.append(child)
	var root_scale := maxf(absf(root.scale.x), absf(root.scale.z))
	return radius * root_scale


func _update_crystal(delta: float) -> void:
	if crystal_node == null or not is_instance_valid(crystal_node):
		return
	if crystal_state == "ground":
		crystal_timer += delta
		pickup_delay = maxf(0.0, pickup_delay - delta)
		crystal_node.rotation.y += delta * 1.8
		crystal_node.position.y = 1.1 + sin(crystal_timer * 2.4) * 0.12
		if crystal_timer >= GROUND_CRYSTAL_LIFETIME:
			var expired_position := crystal_node.global_position
			crystal_node.queue_free()
			crystal_node = null
			crystal_state = "none"
			carrier = null
			pickup_delay = 0.0
			burst(expired_position, Color(0.7, 0.9, 1.0), 18)
			return
		if crystal_timer > 35.0:
			crystal_node.global_position = Vector3(0.0, 1.1, 0.0)
			crystal_timer = 0.0
			announce("Осколок вернулся к алтарю", Color(0.75, 0.9, 1.0), 1.8)
		if state == "live" and pickup_delay <= 0.0:
			_try_pickup()
	elif crystal_state == "carried" and carrier != null and is_instance_valid(carrier):
		crystal_node.global_position = carrier.global_position + Vector3(0.0, 2.9, 0.0)
		if not is_instance_valid(crystal_node):
			crystal_state = "none"
			carrier.carrying = false
			carrier = null
		crystal_node.rotation.y += delta * 2.4
		var base_z := BASE_POSITION_Z if carrier.team == 0 else -BASE_POSITION_Z
		if Vector2(carrier.global_position.x, carrier.global_position.z - base_z).length() < BASE_DELIVERY_RADIUS:
			_deliver(carrier)


func _try_pickup() -> void:
	var best: HeroUnit = null
	var best_d := CRYSTAL_PICKUP_RADIUS
	for h in heroes:
		if h == null or not is_instance_valid(h) or h.dead or h.carrying:
			continue
		var d := Vector2(h.global_position.x, h.global_position.z).distance_to(
			Vector2(crystal_node.global_position.x, crystal_node.global_position.z)
		)
		if d < best_d:
			best_d = d
			best = h
	if best != null:
		best.carrying = true
		carrier = best
		crystal_state = "carried"
		play_sfx("shard_pickup", -9.0)
		if best == player:
			announce("Осколок у тебя! Неси на базу", Color(0.75, 1.0, 0.85), 2.0)
		else:
			announce("%s несёт осколок %s" % [best.display_name, "к свету" if best.team == 0 else "во тьму"], Color(0.85, 0.85, 0.95), 1.6)


func _deliver(h: HeroUnit) -> void:
	if tutorial_mode:
		h.carrying = false
		carrier = null
		crystal_state = "none"
		if crystal_node != null and is_instance_valid(crystal_node):
			burst(crystal_node.global_position, Color(0.7, 0.95, 1.0), 40)
			crystal_node.queue_free()
			crystal_node = null
		play_sfx("shard_delivery", -8.0)
		if tutorial_controller != null:
			tutorial_controller.call("on_delivery")
		return
	h.carrying = false
	score[h.team] += 1
	if player != null and h.team == player.team:
		award_gold(100)
	if not h.is_player:
		h.bot_gold += 100
	if h == player:
		p_crystals += 1
	carrier = null
	crystal_state = "none"
	if crystal_node != null and is_instance_valid(crystal_node):
		burst(crystal_node.global_position, Color(0.7, 0.95, 1.0), 40)
		crystal_node.queue_free()
		crystal_node = null
	play_sfx("shard_delivery", -8.0)
	var team_name := "Свет" if h.team == 0 else "Тьма"
	announce("Осколок на базе: %s  %d : %d" % [team_name, score[0], score[1]], Color(1.0, 0.9, 0.6), 2.6)
	if network_play:
		NetworkManager.send_match_event("shard_delivered", h.team)
		shell_phase = "idle"
	elif sudden_death or score[h.team] >= CRYSTALS_TO_WIN:
		end_match(h.team == 0)
	else:
		shell_phase = "idle"


func drop_crystal(pos: Vector3) -> void:
	if crystal_node == null or not is_instance_valid(crystal_node):
		return
	crystal_state = "ground"
	crystal_timer = 0.0
	pickup_delay = 0.5
	carrier = null
	crystal_node.global_position = Vector3(pos.x, 0.5, pos.z)


func on_hero_died(h: HeroUnit) -> void:
	burst(h.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.45, 0.4), 22)
	h.spawn_vfx_silent(HeroUnit.VFX_GOLDEN_SCENE, h.global_position + Vector3(0.0, 0.4, 0.0), 1.2)
	play_sfx("hit", -6.0)
	if h == player:
		p_deaths += 1
		if network_play:
			NetworkManager.send_death()
	if h == carrier or h.carrying:
		drop_crystal(h.global_position)
		announce("Осколок выбит!", Color(1.0, 0.7, 0.4), 1.8)
	if h == player:
		announce("Ты пал. Возрождение через %d" % int(ceil(h.respawn_timer)), Color(1.0, 0.5, 0.45), 2.2)


func record_hero_damage(target: HeroUnit, source: Node, damage: float, killed: bool) -> void:
	if source is HeroUnit and killed and target.team != (source as HeroUnit).team and not (source as HeroUnit).is_player:
		(source as HeroUnit).bot_gold += 50
	if player == null or source != player or target == player or target.team == player.team or damage <= 0.0:
		return
	p_damage += damage
	if killed:
		p_kills += 1
		award_gold(50)


func on_hero_respawned(h: HeroUnit) -> void:
	if h == player:
		death_camera_active = false
		if network_play:
			var visual_rotation := h.global_rotation.y
			if h.visual != null:
				visual_rotation = h.visual.global_rotation.y
			NetworkManager.send_respawn(h.global_position, visual_rotation)
			NetworkManager.send_stats(h.max_health, h.health, h.attack_damage)
	burst(h.global_position + Vector3(0.0, 0.6, 0.0), Color(0.6, 0.9, 1.0), 18)


func end_match(team_zero_won: bool) -> void:
	if state != "live":
		return
	state = "over"
	if network_play:
		NetworkManager.unregister_local_player()
	set_shop_open(false)
	var player_team := 0
	if player != null and is_instance_valid(player):
		player_team = player.team
	player_won = team_zero_won if player_team == 0 else not team_zero_won
	var player_place := _get_player_place()
	var player_is_mvp := _is_player_mvp()
	result_text = "ПОБЕДА" if player_won else "ПОРАЖЕНИЕ"
	get_tree().set_meta("last_match_won", player_won)
	get_tree().set_meta("last_match_score", score.duplicate())
	get_tree().set_meta("last_match_team", player_team)
	get_tree().set_meta("last_match_place", player_place)
	get_tree().set_meta("last_match_is_mvp", player_is_mvp)
	get_tree().set_meta("last_match_stats", {
		"p_kills": p_kills,
		"p_deaths": p_deaths,
		"p_damage": p_damage,
		"p_crystals": p_crystals,
		"p_shells_destroyed": p_shells_destroyed,
		"p_coins_collected": player.match_coins_collected if player != null else 0,
		"p_gold_earned": gold_earned_this_match,
		"p_gold_spent": player.match_gold_spent if player != null else 0,
	})
	if player != null and is_instance_valid(player):
		get_tree().set_meta("selected_class", player.hero_class)
		player.is_player = false
	announce(result_text, Color(0.85, 1.0, 0.7) if player_won else Color(1.0, 0.5, 0.45), 6.0)
	var transition_timer := get_tree().create_timer(2.8)
	transition_timer.timeout.connect(_open_results_screen)


func _get_player_place() -> int:
	if player == null or not is_instance_valid(player):
		return 4
	var place := 1
	var player_coin_score := player.match_coins_collected + player.match_gold_spent
	for hero in heroes:
		if hero == null or not is_instance_valid(hero) or hero == player:
			continue
		var hero_coin_score := hero.match_coins_collected + hero.match_gold_spent
		if hero_coin_score > player_coin_score:
			place += 1
	return place


func _is_player_mvp() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var player_coin_score := player.match_coins_collected + player.match_gold_spent
	for hero in heroes:
		if hero == null or not is_instance_valid(hero) or hero == player:
			continue
		if hero.match_coins_collected + hero.match_gold_spent >= player_coin_score:
			return false
	return true


func _open_results_screen() -> void:
	if state != "over":
		return
	var error := get_tree().change_scene_to_file("res://scenes/ResultsScreen.tscn")
	if error != OK:
		push_error("Failed to open ResultsScreen: %s" % error_string(error))


func announce(text: String, color: Color, duration := 2.0) -> void:
	last_announce = text
	if hud != null:
		hud.show_announcement(text, color, duration)


func network_attack_target(from_position: Vector3, team: int, max_dist: float, facing: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := max_dist
	for remote in remote_players.values():
		if remote == null or not is_instance_valid(remote) or remote.dead or remote.team == team:
			continue
		var offset: Vector3 = remote.global_position - from_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.01 or distance > max_dist:
			continue
		if facing.length_squared() > 0.01 and facing.normalized().dot(offset.normalized()) < 0.0:
			continue
		if distance < best_distance:
			best_distance = distance
			best = remote
	return best


func network_nearest_enemy(from_position: Vector3, team: int, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_distance := max_dist
	for remote in remote_players.values():
		if remote == null or not is_instance_valid(remote) or remote.dead or remote.team == team:
			continue
		var distance := from_position.distance_to(remote.global_position)
		if distance < best_distance:
			best_distance = distance
			best = remote
	return best


func network_enemies_in_radius(center: Vector3, radius: float, team: int) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for remote in remote_players.values():
		if remote == null or not is_instance_valid(remote) or remote.dead or remote.team == team:
			continue
		if center.distance_to(remote.global_position) <= radius:
			result.append(remote)
	return result


func network_allies_in_radius(center: Vector3, radius: float, team: int) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for remote in remote_players.values():
		if remote == null or not is_instance_valid(remote) or remote.dead or remote.team != team:
			continue
		if center.distance_to(remote.global_position) <= radius:
			result.append(remote)
	return result


func enemies_of(team: int, observer: HeroUnit = null) -> Array[HeroUnit]:
	var out: Array[HeroUnit] = []
	for h in heroes:
		if h.team == team or h.dead:
			continue
		if observer != null and h.is_hidden_from(observer):
			continue
		out.append(h)
	return out


func nearest_enemy(from: Vector3, team: int, max_dist: float, observer: HeroUnit = null) -> HeroUnit:
	var best: HeroUnit = null
	var best_d := max_dist
	for h in heroes:
		if h.team == team or h.dead:
			continue
		if observer != null and h.is_hidden_from(observer):
			continue
		var d := from.distance_to(h.global_position)
		if d < best_d:
			best_d = d
			best = h
	return best


func enemies_in_radius(center: Vector3, radius: float, team: int, observer: HeroUnit = null) -> Array[HeroUnit]:
	var nearby: Array[HeroUnit] = []
	for enemy in enemies_of(team, observer):
		if enemy.global_position.distance_to(center) <= radius:
			nearby.append(enemy)
	return nearby


func _on_bush_body_entered(body: Node3D, bush: Area3D) -> void:
	if body is HeroUnit:
		(body as HeroUnit).set_bush_presence(bush, true)


func _on_bush_body_exited(body: Node3D, bush: Area3D) -> void:
	if body is HeroUnit:
		(body as HeroUnit).set_bush_presence(bush, false)


func set_tutorial_target(world_position: Vector3, color: Color) -> void:
	tutorial_target_position = world_position
	tutorial_target_color = color
	tutorial_target_active = true
	_ensure_tutorial_arrow()
	if tutorial_arrow_material != null:
		tutorial_arrow_material.albedo_color = color
		tutorial_arrow_material.emission = color
	if tutorial_arrow != null:
		tutorial_arrow.visible = true


func clear_tutorial_target() -> void:
	tutorial_target_active = false
	if tutorial_arrow != null and is_instance_valid(tutorial_arrow):
		tutorial_arrow.visible = false


func _ensure_tutorial_arrow() -> void:
	if tutorial_arrow != null and is_instance_valid(tutorial_arrow):
		return
	tutorial_arrow = MeshInstance3D.new()
	tutorial_arrow.name = "TutorialArrow"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.55
	cone.height = 1.2
	cone.radial_segments = 20
	tutorial_arrow.mesh = cone
	tutorial_arrow.rotation.x = PI
	tutorial_arrow_material = StandardMaterial3D.new()
	tutorial_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tutorial_arrow_material.albedo_color = Color(1.0, 0.82, 0.32)
	tutorial_arrow_material.emission_enabled = true
	tutorial_arrow_material.emission = Color(1.0, 0.82, 0.32)
	tutorial_arrow_material.emission_energy_multiplier = 2.2
	tutorial_arrow_material.no_depth_test = true
	tutorial_arrow_material.render_priority = 2
	tutorial_arrow.material_override = tutorial_arrow_material
	add_child(tutorial_arrow)


func _update_tutorial_arrow(delta: float) -> void:
	if tutorial_arrow == null or not is_instance_valid(tutorial_arrow):
		return
	if not tutorial_mode or not tutorial_target_active:
		tutorial_arrow.visible = false
		return
	tutorial_pulse_time += delta
	var pulse := 0.5 + 0.5 * sin(tutorial_pulse_time * 4.2)
	tutorial_arrow.visible = true
	tutorial_arrow.global_position = tutorial_target_position + Vector3(0.0, 3.4 + sin(tutorial_pulse_time * 2.4) * 0.25, 0.0)
	tutorial_arrow.rotation.y += delta * 1.8
	tutorial_arrow.scale = Vector3.ONE * (1.0 + pulse * 0.14)
	if tutorial_arrow_material != null:
		tutorial_arrow_material.emission_energy_multiplier = 1.4 + pulse * 2.0


func spawn_tutorial_dummy() -> void:
	if tutorial_dummy != null and is_instance_valid(tutorial_dummy):
		return
	tutorial_dummy = _spawn_hero(HeroUnit.Cls.WARRIOR, 1 - player.team, false, Vector3(0.0, 0.76, 0.0))
	tutorial_dummy.name = "TrainingDummy"
	tutorial_dummy.display_name = "Манекен"
	tutorial_dummy.tutorial_dummy = true
	tutorial_dummy.max_health = 1000.0
	tutorial_dummy.health = 1000.0
	tutorial_dummy.move_speed = 0.0
	tutorial_dummy.attack_damage = 0.0
	tutorial_dummy.set_physics_process(false)
	tutorial_dummy._update_health_display()


func remove_tutorial_dummy() -> void:
	if tutorial_dummy == null or not is_instance_valid(tutorial_dummy):
		return
	heroes.erase(tutorial_dummy)
	tutorial_dummy.queue_free()
	tutorial_dummy = null


func lowest_ally(from: Vector3, team: int, max_dist: float) -> HeroUnit:
	var best: HeroUnit = null
	var best_frac := 1.0
	for h in heroes:
		if h.team != team or h.dead:
			continue
		if from.distance_to(h.global_position) > max_dist:
			continue
		var frac := h.health / h.max_health
		if frac < best_frac:
			best_frac = frac
			best = h
	return best


func alive_heroes_near(center: Vector3, radius: float) -> int:
	var count := 0
	for h in heroes:
		if not h.dead and center.distance_to(h.global_position) <= radius:
			count += 1
	return count


func pick_shell_target() -> HeroUnit:
	var options: Array[HeroUnit] = []
	for h in heroes:
		if not h.dead and h.global_position.distance_to(Vector3.ZERO) < 14.5:
			options.append(h)
	if options.is_empty():
		return null
	if carrier != null and not carrier.dead and randf() < 0.55:
		return carrier
	return options[randi() % options.size()]


func aoe(center: Vector3, radius: float, amount: float, source_team: int, stun_time: float, hurt_shell: bool, source: HeroUnit = null, damage_type: String = "physical") -> void:
	var adjusted_amount := amount * (source.get_blessing_damage_multiplier() if source != null else 1.0)
	for h in enemies_of(source_team):
		if h.global_position.distance_to(center) <= radius:
			var hit_damage := source.roll_direct_damage(adjusted_amount) if source != null else adjusted_amount
			h.take_damage(hit_damage, source, damage_type)
			if stun_time > 0.0:
				h.stun(stun_time)
	if hurt_shell and shell != null and is_instance_valid(shell) and shell.alive:
		if shell.global_position.distance_to(center) <= radius + 1.0:
			var shell_damage := source.roll_direct_damage(adjusted_amount * 0.8) if source != null else adjusted_amount * 0.8
			shell.take_damage(shell_damage, source)


func heal_area(center: Vector3, radius: float, amount: float, team: int, max_targets: int, source: HeroUnit = null) -> void:
	var targets: Array[HeroUnit] = []
	for h in heroes:
		if h.team != team or h.dead:
			continue
		if h.global_position.distance_to(center) <= radius and h.health < h.max_health:
			targets.append(h)
	targets.sort_custom(func(a, b): return a.health / a.max_health < b.health / b.max_health)
	var count := 0
	for h in targets:
		if count >= max_targets:
			break
		h.heal(amount)
		ring_fx(Vector3(h.global_position.x, 0.3, h.global_position.z), Color(0.58, 1.0, 0.7), 1.25)
		count += 1
	if source != null and source.is_player:
		for remote in network_allies_in_radius(center, radius, team):
			if count >= max_targets:
				break
			if remote.dead or remote.health >= remote.max_health:
				continue
			remote.receive_heal(amount, source)
			ring_fx(Vector3(remote.global_position.x, 0.3, remote.global_position.z), Color(0.58, 1.0, 0.7), 1.25)
			count += 1


func bless_team(team: int, duration: float) -> void:
	for hero in heroes:
		if hero.team == team and not hero.dead:
			hero.apply_blessing(duration)


func spawn_projectile(from: Vector3, target: Node3D, damage: float, color: Color, source: HeroUnit, stun_time := 0.0, damage_type: String = "physical", effect_type: String = "") -> void:
	if target == null or not is_instance_valid(target):
		return
	var node := _acquire_projectile()
	if node == null:
		return
	var mat := node.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = color
	node.visible = true
	node.global_position = from
	projectiles.append({
		"node": node,
		"target": target,
		"damage": damage,
		"color": color,
		"source": source,
		"stun": stun_time,
		"damage_type": damage_type,
		"effect_type": effect_type,
		"life": 2.5,
		"pooled": true,
	})


func _update_projectiles(delta: float) -> void:
	var keep: Array = []
	for p in projectiles:
		var node: Node3D = p["node"]
		var target = p["target"]
		if not is_instance_valid(node):
			continue
		p["life"] = float(p["life"]) - delta
		if p["life"] <= 0.0:
			_release_projectile(node, bool(p.get("pooled", false)))
			continue
		if p.get("black_hole", false):
			var bh_dir: Vector3 = p.get("bh_dir", Vector3.FORWARD)
			node.global_position += bh_dir * 5.0 * delta
			for h in enemies_of(p["source"].team if p.has("source") else 0):
				if not h.dead and h.global_position.distance_to(node.global_position) <= float(p.get("radius", 3.5)):
					h.take_damage(float(p["damage"]) * delta * 0.5, p["source"], String(p.get("damage_type", "magic")))
			if randf() < 0.3:
				burst(node.global_position, p["color"], 3)
			keep.append(p)
			continue
		if not is_instance_valid(target) or (target is HeroUnit and (target as HeroUnit).dead):
			_release_projectile(node, bool(p.get("pooled", false)))
			continue
		var goal: Vector3 = target.global_position + Vector3(0.0, 1.1, 0.0)
		var to_goal: Vector3 = goal - node.global_position
		var dist := to_goal.length()
		if dist < 0.6:
			if target.has_method("take_damage"):
				target.take_damage(p["damage"], p["source"], String(p.get("damage_type", "physical")), String(p.get("effect_type", "auto")))
				var attack_source := p.get("source") as HeroUnit
				if attack_source != null:
					attack_source.spawn_attack_impact_vfx(target.global_position + Vector3(0.0, 0.9, 0.0), String(p.get("effect_type", "")))
				if float(p["stun"]) > 0.0 and target is HeroUnit:
					(target as HeroUnit).stun(float(p["stun"]))
			var effect_type := String(p.get("effect_type", ""))
			if effect_type == "root":
				root_snare_fx(target.global_position, Color(0.35, 0.92, 0.48))
			elif effect_type == "stun":
				stun_impact_fx(target.global_position, p["color"])
			burst(node.global_position, p["color"], 10)
			if p.get("source") == null:
				play_sfx("magic", -12.0)
			_release_projectile(node, bool(p.get("pooled", false)))
			continue
		node.global_position += to_goal.normalized() * minf(dist, 26.0 * delta)
		keep.append(p)
	projectiles = keep


func melee_fx(_from: Vector3, to: Vector3) -> void:
	burst(to + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.85, 0.5), 10)


func mage_storm_tick(mage: HeroUnit, radius: float, damage: float) -> void:
	if state != "live" or mage.dead:
		return
	play_sfx("thunder", -10.0)
	for enemy in enemies_in_radius(mage.global_position, radius, mage.team):
		_activate_shell_beam(enemy.global_position, Color(0.38, 0.82, 1.0, 0.95))
		mage.spawn_ability_vfx(2, enemy.global_position + Vector3(0.0, 0.1, 0.0))
		var rolled_damage := mage.roll_ultimate_damage(damage)
		enemy.take_damage(mage._outgoing_damage(rolled_damage) * mage.get_blessing_damage_multiplier(), mage, "magic")
	if mage.is_player:
		for remote_enemy in network_enemies_in_radius(mage.global_position, radius, mage.team):
			_activate_shell_beam(remote_enemy.global_position, Color(0.38, 0.82, 1.0, 0.95))
			mage.spawn_ability_vfx(2, remote_enemy.global_position + Vector3(0.0, 0.1, 0.0))
			var network_damage := mage.roll_ultimate_damage(damage)
			remote_enemy.take_damage(mage._outgoing_damage(network_damage) * mage.get_blessing_damage_multiplier(), mage, "magic", "ult_lightning_storm")


func shell_bolt(pos: Vector3, radius: float, damage: float) -> void:
	play_sfx("thunder", -2.0)
	shake(0.7)
	_activate_shell_beam(pos)
	burst(pos + Vector3(0.0, 0.6, 0.0), Color(0.85, 0.65, 1.0), 34)
	ring_fx(Vector3(pos.x, 0.2, pos.z), Color(0.85, 0.65, 1.0), radius)
	for h in heroes:
		if not h.dead and h.global_position.distance_to(pos) <= radius:
			h.take_damage(damage, null, "magic")
			h.stun(1.0)


func telegraph(pos: Vector3, radius: float, duration: float) -> void:
	var start_scale := Vector3(radius, 1.0, radius)
	var target_scale := Vector3(radius * 1.15, 1.0, radius * 1.15)
	_activate_ring(Vector3(pos.x, 0.25, pos.z), Color(1.0, 0.35, 0.55), duration, start_scale, target_scale, false, 0.9)


func burst(pos: Vector3, color: Color, count := 16) -> void:
	var entry := _acquire_burst(count)
	if entry.is_empty():
		return
	var particles := entry["node"] as CPUParticles3D
	var material := entry["material"] as StandardMaterial3D
	material.albedo_color = color
	material.emission = color
	particles.global_position = pos
	particles.visible = true
	particles.emitting = false
	particles.restart()
	particles.emitting = true


func ring_fx(pos: Vector3, color: Color, radius: float) -> void:
	_activate_ring(Vector3(pos.x, 0.35, pos.z), color, 0.4, Vector3.ONE, Vector3(radius, 1.0, radius), true, 0.8)


func dash_fx(start_pos: Vector3, end_pos: Vector3, color: Color) -> void:
	burst(start_pos + Vector3(0.0, 0.9, 0.0), color, 20)
	burst(start_pos.lerp(end_pos, 0.5) + Vector3(0.0, 0.8, 0.0), color, 14)
	burst(end_pos + Vector3(0.0, 0.9, 0.0), color, 28)
	_activate_ring(Vector3(end_pos.x, 0.3, end_pos.z), color, 0.42, Vector3(0.35, 1.0, 0.35), Vector3(2.6, 1.0, 2.6), true, 0.9)


func earthquake_fx(center: Vector3, radius: float, duration: float) -> void:
	earthquake_timer = maxf(earthquake_timer, duration)
	earthquake_intensity = maxf(earthquake_intensity, 0.55)
	if player != null and is_instance_valid(player) and player.global_position.distance_to(center) <= radius + 5.0:
		shake(earthquake_intensity)
	var crack_material := StandardMaterial3D.new()
	crack_material.albedo_color = Color(0.12, 0.065, 0.025, 0.95)
	crack_material.emission_enabled = true
	crack_material.emission = Color(0.65, 0.24, 0.035)
	crack_material.emission_energy_multiplier = 1.8
	crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for crack_index in range(12):
		var angle := TAU * float(crack_index) / 12.0 + randf_range(-0.12, 0.12)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var perpendicular := Vector3(-direction.z, 0.0, direction.x)
		for section in range(5):
			var start_t := 0.08 + float(section) * 0.17
			var end_t := minf(0.96, start_t + 0.15)
			var start_point := direction * radius * start_t + perpendicular * randf_range(-0.16, 0.16)
			var end_point := direction * radius * end_t + perpendicular * randf_range(-0.16, 0.16)
			var start_width := lerpf(0.075, 0.025, start_t)
			var end_width := lerpf(0.075, 0.025, end_t)
			var start_left := start_point + perpendicular * start_width
			var start_right := start_point - perpendicular * start_width
			var end_left := end_point + perpendicular * end_width
			var end_right := end_point - perpendicular * end_width
			surface.add_vertex(start_left)
			surface.add_vertex(start_right)
			surface.add_vertex(end_left)
			surface.add_vertex(end_left)
			surface.add_vertex(start_right)
			surface.add_vertex(end_right)
	surface.set_material(crack_material)
	var cracks := MeshInstance3D.new()
	cracks.mesh = surface.commit()
	cracks.material_override = crack_material
	add_child(cracks)
	cracks.global_position = Vector3(center.x, 0.055, center.z)
	var fade_tween := create_tween()
	fade_tween.tween_property(crack_material, 'albedo_color:a', 0.0, duration)
	fade_tween.parallel().tween_property(crack_material, 'emission_energy_multiplier', 0.0, duration)
	fade_tween.tween_callback(cracks.queue_free)


func golden_blessing_fx(center: Vector3, team: int, caster: HeroUnit) -> void:
	play_sfx('fairy_ult', -4.0)
	var gold := Color(1.0, 0.78, 0.22)
	burst(center + Vector3(0.0, 1.0, 0.0), gold, 28)
	_activate_ring(Vector3(center.x, 0.22, center.z), gold, 0.85, Vector3.ONE * 0.35, Vector3(4.5, 1.0, 4.5), true, 0.9)
	if caster != null and is_instance_valid(caster):
		caster.spawn_ability_vfx(2, center)
	for hero in heroes:
		if hero.dead or hero.team != team:
			continue
		var hero_position: Vector3 = hero.global_position
		burst(hero_position + Vector3(0.0, 1.25, 0.0), gold, 18)
		_activate_ring(Vector3(hero_position.x, 0.24, hero_position.z), gold, 0.8, Vector3.ONE * 0.35, Vector3(2.8, 1.0, 2.8), true, 0.85)
		if caster != null and is_instance_valid(caster):
			caster.spawn_ability_vfx(2, hero_position)


func fear_pulse_fx(center: Vector3, radius: float, color: Color) -> void:
	burst(center + Vector3(0.0, 0.7, 0.0), color, 40)
	_activate_ring(Vector3(center.x, 0.28, center.z), color, 0.62, Vector3.ONE * 0.4, Vector3(radius, 1.0, radius), true, 0.9)
	_activate_ring(Vector3(center.x, 0.32, center.z), Color(1.0, 0.82, 0.55), 0.48, Vector3.ONE * 0.3, Vector3(radius * 0.72, 1.0, radius * 0.72), true, 0.75)


func stun_impact_fx(pos: Vector3, color: Color) -> void:
	burst(pos + Vector3(0.0, 0.9, 0.0), color, 20)
	_activate_ring(Vector3(pos.x, 0.3, pos.z), color, 0.36, Vector3.ONE * 0.45, Vector3.ONE * 2.0, true, 0.9)
	_activate_ring(Vector3(pos.x, 0.34, pos.z), Color(0.85, 1.0, 0.72), 0.3, Vector3.ONE * 0.25, Vector3.ONE * 1.3, true, 0.9)


func root_snare_fx(pos: Vector3, color: Color) -> void:
	burst(pos + Vector3(0.0, 0.35, 0.0), color, 28)
	_activate_ring(Vector3(pos.x, 0.28, pos.z), color, 0.65, Vector3.ONE * 0.35, Vector3(2.8, 1.0, 2.8), true, 0.85)
	var activated := 0
	for index in root_spike_pool.size():
		var entry: Dictionary = root_spike_pool[index]
		if bool(entry["busy"]):
			continue
		var angle := TAU * float(activated) / 6.0 + randf_range(-0.12, 0.12)
		var spike_radius := randf_range(0.85, 1.45)
		var spike_position := Vector3(pos.x + cos(angle) * spike_radius, 0.0, pos.z + sin(angle) * spike_radius)
		var spike_height := randf_range(0.8, 1.45)
		var spike := entry["node"] as MeshInstance3D
		var material := entry["material"] as StandardMaterial3D
		material.albedo_color = color
		material.emission = color.darkened(0.2)
		material.emission_energy_multiplier = 1.4
		spike.visible = true
		spike.scale = Vector3(1.0, 0.01, 1.0)
		spike.rotation.y = angle
		spike.global_position = spike_position
		entry["busy"] = true
		entry["elapsed"] = 0.0
		entry["duration"] = 0.95
		entry["position"] = spike_position
		entry["height"] = spike_height
		entry["color"] = color
		root_spike_pool[index] = entry
		activated += 1
		if activated >= 6:
			break


func damage_number(pos: Vector3, amount: float, _team: int, is_shell := false) -> void:
	var label := Label3D.new()
	label.font = UI_FONT
	label.text = str(int(round(amount)))
	label.font_size = 64
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.85, 0.9, 1.0) if is_shell else Color(1.0, 0.55, 0.45)
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.03, 0.08, 0.9)
	add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	var tween := create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector3(0.0, 1.1, 0.0), 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)


func heal_number(pos: Vector3, amount: float) -> void:
	var label := Label3D.new()
	label.font = UI_FONT
	label.text = "+" + str(int(round(amount)))
	label.font_size = 56
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.6, 1.0, 0.7)
	label.outline_size = 12
	label.outline_modulate = Color(0.03, 0.08, 0.05, 0.9)
	add_child(label)
	label.global_position = pos
	var tween := create_tween()
	tween.tween_property(label, "global_position", pos + Vector3(0.0, 1.0, 0.0), 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)


func shake(amount: float) -> void:
	shake_amount = maxf(shake_amount, amount)


func _setup_network_play() -> void:
	if remote_root == null:
		remote_root = Node3D.new()
		remote_root.name = "RemotePlayers"
		add_child(remote_root)
	if not NetworkManager.remote_player_joined.is_connected(_on_remote_player_joined):
		NetworkManager.remote_player_joined.connect(_on_remote_player_joined)
	if not NetworkManager.remote_player_state.is_connected(_on_remote_player_state):
		NetworkManager.remote_player_state.connect(_on_remote_player_state)
	if not NetworkManager.remote_player_left.is_connected(_on_remote_player_left):
		NetworkManager.remote_player_left.connect(_on_remote_player_left)
	if not NetworkManager.remote_attack_received.is_connected(_on_remote_attack_received):
		NetworkManager.remote_attack_received.connect(_on_remote_attack_received)
	if not NetworkManager.remote_damage_received.is_connected(_on_remote_damage_received):
		NetworkManager.remote_damage_received.connect(_on_remote_damage_received)
	if not NetworkManager.remote_death_received.is_connected(_on_remote_death_received):
		NetworkManager.remote_death_received.connect(_on_remote_death_received)
	if not NetworkManager.remote_respawn_received.is_connected(_on_remote_respawn_received):
		NetworkManager.remote_respawn_received.connect(_on_remote_respawn_received)
	if not NetworkManager.remote_heal_received.is_connected(_on_remote_heal_received):
		NetworkManager.remote_heal_received.connect(_on_remote_heal_received)
	if not NetworkManager.remote_stats_updated.is_connected(_on_remote_stats_updated):
		NetworkManager.remote_stats_updated.connect(_on_remote_stats_updated)
	if not NetworkManager.bot_state_updated.is_connected(_on_bot_state_updated):
		NetworkManager.bot_state_updated.connect(_on_bot_state_updated)
	if not NetworkManager.attack_denied.is_connected(_on_attack_denied):
		NetworkManager.attack_denied.connect(_on_attack_denied)
	if not NetworkManager.match_score_updated.is_connected(_on_match_score_updated):
		NetworkManager.match_score_updated.connect(_on_match_score_updated)
	if not NetworkManager.match_event_received.is_connected(_on_match_event_received):
		NetworkManager.match_event_received.connect(_on_match_event_received)
	if not NetworkManager.match_finished.is_connected(_on_network_match_finished):
		NetworkManager.match_finished.connect(_on_network_match_finished)
	if not NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.connect(_on_network_disconnected)
	if player != null and is_instance_valid(player):
		NetworkManager.register_local_player(player)
		NetworkManager.send_stats(player.max_health, player.health, player.attack_damage)
	var snapshot := NetworkManager.get_remote_snapshot()
	for player_id in snapshot.keys():
		_on_remote_player_joined(int(player_id), snapshot[player_id])
	if not NetworkManager.is_server_connected() and not NetworkManager.is_connecting():
		announce("Сетевой сервер недоступен — игра с ботами", Color(1.0, 0.72, 0.4), 3.0)


func _on_remote_player_joined(player_id: int, info: Dictionary) -> void:
	if not network_play or remote_root == null:
		return
	if player_id == NetworkManager.local_peer_id:
		return
	if remote_players.has(player_id):
		var existing = remote_players[player_id]
		if existing != null and is_instance_valid(existing):
			existing.update_info(info)
			if info.has("alive") and not bool(info.get("alive", true)):
				existing.apply_network_death()
			if bool(info.get("has_state", false)):
				var existing_position: Vector3 = info.get("position", existing.global_position)
				existing.apply_state(existing_position, float(info.get("rotation", 0.0)))
		return
	var remote = REMOTE_PLAYER_SCRIPT.new()
	if remote == null:
		return
	remote.name = "RemotePlayer_%d" % player_id
	remote_root.add_child(remote)
	remote.game = self
	remote.setup(player_id, info)
	remote_players[player_id] = remote


func _on_remote_player_state(player_id: int, position: Vector3, rotation_y: float) -> void:
	if not network_play:
		return
	var remote = remote_players.get(player_id)
	if remote == null or not is_instance_valid(remote):
		_on_remote_player_joined(player_id, {
			"id": player_id,
			"name": "Игрок %d" % player_id,
			"class": 0,
			"team": 0,
			"has_state": true,
			"position": position,
			"rotation": rotation_y,
		})
	else:
		remote.apply_state(position, rotation_y)


func _on_remote_player_left(player_id: int) -> void:
	var remote = remote_players.get(player_id)
	if remote != null and is_instance_valid(remote):
		remote.queue_free()
	remote_players.erase(player_id)


func _on_remote_attack_received(player_id: int, attack_type: String, _target_id: int) -> void:
	var remote = remote_players.get(player_id)
	if remote != null and is_instance_valid(remote):
		remote.play_attack(attack_type)


func _on_remote_damage_received(source_id: int, target_id: int, amount: float, skill: String) -> void:
	if source_id < 0:
		var source_bot = remote_players.get(source_id)
		if source_bot != null and is_instance_valid(source_bot):
			source_bot.play_attack(skill)
	var target_bot = network_bots.get(target_id)
	if target_bot != null and is_instance_valid(target_bot):
		target_bot.apply_network_damage(amount)
		return
	if target_id == NetworkManager.local_peer_id:
		if player != null and is_instance_valid(player):
			player.apply_network_damage(amount)
		return
	var remote = remote_players.get(target_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_network_damage(amount)


func _on_remote_death_received(player_id: int) -> void:
	if player_id == NetworkManager.local_peer_id:
		return
	var bot = network_bots.get(player_id)
	if bot != null and is_instance_valid(bot):
		bot.apply_network_damage(bot.health)
		return
	var remote = remote_players.get(player_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_network_death()


func _on_remote_respawn_received(player_id: int, position: Vector3, rotation_y: float) -> void:
	if player_id == NetworkManager.local_peer_id:
		return
	var remote = remote_players.get(player_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_network_respawn(position, rotation_y)


func _on_remote_heal_received(_source_id: int, target_id: int, amount: float) -> void:
	if target_id == NetworkManager.local_peer_id:
		if player != null and is_instance_valid(player):
			player.apply_network_heal(amount)
			NetworkManager.send_stats(player.max_health, player.health, player.attack_damage)
		return
	var remote = remote_players.get(target_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_network_heal(amount)


func _on_remote_stats_updated(player_id: int, max_hp: float, hp: float, attack_damage: float) -> void:
	var remote = remote_players.get(player_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_stats(max_hp, hp, attack_damage)


func _on_bot_state_updated(bot_id: int, info: Dictionary) -> void:
	if not network_play or network_host:
		return
	var remote = remote_players.get(bot_id)
	if remote == null or not is_instance_valid(remote):
		_on_remote_player_joined(bot_id, info)
		remote = remote_players.get(bot_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_bot_state(info)


func _on_attack_denied(target_id: int, skill: String, reason: String) -> void:
	print("[NET] attack_denied target=", target_id, " skill=", skill, " reason=", reason)


func _on_match_score_updated(score_0: int, score_1: int, server_sudden_death: bool) -> void:
	if not network_play:
		return
	score[0] = score_0
	score[1] = score_1
	if server_sudden_death and not sudden_death:
		sudden_death = true
		announce("Решающий осколок!", Color(1.0, 0.75, 0.35), 3.0)


func _on_match_event_received(event: String, _team: int) -> void:
	if not network_play:
		return
	if event == "sudden_death" and not sudden_death:
		sudden_death = true
		announce("Решающий осколок!", Color(1.0, 0.75, 0.35), 3.0)


func _on_network_match_finished(winning_team: int) -> void:
	if not network_play or state != "live":
		return
	end_match(winning_team == 0)


func _on_network_disconnected() -> void:
	if network_shutting_down or not network_play:
		return
	for remote in remote_players.values():
		if remote != null and is_instance_valid(remote):
			remote.queue_free()
	remote_players.clear()
	announce("Соединение с сервером потеряно", Color(1.0, 0.55, 0.4), 3.0)


func _exit_tree() -> void:
	if network_play:
		network_shutting_down = true
		NetworkManager.unregister_local_player()
		NetworkManager.clear_bots()
		NetworkManager.disconnect_from_server(false)
		var tree := get_tree()
		if tree != null:
			tree.set_meta("network_play", false)


func _unhandled_input(event: InputEvent) -> void:
	if state == "live" and player != null:
		if event is InputEventKey:
			if event.pressed and not event.echo:
				player.notify_player_input()
		elif event is InputEventMouseButton and event.pressed:
			player.notify_player_input()

	if event is InputEventMouseButton and event.pressed and (state == "live" or death_camera_active):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clampf(camera_distance - zoom_speed * 2.0, min_zoom_distance, max_zoom_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clampf(camera_distance + zoom_speed * 2.0, min_zoom_distance, max_zoom_distance)
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and not event.echo:
		var digit_index := _digit_index_from_event(event)
		if state == "select":
			if digit_index >= 0:
				start_match(digit_index)
		elif state == "live" and player != null:
			var ability_index := _ability_index_from_event(event)
			if ability_index >= 0:
				player.use_ability(ability_index)


func _digit_index_from_event(event: InputEventKey) -> int:
	var key_codes := [KEY_1, KEY_2, KEY_3]
	var numpad_codes := [KEY_KP_1, KEY_KP_2, KEY_KP_3]
	for index in range(3):
		if event.keycode == key_codes[index] or event.physical_keycode == key_codes[index]:
			return index
		if event.keycode == numpad_codes[index] or event.physical_keycode == numpad_codes[index]:
			return index
	return -1


func _ability_index_from_event(event: InputEventKey) -> int:
	var actions := ["ability_1", "ability_2", "ability_3"]
	var numpad_codes := [KEY_KP_1, KEY_KP_2, KEY_KP_3]
	for index in range(actions.size()):
		if event.is_action_pressed(actions[index]):
			return index
		if event.keycode == numpad_codes[index] or event.physical_keycode == numpad_codes[index]:
			return index
	return -1


func objective_text() -> String:
	if state == "select":
		return "Выбери класс — 1 Воин · 2 Маг · 3 Фея"
	if state == "over":
		return ""
	if crystal_state == "carried" and carrier != null and is_instance_valid(carrier):
		var who := "Ты несёшь осколок — на базу!" if carrier == player else "%s несёт осколок" % carrier.display_name
		return who
	if crystal_state == "ground":
		return "Осколок свободен — подбери его"
	match shell_phase:
		"warning":
			return "Оболочка пробуждается: %d" % int(ceil(shell_timer))
		"active":
			return "Разбей Оболочку: %d" % int(ceil(shell_window))
	return "Оболочка появится через %d" % int(ceil(shell_timer))


func debug_state() -> Dictionary:
	var info := {}
	info["state"] = state
	info["time"] = int(match_time)
	info["score"] = [score[0], score[1]]
	info["shell_phase"] = shell_phase
	info["shell_timer"] = int(ceil(shell_timer))
	info["shell_window"] = int(ceil(shell_window))
	info["crystal"] = crystal_state
	info["sudden_death"] = sudden_death
	var names: Array[String] = []
	for h in heroes:
		names.append("%s t%d hp%d%s" % [h.display_name, h.team, int(h.health), " C" if h.carrying else ""])
	info["heroes"] = names
	if shell != null and is_instance_valid(shell):
		info["shell_hp"] = int(shell.health)
	return info
