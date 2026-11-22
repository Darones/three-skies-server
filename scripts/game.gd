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
const TEST_STARTING_GOLD := 0
const ARENA_SAFE_HALF_X := 52.0
const ARENA_SAFE_HALF_Z := 37.0
const DEATH_CAM_HALF_X := 50.0
const DEATH_CAM_HALF_Z := 35.0
const DEATH_CAM_MIN_HEIGHT := 4.0
const DEATH_CAM_MAX_HEIGHT := 55.0
const VISIBILITY_COLLISION_MASK := 3
const VISIBILITY_REFRESH_INTERVAL := 0.2
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
const BOT_CALLSIGNS := [
	"Тёмный Лис", "Северный Ветер", "Тихий Шторм", "Искра", "Каменный Путь",
	"Звёздный След", "Сумрачный Клинок", "Белый Ворон", "Летний Дождь",
	"Холодный Рассвет", "Лунная Тень", "Стальной Волк", "Ветер Перемен",
	"Пепел", "Огненный Лис", "Ночная Птица",
]
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const CLOUD_WALL_SHADER: Shader = preload("res://shaders/cloud_wall.gdshader")
const FOG_OF_WAR_SHADER_PATH := "res://shaders/fog_of_war.gdshader"
const FOG_VIEW_RADIUS := 10.0
const SHOP_STALL_SCENE: PackedScene = preload("res://assets/shop_stall/3d_4f92fe433b084100af7a1d7f_1790958942025.glb")
const TUTORIAL_CONTROLLER_SCRIPT: Script = preload("res://scripts/tutorial_controller.gd")
const REMOTE_PLAYER_SCRIPT: Script = preload("res://scripts/remote_player.gd")
const SHOP_ITEMS := [
	{"id": "life_amulet", "name": "Амулет Жизни", "effect": "+150 Max HP", "price": 500, "icon": 10},
	{"id": "revival_talisman", "name": "Талисман Возрождения", "effect": "+10 HP/сек реген", "price": 450, "icon": 2},
	{"id": "titan_shell", "name": "Панцирь Титана", "effect": "-15% входящего урона", "price": 450, "icon": 12},
	{"id": "power_glove", "name": "Перчатка Силы", "effect": "+25 к урону атаки", "price": 500, "icon": 0},
	{"id": "vampire_fang", "name": "Клык Вампира", "effect": "15% вампиризма", "price": 500, "icon": 4},
	{"id": "agility_mark", "name": "Знак Ловкости", "effect": "+20% скорости атаки", "price": 450, "icon": 15},
	{"id": "wind_boots", "name": "Сапоги Ветра", "effect": "+15% скорости бега", "price": 350, "icon": 11},
	{"id": "hourglass", "name": "Песочные Часы", "effect": "-15% КД скиллов", "price": 450, "icon": 6},
	{"id": "cleansing_charm", "name": "Оберег Очищения", "effect": "-20% времени станов", "price": 350, "icon": 3},
]

const SHOP_ITEM_TEXTURES := {
	"life_amulet": preload("res://assets/ui/shop/life_amulet.webp"),
	"revival_talisman": preload("res://assets/ui/shop/revival_talisman.webp"),
	"titan_shell": preload("res://assets/ui/shop/titan_shell.webp"),
	"power_glove": preload("res://assets/ui/shop/power_glove.webp"),
	"vampire_fang": preload("res://assets/ui/shop/vampire_fang.webp"),
	"agility_mark": preload("res://assets/ui/shop/agility_mark.webp"),
	"wind_boots": preload("res://assets/ui/shop/wind_boots.webp"),
	"hourglass": preload("res://assets/ui/shop/hourglass.webp"),
	"cleansing_charm": preload("res://assets/ui/shop/cleansing_charm.webp"),
}
const MUSIC_PATH := "res://audio/music/dread/6adcd384-a1c6-4d03-ab8f-2885c6220fd5_music_dark_fantasy_arena_battle_them__1793744175999.mp3"
const AMBIENT_PATH := "res://audio/ambient/arena_wind.mp3"
const SFX_PATHS := {
	"fairy_ult": "res://audio/sfx/fairy_blessing_free/sfx_magical_fairy_chime_bell_brig_.mp3",
	"hit": "res://audio/sfx/sword_hit.mp3",
	"magic": "res://audio/sfx/magic_burst.mp3",
	"thunder": "res://audio/sfx/shell_thunder.mp3",
	"coin_pickup": "res://audio/sfx/misc_coin_wallet.mp3",
	"shop_purchase": "res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/coins_1.mp3",
	"shard_pickup": "res://audio/sfx/misc_shard_pickup.mp3",
	"shard_delivery": "res://audio/sfx/misc_shard_delivery.mp3",
	"death": "res://audio/sfx/death_soft_thud.mp3",
	"death_scream": "res://audio/sfx/fairy_death_scream.mp3",
	"respawn": "res://assets/audio/Soundza_Game_SFX_Pack/jingles_stingers/level_up_chime.mp3",
	"shell_hit": "res://audio/sfx/misc_shell_hit.mp3",
	"shell_destroyed": "res://audio/sfx/misc_shell_destroyed.mp3",
	"match_start": "res://audio/sfx/misc_start_kenney_hit_15.ogg",
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
var carrier = null
var crystal_carrier_node: Node3D = null
var crystal_intent_timer := 0.0

var state := "select"
var match_started := false
var match_time := MATCH_LENGTH
var time_up_announced := false
var match_end_reason := ""
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
var gold_coin_mesh: CylinderMesh = null
var gold_coin_material: StandardMaterial3D = null
var shop_pending_item := ""
var shop_pending_timer := 0.0
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
var shell_stuck_timer := 0.0
var shell_hold_timer := 0.0
var shell_death_event_seen := false
var shell_spawn_id := 0
var shell_last_boundary := 0
var shell_audit := false
var sudden_death_shell_spawned := false
var shell_trace_timer := 0.0
var shell_echo_phase := ""
var shell_echo_alive := false
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
var projectile_mesh: SphereMesh
var projectile_bolt_mesh: BoxMesh
var shake_amount := 0.0
var earthquake_timer := 0.0
var earthquake_intensity := 0.0
var select_angle := 0.6
var camera_pos := Vector3.ZERO
var camera_distance := 16.0
var visibility_refresh_timer := 0.0
var net_debug_timer := 0.0
var shell_sync_timer := 0.0
var last_deny_msec := 0
var death_camera_active := false
var death_camera_last_distance := 16.0
var zoom_speed := 1.0
var min_zoom_distance := 12.0
var max_zoom_distance := 42.0

var music: AudioStreamPlayer
var ambient: AudioStreamPlayer
var sfx_streams := {}
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_index := 0
var _master_muted_before_blur := false
var _audio_muted_by_blur := false


func _ready() -> void:
	randomize()
	shell_audit = OS.get_cmdline_user_args().has("--shell-audit")
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
	camera_distance = DeviceProfile.camera_distance
	min_zoom_distance = DeviceProfile.min_zoom_distance
	max_zoom_distance = DeviceProfile.max_zoom_distance
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
		_soften_baked_base_rings()
	_create_base_shield_domes()
	_create_fog_of_war()
	_create_shop_stall()
	_create_gold_fountain()
	if arena_root != null:
		_create_ambient_decor(arena_root)
	_apply_mobile_quality()
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
	if DeviceProfile.mobile_ui:
		await _warm_battle_world()
	if get_tree().has_meta("selected_class"):
		var selected_class := int(get_tree().get_meta("selected_class"))
		if selected_class >= 0 and selected_class <= 2:
			var selected_team := clampi(int(get_tree().get_meta("selected_team", get_meta("selected_team", 0))), 0, 1)
			call_deferred("start_match", selected_class, selected_team)
	if network_play:
		_setup_network_play()
	if OS.get_cmdline_user_args().has("--shop-preview"):
		hud.call("set_shop_open", true)


func _warm_battle_world() -> void:
	# Render the real arena through a tiny SubViewport sharing the battle
	# World3D. This compiles the arena materials and uploads their textures
	# before the player reaches the center, so the first clash does not hitch.
	var warm_viewport := SubViewport.new()
	warm_viewport.name = "BattleWarmupViewport"
	warm_viewport.size = Vector2i(160, 160)
	warm_viewport.own_world_3d = false
	warm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(warm_viewport)
	var warm_camera := Camera3D.new()
	warm_camera.fov = 70.0
	warm_camera.near = 0.1
	warm_camera.far = 250.0
	warm_camera.position = Vector3(0.0, 70.0, 10.0)
	warm_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	warm_viewport.add_child(warm_camera)
	warm_camera.current = true
	for _frame in 3:
		await get_tree().process_frame
	if is_instance_valid(warm_viewport):
		warm_viewport.queue_free()
	await get_tree().process_frame


func _warm_combat_world() -> void:
	# Render the freshly spawned heroes (weapons, nameplates, particles) and
	# every combat VFX scene once in the real World3D. The warm camera is
	# tiny and off-screen, so only the shader cache is affected.
	var warm_viewport := SubViewport.new()
	warm_viewport.name = "CombatWarmupViewport"
	warm_viewport.size = Vector2i(192, 192)
	warm_viewport.own_world_3d = false
	warm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(warm_viewport)
	var warm_camera := Camera3D.new()
	warm_camera.fov = 78.0
	warm_camera.near = 0.1
	warm_camera.far = 250.0
	warm_camera.position = Vector3(0.0, 48.0, 0.1)
	warm_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	warm_viewport.add_child(warm_camera)
	warm_camera.current = true
	for _frame in 3:
		await get_tree().process_frame
	warm_camera.position = Vector3(0.0, -94.0, 8.0)
	warm_camera.look_at(Vector3(0.0, -100.0, 0.0), Vector3.UP)
	var vfx_paths := [
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_01.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_02.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_02.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_01.tscn",
		"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_02.tscn",
	]
	for path in vfx_paths:
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var effect := packed.instantiate() as Node3D
		if effect == null:
			continue
		add_child(effect)
		effect.global_position = Vector3(0.0, -100.0, 0.0)
		effect.visible = true
		for _frame in 2:
			await get_tree().process_frame
		effect.queue_free()
		await get_tree().process_frame
	if is_instance_valid(warm_viewport):
		warm_viewport.queue_free()
	await get_tree().process_frame


func _warm_first_clash_vfx() -> void:
	# One main-world render of the cheap hit scene used by all mobile bot and
	# auto attacks. The class-select panel still covers the screen here, so
	# its one-time shader compile is hidden instead of freezing the clash.
	var warm_viewport := SubViewport.new()
	warm_viewport.name = "FirstClashWarmup"
	warm_viewport.size = Vector2i(128, 128)
	warm_viewport.own_world_3d = false
	warm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(warm_viewport)
	var warm_camera := Camera3D.new()
	warm_camera.fov = 60.0
	warm_camera.near = 0.1
	warm_camera.far = 50.0
	warm_camera.position = Vector3(0.0, -94.0, 8.0)
	warm_camera.look_at(Vector3(0.0, -100.0, 0.0), Vector3.UP)
	warm_viewport.add_child(warm_camera)
	warm_camera.current = true
	var packed := load("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_01.tscn") as PackedScene
	if packed != null:
		var effect := packed.instantiate() as Node3D
		if effect != null:
			add_child(effect)
			effect.global_position = Vector3(0.0, -100.0, 0.0)
			effect.visible = true
			for _frame in 2:
				await get_tree().process_frame
			effect.queue_free()
	if is_instance_valid(warm_viewport):
		warm_viewport.queue_free()
	await get_tree().process_frame


func _apply_mobile_quality() -> void:
	if not DeviceProfile.mobile_ui:
		return
	if DeviceProfile.quality_override == "full":
		return
	var viewport := get_viewport()
	if viewport != null:
		# The phone renders the 3D scene below native resolution; the UI is
		# still sharp and the difference is invisible on a small screen.
		if DeviceProfile.quality_override != "noscale":
			viewport.scaling_3d_scale = 0.6
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	for node in find_children("*", "WorldEnvironment", true, false):
		var world_env := node as WorldEnvironment
		if world_env == null or world_env.environment == null:
			continue
		var env := world_env.environment
		env.glow_enabled = false
		env.fog_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.volumetric_fog_enabled = false
	for node in find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		sun.shadow_enabled = false
	for node in find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		light.shadow_enabled = false
		var light_name := String(light.name).to_lower()
		var parent_name := String(light.get_parent().name).to_lower() if light.get_parent() != null else ""
		var keep := light_name.contains("fountain") or light_name.contains("shop") or light_name.contains("altar") or light_name.contains("rim") or light_name.contains("halfglow") or parent_name.contains("base")
		if not keep:
			light.visible = false


func _soften_baked_base_rings() -> void:
	var base_configs := [
		{"name": "LightBase", "color": Color(0.55, 0.85, 1.0)},
		{"name": "DarkBase", "color": Color(0.68, 0.32, 1.0)},
	]
	for config in base_configs:
		var base := get_node_or_null("Arena/Bases/%s" % String(config["name"])) as Node3D
		if base == null:
			continue
		for child in base.get_children():
			if not child is MeshInstance3D:
				continue
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh is CylinderMesh:
				var cylinder := mesh_instance.mesh as CylinderMesh
				if cylinder.height < 0.5:
					var platform_material := StandardMaterial3D.new()
					var base_color: Color = config["color"]
					platform_material.albedo_color = Color(0.3, 0.32, 0.36).lerp(base_color, 0.15)
					platform_material.roughness = 0.9
					mesh_instance.material_override = platform_material
				else:
					mesh_instance.queue_free()
			elif mesh_instance.mesh is PrismMesh:
				mesh_instance.queue_free()
			elif mesh_instance.mesh is TorusMesh and mesh_instance.name != "TeamRing":
				mesh_instance.queue_free()
	# Центральный алтарь: опускаем диск, чтобы кольцо кристалла не пересекалось с полом.
	var altar_disc := get_node_or_null("Arena/Altar/AltarDisc") as MeshInstance3D
	if altar_disc != null:
		altar_disc.position.y -= 0.15


func _create_base_shield_domes() -> void:
	var shield_configs := [
		{"path": "Arena/Bases/LightBase", "color": Color(0.42, 0.72, 1.0, 0.012)},
		{"path": "Arena/Bases/DarkBase", "color": Color(0.72, 0.46, 0.92, 0.012)},
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
		material.rim_enabled = true
		material.rim = 0.25
		material.rim_tint = 0.35
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
	cloud_material.set_shader_parameter("cloud_tint", Color(0.78, 0.9, 0.97, 0.18))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segment_count := 72
	var ring_radius_x := 60.0
	var ring_radius_z := 44.0
	var wall_bottom := -16.0
	var wall_top := 4.0
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
	shop.position = SHOP_INTERACTION_POINT
	shop.rotation_degrees.y = 90.0
	parent.add_child(shop)

	var stall_model := SHOP_STALL_SCENE.instantiate() as Node3D
	stall_model.name = "MarketStallModel"
	shop.add_child(stall_model)
	var model_bounds := _model_aabb_local(stall_model)
	var model_scale := 4.0 / maxf(model_bounds.size.y, 0.01)
	stall_model.scale = Vector3.ONE * model_scale
	stall_model.position.y = -model_bounds.position.y * model_scale
	_disable_mesh_shadows(stall_model)
	_add_box_collision(shop, Vector3(4.6, 3.4, 3.6), "ShopCollision")
	var shop_obstacle := NavigationObstacle3D.new()
	shop_obstacle.name = "ShopNavObstacle"
	shop_obstacle.radius = 3.6
	shop_obstacle.height = 3.2
	shop.add_child(shop_obstacle)

	var sign := MeshInstance3D.new()
	sign.name = "ShopSign"
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(3.6, 0.82, 0.14)
	sign.mesh = sign_mesh
	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = Color(0.18, 0.085, 0.045)
	sign_material.roughness = 0.9
	sign.material_override = sign_material
	sign.position = Vector3(0.0, 3.0, 2.25)
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shop.add_child(sign)
	var title := Label3D.new()
	title.name = "ShopTitle"
	title.font = UI_FONT
	title.text = "МАГАЗИН"
	title.position = Vector3(0.0, 3.0, 2.34)
	title.font_size = 80
	title.pixel_size = 0.006
	title.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	title.modulate = Color(1.0, 0.82, 0.48)
	title.outline_size = 9
	title.outline_modulate = Color(0.045, 0.03, 0.02, 0.95)
	title.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shop.add_child(title)

	_add_kaykit_prop(shop, ArenaKit.KAYKIT_CRATES_SCENE, Vector3(-2.6, 0.0, -1.5), 0.7, 18.0)
	_add_kaykit_prop(shop, ArenaKit.KAYKIT_CRATES_SCENE, Vector3(2.7, 0.0, -1.3), 0.55, -24.0)
	_add_kaykit_prop(shop, ArenaKit.KAYKIT_BARREL_SCENE, Vector3(2.5, 0.0, 1.4), 0.65, 0.0)
	_add_kaykit_prop(shop, ArenaKit.KAYKIT_WOOD_LOGS_SCENE, Vector3(-2.8, 0.0, 1.5), 0.75, 90.0)
	_add_kaykit_prop(shop, ArenaKit.KAYKIT_TEXTILES_SCENE, Vector3(0.0, 0.6, -1.9), 0.9, 0.0)
	_add_kaykit_prop(shop, ArenaKit.KAYKIT_POT_SCENE, Vector3(2.9, 0.0, 0.3), 0.65, 0.0)

	var light := OmniLight3D.new()
	light.name = "ShopWarmLight"
	light.light_color = Color(1.0, 0.78, 0.46)
	light.light_energy = 1.4
	light.omni_range = 9.0
	light.position = Vector3(0.0, 3.0, 0.0)
	shop.add_child(light)


func _disable_mesh_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_mesh_shadows(child)

func _add_box_collision(parent: Node3D, size: Vector3, collision_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = collision_name
	body.collision_layer = 1
	body.collision_mask = 1
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision_shape.shape = box
	collision_shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(collision_shape)
	parent.add_child(body)


func _model_aabb_local(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var inverse := root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).mesh != null:
			var mesh_instance := current as MeshInstance3D
			var box := inverse * mesh_instance.global_transform * mesh_instance.get_aabb()
			result = box if not found else result.merge(box)
			found = true
		for child in current.get_children():
			stack.append(child)
	return result


func _add_kaykit_prop(parent: Node3D, scene: PackedScene, pos: Vector3, scale_factor: float, rot_y: float) -> Node3D:
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	node.position = pos
	node.rotation_degrees.y = rot_y
	node.scale = Vector3.ONE * scale_factor
	parent.add_child(node)
	_disable_mesh_shadows(node)
	return node


func _create_ambient_decor(arena_root: Node3D) -> void:
	if arena_root.get_node_or_null("AmbientDecor") != null:
		return
	var decor := Node3D.new()
	decor.name = "AmbientDecor"
	arena_root.add_child(decor)
	_create_fireflies(decor, Vector3(37.0, 0.0, 0.0), 5.0, Color(1.0, 0.85, 0.45))
	_create_fireflies(decor, Vector3(0.0, 0.0, 0.0), 4.5, Color(0.55, 0.85, 1.0))
	_create_fireflies(decor, Vector3(0.0, 0.0, 10.0), 3.5, Color(0.5, 0.8, 1.0))
	_create_fireflies(decor, Vector3(0.0, 0.0, -10.0), 3.5, Color(0.75, 0.55, 1.0))
	_create_fireflies(decor, Vector3(-24.0, 0.0, 12.0), 3.0, Color(1.0, 0.8, 0.4))
	_create_fireflies(decor, Vector3(24.0, 0.0, -12.0), 3.0, Color(0.7, 0.6, 1.0))


func _create_fireflies(parent: Node3D, position: Vector3, radius: float, color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Fireflies"
	particles.amount = 20
	particles.lifetime = 6.0
	particles.preprocess = 4.0
	particles.position = position + Vector3(0.0, 1.6, 0.0)
	particles.visibility_aabb = AABB(Vector3(-radius, -2.0, -radius), Vector3(radius * 2.0, 4.0, radius * 2.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.gravity = Vector3(0.0, 0.02, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	particles.process_material = process
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = StandardMaterial3D.new()
	var dot_material := dot.material as StandardMaterial3D
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.albedo_color = color
	dot_material.emission_enabled = true
	dot_material.emission = color
	dot_material.emission_energy_multiplier = 2.0
	particles.draw_pass_1 = dot
	parent.add_child(particles)


func _create_gold_fountain() -> void:
	var parent := get_node_or_null("Arena/Decor") as Node3D
	if parent == null:
		parent = get_node_or_null("Arena") as Node3D
	if parent == null or parent.get_node_or_null("GoldFountain") != null:
		return

	gold_fountain = Node3D.new()
	gold_fountain.name = "GoldFountain"
	gold_fountain.position = Vector3(37.0, 0.0, 0.0)
	parent.add_child(gold_fountain)

	var well_model := ArenaKit.KAYKIT_WELL_SCENE.instantiate() as Node3D
	if well_model != null:
		well_model.name = "StoneFountainModel"
		gold_fountain.add_child(well_model)
		var well_bounds := _model_aabb_local(well_model)
		var well_scale := 4.2 / maxf(well_bounds.size.y, 0.01)
		well_model.scale = Vector3.ONE * well_scale
		well_model.position.y = -well_bounds.position.y * well_scale
		_disable_mesh_shadows(well_model)
	else:
		_build_primitive_fountain(gold_fountain)
	_add_box_collision(gold_fountain, Vector3(3.4, 3.0, 3.4), "FountainCollision")
	var fountain_obstacle := NavigationObstacle3D.new()
	fountain_obstacle.name = "FountainNavObstacle"
	fountain_obstacle.radius = 3.2
	fountain_obstacle.height = 3.0
	gold_fountain.add_child(fountain_obstacle)

	_add_kaykit_prop(gold_fountain, ArenaKit.KAYKIT_GOLD_BARS_SCENE, Vector3(-1.4, 0.1, 1.4), 1.3, 22.0)
	_add_kaykit_prop(gold_fountain, ArenaKit.KAYKIT_GOLD_NUGGETS_SCENE, Vector3(1.5, 0.1, 1.2), 1.2, -18.0)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + 0.4
		_add_kaykit_prop(gold_fountain, ArenaKit.KAYKIT_COIN_STACK_SCENE, Vector3(cos(angle) * 2.0, 0.1, sin(angle) * 2.0), 1.2, float(i) * 33.0)

	var fountain_light := OmniLight3D.new()
	fountain_light.name = "FountainGoldLight"
	fountain_light.light_color = Color(1.0, 0.78, 0.35)
	fountain_light.light_energy = 1.6
	fountain_light.omni_range = 8.0
	fountain_light.position = Vector3(0.0, 1.6, 0.0)
	gold_fountain.add_child(fountain_light)
	var fountain_glow := FxUtils.soft_ground_glow(6.0, Color(1.0, 0.82, 0.35, 0.35), 0.0, 0.2)
	fountain_glow.name = "FountainGlow"
	fountain_glow.position = Vector3(0.0, 0.2, 0.0)
	gold_fountain.add_child(fountain_glow)

	var title := Label3D.new()
	title.name = "FountainTitle"
	title.font = UI_FONT
	title.text = "ФОНТАН"
	title.position = Vector3(0.0, 4.9, 0.0)
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
	if gold_coin_mesh == null:
		gold_coin_mesh = CylinderMesh.new()
		gold_coin_mesh.top_radius = 0.22
		gold_coin_mesh.bottom_radius = 0.22
		gold_coin_mesh.height = 0.075
		gold_coin_mesh.radial_segments = 12
	if gold_coin_material == null:
		gold_coin_material = StandardMaterial3D.new()
		gold_coin_material.albedo_color = Color(1.0, 0.68, 0.12)
		gold_coin_material.metallic = 0.78
		gold_coin_material.roughness = 0.22
		gold_coin_material.emission_enabled = true
		gold_coin_material.emission = Color(1.0, 0.48, 0.04)
		gold_coin_material.emission_energy_multiplier = 0.8
	coin.mesh = gold_coin_mesh
	coin.material_override = gold_coin_material
	add_child(coin)
	var coin_angle := randf_range(0.0, TAU)
	var coin_radius := randf_range(0.35, 1.0) if tutorial_spawn else GOLD_COIN_SPAWN_BASE_RADIUS + randf_range(0.0, GOLD_COIN_SPAWN_EXTRA_RADIUS)
	var coin_center: Vector3 = player.global_position if tutorial_spawn and player != null else gold_fountain.global_position
	var spawn_position := coin_center + Vector3(cos(coin_angle) * coin_radius, 0.45, sin(coin_angle) * coin_radius)
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
			var coin_value := int(coin.get_meta("gold_value", 1))
			if collector.is_player:
				play_sfx("coin_pickup", -10.0)
				award_gold(coin_value)
				if network_play and NetworkManager.server_protocol >= 4:
					NetworkManager.send_coin_pickup(coin_value)
				if tutorial_mode and tutorial_controller != null:
					tutorial_controller.call("on_coin_collected")
			else:
				collector.bot_gold += coin_value


func spawn_tutorial_coin(gold_value: int) -> void:
	if not tutorial_mode or gold_fountain == null or not is_instance_valid(gold_fountain):
		return
	# Tutorial coins must appear around the player, not on the fountain
	# platform: the fountain has collision and the stage could soft-lock.
	_spawn_gold_coin(gold_value, true)


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
		# The battle theme is 72 s. Without loop it ended before the match
		# started and the arena was silent. Loop it and restart on live.
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		music.stream = stream
		music.volume_db = -8.0
		add_child(music)
		music.play()
	ambient = AudioStreamPlayer.new()
	ambient.name = "Ambient"
	var ambient_stream := load(AMBIENT_PATH) as AudioStream
	if ambient_stream != null:
		if ambient_stream is AudioStreamMP3:
			(ambient_stream as AudioStreamMP3).loop = true
		elif ambient_stream is AudioStreamWAV:
			var wav_stream := ambient_stream as AudioStreamWAV
			wav_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav_stream.loop_begin = 0
			wav_stream.loop_end = int(wav_stream.get_length() * float(wav_stream.mix_rate))
		ambient.stream = ambient_stream
		ambient.volume_db = -18.0
		add_child(ambient)
		ambient.play()
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


func _notification(what: int) -> void:
	# A VK mini app can be hidden without unloading the page: the iframe keeps
	# running and the arena wind/music keeps sounding behind the feed. Mute the
	# whole master bus while the app has no focus and restore it on return.
	if not is_inside_tree():
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_mute_master_for_blur()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_restore_master_audio()


func _mute_master_for_blur() -> void:
	if _audio_muted_by_blur:
		return
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	_master_muted_before_blur = AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, true)
	_audio_muted_by_blur = true


func _restore_master_audio() -> void:
	if not _audio_muted_by_blur:
		return
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, _master_muted_before_blur)
	_audio_muted_by_blur = false


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
		var ring := FxUtils.soft_ground_glow(1.0, Color.WHITE, 0.75, 0.7, 0.35)
		ring.name = "PooledRing%d" % index
		ring.visible = false
		add_child(ring)
		var material := ring.material_override as ShaderMaterial
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

	projectile_mesh = SphereMesh.new()
	projectile_mesh.radius = 0.18
	projectile_mesh.height = 0.36
	projectile_mesh.radial_segments = 6
	projectile_mesh.rings = 3
	projectile_bolt_mesh = BoxMesh.new()
	projectile_bolt_mesh.size = Vector3(0.07, 0.07, 0.55)
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
		var material := entry["material"] as ShaderMaterial
		var start_scale: Vector3 = entry["start_scale"]
		var target_scale: Vector3 = entry["target_scale"]
		ring.scale = start_scale.lerp(target_scale, progress)
		if bool(entry["fade"]) and material != null:
			material.set_shader_parameter("intensity", float(entry["alpha"]) * (1.0 - progress))
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
		var material := entry["material"] as ShaderMaterial
		var tint := color
		tint.a = alpha
		if material != null:
			material.set_shader_parameter("glow_color", tint)
			material.set_shader_parameter("intensity", alpha)
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


func lightning_strike_fx(target: Vector3, bolt_color := Color(0.55, 0.85, 1.0)) -> void:
	var root := Node3D.new()
	root.name = "LightningStrike"
	add_child(root)
	# One mesh/material set per strike instead of one per segment: the old code
	# created ~27 meshes and materials each cast, which froze the mage storm.
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 1.0
	core_mesh.bottom_radius = 1.0
	core_mesh.height = 1.0
	core_mesh.radial_segments = 4
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = bolt_color
	core_material.emission_enabled = true
	core_material.emission = bolt_color
	core_material.emission_energy_multiplier = 5.5
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_material.no_depth_test = true
	var halo_mesh := CylinderMesh.new()
	halo_mesh.top_radius = 1.0
	halo_mesh.bottom_radius = 1.0
	halo_mesh.height = 1.0
	halo_mesh.radial_segments = 4
	var halo_material := StandardMaterial3D.new()
	halo_material.albedo_color = Color(bolt_color.r, bolt_color.g, bolt_color.b, 0.22)
	halo_material.emission_enabled = true
	halo_material.emission = bolt_color
	halo_material.emission_energy_multiplier = 2.0
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.no_depth_test = true
	var start := target + Vector3(randf_range(-1.2, 1.2), 15.0, randf_range(-1.2, 1.2))
	var current := start
	var segments := 11
	for i in range(segments):
		var t := float(i + 1) / float(segments)
		var next := start.lerp(target, t) + Vector3(randf_range(-0.8, 0.8), 0.0, randf_range(-0.8, 0.8)) * (1.0 - t * 0.65)
		if i == segments - 1:
			next = target
		_add_lightning_segment(root, current, next, core_mesh, core_material, halo_mesh, halo_material, 0.05)
		if i == 4 or i == 7:
			var branch_end := current + Vector3(randf_range(-1.6, 1.6), -randf_range(0.8, 1.8), randf_range(-1.6, 1.6))
			_add_lightning_segment(root, current, branch_end, core_mesh, core_material, halo_mesh, halo_material, 0.032)
		current = next
	var flash := OmniLight3D.new()
	flash.light_color = bolt_color
	flash.light_energy = 7.0
	flash.omni_range = 11.0
	flash.position = target + Vector3(0.0, 1.4, 0.0)
	root.add_child(flash)
	var flash_tween := create_tween()
	flash_tween.tween_property(flash, "light_energy", 0.0, 0.35)
	var flash_sphere := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	flash_sphere.mesh = sphere
	var flash_material := StandardMaterial3D.new()
	flash_material.albedo_color = Color(bolt_color.r, bolt_color.g, bolt_color.b, 0.75)
	flash_material.emission_enabled = true
	flash_material.emission = bolt_color
	flash_material.emission_energy_multiplier = 4.5
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.no_depth_test = true
	flash_sphere.material_override = flash_material
	flash_sphere.position = target + Vector3(0.0, 0.7, 0.0)
	root.add_child(flash_sphere)
	var sphere_tween := create_tween()
	sphere_tween.tween_property(flash_sphere, "scale", Vector3.ONE * 2.4, 0.28)
	sphere_tween.parallel().tween_property(flash_material, "albedo_color", Color(bolt_color.r, bolt_color.g, bolt_color.b, 0.0), 0.28)
	burst(target + Vector3(0.0, 0.5, 0.0), bolt_color, 22)
	_activate_ring(Vector3(target.x, 0.22, target.z), bolt_color, 0.38, Vector3.ONE * 0.35, Vector3.ONE * 3.2, true, 0.85)
	get_tree().create_timer(0.45).timeout.connect(root.queue_free)


func _add_lightning_segment(parent: Node3D, from: Vector3, to: Vector3, core_mesh: Mesh, core_material: Material, halo_mesh: Mesh, halo_material: Material, thickness: float) -> void:
	var diff := to - from
	var length := diff.length()
	if length < 0.001:
		return
	var y_axis := diff.normalized()
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.01:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var center := (from + to) * 0.5
	var seg := MeshInstance3D.new()
	seg.mesh = core_mesh
	seg.material_override = core_material
	seg.transform = Transform3D(Basis(x_axis * thickness, y_axis * length, z_axis * thickness), center)
	parent.add_child(seg)
	var halo := MeshInstance3D.new()
	halo.mesh = halo_mesh
	halo.material_override = halo_material
	var halo_radius := thickness * 3.4
	halo.transform = Transform3D(Basis(x_axis * halo_radius, y_axis * length, z_axis * halo_radius), center)
	parent.add_child(halo)


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


func play_sfx(key: String, volume_db := -4.0, pitch := 1.0) -> void:
	if not sfx_streams.has(key) or sfx_players.is_empty():
		return
	var profiler_start := Time.get_ticks_usec() if CombatProfiler.enabled else 0
	for offset in range(sfx_players.size()):
		var index := (sfx_index + offset) % sfx_players.size()
		var player := sfx_players[index]
		if player.is_playing():
			continue
		player.stream = sfx_streams[key]
		player.volume_db = volume_db
		player.pitch_scale = pitch
		player.play()
		if CombatProfiler.enabled:
			CombatProfiler.mark("sfx", "%s %.1fms" % [key, (Time.get_ticks_usec() - profiler_start) / 1000.0])
		sfx_index = (index + 1) % sfx_players.size()
		return


func start_match(player_class: int, requested_team: int = -1) -> void:
	if state != "select" or match_started:
		return
	match_started = true
	state = "starting"
	Stats.track("match_start", {
		"class": ["warrior", "mage", "fairy"][clampi(player_class, 0, 2)],
		"network": network_play,
	})
	p_kills = 0
	p_deaths = 0
	p_damage = 0.0
	p_crystals = 0
	p_shells_destroyed = 0
	match_end_reason = ""
	time_up_announced = false
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
	if tutorial_mode:
		spawn_tutorial_dummy()
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
	if DeviceProfile.mobile_ui:
		await _warm_first_clash_vfx()
	state = "live"
	if network_play:
		_setup_network_play()
	if music != null and is_instance_valid(music):
		# Start the battle loop from the beginning, not from the class-select
		# time; otherwise a long lobby eats most of the track.
		music.play()
	match_time = MATCH_LENGTH
	shell_phase = "idle"
	shell_last_boundary = 0
	shell_cycle_timer = SHELL_SPAWN_INTERVAL
	shell_timer = SHELL_SPAWN_INTERVAL
	shell_hold_timer = 0.0
	shell_death_event_seen = false
	shell_trace_timer = 0.0
	shell_echo_phase = ""
	shell_echo_alive = false
	sudden_death_shell_spawned = false
	if not tutorial_mode:
		play_sfx("match_start", -4.0)
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
		if bot_name.is_empty() or bot_name.begins_with("Игрок"):
			bot_name = _next_bot_callsign()
		if not bot_name.is_empty():
			bot.set_display_name(bot_name)
		network_bots[bot.network_id] = bot
		NetworkManager.register_bot(bot)


func _spawn_hero(cls: int, team: int, is_player: bool, pos: Vector3) -> HeroUnit:
	var h := HeroUnit.new()
	h.name = ("Player" if is_player else "%s_%d_%d" % [HeroUnit.CLASS_DATA[cls]["name"], team, heroes.size()])
	add_child(h)
	h.setup(self, cls, team, is_player)
	if is_player:
		var nickname := MetaProgression.player_nickname.strip_edges()
		if not nickname.is_empty():
			h.set_display_name(nickname)
	else:
		h.set_display_name(_next_bot_callsign())
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


func get_shop_item_texture(item_id: String) -> Texture2D:
	return SHOP_ITEM_TEXTURES.get(item_id, null) as Texture2D


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
	if bot == null or not is_instance_valid(bot):
		return false
	if bot.is_player and not bot.afk_active:
		return false
	var wallet := gold if bot.is_player else bot.bot_gold
	var purchased: Array = purchased_shop_items if bot.is_player else bot.bot_purchased_shop_items
	for item in SHOP_ITEMS:
		if String(item["id"]) not in purchased and wallet >= int(item["price"]):
			return true
	return false


func bot_shop_goal() -> Vector3:
	return clamp_to_arena(SHOP_INTERACTION_POINT + Vector3(3.0, 0.0, 0.0))


func purchase_bot_shop_item(bot: HeroUnit) -> bool:
	if state != "live" or bot == null or not is_instance_valid(bot) or bot.dead:
		return false
	if bot.is_player and not bot.afk_active:
		return false
	if not is_hero_near_shop(bot):
		return false
	for item in SHOP_ITEMS:
		var item_id := String(item["id"])
		var price := int(item["price"])
		if bot.is_player:
			if item_id in purchased_shop_items or gold < price:
				continue
			if buy_item(item_id, true):
				return true
		else:
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


func buy_item(item_id: String, from_afk := false) -> bool:
	if player == null or item_id in purchased_shop_items:
		return false
	if not shop_open and not from_afk:
		return false
	if from_afk and (state != "live" or not player.afk_active or not is_hero_near_shop(player)):
		return false
	if tutorial_mode and (tutorial_controller == null or not bool(tutorial_controller.call("can_buy_item", item_id))):
		return false
	for item in SHOP_ITEMS:
		if String(item["id"]) != item_id:
			continue
		var price := int(item["price"])
		if gold < price:
			return false
		if network_play and NetworkManager.server_protocol >= 4:
			# The server owns the match wallet and the purchase validation; the
			# item is applied only after shop_purchase confirms it.
			if not shop_pending_item.is_empty():
				return false
			shop_pending_item = item_id
			shop_pending_timer = 3.0
			NetworkManager.send_buy_item(item_id)
			return true
		if not player.apply_shop_item(item_id):
			return false
		gold -= price
		player.match_gold_spent += price
		purchased_shop_items.append(item_id)
		if hud != null:
			hud.update_gold()
			hud.update_shop()
		play_sfx("shop_purchase", -7.0)
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
	if network_play and network_host and NetworkManager.server_protocol >= 2 and state == "live":
		shell_sync_timer += delta
		if shell_sync_timer >= 0.1:
			shell_sync_timer = 0.0
			var shell_alive := shell != null and is_instance_valid(shell) and shell.alive
			var shell_pos := Vector3(0.0, 0.45, 0.0)
			if shell_alive:
				shell_pos = shell.global_position
			NetworkManager.send_shell_state(shell_alive, shell_pos.x, shell_pos.y, shell_pos.z, shell_phase, shell_timer, shell_spawn_id)
	if not shop_pending_item.is_empty() and state == "live":
		shop_pending_timer -= delta
		if shop_pending_timer <= 0.0:
			shop_pending_item = ""
			announce("Сервер не подтвердил покупку", Color(1.0, 0.62, 0.4), 1.8)
	if network_play and CombatProfiler.enabled and state == "live":
		net_debug_timer += delta
		if net_debug_timer >= 1.0:
			net_debug_timer = 0.0
			var parts: Array[String] = []
			if player != null and is_instance_valid(player):
				parts.append("L:%d hp=%.0f/%.0f sync=%.0f dead=%s" % [
					NetworkManager.local_peer_id, player.health, player.max_health,
					player.last_server_hp, str(player.dead)
				])
			for remote_id in remote_players.keys():
				var remote = remote_players[remote_id]
				if remote != null and is_instance_valid(remote):
					parts.append("R:%d hp=%.0f/%.0f dead=%s" % [
						int(remote_id), remote.health, remote.max_health, str(remote.dead)
					])
			if network_host:
				for bot_id in network_bots.keys():
					var bot = network_bots[bot_id]
					if bot != null and is_instance_valid(bot):
						parts.append("B:%d hp=%.0f/%.0f dead=%s" % [
							int(bot_id), bot.health, bot.max_health, str(bot.dead)
						])
			if shell != null and is_instance_valid(shell):
				parts.append("S hp=%.0f/%.0f alive=%s" % [
					shell.health, shell.max_health, str(shell.alive)
				])
			print("[HP] host=%s room=%d %s" % [str(network_host), network_room_id, " | ".join(parts)])

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
	if DeviceProfile.mobile_ui:
		# Full-arena transparent shader plane; one of the most expensive
		# overdraw passes on phone GPUs. Enemy visibility is scripted, so
		# skipping the visual fog does not change gameplay.
		return
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


func _clamp_death_camera(position: Vector3) -> Vector3:
	return Vector3(
		clampf(position.x, -DEATH_CAM_HALF_X, DEATH_CAM_HALF_X),
		clampf(position.y, DEATH_CAM_MIN_HEIGHT, DEATH_CAM_MAX_HEIGHT),
		clampf(position.z, -DEATH_CAM_HALF_Z, DEATH_CAM_HALF_Z)
	)


func _update_camera(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return

	if player.dead:
		if not death_camera_active:
			death_camera_active = true
			camera_pos = camera.global_position
			death_camera_last_distance = camera_distance
			var camera_hint := "Наблюдение: свайп — камера" if _uses_touch_controls() else "Наблюдение: WASD — камера, колесико — зум"
			announce(camera_hint, Color(0.82, 0.9, 1.0), 4.0)

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

		# камера наблюдателя не должна уезжать за арену
		camera_pos = _clamp_death_camera(camera.global_position)
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
			if _has_clear_vision(space_state, ally.global_position + Vector3(0.0, 1.15, 0.0), target_position, excluded_rids):
				seen_by_team = true
				break
		hero.set_occluded_from_player(not seen_by_team)


func _has_clear_vision(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, excluded_rids: Array[RID]) -> bool:
	var ignore: Array[RID] = excluded_rids.duplicate()
	for _attempt in 4:
		var ray := PhysicsRayQueryParameters3D.create(from, to, VISIBILITY_COLLISION_MASK, ignore)
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		var hit := space_state.intersect_ray(ray)
		if hit.is_empty():
			return true
		var collider := hit.get("collider") as Node
		if collider == null or not _is_small_vision_blocker(collider):
			return false
		ignore.append(collider.get_rid())
	return false


func _is_small_vision_blocker(node: Node) -> bool:
	var node_name := String(node.name)
	if node_name == "CrystalCollision" or node_name == "ShellNavBlocker":
		return true
	if node_name == "PillarCollision":
		# Columns in the centre and at the bases must not turn heroes
		# invisible; standing behind them gave free stealth.
		return true
	var parent := node.get_parent()
	return parent != null and String(parent.name) == "Decor"

func _update_shake(delta: float) -> void:
	shake_amount = maxf(0.0, shake_amount - delta * 2.2)
	if shake_amount > 0.01:
		camera.h_offset = randf_range(-1.0, 1.0) * shake_amount * 0.5
		camera.v_offset = randf_range(-1.0, 1.0) * shake_amount * 0.5
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _update_match(delta: float) -> void:
	if tutorial_mode:
		return
	if sudden_death:
		match_time = 0.0
	else:
		match_time = maxf(0.0, match_time - delta)
		if match_time <= 0.0:
			if network_play:
				# Сетевой матч завершает только сервер. Локальный таймер
				# может убежать вперёд из-за загрузки/реконнекта; если он
				# обрывал бой, игрок видел конец матча без причины.
				if not time_up_announced:
					time_up_announced = true
					announce("Время вышло — ждём результат сервера", Color(1.0, 0.75, 0.35), 3.0)
			elif score[0] == score[1]:
				sudden_death = true
				announce("Решающий осколок!", Color(1.0, 0.75, 0.35), 3.0)
			else:
				match_end_reason = "Время вышло"
				end_match(score[0] > score[1])
				return

	if network_play and not network_host and NetworkManager.server_protocol >= 2:
		# The host simulates the shell; the guest only renders the server
		# state. No local spawn, timer or shell AI on the guest.
		pass
	else:
		if sudden_death:
			# A tie at 10:00 must be decided by a shard, not by two silent
			# minutes and a coin flip. Spawn one decisive shell; the server
			# ends the match on the next delivery (handleCrystalDeliver).
			if not sudden_death_shell_spawned:
				sudden_death_shell_spawned = true
				if shell == null or not is_instance_valid(shell) or not shell.alive:
					_shell_log("sudden_death_spawn")
					_spawn_shell()
			return
		if shell_hold_timer > 0.0:
			# The server said "not alive". Wait for the shell_destroyed event:
			# a real death keeps the fixed 2/4/6/8 schedule; a refused spawn
			# waits for the next normal interval instead of an early 5 s shell.
			shell_hold_timer -= delta
			if shell_hold_timer <= 0.0 and not shell_death_event_seen:
				shell_cycle_timer = SHELL_SPAWN_INTERVAL
				shell_timer = shell_cycle_timer
		else:
			# The schedule is the server match clock, not the local scene
			# clock. On web the Game scene can load 30-90 s after match_start;
			# a free-running 120 s timer then spawned the first shell at 3:30
			# instead of 2:00, and the player never saw it.
			var elapsed := maxf(0.0, float(MATCH_LENGTH) - match_time)
			var boundary_index := floori(elapsed / float(SHELL_SPAWN_INTERVAL))
			var next_boundary := ceilf(maxf(elapsed, 0.001) / float(SHELL_SPAWN_INTERVAL)) * float(SHELL_SPAWN_INTERVAL)
			shell_cycle_timer = maxf(0.0, next_boundary - elapsed)
			shell_timer = shell_cycle_timer
			var since_boundary := elapsed - float(boundary_index) * float(SHELL_SPAWN_INTERVAL)
			if shell_audit:
				shell_trace_timer += delta
				if shell_trace_timer >= 5.0:
					shell_trace_timer = 0.0
					print("[SHELL-TRACE] t=%.1f phase=%s cycle=%.1f window=%.1f hold=%.1f last_boundary=%d boundary=%d since=%.1f crystal=%s shell=%s" % [
						elapsed, shell_phase, shell_cycle_timer, shell_window, shell_hold_timer,
						shell_last_boundary, boundary_index, since_boundary, crystal_state,
						"none" if shell == null or not is_instance_valid(shell) else ("alive" if shell.alive else "dead"),
					])
			if shell_phase == "idle" and boundary_index > shell_last_boundary and since_boundary < SHELL_WINDOW and match_time > 0.0:
				# The scene loaded after the boundary but the 45 s shell window
				# is still open: show the shell the player expected at 2/4/6/8.
				shell_last_boundary = boundary_index
				_spawn_shell()
			if shell_phase == "idle" and shell_cycle_timer <= SHELL_WARNING_TIME:
				shell_phase = "warning"
				announce("Оболочка пробуждается — 10 секунд!", Color(0.78, 0.6, 1.0), 2.4)
			if shell_phase == "warning":
				if boundary_index > shell_last_boundary:
					shell_last_boundary = boundary_index
					if match_time > 0.0:
						_spawn_shell()
					else:
						shell_phase = "idle"
			elif shell_phase == "active":
				shell_window -= delta
				if shell_window <= 0.0 and shell != null and is_instance_valid(shell) and shell.alive:
					shell.despawn()
					shell = null
					shell_phase = "idle"
					announce("Оболочка ушла в тень", Color(0.7, 0.7, 0.8), 1.6)
				if shell == null or not is_instance_valid(shell) or not shell.alive:
					# Safety net: a refused spawn or a missed destroy event must
					# not freeze the cycle in "active" forever.
					shell_stuck_timer += delta
					if shell_stuck_timer >= 3.0:
						shell_stuck_timer = 0.0
						shell_phase = "idle"
						shell_window = SHELL_WINDOW
						shell_last_boundary = boundary_index
						shell_cycle_timer = SHELL_SPAWN_INTERVAL
						shell_timer = shell_cycle_timer
				else:
					shell_stuck_timer = 0.0


func _shell_log(tag: String) -> void:
	if not shell_audit:
		return
	print("[SHELL-AUDIT] %s t=%.1f phase=%s cycle=%.1f hold=%.1f spawn_id=%d crystal=%s" % [
		tag, float(MATCH_LENGTH) - match_time, shell_phase, shell_cycle_timer,
		shell_hold_timer, shell_spawn_id, crystal_state,
	])


func _spawn_shell() -> void:
	if CombatProfiler.enabled:
		CombatProfiler.mark("shell", "spawn")
	shell_spawn_id += 1
	_shell_log("spawn")
	var s := shell_pool
	if s == null or not is_instance_valid(s):
		s = SkyShell.new()
		s.name = "Shell"
		add_child(s)
		s.setup(self)
		shell_pool = s
	if tutorial_mode:
		s.max_health = 1000.0
	var shell_y := 0.16 if tutorial_mode else 0.45
	s.activate(self, Vector3(0.0, shell_y, 0.0))
	shell = s
	shell_phase = "active"
	shell_window = SHELL_WINDOW
	shell_cycle_timer = SHELL_SPAWN_INTERVAL
	shell_timer = shell_cycle_timer
	shell_hold_timer = 0.0
	shell_death_event_seen = false
	announce("Оболочка здесь", Color(0.85, 0.62, 1.0), 2.6)
	play_sfx("thunder", -3.0)
	shake(0.6)
	burst(Vector3(0.0, shell_y + 1.2, 0.0), Color(0.8, 0.5, 1.0), 44)
	ring_fx(Vector3(0.0, shell_y + 0.05, 0.0), Color(0.8, 0.5, 1.0), 8.0)


func on_shell_died(s: SkyShell, source: Node = null) -> void:
	if s != shell:
		return
	_shell_log("died")
	if source == player and not tutorial_mode:
		p_shells_destroyed += 1
	if not tutorial_mode and source is HeroUnit:
		(source as HeroUnit).match_shells += 1
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
	play_sfx("shell_destroyed", -3.0)
	shake(0.8)
	if network_play and NetworkManager.server_protocol >= 3:
		# The server owns the crystal and broadcasts crystal_state.
		pass
	else:
		spawn_crystal(pos, true)
	if not network_play or NetworkManager.server_protocol < 3 or crystal_state == "none":
		# In server-owned mode the shard is created only when no other shard is
		# active. Do not promise a shard that the server did not create.
		announce("Оболочка пала! Осколок свободен", Color(0.8, 0.95, 1.0), 2.4)
	else:
		announce("Оболочка пала!", Color(0.8, 0.95, 1.0), 2.4)
	s.retire(0.5)
	shell = null
	shell_phase = "idle"
	if network_play and NetworkManager.server_protocol < 3:
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
		_set_carrier_state(carrier, false)
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
	var ring := FxUtils.soft_ground_glow(2.6, Color(0.7, 0.95, 1.0, 0.55), 0.35, 0.42)
	ring.name = "CrystalRing"
	ring.position.y = -0.6
	c.add_child(ring)
	var drop_position := Vector3.ZERO if spawn_on_pedestal else _find_crystal_drop_position(pos)
	c.global_position = Vector3(drop_position.x, 1.3, drop_position.z)
	ring.position.y = 0.02 - c.global_position.y
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
	if network_play and NetworkManager.server_protocol >= 3:
		_update_network_crystal(delta)
		return
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
			var altar_ring := crystal_node.get_node_or_null("CrystalRing") as MeshInstance3D
			if altar_ring != null:
				altar_ring.position = Vector3(0.0, 0.02 - crystal_node.global_position.y, 0.0)
				altar_ring.scale = Vector3.ONE
			crystal_timer = 0.0
			announce("Осколок вернулся к алтарю", Color(0.75, 0.9, 1.0), 1.8)
		if state == "live" and pickup_delay <= 0.0:
			_try_pickup()
	elif crystal_state == "carried" and carrier != null and is_instance_valid(carrier):
		crystal_node.global_position = carrier.global_position + Vector3(0.0, 2.9, 0.0)
		var carry_ring := crystal_node.get_node_or_null("CrystalRing") as MeshInstance3D
		if carry_ring != null:
			carry_ring.global_position = Vector3(carrier.global_position.x, 0.08, carrier.global_position.z)
			carry_ring.scale = Vector3(1.7, 1.0, 1.7)
		if not is_instance_valid(crystal_node):
			crystal_state = "none"
			carrier.carrying = false
			carrier = null
		crystal_node.rotation.y += delta * 2.4
		var base_z := BASE_POSITION_Z if carrier.team == 0 else -BASE_POSITION_Z
		if Vector2(carrier.global_position.x, carrier.global_position.z - base_z).length() < BASE_DELIVERY_RADIUS:
			_deliver(carrier)


func _update_network_crystal(delta: float) -> void:
	crystal_intent_timer = maxf(0.0, crystal_intent_timer - delta)
	if crystal_node == null or not is_instance_valid(crystal_node):
		return
	if crystal_state == "ground":
		crystal_timer += delta
		crystal_node.rotation.y += delta * 1.8
		crystal_node.position.y = 1.1 + sin(crystal_timer * 2.4) * 0.12
		if crystal_intent_timer > 0.0 or state != "live":
			return
		var crystal_pos := Vector2(crystal_node.global_position.x, crystal_node.global_position.z)
		if player != null and is_instance_valid(player) and not player.dead:
			if Vector2(player.global_position.x, player.global_position.z).distance_to(crystal_pos) <= CRYSTAL_PICKUP_RADIUS:
				NetworkManager.send_crystal_pickup()
				crystal_intent_timer = 0.6
				return
		if network_host:
			for bot_id in network_bots.keys():
				var bot = network_bots[bot_id]
				if bot == null or not is_instance_valid(bot) or bot.dead:
					continue
				if Vector2(bot.global_position.x, bot.global_position.z).distance_to(crystal_pos) <= CRYSTAL_PICKUP_RADIUS:
					NetworkManager.send_crystal_pickup(int(bot_id))
					crystal_intent_timer = 0.6
					return
	elif crystal_state == "carried" and crystal_carrier_node != null and is_instance_valid(crystal_carrier_node):
		crystal_node.global_position = crystal_carrier_node.global_position + Vector3(0.0, 2.9, 0.0)
		var carry_ring := crystal_node.get_node_or_null("CrystalRing") as MeshInstance3D
		if carry_ring != null:
			carry_ring.global_position = Vector3(crystal_carrier_node.global_position.x, 0.08, crystal_carrier_node.global_position.z)
			carry_ring.scale = Vector3(1.7, 1.0, 1.7)
		crystal_node.rotation.y += delta * 2.4
		if crystal_intent_timer > 0.0 or state != "live":
			return
		var source_id := _network_carrier_source_id()
		if source_id == 0:
			return
		var carrier_team := int(crystal_carrier_node.get("team"))
		var base_z := BASE_POSITION_Z if carrier_team == 0 else -BASE_POSITION_Z
		if Vector2(crystal_carrier_node.global_position.x, crystal_carrier_node.global_position.z - base_z).length() < BASE_DELIVERY_RADIUS:
			NetworkManager.send_crystal_deliver(source_id)
			crystal_intent_timer = 0.7


func _network_carrier_source_id() -> int:
	if crystal_carrier_node == null or not is_instance_valid(crystal_carrier_node):
		return 0
	if player != null and is_instance_valid(player) and crystal_carrier_node == player:
		return NetworkManager.local_peer_id
	if network_host and crystal_carrier_node is HeroUnit:
		var bot_id := int(crystal_carrier_node.get("network_id"))
		if bot_id < 0:
			return bot_id
	return 0


func _set_carrier_state(node: Node3D, value: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	var current = node.get("carrying")
	if current != null:
		node.set("carrying", value)


func _clear_network_carrier() -> void:
	if crystal_carrier_node != null and is_instance_valid(crystal_carrier_node):
		_set_carrier_state(crystal_carrier_node, false)
	crystal_carrier_node = null
	carrier = null


func _network_combatant(player_id: int) -> Node:
	if network_bots.has(player_id):
		return network_bots[player_id]
	if remote_players.has(player_id):
		return remote_players[player_id]
	return null


func _node_for_network_id(player_id: int) -> Node3D:
	if player_id == 0:
		return null
	if player_id == NetworkManager.local_peer_id:
		return player
	if network_bots.has(player_id):
		return network_bots[player_id] as Node3D
	if remote_players.has(player_id):
		return remote_players[player_id] as Node3D
	return null


func _on_crystal_state_received(state: Dictionary) -> void:
	if not network_play or NetworkManager.server_protocol < 3:
		return
	var state_name := String(state.get("state", "none"))
	var x := float(state.get("x", 0.0))
	var y := float(state.get("y", 0.5))
	var z := float(state.get("z", 0.0))
	var carrier_id := int(state.get("carrier_id", 0))
	var delivered_node := crystal_carrier_node
	var was_carried := crystal_state == "carried"
	_clear_network_carrier()
	if state_name == "none" or state_name == "delivered":
		crystal_state = "none"
		if was_carried and NetworkManager.server_protocol < 4:
			_legacy_award_delivery(delivered_node)
		if crystal_node != null and is_instance_valid(crystal_node):
			crystal_node.queue_free()
			crystal_node = null
		return
	if state_name == "ground":
		crystal_state = "ground"
		if crystal_node == null or not is_instance_valid(crystal_node):
			spawn_crystal(Vector3(x, y, z), true)
		crystal_node.global_position = Vector3(x, 1.3, z)
		crystal_timer = 0.0
		pickup_delay = 0.0
		return
	if state_name == "carried":
		var node := _node_for_network_id(carrier_id)
		# spawn_crystal() resets crystal_state to "ground" and clears the
		# carrier, so create the node first and only then bind the carrier.
		if crystal_node == null or not is_instance_valid(crystal_node):
			spawn_crystal(node.global_position if node != null else Vector3(x, y, z), true)
		crystal_state = "carried"
		crystal_carrier_node = node
		carrier = node
		if node != null:
			_set_carrier_state(node, true)
		crystal_node.global_position = (node.global_position if node != null else Vector3(x, y, z)) + Vector3(0.0, 2.9, 0.0)


func _legacy_award_delivery(node: Node3D) -> void:
	# Protocol 3 servers do not send the shard_delivered event; infer the
	# delivery from the crystal state transition instead.
	if node == null or not is_instance_valid(node):
		return
	var team := int(node.get("team"))
	var source_id := 0
	if node == player:
		source_id = NetworkManager.local_peer_id
	elif network_host and node is HeroUnit:
		var bot_id := int(node.get("network_id"))
		if bot_id < 0:
			source_id = bot_id
	_award_network_delivery(team, source_id)


func _award_network_delivery(team: int, source_id: int) -> void:
	# Gold is a local match reward; the server event says who delivered.
	if player == null or not is_instance_valid(player):
		return
	if team == player.team:
		if NetworkManager.server_protocol < 4:
			award_gold(100)
		else:
			gold_earned_this_match += 100
		play_sfx("shard_delivery", -5.0)
	if source_id == NetworkManager.local_peer_id:
		p_crystals += 1
	elif source_id < 0:
		var bot = _network_combatant(source_id)
		if bot != null and is_instance_valid(bot):
			bot.match_crystals += 1
			if network_host and bot is HeroUnit:
				bot.bot_gold += 100
	elif source_id > 0 and remote_players.has(source_id):
		var remote = remote_players[source_id]
		if remote != null and is_instance_valid(remote):
			remote.match_crystals += 1


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
		play_sfx("shard_pickup", -6.0)
		if best == player:
			announce("Осколок у тебя! Неси на базу", Color(0.75, 1.0, 0.85), 2.0)
		else:
			announce("%s несёт осколок %s" % [best.display_name, "к свету" if best.team == 0 else "во тьму"], Color(0.85, 0.85, 0.95), 1.6)


func _deliver(h: HeroUnit) -> void:
	if network_play and NetworkManager.server_protocol >= 3:
		return
	if tutorial_mode:
		h.carrying = false
		carrier = null
		crystal_state = "none"
		if crystal_node != null and is_instance_valid(crystal_node):
			burst(crystal_node.global_position, Color(0.7, 0.95, 1.0), 40)
			crystal_node.queue_free()
			crystal_node = null
		play_sfx("shard_delivery", -5.0)
		if tutorial_controller != null:
			tutorial_controller.call("on_delivery")
		return
	h.carrying = false
	h.match_crystals += 1
	# Начисляем очко сразу на клиенте: сервер подтвердит его, но не сможет
	# обнулить счёт, если ответ потеряется или задержится.
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
	play_sfx("shard_delivery", -5.0)
	var team_name := "Свет" if h.team == 0 else "Тьма"
	announce("Осколок на базе: %s  %d : %d" % [team_name, score[0], score[1]], Color(1.0, 0.9, 0.6), 2.6)
	if network_play:
		print("[SCORE] deliver team=", h.team, " ws=", NetworkManager.state, " assigned=", NetworkManager.assigned_team)
		NetworkManager.send_match_event("shard_delivered", h.team)
		shell_phase = "idle"
		# Счёт на клиенте — только отображение. Третье очко подтверждает
		# сервер через match_finished; локальный счёт не обрывает бой.
		if score[h.team] >= CRYSTALS_TO_WIN:
			announce("Осколки: %d : %d — ждём подтверждение сервера" % [score[0], score[1]], Color(1.0, 0.9, 0.6), 2.0)
	elif sudden_death or score[h.team] >= CRYSTALS_TO_WIN:
		match_end_reason = "Решающий осколок" if sudden_death else "Осколки"
		end_match(h.team == 0)
	else:
		shell_phase = "idle"


func drop_crystal(pos: Vector3) -> void:
	if network_play and NetworkManager.server_protocol >= 3:
		return
	if crystal_node == null or not is_instance_valid(crystal_node):
		return
	crystal_state = "ground"
	crystal_timer = 0.0
	pickup_delay = 0.5
	carrier = null
	crystal_node.global_position = Vector3(pos.x, 0.5, pos.z)
	var ring := crystal_node.get_node_or_null("CrystalRing") as MeshInstance3D
	if ring != null:
		ring.position = Vector3(0.0, 0.02 - crystal_node.global_position.y, 0.0)
		ring.scale = Vector3.ONE


func on_hero_died(h: HeroUnit) -> void:
	burst(h.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.45, 0.4), 22)
	h.spawn_vfx_silent(HeroUnit.VFX_GOLDEN_SCENE, h.global_position + Vector3(0.0, 0.4, 0.0), 1.2)
	play_sfx("death", -3.0)
	if h == player:
		var death_pitch := 1.0
		match h.hero_class:
			HeroUnit.Cls.WARRIOR:
				death_pitch = 0.7
			HeroUnit.Cls.MAGE:
				death_pitch = 0.85
		play_sfx("death_scream", -7.0, death_pitch)
		p_deaths += 1
		if network_play:
			NetworkManager.send_death()
	h.match_deaths += 1
	if h == carrier or h.carrying:
		drop_crystal(h.global_position)
		announce("Осколок выбит!", Color(1.0, 0.7, 0.4), 1.8)
	if h == player:
		announce("Ты пал. Возрождение через %d" % int(ceil(h.respawn_timer)), Color(1.0, 0.5, 0.45), 2.2)


func record_hero_damage(target: HeroUnit, source: Node, damage: float, killed: bool) -> void:
	if source is HeroUnit:
		var source_hero := source as HeroUnit
		source_hero.match_damage_dealt += maxf(damage, 0.0)
		if killed and target.team != source_hero.team:
			source_hero.match_kills += 1
	if source is HeroUnit and killed and target.team != (source as HeroUnit).team and not (source as HeroUnit).is_player:
		(source as HeroUnit).bot_gold += 50
	if killed and source is HeroUnit and target.team != (source as HeroUnit).team and hud != null:
		hud.call("show_kill_feed", (source as HeroUnit).display_name, target.display_name, (source as HeroUnit).team, target.team)
	if player == null or source != player or target == player or target.team == player.team or damage <= 0.0:
		return
	p_damage += damage
	if killed:
		p_kills += 1
		award_gold(50)
		announce("Ты убил %s  +50 золота" % target.display_name, Color(1.0, 0.85, 0.35), 1.8)


func on_hero_respawned(h: HeroUnit) -> void:
	if h == player:
		death_camera_active = false
		play_sfx("respawn", -6.0)
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
	if match_end_reason.is_empty():
		match_end_reason = "Матч завершён"
	var stats_class := "unknown"
	if player != null and is_instance_valid(player):
		stats_class = ["warrior", "mage", "fairy"][clampi(int(player.hero_class), 0, 2)]
	Stats.track("match_end", {
		"result": result_text,
		"score": "%d:%d" % [score[0], score[1]],
		"reason": match_end_reason,
		"class": stats_class,
		"network": network_play,
	})
	get_tree().set_meta("last_match_won", player_won)
	get_tree().set_meta("last_match_reason", match_end_reason)
	get_tree().set_meta("last_match_score", score.duplicate())
	get_tree().set_meta("last_match_team", player_team)
	get_tree().set_meta("last_match_place", player_place)
	get_tree().set_meta("last_match_is_mvp", player_is_mvp)
	# The results screen runs after Main.tscn is freed (and the WS disconnected),
	# so keep the room id here: the reward claim must still know the match.
	get_tree().set_meta("last_match_room", network_room_id if network_play else 0)
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
	var players_table: Array = []
	for h in heroes:
		if h == null or not is_instance_valid(h):
			continue
		players_table.append({
			"name": h.display_name,
			"team": h.team,
			"kills": h.match_kills,
			"deaths": h.match_deaths,
			"damage": int(h.match_damage_dealt),
			"crystals": h.match_crystals,
			"is_player": h.is_player,
		})
	for remote in remote_players.values():
		if remote == null or not is_instance_valid(remote):
			continue
		players_table.append({
			"name": remote.display_name,
			"team": remote.team,
			"kills": remote.match_kills,
			"deaths": remote.match_deaths,
			"damage": int(remote.match_damage_dealt),
			"crystals": remote.match_crystals,
			"is_player": false,
		})
	get_tree().set_meta("last_match_players", players_table)
	if player != null and is_instance_valid(player):
		get_tree().set_meta("selected_class", player.hero_class)
		player.is_player = false
	announce("%s · %s" % [result_text, match_end_reason], Color(0.85, 1.0, 0.7) if player_won else Color(1.0, 0.5, 0.45), 6.0)
	var transition_timer := get_tree().create_timer(2.8)
	transition_timer.timeout.connect(_open_results_screen)


func _hero_performance_score(hero: HeroUnit) -> float:
	return float(hero.match_kills) * 3.0 \
		+ hero.match_damage_dealt / 100.0 \
		+ float(hero.match_shells) * 2.0 \
		+ float(hero.match_crystals) * 3.0 \
		+ float(hero.match_coins_collected) * 0.1 \
		+ float(hero.match_gold_spent) * 0.02


func _remote_performance_score(remote: Node) -> float:
	return float(remote.get("match_kills")) * 3.0 \
		+ float(remote.get("match_damage_dealt")) / 100.0 \
		+ float(remote.get("match_shells")) * 2.0 \
		+ float(remote.get("match_crystals")) * 3.0


func _get_player_place() -> int:
	if player == null or not is_instance_valid(player):
		return 4
	var place := 1
	var player_score := _hero_performance_score(player)
	for hero in heroes:
		if hero == null or not is_instance_valid(hero) or hero == player:
			continue
		if _hero_performance_score(hero) > player_score:
			place += 1
	for remote in remote_players.values():
		if remote == null or not is_instance_valid(remote):
			continue
		if _remote_performance_score(remote) > player_score:
			place += 1
	return place


func _is_player_mvp() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var player_score := _hero_performance_score(player)
	for hero in heroes:
		if hero == null or not is_instance_valid(hero) or hero == player:
			continue
		if _hero_performance_score(hero) >= player_score:
			return false
	for remote in remote_players.values():
		if remote == null or not is_instance_valid(remote):
			continue
		if _remote_performance_score(remote) >= player_score:
			return false
	return true


func _open_results_screen() -> void:
	if state != "over":
		return
	var error := get_tree().change_scene_to_file("res://scenes/ResultsScreen.tscn")
	if error != OK:
		push_error("Failed to open ResultsScreen: %s" % error_string(error))


func _uses_touch_controls() -> bool:
	return DeviceProfile.touch_controls


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


func enemy_within(pos: Vector3, team: int, radius: float) -> bool:
	# Used by the bush stealth: an enemy this close reveals the hidden hero.
	var limit := radius * radius
	for h in heroes:
		if h.team == team or h.dead:
			continue
		if pos.distance_squared_to(h.global_position) <= limit:
			return true
	for remote in remote_players.values():
		if remote == null or not is_instance_valid(remote):
			continue
		if int(remote.get("team")) == team or bool(remote.get("dead")):
			continue
		if pos.distance_squared_to((remote as Node3D).global_position) <= limit:
			return true
	return false


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
	cone.bottom_radius = 0.22
	cone.height = 0.55
	cone.radial_segments = 16
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
	tutorial_arrow.global_position = tutorial_target_position + Vector3(0.0, 2.6 + sin(tutorial_pulse_time * 2.4) * 0.18, 0.0)
	tutorial_arrow.rotation.y += delta * 1.8
	tutorial_arrow.scale = Vector3.ONE * (1.0 + pulse * 0.14)
	if tutorial_arrow_material != null:
		tutorial_arrow_material.emission_energy_multiplier = 1.4 + pulse * 2.0


func spawn_tutorial_dummy() -> void:
	if tutorial_dummy != null and is_instance_valid(tutorial_dummy):
		tutorial_dummy.max_health = 1000.0
		tutorial_dummy.health = 1000.0
		tutorial_dummy._update_health_display()
		return
	# Манекен сразу стоит в центре арены, а не появляется рядом с игроком.
	tutorial_dummy = _spawn_hero(HeroUnit.Cls.WARRIOR, 1 - player.team, false, Vector3(0.0, 0.15, 0.0))
	tutorial_dummy.name = "TrainingDummy"
	tutorial_dummy.set_display_name("Манекен")
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


func pick_shell_target() -> Node3D:
	var options: Array[Node3D] = []
	for h in heroes:
		if not h.dead and h.global_position.distance_to(Vector3.ZERO) < 14.5:
			options.append(h)
	# Guests are RemotePlayers on the host; the shell must be able to hit them
	# too (their HP is server-owned, damage goes through world_damage).
	if network_play and network_host:
		for remote in remote_players.values():
			if remote != null and is_instance_valid(remote) and not remote.dead:
				if remote.global_position.distance_to(Vector3.ZERO) < 14.5:
					options.append(remote as Node3D)
	if options.is_empty():
		return null
	if carrier != null and is_instance_valid(carrier) and not bool(carrier.get("dead")) and randf() < 0.55:
		return carrier as Node3D
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
			hero.apply_blessing(duration, team)


func spawn_projectile(from: Vector3, target: Node3D, damage: float, color: Color, source: HeroUnit, stun_time := 0.0, damage_type: String = "physical", effect_type: String = "", is_crit := false) -> void:
	if target == null or not is_instance_valid(target):
		return
	var profiler_start := Time.get_ticks_usec() if CombatProfiler.enabled else 0
	var node := _acquire_projectile()
	if node == null:
		return
	var is_bolt := source != null and source.hero_class == HeroUnit.Cls.FAIRY
	node.mesh = projectile_bolt_mesh if is_bolt else projectile_mesh
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
		"crit": is_crit,
		"bolt": is_bolt,
		"life": 2.5,
		"pooled": true,
	})
	if CombatProfiler.enabled:
		CombatProfiler.mark("projectile", "%.0f %.1fms" % [damage, (Time.get_ticks_usec() - profiler_start) / 1000.0])


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
				if target is HeroUnit:
					(target as HeroUnit).take_damage(p["damage"], p["source"], String(p.get("damage_type", "physical")), String(p.get("effect_type", "auto")), bool(p.get("crit", false)))
				else:
					target.take_damage(p["damage"], p["source"], String(p.get("damage_type", "physical")), String(p.get("effect_type", "auto")))
				if not (target is SkyShell) and shell != null and is_instance_valid(shell) and shell.alive:
					if shell.global_position.distance_to(node.global_position) <= 1.8:
						shell.take_damage(float(p["damage"]) * 0.8, p["source"], String(p.get("damage_type", "physical")))
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
				play_sfx("magic", -8.0)
			_release_projectile(node, bool(p.get("pooled", false)))
			continue
		node.global_position += to_goal.normalized() * minf(dist, 26.0 * delta)
		if bool(p.get("bolt", false)):
			node.look_at(node.global_position + to_goal.normalized(), Vector3.UP)
		keep.append(p)
	projectiles = keep


func melee_fx(_from: Vector3, to: Vector3) -> void:
	burst(to + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.85, 0.5), 10)


func mage_storm_tick(mage: HeroUnit, radius: float, damage: float) -> void:
	if state != "live" or mage.dead:
		return
	play_sfx("thunder", -16.0)
	var struck := false
	for enemy in enemies_in_radius(mage.global_position, radius, mage.team, mage):
		lightning_strike_fx(enemy.global_position)
		struck = true
		_activate_shell_beam(enemy.global_position, Color(0.38, 0.82, 1.0, 0.95))
		mage.spawn_ability_vfx(2, enemy.global_position + Vector3(0.0, 0.1, 0.0))
		var rolled_damage := mage.roll_ultimate_damage(damage)
		enemy.take_damage(mage._outgoing_damage(rolled_damage) * mage.get_blessing_damage_multiplier(), mage, "magic", "ult_lightning_storm")
	if mage.is_player:
		for remote_enemy in network_enemies_in_radius(mage.global_position, radius, mage.team):
			lightning_strike_fx(remote_enemy.global_position)
			struck = true
			_activate_shell_beam(remote_enemy.global_position, Color(0.38, 0.82, 1.0, 0.95))
			mage.spawn_ability_vfx(2, remote_enemy.global_position + Vector3(0.0, 0.1, 0.0))
			var network_damage := mage.roll_ultimate_damage(damage)
			remote_enemy.take_damage(mage._outgoing_damage(network_damage) * mage.get_blessing_damage_multiplier(), mage, "magic", "ult_lightning_storm")
	if shell != null and is_instance_valid(shell) and shell.alive:
		if shell.global_position.distance_to(mage.global_position) <= radius:
			lightning_strike_fx(shell.global_position)
			_activate_shell_beam(shell.global_position, Color(0.38, 0.82, 1.0, 0.95))
			shell.take_damage(mage.roll_ultimate_damage(damage) * mage.get_blessing_damage_multiplier() * 0.8, mage, "magic", "ult_lightning_storm")
			struck = true
	if not struck:
		var angle := randf() * TAU
		var distance := randf_range(2.0, radius * 0.75)
		lightning_strike_fx(mage.global_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance))


func shell_bolt(pos: Vector3, radius: float, damage: float) -> void:
	play_sfx("thunder", -2.0)
	shake(0.7)
	lightning_strike_fx(pos, Color(0.85, 0.65, 1.0))
	_activate_shell_beam(pos)
	burst(pos + Vector3(0.0, 0.6, 0.0), Color(0.85, 0.65, 1.0), 34)
	ring_fx(Vector3(pos.x, 0.2, pos.z), Color(0.85, 0.65, 1.0), radius)
	for h in heroes:
		if not h.dead and h.global_position.distance_to(pos) <= radius:
			if network_play and network_host and h == player:
				# The host's own HP is server-owned too: send the shell hit to
				# the server instead of applying it locally (sync rolled it back).
				NetworkManager.send_world_damage(NetworkManager.local_peer_id, damage)
			else:
				h.take_damage(damage, null, "magic")
				h.stun(1.0)
	if network_play and network_host:
		# Guests are RemotePlayers on the host: their HP is server-owned, so the
		# hit goes as a world_damage intent. The bolt VFX is relayed separately.
		for remote_id in remote_players.keys():
			var remote = remote_players[remote_id]
			if remote == null or not is_instance_valid(remote) or remote.dead:
				continue
			if remote.global_position.distance_to(pos) <= radius:
				NetworkManager.send_world_damage(int(remote_id), damage)
		NetworkManager.send_match_event_at("shell_bolt", pos.x, pos.z)


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
	earthquake_intensity = maxf(earthquake_intensity, 0.28)
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


func fairy_ult_burst_fx(center: Vector3, radius: float, color: Color) -> void:
	var gold := Color(1.0, 0.82, 0.32)
	burst(center + Vector3(0.0, 1.0, 0.0), gold, 36)
	_activate_ring(Vector3(center.x, 0.22, center.z), color, 0.7, Vector3.ONE * 0.4, Vector3(radius * 0.9, 1.0, radius * 0.9), true, 0.95)
	_activate_ring(Vector3(center.x, 0.28, center.z), gold, 0.55, Vector3.ONE * 0.3, Vector3(radius * 0.6, 1.0, radius * 0.6), true, 0.8)
	shake(0.35)


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


var number_label_pool: Array[Label3D] = []


func _acquire_number_label() -> Label3D:
	while not number_label_pool.is_empty():
		var node = number_label_pool.pop_back()
		if node != null and is_instance_valid(node):
			var old_tween = node.get_meta("number_tween", null)
			if old_tween is Tween:
				(old_tween as Tween).kill()
			node.visible = true
			node.modulate.a = 1.0
			return node
	var label := Label3D.new()
	label.font = UI_FONT
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	add_child(label)
	return label


func _release_number_label(label: Label3D) -> void:
	if not is_instance_valid(label):
		return
	label.visible = false
	label.modulate.a = 1.0
	if number_label_pool.size() < 32:
		number_label_pool.append(label)
	else:
		label.queue_free()


func damage_number(pos: Vector3, amount: float, _team: int, is_shell := false, is_crit := false) -> void:
	var profiler_start := Time.get_ticks_usec() if CombatProfiler.enabled else 0
	var label := _acquire_number_label()
	label.text = str(int(round(amount)))
	label.font_size = 76 if is_crit else 64
	if is_shell:
		label.modulate = Color(0.85, 0.9, 1.0)
	elif is_crit:
		label.modulate = Color(1.0, 0.25, 0.2)
	else:
		label.modulate = Color(1.0, 0.92, 0.65)
	label.outline_modulate = Color(0.05, 0.03, 0.08, 0.9)
	label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	var tween := create_tween()
	label.set_meta("number_tween", tween)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0.0, 1.1, 0.0), 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(_release_number_label.bind(label))
	if CombatProfiler.enabled:
		CombatProfiler.mark("number", "%.0f crit=%s %.1fms" % [amount, str(is_crit), (Time.get_ticks_usec() - profiler_start) / 1000.0])


func heal_number(pos: Vector3, amount: float) -> void:
	var label := _acquire_number_label()
	label.text = "+" + str(int(round(amount)))
	label.font_size = 56
	label.modulate = Color(0.6, 1.0, 0.7)
	label.outline_modulate = Color(0.03, 0.08, 0.05, 0.9)
	label.global_position = pos
	var tween := create_tween()
	label.set_meta("number_tween", tween)
	tween.tween_property(label, "global_position", pos + Vector3(0.0, 1.0, 0.0), 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(_release_number_label.bind(label))


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
	if not NetworkManager.shell_state_received.is_connected(_on_shell_state_received):
		NetworkManager.shell_state_received.connect(_on_shell_state_received)
	if not NetworkManager.shell_damage_received.is_connected(_on_shell_damage_received):
		NetworkManager.shell_damage_received.connect(_on_shell_damage_received)
	if not NetworkManager.crystal_state_received.is_connected(_on_crystal_state_received):
		NetworkManager.crystal_state_received.connect(_on_crystal_state_received)
	if not NetworkManager.bot_roster_received.is_connected(_on_bot_roster_received):
		NetworkManager.bot_roster_received.connect(_on_bot_roster_received)
	if not NetworkManager.host_changed.is_connected(_on_network_host_changed):
		NetworkManager.host_changed.connect(_on_network_host_changed)
	if not NetworkManager.gold_updated.is_connected(_on_gold_updated):
		NetworkManager.gold_updated.connect(_on_gold_updated)
	if not NetworkManager.shop_purchase_received.is_connected(_on_shop_purchase_received):
		NetworkManager.shop_purchase_received.connect(_on_shop_purchase_received)
	if not NetworkManager.attack_denied.is_connected(_on_attack_denied):
		NetworkManager.attack_denied.connect(_on_attack_denied)
	if not NetworkManager.sync_received.is_connected(_on_network_sync):
		NetworkManager.sync_received.connect(_on_network_sync)
	if not NetworkManager.match_time_sync.is_connected(_on_match_time_sync):
		NetworkManager.match_time_sync.connect(_on_match_time_sync)
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


func _on_remote_damage_received(source_id: int, target_id: int, amount: float, skill: String, crit := false, stun := 0.0) -> void:
	if shell_audit and skill.to_lower() == "ult_lightning_storm":
		print("[DMG-AUDIT] source=%d target=%d amount=%.1f skill=%s" % [source_id, target_id, amount, skill])
	if CombatProfiler.enabled:
		print("[DMG] source=%d target=%d amount=%.0f skill=%s" % [source_id, target_id, amount, skill])
	var show_number := source_id == NetworkManager.local_peer_id or target_id == NetworkManager.local_peer_id
	if source_id < 0:
		var source_bot = remote_players.get(source_id)
		if source_bot != null and is_instance_valid(source_bot):
			source_bot.play_attack(skill)
	var target_team := -1
	var target_name := ""
	var killed := false
	var target_bot = network_bots.get(target_id)
	if target_bot != null and is_instance_valid(target_bot):
		killed = target_bot.apply_network_damage(amount, show_number, crit)
		target_team = int(target_bot.team)
		target_name = String(target_bot.display_name)
	elif target_id == NetworkManager.local_peer_id:
		if player != null and is_instance_valid(player):
			killed = player.apply_network_damage(amount, show_number, crit)
			target_team = int(player.team)
			target_name = String(player.display_name)
	else:
		var remote = remote_players.get(target_id)
		if remote != null and is_instance_valid(remote):
			killed = remote.apply_network_damage(amount, show_number, crit)
			target_team = int(remote.team)
			target_name = String(remote.display_name)
	# Stun is server-confirmed. Only the target's own client applies it to the
	# local hero; the host also applies it to its simulated bots.
	if stun > 0.0:
		if target_id == NetworkManager.local_peer_id:
			if player != null and is_instance_valid(player):
				player.stun(stun)
		elif network_bots.has(target_id):
			var stunned_bot = network_bots[target_id]
			if stunned_bot != null and is_instance_valid(stunned_bot):
				stunned_bot.stun(stun)
	if player == null or not is_instance_valid(player) or target_team == player.team:
		return
	# Damage stats come from the confirmed hit; kills are credited once from
	# the server death packet (protocol 4), or from this hit on protocol 3.
	if source_id == NetworkManager.local_peer_id:
		player.match_damage_dealt += maxf(amount, 0.0)
		p_damage += maxf(amount, 0.0)
	elif source_id > 0 and remote_players.has(source_id):
		var source_remote = remote_players[source_id]
		if source_remote != null and is_instance_valid(source_remote):
			source_remote.match_damage_dealt += maxf(amount, 0.0)
			source_remote.play_attack(skill)
	elif source_id < 0:
		var source_bot = _network_combatant(source_id)
		if source_bot != null and is_instance_valid(source_bot) and int(source_bot.get("team")) != target_team:
			source_bot.match_damage_dealt += maxf(amount, 0.0)
	if killed and NetworkManager.server_protocol < 4:
		_credit_network_kill(source_id, target_name, target_team)


func _credit_network_kill(source_id: int, victim_name: String, victim_team: int) -> void:
	if player == null or not is_instance_valid(player) or victim_team == player.team:
		return
	if source_id == NetworkManager.local_peer_id:
		p_kills += 1
		player.match_kills += 1
		if NetworkManager.server_protocol < 4:
			award_gold(50)
		else:
			# The server credits the wallet and sends `gold`; only track stats.
			gold_earned_this_match += 50
		announce("Ты убил %s  +50 золота" % victim_name, Color(1.0, 0.85, 0.35), 1.8)
	elif source_id < 0:
		var killer_bot = _network_combatant(source_id)
		if killer_bot != null and is_instance_valid(killer_bot):
			killer_bot.match_kills += 1
			if network_host and killer_bot is HeroUnit:
				killer_bot.bot_gold += 50
	elif source_id > 0 and remote_players.has(source_id):
		var killer_remote = remote_players[source_id]
		if killer_remote != null and is_instance_valid(killer_remote):
			killer_remote.match_kills += 1
	if source_id != 0 and hud != null:
		var killer_node := _node_for_network_id(source_id)
		var killer_name := "?"
		var killer_team := -1
		if killer_node != null:
			killer_name = String(killer_node.get("display_name"))
			killer_team = int(killer_node.get("team"))
		hud.call("show_kill_feed", killer_name, victim_name, killer_team, victim_team)


func _on_remote_death_received(player_id: int, source_id: int = 0) -> void:
	var victim_name := ""
	var victim_team := -1
	if player_id == NetworkManager.local_peer_id:
		if player != null and is_instance_valid(player):
			victim_name = String(player.display_name)
			victim_team = int(player.team)
			player.apply_network_sync(0.0, player.max_health, false)
	elif network_bots.has(player_id):
		var bot = network_bots[player_id]
		if bot != null and is_instance_valid(bot):
			victim_name = String(bot.display_name)
			victim_team = int(bot.team)
			bot.apply_network_damage(bot.health, false)
	elif remote_players.has(player_id):
		var remote = remote_players[player_id]
		if remote != null and is_instance_valid(remote):
			victim_name = String(remote.display_name)
			victim_team = int(remote.team)
			remote.apply_network_death()
	if victim_team < 0:
		return
	if NetworkManager.server_protocol >= 4:
		_credit_network_kill(source_id, victim_name, victim_team)


func _on_remote_respawn_received(player_id: int, position: Vector3, rotation_y: float) -> void:
	if player_id == NetworkManager.local_peer_id:
		return
	var remote = remote_players.get(player_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_network_respawn(position, rotation_y)


func _on_remote_heal_received(source_id: int, target_id: int, amount: float) -> void:
	# The healer's own client already applied the heal locally for remote
	# allies (receive_heal), so the echo would double the HP and the +N. Bots
	# and the local player are different: their heal was only sent, never
	# applied locally, so the echo is the only place the HP and +N happen.
	if source_id == NetworkManager.local_peer_id:
		if target_id == NetworkManager.local_peer_id:
			if player != null and is_instance_valid(player):
				player.apply_network_heal(amount)
				NetworkManager.send_stats(player.max_health, player.health, player.attack_damage)
			return
		var local_bot = network_bots.get(target_id)
		if local_bot != null and is_instance_valid(local_bot):
			local_bot.apply_network_heal(amount)
		return
	if target_id == NetworkManager.local_peer_id:
		if player != null and is_instance_valid(player):
			player.apply_network_heal(amount)
			NetworkManager.send_stats(player.max_health, player.health, player.attack_damage)
		return
	var bot = network_bots.get(target_id)
	if bot != null and is_instance_valid(bot):
		bot.apply_network_heal(amount)
		return
	var remote = remote_players.get(target_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_network_heal(amount)


func _on_remote_stats_updated(player_id: int, max_hp: float, hp: float, attack_damage: float) -> void:
	var remote = remote_players.get(player_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_stats(max_hp, hp, attack_damage)


func _on_bot_state_updated(bot_id: int, info: Dictionary) -> void:
	if not network_play:
		return
	if network_host:
		if NetworkManager.server_protocol < 2:
			return
		var bot = network_bots.get(bot_id)
		if bot == null or not is_instance_valid(bot):
			return
		var max_hp := maxf(float(info.get("max_hp", bot.max_health)), 1.0)
		var hp := clampf(float(info.get("hp", bot.health)), 0.0, max_hp)
		var alive := bool(info.get("alive", true))
		bot.max_health = max_hp
		if not alive:
			if bot.network_respawn_grace > 0.0:
				# A snapshot from before the host respawned the bot. The server
				# restores it after the host reports alive; killing it here
				# produced the "respawn and die instantly" loop.
				return
			if not bot.dead:
				bot.apply_network_damage(bot.health, false)
			return
		if bot.dead:
			bot._respawn()
			if hp <= 0.0:
				hp = max_hp
		if hp > bot.health and bot.seconds_since_damage < 0.6:
			# A snapshot created just before the server confirmed our hit can
			# arrive after the damage packet. Hold the confirmed value briefly.
			hp = bot.health
		bot.health = hp
		bot._update_health_display()
		return
	var remote = remote_players.get(bot_id)
	if remote == null or not is_instance_valid(remote):
		_on_remote_player_joined(bot_id, info)
		remote = remote_players.get(bot_id)
	if remote != null and is_instance_valid(remote):
		remote.apply_bot_state(info)


func _on_shell_state_received(state: Dictionary) -> void:
	if not network_play or NetworkManager.server_protocol < 2 or state.is_empty():
		return
	var state_spawn_id := int(state.get("spawn_id", 0))
	if shell_spawn_id > 0 and state_spawn_id < shell_spawn_id:
		# Packets from the previous shell can arrive right after a new spawn
		# (death echo, despawn echo). A stale "alive=false" without a spawn id
		# (id 0) is the usual cause of "explosion, then the shell is gone".
		return
	if state_spawn_id > 0:
		shell_spawn_id = maxi(shell_spawn_id, state_spawn_id)
	var alive := bool(state.get("alive", false))
	var hp := float(state.get("hp", 0.0))
	var max_hp := maxf(float(state.get("max_hp", 1000.0)), 1.0)
	var x := float(state.get("x", 0.0))
	var y := float(state.get("y", 0.45))
	var z := float(state.get("z", 0.0))
	if shell_audit:
		var echo_phase := String(state.get("phase", "idle"))
		if echo_phase != shell_echo_phase or alive != shell_echo_alive:
			print("[SHELL-ECHO] alive=%s phase=%s local_phase=%s spawn=%d local_spawn=%d" % [
				str(alive), echo_phase, shell_phase, state_spawn_id, shell_spawn_id,
			])
			shell_echo_phase = echo_phase
			shell_echo_alive = alive
	if not network_host:
		# The host owns the 2/4/6/8 schedule and its own shell timer. Taking
		# them from the server echo (a 100 ms old copy of the host's own
		# packet) can flip the phase around a spawn and skip a cycle. Only the
		# server-authoritative HP and alive flag are applied below.
		shell_phase = String(state.get("phase", "idle"))
		shell_timer = float(state.get("timer", 0.0))
	if network_host:
		if shell == null or not is_instance_valid(shell):
			return
		if not alive:
			var was_alive := shell.alive
			shell.alive = false
			shell.visible = false
			shell.health = 0.0
			shell._refresh_health_bar()
			if was_alive and shell_phase == "active":
				# Could be a real death or a refused spawn. Wait for the
				# shell_destroyed event: a real death keeps the fixed
				# 2/4/6/8 schedule, only a refusal retries in 5 s.
				shell_phase = "idle"
				shell_window = SHELL_WINDOW
				shell_hold_timer = 0.5
				shell_death_event_seen = false
				_shell_log("state_dead")
			if shell.has_method("deactivate"):
				shell.deactivate()
			return
		shell.alive = true
		shell.visible = true
		shell.max_health = max_hp
		shell.health = clampf(hp, 0.0, max_hp)
		shell._refresh_health_bar()
		return
	if alive:
		_ensure_remote_shell(Vector3(x, y, z), hp, max_hp)
	elif shell != null and is_instance_valid(shell):
		shell.alive = false
		shell.visible = false
		shell.health = 0.0
		# SkyShell only disables its collision in deactivate(); without this
		# the guest kept an invisible solid cylinder in the arena centre.
		if shell.has_method("deactivate"):
			shell.deactivate()
		else:
			shell.collision_layer = 0
			shell.collision_mask = 0
		shell._refresh_health_bar()


func _ensure_remote_shell(pos: Vector3, hp: float, max_hp: float) -> void:
	if shell == null or not is_instance_valid(shell):
		var s := SkyShell.new()
		s.name = "RemoteShell"
		add_child(s)
		s.setup(self)
		s.activate(self, pos)
		s.set_physics_process(false)
		shell = s
	elif not shell.alive:
		# deactivate() disabled the collision shape; a new cycle must restore
		# it or the guest walks through the shell.
		shell.activate(self, pos)
		shell.set_physics_process(false)
	shell.alive = true
	shell.visible = true
	shell.max_health = max_hp
	shell.health = clampf(hp, 0.0, max_hp)
	shell.global_position = pos
	shell.set_physics_process(false)
	shell._refresh_health_bar()


func _on_shell_destroyed_network(team: int = -1, source_id: int = 0, spawn_id: int = 0) -> void:
	if state != "live" or NetworkManager.server_protocol < 2:
		return
	if spawn_id > 0 and shell_spawn_id > 0 and spawn_id < shell_spawn_id:
		# A late "destroyed" from the previous shell must not kill the new one.
		return
	if spawn_id > 0:
		shell_spawn_id = maxi(shell_spawn_id, spawn_id)
	# The server owns the shell kill and reports who landed it.
	if not tutorial_mode and player != null and is_instance_valid(player) and team == player.team:
		if NetworkManager.server_protocol < 4:
			award_gold(100)
		else:
			gold_earned_this_match += 100
	if source_id != 0 and source_id == NetworkManager.local_peer_id:
		p_shells_destroyed += 1
		if player != null and is_instance_valid(player):
			player.match_shells += 1
	elif source_id < 0 and network_host:
		var killer_bot = network_bots.get(source_id)
		if killer_bot != null and is_instance_valid(killer_bot):
			killer_bot.bot_gold += 100
			killer_bot.match_shells += 1
	elif source_id > 0 and remote_players.has(source_id):
		var killer_remote = remote_players[source_id]
		if killer_remote != null and is_instance_valid(killer_remote):
			killer_remote.match_shells += 1
	if shell != null and is_instance_valid(shell):
		# The server event is the only "destroyed" signal; a normal despawn
		# only hides the shell and must not create a crystal.
		on_shell_died(shell, null)
	shell_death_event_seen = true
	shell_hold_timer = 0.0
	shell_phase = "idle"
	shell_timer = SHELL_SPAWN_INTERVAL
	shell_window = SHELL_WINDOW
	_shell_log("event_destroyed")


func _on_shell_damage_received(amount: float, source_id: int) -> void:
	if NetworkManager.server_protocol < 2 or amount <= 0.0 or source_id != NetworkManager.local_peer_id:
		return
	if shell_audit:
		print("[SHELL-AUDIT] damage amount=%.0f source=%d" % [amount, source_id])
	if shell != null and is_instance_valid(shell):
		damage_number(shell.global_position + Vector3(0.0, 3.4, 0.0), amount, 1, true)


func _on_gold_updated(amount: int) -> void:
	if not network_play:
		return
	gold = maxi(0, amount)
	if hud != null:
		hud.update_gold()
		if shop_open:
			hud.update_shop()


func _on_shop_purchase_received(item_id: String, ok: bool, server_gold: int) -> void:
	if not network_play:
		return
	shop_pending_item = ""
	shop_pending_timer = 0.0
	gold = maxi(0, server_gold)
	if ok and player != null and is_instance_valid(player) and not item_id in purchased_shop_items:
		if player.apply_shop_item(item_id):
			for item in SHOP_ITEMS:
				if String(item["id"]) == item_id:
					player.match_gold_spent += int(item["price"])
					break
			purchased_shop_items.append(item_id)
			play_sfx("shop_purchase", -7.0)
		else:
			announce("Предмет недоступен", Color(1.0, 0.62, 0.4), 1.8)
	elif not ok:
		announce("Покупка не подтверждена: недостаточно золота", Color(1.0, 0.62, 0.4), 1.8)
	if hud != null:
		hud.update_gold()
		hud.update_shop()


func _on_network_host_changed(new_host_id: int) -> void:
	network_host = NetworkManager.is_host
	print("[NET] host changed -> ", new_host_id, " local_host=", network_host)
	if network_host and state == "live":
		# We inherited the shell simulation: drop the guest copy and wait for
		# the next fixed 2/4/6/8 boundary instead of restarting a 5 s cycle.
		if shell != null and is_instance_valid(shell):
			shell.queue_free()
		shell = null
		shell_phase = "idle"
		shell_timer = 0.0
		shell_window = SHELL_WINDOW
		var wait_for_shell := 5.0
		if not sudden_death:
			var elapsed := maxf(0.0, float(MATCH_LENGTH) - match_time)
			var boundary_index := floori(elapsed / float(SHELL_SPAWN_INTERVAL))
			var since_boundary := elapsed - float(boundary_index) * float(SHELL_SPAWN_INTERVAL)
			shell_last_boundary = boundary_index - 1 if boundary_index > 0 and since_boundary < SHELL_WINDOW else boundary_index
			var next_boundary := ceilf(maxf(elapsed, 0.001) / float(SHELL_SPAWN_INTERVAL)) * float(SHELL_SPAWN_INTERVAL)
			wait_for_shell = maxf(0.0, next_boundary - elapsed)
		else:
			shell_last_boundary = floori(maxf(0.0, float(MATCH_LENGTH) - match_time) / float(SHELL_SPAWN_INTERVAL))
		shell_cycle_timer = wait_for_shell
		shell_timer = wait_for_shell
		shell_hold_timer = 0.0
		shell_death_event_seen = false
		_shell_log("host_changed")


func _on_bot_roster_received(bots: Array) -> void:
	if not network_play:
		return
	for entry in bots:
		if not entry is Dictionary:
			continue
		var bot_id := int(entry.get("id", 0))
		if bot_id >= 0:
			continue
		if network_host:
			if network_bots.has(bot_id):
				var existing = network_bots[bot_id]
				if existing != null and is_instance_valid(existing):
					continue
			var remote = remote_players.get(bot_id)
			if remote != null:
				_on_remote_player_left(bot_id)
			_spawn_network_bot_from_info(entry)
		elif not remote_players.has(bot_id):
			_on_remote_player_joined(bot_id, entry)


func _spawn_network_bot_from_info(info: Dictionary) -> HeroUnit:
	var bot_id := int(info.get("id", 0))
	var bot_class := clampi(int(info.get("class", 0)), 0, 2)
	var bot_team := clampi(int(info.get("team", 0)), 0, 1)
	var pos := Vector3(
		float(info.get("x", 0.0)),
		float(info.get("y", 0.76)),
		float(info.get("z", 0.0))
	)
	if pos.length_squared() < 0.01:
		pos = Vector3(0.0, 0.76, 28.0 if bot_team == 0 else -28.0)
	var bot := _spawn_hero(bot_class, bot_team, false, pos)
	bot.network_id = bot_id
	var bot_name := String(info.get("name", "")).strip_edges()
	if bot_name.is_empty() or bot_name.begins_with("Игрок"):
		bot_name = _next_bot_callsign()
	bot.set_display_name(bot_name)
	var max_hp := maxf(float(info.get("max_hp", bot.max_health)), 1.0)
	bot.max_health = max_hp
	bot.health = clampf(float(info.get("hp", max_hp)), 1.0, max_hp)
	bot.attack_damage = maxf(float(info.get("attack_damage", bot.attack_damage)), 0.0)
	bot.rotation.y = float(info.get("rotation", 0.0))
	bot._update_health_display()
	network_bots[bot_id] = bot
	NetworkManager.register_bot(bot)
	return bot


func _on_attack_denied(target_id: int, skill: String, reason: String) -> void:
	print("[NET] attack_denied target=", target_id, " skill=", skill, " reason=", reason)
	var now := Time.get_ticks_msec()
	if now - last_deny_msec < 1200:
		return
	var text := ""
	match reason:
		"out_of_range":
			text = "Слишком далеко"
		"cooldown":
			text = "Перезарядка"
		"invalid_target":
			text = "Цель недоступна"
		"invalid_source":
			text = "Вы мертвы"
		"protected":
			text = "Цель под защитой"
	if text.is_empty():
		return
	last_deny_msec = now
	announce("Удар не прошёл: " + text, Color(1.0, 0.72, 0.35), 0.9)


func _on_network_sync(hp: float, max_hp: float, alive: bool) -> void:
	if not network_play or player == null or not is_instance_valid(player):
		return
	player.apply_network_sync(hp, max_hp, alive)


func _on_match_time_sync(seconds: float) -> void:
	# Both devices must show the same clock. The server owns match time; only
	# correct a real drift so the local countdown stays smooth.
	if not network_play or state != "live":
		return
	var left := maxf(0.0, seconds)
	if absf(match_time - left) > 0.75:
		match_time = left
		time_up_announced = false


func _on_match_score_updated(score_0: int, score_1: int, server_sudden_death: bool) -> void:
	if not network_play or state != "live":
		return
	# Сервер может только увеличивать счёт: локальные доставки уже начислены.
	print("[SCORE] server=", score_0, ":", score_1, " local=", score[0], ":", score[1])
	# Сервер — единственный источник счёта. Раньше здесь стоял max(local,
	# server): оптимистичное локальное очко, которое сервер не подтвердил,
	# оставалось на экране и могло показать ложные 3 осколка.
	score[0] = score_0
	score[1] = score_1
	# Завершает сетевой матч только match_finished от сервера. Раньше
	# локальный max() мог набрать 3 осколка из рассинхрона и оборвать
	# бой, хотя на таймере оставалось ещё несколько минут.
	if server_sudden_death and not sudden_death:
		sudden_death = true
		announce("Решающий осколок!", Color(1.0, 0.75, 0.35), 3.0)


func _on_match_event_received(event: String, team: int, source_id: int, x := 0.0, z := 0.0, spawn_id := 0) -> void:
	if not network_play:
		return
	if event == "shell_destroyed" and NetworkManager.server_protocol >= 2:
		_on_shell_destroyed_network(team, source_id, spawn_id)
	elif event == "shard_delivered" and NetworkManager.server_protocol >= 4:
		_award_network_delivery(team, source_id)
	elif event == "shell_bolt":
		if not network_host:
			var bolt_pos := Vector3(x, 0.0, z)
			lightning_strike_fx(bolt_pos, Color(0.85, 0.65, 1.0))
			ring_fx(Vector3(bolt_pos.x, 0.2, bolt_pos.z), Color(0.85, 0.65, 1.0), 2.7)
			shake(0.35)
	elif event == "sudden_death" and not sudden_death:
		sudden_death = true
		announce("Решающий осколок!", Color(1.0, 0.75, 0.35), 3.0)


func _on_network_match_finished(winning_team: int) -> void:
	if not network_play or state != "live":
		return
	# Сетевой матч завершает только сервер. Локальный счёт — отображение,
	# он не должен переворачивать или обрывать результат.
	match_end_reason = "Матч завершён сервером"
	match String(NetworkManager.last_match_end_reason).to_lower():
		"score":
			match_end_reason = "Победили по осколкам"
		"time":
			match_end_reason = "Время вышло"
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
	if music != null and is_instance_valid(music):
		music.stop()
	if ambient != null and is_instance_valid(ambient):
		ambient.stop()
	_restore_master_audio()
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
		return "Выбери класс — 1 Воин · 2 Маг · 3 Арбалетчица"
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
