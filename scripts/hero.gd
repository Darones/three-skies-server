class_name HeroUnit
extends CharacterBody3D

signal hero_died(hero: HeroUnit)

enum Cls { WARRIOR, MAGE, FAIRY }

const GRAVITY := 26.0
const BASE_POSITION_Z := 28.0
const HERO_OUTGOING_DAMAGE_MULTIPLIER := 2.0
const DIRECT_DAMAGE_MIN_MULTIPLIER := 0.75
const DIRECT_DAMAGE_MAX_MULTIPLIER := 1.25
const CRITICAL_CHANCE := 0.05
const CRITICAL_DAMAGE_MULTIPLIER := 2.0
const HEALTH_BAR_FILL_WIDTH := 1.18
const GROUND_Y_OFFSET := -0.7
const HEALTH_REGEN_PER_SECOND := 10.0
const BASE_REGEN_RADIUS := 6.5
const BASE_SHIELD_RADIUS := 4.9
const BUSH_REVEAL_DURATION := 3.0
const BOT_DAMAGE_MULTIPLIER := 0.8
const BOT_ATTACK_INTERVAL_MULTIPLIER := 1.15
const BOT_ABILITY_COOLDOWN_MULTIPLIER := 1.2
const BOT_MOVE_ACCELERATION := 14.0
const BOT_RETREAT_START_RATIO := 0.22
const BOT_RETREAT_END_RATIO := 0.4
const AFK_TIMEOUT := 60.0
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const WEAPON_MAGE_GLOW := Color(0.35, 0.78, 1.0)
const WEAPON_WARRIOR_GLOW := Color(1.0, 0.64, 0.24)
const WEAPON_FAIRY_GLOW := Color(0.55, 1.0, 0.62)
const WARRIOR_SWING_SOUNDS := [
	preload("res://audio/sfx/warrior_attack_sword_01.wav"),
]
const WARRIOR_HIT_SOUNDS := [
	preload("res://audio/sfx/warrior_hit.wav"),
]
const MAGE_ATTACK_SOUNDS := [
	preload("res://audio/sfx/mage_ice_ball.wav"),
]
const MAGE_HIT_SOUNDS := [
	preload("res://audio/sfx/mage_hit.wav"),
]
const FAIRY_ATTACK_SOUNDS := [
	preload("res://audio/sfx/fairy_bow_release_01.wav"),
]
const FAIRY_HIT_SOUNDS := [
	preload("res://audio/sfx/fairy_hit.wav"),
]
const WARRIOR_ULT_SOUND := [
	preload("res://audio/sfx/warrior_quake_ult.wav"),
]
const VFX_HIT_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_01.tscn")
const VFX_HIT_02_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_02.tscn")
const VFX_BIG_IMPACT_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn")
const VFX_BIG_IMPACT_02_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_02.tscn")
const VFX_LIGHTNING_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_01.tscn")
const VFX_GOLDEN_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_02.tscn")
const VFX_HIT_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_punch_impact.wav")
const FOOTSTEP_SOUNDS := [
	preload("res://assets/audio/kenney_rpg/footstep_0.ogg"),
	preload("res://assets/audio/kenney_rpg/footstep_1.ogg"),
	preload("res://assets/audio/kenney_rpg/footstep_2.ogg"),
	preload("res://assets/audio/kenney_rpg/footstep_3.ogg"),
	preload("res://assets/audio/kenney_rpg/footstep_4.ogg"),
]
const ABILITY_SOUNDS := [
	[
		preload("res://audio/sfx/warrior_dash_shadow.wav"),
		preload("res://audio/sfx/warrior_bloodthirst.wav"),
		null,
	],
	[
		preload("res://audio/sfx/mage_root_vines_short.wav"),
		preload("res://audio/sfx/mage_heal_chime.wav"),
		preload("res://audio/sfx/mage_storm_ult.wav"),
	],
	[
		preload("res://audio/sfx/fairy_stun_shot.wav"),
		preload("res://audio/sfx/fairy_crit_draw_release.wav"),
		preload("res://audio/sfx/fairy_blessing.wav"),
	],
]
const VFX_BIG_IMPACT_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/explosions/fireball_explosion.wav")
const VFX_LIGHTNING_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/magic/spell_2.wav")
const VFX_GOLDEN_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/synth_power_up_ascending.wav")
const MAGE_STORM_DURATION := 5.0
const MAGE_STORM_RADIUS := 10.0
const WARRIOR_ULT_RADIUS := 8.0
const FAIRY_ULT_RADIUS := 5.0
const FAIRY_ULT_DAMAGE := 75.0
const FAIRY_ULT_SLOW := 0.3
const FAIRY_ULT_SLOW_DURATION := 2.0
const MAGE_STORM_DAMAGE := 100.0
const FAIRY_CRIT_CAST_TIME := 1.0
const FAIRY_CRIT_MULTIPLIER := 3.0
const CRIT_CAST_COLOR := Color(1.0, 0.16, 0.1)

const CLASS_DATA := {
	Cls.WARRIOR: {
		"name": "Воин",
		"title": "Воин Света",
		"hp": 1050.0,
		"speed": 6.4,
		"range": 3.5,
		"damage": 44.0,
		"interval": 0.6,
		"attack_anim_time": 0.25,
		"ranged": false,
		"color": Color(1.0, 0.78, 0.4),
		"abilities": [
			{"name": "Теневой рывок", "cd": 8.0, "type": "shadow_assassin"},
			{"name": "Жажда крови", "cd": 10.0, "type": "crit_buff"},
			{"name": "Крик ужаса", "cd": 25.0, "type": "fear_ult"},
		],
	},
	Cls.MAGE: {
		"name": "Маг",
		"title": "Маг-целитель",
		"hp": 1000.0,
		"speed": 5.9,
		"range": 9.0,
		"damage": 26.0,
		"interval": 1.0,
		"ranged": true,
		"color": Color(0.6, 0.95, 1.0),
		"abilities": [
			{"name": "Лозы", "cd": 10.0, "type": "root"},
			{"name": "Исцеление", "cd": 8.0, "type": "heal"},
			{"name": "Грозовой шквал", "cd": 28.0, "type": "ult_lightning_storm"},
		],
	},
	Cls.FAIRY: {
		"name": "Фея",
		"title": "Фея-лучница",
		"hp": 950.0,
		"speed": 4.5,
		"range": 11.0,
		"damage": 60.0,
		"interval": 0.75,
		"ranged": true,
		"color": Color(0.72, 0.95, 0.55),
		"abilities": [
			{"name": "Оглушающий выстрел", "cd": 12.0, "type": "stun_shot"},
			{"name": "100% Крит", "cd": 15.0, "type": "crit_shot"},
			{"name": "Золотое благословение", "cd": 24.0, "type": "golden_blessing"},
		],
	},
}

var game: Node = null
var team := 0
var hero_class: int = Cls.WARRIOR
var is_player := false
var network_id := 0
var afk_active := false
var afk_idle_time := 0.0
var afk_label: Label3D = null
var display_name := ""

var max_health := 200.0
var health := 200.0
var seconds_since_damage := 0.0
var move_speed := 6.0
var attack_range := 2.5
var attack_damage := 20.0
var attack_interval := 0.8
var attack_animation_duration := 0.45
var attack_speed_multiplier := 1.0
var bonus_regen_per_second := 0.0
var damage_reduction := 0.0
var lifesteal_fraction := 0.0
var cooldown_reduction := 0.0
var stun_duration_reduction := 0.0
var ranged := false

var carrying := false
var dead := false
var tutorial_dummy := false
var bot_gold := 0
var match_coins_collected := 0
var match_gold_spent := 0
var match_kills := 0
var match_damage_dealt := 0.0
var match_shells := 0
var match_crystals := 0
var bot_purchased_shop_items: Array[String] = []
var stun_timer := 0.0
var slow_timer := 0.0
var slow_factor := 0.0
var footstep_timer := 0.0
var footstep_player: AudioStreamPlayer
var ability_sfx_player: AudioStreamPlayer
var attack_cd := 0.0
var attack_anim_time := 0.0
var respawn_timer := 0.0
var ability_cds: Array[float] = [0.0, 0.0, 0.0]
var cast_flash := 0.0
var lightning_storm_timer := 0.0
var lightning_storm_tick_timer := 0.0
var lightning_storm_ring: MeshInstance3D
var crit_buff := false
var crit_buff_timer := 0.0
var crit_buff_multiplier := 2.0
var crit_buff_ring: MeshInstance3D = null
var crit_cast_timer := 0.0
var crit_cast_target: Node3D = null
var crit_cast_material_restores: Array = []
var crit_cast_particle_restores: Array = []
var crit_cast_particles: CPUParticles3D = null
var crit_cast_light: OmniLight3D = null
var blessing_timer := 0.0
var blessing_ring: Node3D = null
var blessing_rune: MeshInstance3D = null
var blessing_ground_timer := 0.0

var ai_goal := Vector3.ZERO
var navigation_agent: NavigationAgent3D = null
var navigation_target_set := false
var ai_think := 0.0
var ai_attack_target: Node3D = null
var ai_offset := Vector3.ZERO
var ai_retreating := false
var ai_kiting := false
var ai_strafe_sign := 1.0
var ai_strafe_timer := 0.0

var visual: Node3D
var wing_attachment: Node3D
var wing_bone_attachment: BoneAttachment3D
var wing_attachment_fallback := false
var wing_sway_time := 0.0
var anim_player: AnimationPlayer = null
var current_anim := ""
var weapon_attachment: BoneAttachment3D = null
var weapon_instance: Node3D = null
var weapon_anim_player: AnimationPlayer = null
var combat_audio_players: Dictionary = {}
var health_back: MeshInstance3D
var health_fill: MeshInstance3D
var health_label: Label3D
var name_label: Label3D
var occluded_from_player := false
var carry_light: OmniLight3D
var bush_zones: Array[Area3D] = []
var in_bush := false
var bush_reveal_timer := 0.0
var bush_visual_hidden := false
var in_shop_zone := false
var shop_manual_dismissed := false


func _ready() -> void:
	update_wings()


func setup(p_game: Node, p_class: int, p_team: int, p_player: bool) -> void:
	game = p_game
	hero_class = p_class
	team = p_team
	is_player = p_player
	var data: Dictionary = CLASS_DATA[hero_class]
	max_health = data["hp"]
	health = max_health
	move_speed = data["speed"]
	attack_range = data["range"]
	attack_damage = data["damage"]
	attack_interval = data["interval"]
	if not is_player:
		attack_damage *= BOT_DAMAGE_MULTIPLIER
		attack_interval *= BOT_ATTACK_INTERVAL_MULTIPLIER
	attack_animation_duration = float(data.get("attack_anim_time", 0.45))
	ranged = data["ranged"]
	display_name = data["name"]
	ai_offset = Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	ai_think = randf_range(0.05, 0.35)
	ai_strafe_sign = -1.0 if randf() < 0.5 else 1.0
	ai_strafe_timer = randf_range(1.5, 3.0)
	if not is_player:
		navigation_agent = NavigationAgent3D.new()
		navigation_agent.name = "BotNavigationAgent"
		navigation_agent.path_desired_distance = 0.55
		navigation_agent.target_desired_distance = 0.8
		add_child(navigation_agent)
	_build_body()
	_build_visual()
	footstep_player = AudioStreamPlayer.new()
	footstep_player.name = "Footsteps"
	footstep_player.max_polyphony = 1
	add_child(footstep_player)
	ability_sfx_player = AudioStreamPlayer.new()
	ability_sfx_player.name = "AbilitySfx"
	ability_sfx_player.max_polyphony = 1
	add_child(ability_sfx_player)
	update_wings()
	_update_health_display()


const WING_MODEL_DEFAULT := {
	"path": "res://assets/wings/angel_wings_animated.glb",
	"scale": 1.0,
	"position": Vector3.ZERO,
	"rotation": Vector3(0.0, 18.0, 10.0),
}


func _wing_config(wing_id: int) -> Dictionary:
	match wing_id:
		4:
			# демонические: модель пришла в сантиметрах и со сдвинутым origin
			return {
				"path": "res://assets/wings/low_poly_demon_wings_animated.glb",
				"scale": 0.006,
				"position": Vector3(0.0, -1.45, 0.0),
				"rotation": Vector3(0.0, 0.0, 0.0),
			}
		_:
			return WING_MODEL_DEFAULT


func update_wings() -> void:
	if not is_player or visual == null:
		return
	var character_key: String = ["warrior", "mage", "fairy"][hero_class]
	var wing_id := MetaProgression.get_equipped_wing(character_key)
	if wing_id == 0:
		if wing_attachment != null and is_instance_valid(wing_attachment):
			wing_attachment.queue_free()
		if wing_bone_attachment != null and is_instance_valid(wing_bone_attachment):
			wing_bone_attachment.queue_free()
		wing_attachment = null
		wing_bone_attachment = null
		wing_attachment_fallback = false
		return
	if wing_attachment == null or not is_instance_valid(wing_attachment):
		wing_attachment = Node3D.new()
		wing_attachment.name = "WingAttachment"
	_configure_wing_attachment()
	for old_wing in wing_attachment.get_children():
		wing_attachment.remove_child(old_wing)
		old_wing.queue_free()

	var config := _wing_config(wing_id)
	var wing_scene := load(String(config["path"])) as PackedScene
	if wing_scene == null:
		push_warning("Unable to load wing model: %s" % config["path"])
		return
	var wing_model := wing_scene.instantiate() as Node3D
	if wing_model == null:
		return
	wing_model.name = "Wings3D"
	wing_attachment.add_child(wing_model)
	wing_model.scale = Vector3.ONE * float(config["scale"])
	wing_model.position = config["position"]
	wing_model.rotation_degrees = config["rotation"]
	_set_wing_materials_double_sided(wing_model)
	var wing_anim_player := _find_animation_player(wing_model)
	if wing_anim_player != null:
		var played := false
		for animation_name in wing_anim_player.get_animation_list():
			if String(animation_name).to_lower().contains("flap"):
				wing_anim_player.play(animation_name)
				played = true
				break
		if not played:
			# резкую демоническую анимацию не играем — только покачивание
			wing_anim_player.stop()
	wing_sway_time = 0.0


func _configure_wing_attachment() -> void:
	var model_root := visual.get_node_or_null("Model") as Node3D
	var fallback_parent: Node3D = model_root if model_root != null else visual
	var skeleton := _find_skeleton(model_root)
	var bone_index := _find_wing_bone_index(skeleton)
	var target_parent: Node3D = fallback_parent
	wing_attachment_fallback = true
	if skeleton != null and bone_index >= 0:
		var selected_bone := skeleton.get_bone_name(bone_index)
		if wing_bone_attachment == null or not is_instance_valid(wing_bone_attachment) or wing_bone_attachment.get_parent() != skeleton or wing_bone_attachment.bone_name != selected_bone:
			if wing_bone_attachment != null and is_instance_valid(wing_bone_attachment):
				if wing_attachment.get_parent() == wing_bone_attachment:
					wing_attachment.reparent(fallback_parent, false)
				wing_bone_attachment.queue_free()
			wing_bone_attachment = BoneAttachment3D.new()
			wing_bone_attachment.name = "WingBoneAttachment"
			wing_bone_attachment.bone_name = selected_bone
			skeleton.add_child(wing_bone_attachment)
		target_parent = wing_bone_attachment
		wing_attachment_fallback = false
	elif wing_bone_attachment != null and is_instance_valid(wing_bone_attachment):
		if wing_attachment.get_parent() == wing_bone_attachment:
			wing_attachment.reparent(fallback_parent, false)
		wing_bone_attachment.queue_free()
		wing_bone_attachment = null
	if wing_attachment.get_parent() != target_parent:
		if wing_attachment.get_parent() == null:
			target_parent.add_child(wing_attachment)
		else:
			wing_attachment.reparent(target_parent, false)
	var parent_scale := target_parent.global_transform.basis.get_scale()
	var inverse_parent_scale := Vector3(
		1.0 / maxf(absf(parent_scale.x), 0.001),
		1.0 / maxf(absf(parent_scale.y), 0.001),
		1.0 / maxf(absf(parent_scale.z), 0.001)
	)
	wing_attachment.scale = inverse_parent_scale
	wing_attachment.position = Vector3(0.0, 0.0, -0.32) * inverse_parent_scale if not wing_attachment_fallback else Vector3(0.0, 1.43, 0.32)
	wing_attachment.rotation = Vector3.ZERO


func _set_wing_materials_double_sided(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.material_override is BaseMaterial3D:
			var double_sided_override := mesh_instance.material_override.duplicate() as BaseMaterial3D
			double_sided_override.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_instance.material_override = double_sided_override
		elif mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var source_material := mesh_instance.get_active_material(surface_index)
				if source_material is BaseMaterial3D:
					var double_sided_material := source_material.duplicate() as BaseMaterial3D
					double_sided_material.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_instance.set_surface_override_material(surface_index, double_sided_material)
	for child in node.get_children():
		_set_wing_materials_double_sided(child)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_wing_bone_index(skeleton: Skeleton3D) -> int:
	if skeleton == null or skeleton.get_bone_count() == 0:
		return -1
	var preferred_names := ["spine02", "chest", "torso", "body", "spine", "char1"]
	for preferred_name in preferred_names:
		for bone_index in range(skeleton.get_bone_count()):
			if String(skeleton.get_bone_name(bone_index)).to_lower().contains(preferred_name):
				return bone_index
	return -1


func _process(delta: float) -> void:
	if wing_attachment == null or not is_instance_valid(wing_attachment):
		return
	wing_sway_time += delta
	wing_attachment.rotation.z = sin(wing_sway_time * 1.8) * 0.035


func _build_body() -> void:
	collision_layer = 1
	collision_mask = 1
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.7
	col.shape = shape
	col.position = Vector3(0.0, 0.85, 0.0)
	add_child(col)

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)

	var local_player: HeroUnit = game.get("player") as HeroUnit if game != null else null
	var is_ally := is_player or (local_player != null and local_player.team == team)
	var ring_color := Color(0.18, 1.0, 0.52) if is_ally else Color(1.0, 0.2, 0.16)
	var ring := FxUtils.soft_ground_glow(2.4, ring_color, 0.0, 0.42)
	ring.name = "TeamRing"
	ring.position = Vector3(0.0, GROUND_Y_OFFSET, 0.0)
	visual.add_child(ring)

	_build_health_bar()
	_build_health_label()
	_build_name_label()

	carry_light = OmniLight3D.new()
	carry_light.light_color = Color(0.7, 0.9, 1.0)
	carry_light.light_energy = 0.0
	carry_light.omni_range = 5.0
	carry_light.position = Vector3(0.0, 2.4, 0.0)
	add_child(carry_light)
	_build_combat_audio_players()


func _build_combat_audio_players() -> void:
	for channel in ["attack", "impact", "ultimate"]:
		var player := AudioStreamPlayer3D.new()
		player.name = "CombatAudio_%s" % channel.capitalize()
		player.bus = "Master"
		player.max_polyphony = 4
		player.max_distance = 80.0
		player.unit_size = 14.0
		player.volume_db = -6.0
		player.position = Vector3(0.0, 1.0, 0.0)
		add_child(player)
		combat_audio_players[channel] = player


func _play_footstep(volume_db := -24.0) -> void:
	if footstep_player == null or footstep_player.playing:
		return
	footstep_player.stream = FOOTSTEP_SOUNDS[randi_range(0, FOOTSTEP_SOUNDS.size() - 1)]
	footstep_player.volume_db = volume_db
	footstep_player.play()


func _play_ability_sfx(index: int) -> void:
	if not is_player or ability_sfx_player == null:
		return
	if hero_class < 0 or hero_class >= ABILITY_SOUNDS.size():
		return
	if index < 0 or index >= ABILITY_SOUNDS[hero_class].size():
		return
	var stream: AudioStream = ABILITY_SOUNDS[hero_class][index]
	if stream == null:
		return
	ability_sfx_player.stream = stream
	ability_sfx_player.volume_db = -3.0
	ability_sfx_player.play()


func _play_combat_sfx(channel: String, sounds: Array, volume_db: float) -> void:
	var player := combat_audio_players.get(channel) as AudioStreamPlayer3D
	if player == null or sounds.is_empty():
		return
	player.stream = sounds[randi_range(0, sounds.size() - 1)] as AudioStream
	player.volume_db = volume_db
	player.play()


func _play_class_attack_sfx() -> void:
	match hero_class:
		Cls.WARRIOR:
			_play_combat_sfx("attack", WARRIOR_SWING_SOUNDS, -5.0)
		Cls.MAGE:
			_play_combat_sfx("attack", MAGE_ATTACK_SOUNDS, -7.0)
		Cls.FAIRY:
			_play_combat_sfx("attack", FAIRY_ATTACK_SOUNDS, -6.0)


func _play_class_hit_sfx() -> void:
	match hero_class:
		Cls.WARRIOR:
			_play_combat_sfx("impact", WARRIOR_HIT_SOUNDS, -7.0)
		Cls.MAGE:
			_play_combat_sfx("impact", MAGE_HIT_SOUNDS, -8.0)
		Cls.FAIRY:
			_play_combat_sfx("impact", FAIRY_HIT_SOUNDS, -7.0)


func _vfx_palette() -> Dictionary:
	match hero_class:
		Cls.WARRIOR:
			return {
				"primary": Color(1.0, 0.3, 0.16),
				"secondary": Color(1.0, 0.72, 0.24),
				"light": Color(1.0, 0.38, 0.12),
			}
		Cls.MAGE:
			return {
				"primary": Color(0.28, 0.7, 1.0),
				"secondary": Color(0.78, 0.94, 1.0),
				"light": Color(0.3, 0.64, 1.0),
			}
		_:
			return {
				"primary": Color(0.68, 1.0, 0.42),
				"secondary": Color(1.0, 0.8, 0.28),
				"light": Color(0.78, 1.0, 0.45),
			}


func spawn_attack_impact_vfx(pos: Vector3, effect_type: String = "") -> void:
	if effect_type == "root" or effect_type == "stun":
		spawn_ability_vfx(0, pos)
		return
	var scene := VFX_HIT_SCENE
	match hero_class:
		Cls.MAGE:
			scene = VFX_GOLDEN_SCENE
		Cls.FAIRY:
			scene = VFX_HIT_02_SCENE
	var palette := _vfx_palette()
	spawn_vfx(scene, pos, 1.2, 1.3, 1.5, palette["primary"], palette["secondary"], palette["light"])


func spawn_ability_vfx(index: int, pos: Vector3) -> void:
	var scene: PackedScene = VFX_HIT_SCENE
	var effect_scale := 1.15
	var effect_emission := 1.4
	var effect_light := 1.5
	match hero_class:
		Cls.WARRIOR:
			match index:
				0:
					scene = VFX_HIT_02_SCENE
				1:
					scene = VFX_LIGHTNING_SCENE
					effect_scale = 1.5
					effect_emission = 1.8
					effect_light = 2.0
				_:
					scene = VFX_BIG_IMPACT_SCENE
					effect_scale = 2.0
					effect_emission = 1.8
					effect_light = 3.0
		Cls.MAGE:
			match index:
				0:
					scene = VFX_HIT_SCENE
				1:
					scene = VFX_GOLDEN_SCENE
					effect_scale = 1.5
					effect_emission = 1.8
					effect_light = 2.0
				_:
					scene = VFX_LIGHTNING_SCENE
					effect_scale = 2.0
					effect_emission = 1.8
					effect_light = 3.0
		Cls.FAIRY:
			match index:
				0:
					scene = VFX_HIT_SCENE
				1:
					scene = VFX_LIGHTNING_SCENE
					effect_scale = 1.5
					effect_emission = 1.8
					effect_light = 2.0
				_:
					scene = VFX_GOLDEN_SCENE
					effect_scale = 2.0
					effect_emission = 1.8
					effect_light = 1.2
	var palette := _vfx_palette()
	spawn_vfx(scene, pos, effect_scale, effect_emission, effect_light, palette["primary"], palette["secondary"], palette["light"])


func spawn_vfx(
	vfx_scene: PackedScene,
	pos: Vector3,
	effect_scale: float = 1.6,
	effect_emission: float = 1.6,
	effect_light_energy: float = 2.0,
	primary_tint: Color = Color(1.0, 1.0, 1.0),
	secondary_tint: Color = Color(1.0, 0.8, 0.4),
	light_tint: Color = Color(1.0, 0.8, 0.4),
	play_vfx_audio: bool = true
) -> void:
	if vfx_scene == null:
		return
	var effect := vfx_scene.instantiate() as Node3D
	if effect == null:
		return
	var effect_parent: Node = game if game != null and is_instance_valid(game) else get_tree().current_scene
	if effect_parent == null:
		effect.free()
		return
	effect_parent.add_child(effect)
	var effect_position := pos
	effect_position.y += 0.6
	effect.global_position = effect_position
	effect.visible = true
	effect.scale = Vector3.ONE * effect_scale
	# Apply emission to GeometryInstance3D nodes that have StandardMaterial3D
	for child in effect.find_children("*", "GeometryInstance3D"):
		var mat := child.get("material_override") as StandardMaterial3D
		if mat != null:
			mat.emission_enabled = true
			mat.emission = primary_tint
			mat.emission_energy_multiplier = effect_emission
	# Apply light properties only to Light3D nodes
	for child in effect.find_children("*", "Light3D"):
		var light := child as Light3D
		if light != null:
			light.light_energy = effect_light_energy
			light.light_color = light_tint
	var audio_player := effect.find_child("AudioStreamPlayer3D", true, false) as AudioStreamPlayer3D
	if audio_player != null:
		if play_vfx_audio:
			var mapped_stream := _vfx_audio_for_scene(vfx_scene)
			if mapped_stream != null:
				audio_player.stream = mapped_stream
		else:
			audio_player.stop()
			audio_player.stream = null
		audio_player.max_polyphony = 1
		audio_player.max_distance = 80.0
		audio_player.unit_size = 14.0
		audio_player.volume_db = -6.0
		audio_player.bus = "Master"
	# Apply custom script properties only if the effect node supports them
	if effect.has_method("_set_vfx_params"):
		effect.call("_set_vfx_params", primary_tint, secondary_tint, effect_emission)
	var animation_player := effect.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lifetime := 1.0
	if animation_player != null and animation_player.has_animation("main"):
		lifetime = maxf(animation_player.get_animation("main").length, 0.6) + 0.25
	if animation_player != null and animation_player.has_animation("main"):
		animation_player.speed_scale = 1.0
		animation_player.play("main")
		animation_player.seek(0.0, true)
	elif effect.has_method("play"):
		effect.call("play")
	else:
		effect.queue_free()
		return
	if audio_player != null and audio_player.stream != null and not audio_player.is_playing():
		audio_player.play()
	get_tree().create_timer(lifetime).timeout.connect(Callable(effect, "queue_free"), CONNECT_ONE_SHOT)


func spawn_vfx_silent(vfx_scene: PackedScene, pos: Vector3, effect_scale: float = 1.6) -> void:
	var palette := _vfx_palette()
	spawn_vfx(vfx_scene, pos, effect_scale, 1.6, 2.0, palette.primary, palette.secondary, palette.light, false)


func _vfx_audio_for_scene(vfx_scene: PackedScene) -> AudioStream:
	if vfx_scene == VFX_HIT_SCENE or vfx_scene == VFX_HIT_02_SCENE:
		return VFX_HIT_SOUND
	if vfx_scene == VFX_BIG_IMPACT_SCENE or vfx_scene == VFX_BIG_IMPACT_02_SCENE:
		return VFX_BIG_IMPACT_SOUND
	if vfx_scene == VFX_LIGHTNING_SCENE:
		return VFX_LIGHTNING_SOUND
	if vfx_scene == VFX_GOLDEN_SCENE:
		return VFX_GOLDEN_SOUND
	return null


func _build_health_bar() -> void:
	health_back = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.25, 0.065)
	health_back.mesh = quad
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.08, 0.06, 0.1, 0.58)
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	back_mat.no_depth_test = false
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	health_back.material_override = back_mat
	health_back.position = Vector3(0.0, 2.3, 0.0)
	add_child(health_back)

	health_fill = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(HEALTH_BAR_FILL_WIDTH, 0.04)
	health_fill.mesh = fill_quad
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.4, 0.92, 0.6, 0.84)
	fill_mat.emission_enabled = true
	fill_mat.emission = Color(0.4, 0.92, 0.6)
	fill_mat.emission_energy_multiplier = 0.35
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	health_fill.material_override = fill_mat
	health_fill.position = Vector3(0.0, 2.3, 0.01)
	add_child(health_fill)


func _build_health_label() -> void:
	health_label = get_node_or_null("HealthLabel") as Label3D
	if health_label == null:
		health_label = Label3D.new()
		health_label.name = "HealthLabel"
		add_child(health_label)
	health_label.font = UI_FONT
	health_label.position = Vector3(0.0, 2.65, 0.0)
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.font_size = 42
	health_label.pixel_size = 0.005
	health_label.outline_size = 5
	health_label.outline_modulate = Color(0.02, 0.03, 0.05, 0.92)
	health_label.modulate = Color(0.93, 1.0, 0.95, 0.96)


func _build_name_label() -> void:
	name_label = Label3D.new()
	name_label.name = "NameLabel"
	name_label.text = display_name
	name_label.font = UI_FONT
	name_label.font_size = 44
	name_label.pixel_size = 0.006
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.modulate = Color(0.55, 0.9, 1.0) if team == 0 else Color(0.92, 0.66, 1.0)
	name_label.outline_size = 6
	name_label.outline_modulate = Color(0.02, 0.03, 0.06, 0.95)
	name_label.position = Vector3(0.0, 3.0, 0.0)
	add_child(name_label)


func set_display_name(value: String) -> void:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return
	display_name = trimmed
	if name_label != null and is_instance_valid(name_label):
		name_label.text = display_name


func _build_visual() -> void:
	var model := _load_model()
	if model != null:
		for child in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := child as MeshInstance3D
			var mesh_name := mesh_node.name.to_lower()
			print("HERO: mesh = ", mesh_node.name)
			if mesh_name.contains("sword") or mesh_name.contains("blade") or mesh_name.contains("weapon") or mesh_name.contains("weapon_bone") or mesh_name.contains("меч"):
				mesh_node.visible = false
		var holder := Node3D.new()
		holder.name = "Model"
		holder.add_child(model)
		holder.rotation.y = 0.0
		visual.add_child(holder)
		_fit_model(holder)
		anim_player = _find_animation_player(holder)
		_attach_class_weapon(holder)
		_play_anim("idle")
		return
	_build_placeholder()


func _load_model() -> Node3D:
	var folder := ""
	match hero_class:
		Cls.WARRIOR:
			folder = "res://art/generated/warrior"
		Cls.MAGE:
			folder = "res://art/generated/mage"
		Cls.FAIRY:
			folder = "res://art/generated/fairy"
	var dir := DirAccess.open(folder)
	if dir == null:
		return null
	var chosen := ""
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			if chosen == "" or file.to_lower().contains("character"):
				chosen = file
	if chosen == "":
		for file in dir.get_files():
			if file.ends_with(".glb") and (file.to_lower().contains("idle") or chosen == ""):
				chosen = file
	if chosen == "":
		return null
	var packed := load(folder + "/" + chosen) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	return node


func _fit_model(holder: Node3D) -> void:
	var aabb := _node_aabb(holder)
	if aabb.size.y <= 0.01:
		return
	var target := 2.15
	var factor := target / aabb.size.y
	holder.scale = Vector3.ONE * factor
	holder.position.y = -aabb.position.y * factor


func _node_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and n.mesh != null:
			var mi := n as MeshInstance3D
			var box := mi.mesh.get_aabb()
			box.position += mi.global_position - global_position
			if first:
				result = box
				first = false
			else:
				result = result.merge(box)
	return result


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found := _find_animation_player(c)
		if found != null:
			return found
	return null


func _attach_class_weapon(holder: Node3D) -> void:
	var skeleton := _find_skeleton(holder)
	if skeleton == null:
		return
	var desired_bone := "LeftHand" if hero_class == Cls.FAIRY else "RightHand"
	var bone_index := -1
	for index in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(index)).to_lower() == desired_bone.to_lower():
			bone_index = index
			break
	if bone_index < 0:
		return
	var weapon_path := ""
	var weapon_scale := 1.0
	var hand_offset := Vector3(0.06, 0.0, -0.1)
	var weapon_rotation := Vector3.ZERO
	match hero_class:
		Cls.WARRIOR:
			# меч теперь покупается в магазине, по умолчанию воин без оружия
			if not (1 in MetaProgression.unlocked_weapons):
				return
			weapon_path = "res://addons/low_poly_rpg_items/props/longsword.tscn"
			weapon_scale = 0.72
			hand_offset = Vector3(0.06, 0.0, -0.12)
			weapon_rotation = Vector3(0.0, 0.0, -12.0)
		Cls.MAGE:
			weapon_path = "res://addons/low_poly_rpg_items/props/staff_wizard.tscn"
			weapon_scale = 0.62
			hand_offset = Vector3(0.04, 0.0, -0.1)
		Cls.FAIRY:
			if 2 in MetaProgression.unlocked_weapons:
				weapon_path = "res://scenes/LegendaryBow.tscn"
				weapon_scale = 0.82
				hand_offset = Vector3(-0.06, 0.0, -0.1)
				weapon_rotation = Vector3(0.0, 0.0, 8.0)
			else:
				weapon_path = "res://addons/low_poly_rpg_items/props/short_bow.tscn"
				weapon_scale = 0.9
				hand_offset = Vector3(-0.06, 0.0, -0.1)
				weapon_rotation = Vector3(0.0, 0.0, 8.0)
	var packed_weapon := load(weapon_path) as PackedScene
	if packed_weapon == null:
		return
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "WeaponBoneAttachment"
	weapon_attachment.bone_name = skeleton.get_bone_name(bone_index)
	skeleton.add_child(weapon_attachment)
	var attachment_scale := maxf(absf(skeleton.global_transform.basis.get_scale().x), 0.001)
	weapon_attachment.position = hand_offset / attachment_scale
	weapon_instance = packed_weapon.instantiate() as Node3D
	if weapon_instance == null:
		weapon_attachment.queue_free()
		weapon_attachment = null
		return
	weapon_instance.name = "EquippedWeapon"
	weapon_instance.scale = Vector3.ONE * (weapon_scale / attachment_scale)
	weapon_instance.rotation_degrees = weapon_rotation
	weapon_instance.visible = true
	_disable_weapon_collisions(weapon_instance)
	weapon_attachment.add_child(weapon_instance)
	weapon_anim_player = _find_animation_player(weapon_instance)
	_add_weapon_effects(weapon_instance)


func _add_weapon_effects(weapon: Node3D) -> void:
	if weapon.get_node_or_null("WeaponEffects") != null:
		return
	var effects := Node3D.new()
	effects.name = "WeaponEffects"
	weapon.add_child(effects)
	match hero_class:
		Cls.MAGE:
			var staff_tip := Vector3(0.0, 1.18, 0.0)
			_add_weapon_glow_orb(effects, "StaffTipGlow", staff_tip, 0.09, WEAPON_MAGE_GLOW, 2.4)
			_add_weapon_glow_halo(effects, "StaffTipHalo", staff_tip, 0.42, WEAPON_MAGE_GLOW, 0.40)
			_add_weapon_sparks(effects, "ArcaneSparks", staff_tip, 12, 0.32, Vector3(0.0, 0.18, 0.0), WEAPON_MAGE_GLOW, CPUParticles3D.EMISSION_SHAPE_SPHERE, Vector3(0.04, 0.04, 0.04))
			_add_weapon_light(effects, staff_tip, WEAPON_MAGE_GLOW, 0.65, 2.4)
		Cls.WARRIOR:
			_add_weapon_glow_orb(effects, "SwordTipGlow", Vector3(0.0, 0.93, 0.0), 0.05, WEAPON_WARRIOR_GLOW, 2.2)
			_add_weapon_glow_halo(effects, "SwordTipHalo", Vector3(0.0, 0.93, 0.0), 0.24, WEAPON_WARRIOR_GLOW, 0.35)
			_add_weapon_blade_glow(effects, WEAPON_WARRIOR_GLOW)
			_add_weapon_sparks(effects, "BladeSparks", Vector3(0.0, 0.54, 0.0), 12, 0.38, Vector3(0.0, -0.9, 0.0), WEAPON_WARRIOR_GLOW, CPUParticles3D.EMISSION_SHAPE_BOX, Vector3(0.022, 0.36, 0.07))
			_add_weapon_glow_orb(effects, "SwordHiltGlow", Vector3(0.0, 0.0, 0.0), 0.022, WEAPON_WARRIOR_GLOW, 1.4)
			_add_weapon_light(effects, Vector3(0.0, 0.45, 0.0), WEAPON_WARRIOR_GLOW, 0.35, 1.9)
		Cls.FAIRY:
			var bow_center := Vector3(0.0, 0.0, -0.02)
			_add_weapon_glow_orb(effects, "BowGlow", bow_center, 0.028, WEAPON_FAIRY_GLOW, 1.6)
			_add_weapon_glow_halo(effects, "BowHalo", bow_center, 0.15, WEAPON_FAIRY_GLOW, 0.24)
			_add_weapon_sparks(effects, "BowSparks", bow_center, 7, 0.24, Vector3(0.0, 0.2, 0.0), WEAPON_FAIRY_GLOW, CPUParticles3D.EMISSION_SHAPE_SPHERE, Vector3(0.035, 0.035, 0.035))


func _add_weapon_glow_orb(parent: Node3D, node_name: String, at: Vector3, radius: float, color: Color, energy: float) -> void:
	var orb := MeshInstance3D.new()
	orb.name = node_name
	orb.position = at
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.visibility_range_end = 18.0
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	orb.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.92)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.disable_receive_shadows = true
	orb.material_override = material
	parent.add_child(orb)


func _add_weapon_glow_halo(parent: Node3D, node_name: String, at: Vector3, size: float, color: Color, alpha: float) -> void:
	var halo := MeshInstance3D.new()
	halo.name = node_name
	halo.position = at
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.visibility_range_end = 18.0
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	halo.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = _weapon_glow_texture()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	halo.material_override = material
	parent.add_child(halo)


func _add_weapon_blade_glow(parent: Node3D, color: Color) -> void:
	for side in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		strip.name = "BladeGlow"
		strip.position = Vector3(0.03 * side, 0.55, 0.0)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.visibility_range_end = 18.0
		var blade := CylinderMesh.new()
		blade.top_radius = 0.012
		blade.bottom_radius = 0.02
		blade.height = 0.75
		blade.radial_segments = 4
		strip.mesh = blade
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color.r, color.g, color.b, 0.55)
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.8
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.disable_receive_shadows = true
		strip.material_override = material
		parent.add_child(strip)

		var sheen := MeshInstance3D.new()
		sheen.name = "BladeSheen"
		sheen.position = Vector3(0.028 * side, 0.55, 0.0)
		sheen.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		sheen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheen.visibility_range_end = 18.0
		var sheen_quad := QuadMesh.new()
		sheen_quad.size = Vector2(0.16, 0.80)
		sheen.mesh = sheen_quad
		var sheen_material := StandardMaterial3D.new()
		sheen_material.albedo_texture = _weapon_glow_texture()
		sheen_material.albedo_color = Color(color.r, color.g, color.b, 0.18)
		sheen_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sheen_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sheen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sheen_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		sheen_material.disable_receive_shadows = true
		sheen.material_override = sheen_material
		parent.add_child(sheen)


func _add_weapon_sparks(parent: Node3D, node_name: String, at: Vector3, amount: int, speed: float, gravity: Vector3, color: Color, emission_shape: CPUParticles3D.EmissionShape, extents: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.position = at
	particles.amount = amount
	particles.lifetime = 0.65
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.preprocess = 0.45
	particles.visibility_range_end = 18.0
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 35.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = gravity
	particles.scale_amount_min = 0.55
	particles.scale_amount_max = 1.0
	particles.color = color
	particles.color_ramp = _weapon_spark_fade()
	particles.emission_shape = emission_shape
	if emission_shape == CPUParticles3D.EMISSION_SHAPE_SPHERE:
		particles.emission_sphere_radius = maxf(extents.x, 0.01)
	elif emission_shape == CPUParticles3D.EMISSION_SHAPE_BOX:
		particles.emission_box_extents = extents
	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	particles.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = _weapon_glow_texture()
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	particles.material_override = material
	particles.emitting = true
	parent.add_child(particles)


func _add_weapon_light(parent: Node3D, at: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.name = "WeaponLight"
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 10.0
	light.distance_fade_length = 6.0
	parent.add_child(light)


func _weapon_spark_fade() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.18, Color(1.0, 1.0, 1.0, 0.95))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	return gradient


func _weapon_glow_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var uv := Vector2(float(x), float(y)) / 31.0 * 2.0 - Vector2.ONE
			var alpha := pow(maxf(1.0 - uv.length_squared(), 0.0), 2.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _disable_weapon_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	for child in node.get_children():
		_disable_weapon_collisions(child)


func _play_weapon_attack_animation() -> void:
	if weapon_anim_player == null or not is_instance_valid(weapon_anim_player):
		return
	var desired_animation := "shoot" if hero_class == Cls.FAIRY else "swing"
	for animation_name in weapon_anim_player.get_animation_list():
		var candidate := String(animation_name)
		var lowered := candidate.to_lower()
		if lowered == desired_animation or lowered.ends_with("/" + desired_animation):
			weapon_anim_player.play(candidate)
			return


func _play_anim(key: String, restart: bool = false) -> void:
	if anim_player == null or (current_anim == key and not restart):
		return
	anim_player.speed_scale = 2.5 if hero_class == Cls.WARRIOR and key == "attack" else 1.0
	var target := ""
	for animation_name in anim_player.get_animation_list():
		var low := String(animation_name).to_lower()
		if low.contains(key):
			target = String(animation_name)
			break
	if target == "":
		return
	var anim := anim_player.get_animation(target)
	if anim:
		if key in ["idle", "run", "walk"]:
			anim.loop_mode = Animation.LOOP_LINEAR
		else:
			anim.loop_mode = Animation.LOOP_NONE
	current_anim = key
	anim_player.play(target)


func _build_placeholder() -> void:
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.6
	body.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CLASS_DATA[hero_class]["color"]
	body.material_override = mat
	body.position = Vector3(0.0, 0.9, 0.0)
	visual.add_child(body)


func _physics_process(delta: float) -> void:
	_update_blessing(delta)
	if game != null and bool(game.get("tutorial_mode")) and String(game.get("state")) == "tutorial_complete":
		velocity = Vector3.ZERO
		return
	if dead:
		_update_shop_proximity(delta)
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return

	seconds_since_damage = minf(5.0, seconds_since_damage + delta)
	_update_afk(delta)
	_update_shop_proximity(delta)
	bush_reveal_timer = maxf(0.0, bush_reveal_timer - delta)
	_refresh_bush_visibility()
	if seconds_since_damage >= 5.0 and health < max_health:
		var regen_multiplier := 2.0 if (_is_bush_stealthed() or _is_at_own_base()) else 1.0
		if blessing_timer > 0.0:
			regen_multiplier *= 2.0
		health = minf(max_health, health + (HEALTH_REGEN_PER_SECOND + bonus_regen_per_second) * regen_multiplier * delta)

	stun_timer = maxf(0.0, stun_timer - delta)
	slow_timer = maxf(0.0, slow_timer - delta)
	if slow_timer <= 0.0:
		slow_factor = 0.0
	attack_cd = maxf(0.0, attack_cd - delta)
	cast_flash = maxf(0.0, cast_flash - delta)
	attack_anim_time = maxf(0.0, attack_anim_time - delta)
	crit_buff_timer = maxf(0.0, crit_buff_timer - delta)
	if crit_buff_timer <= 0.0:
		crit_buff = false
		if crit_buff_ring != null:
			crit_buff_ring.visible = false
	for i in ability_cds.size():
		ability_cds[i] = maxf(0.0, ability_cds[i] - delta)

	var channeling_crit := crit_cast_timer > 0.0
	if channeling_crit:
		crit_cast_timer = maxf(0.0, crit_cast_timer - delta)
		_aim_crit_cast(delta)
		_update_crit_cast_visuals()
		if crit_cast_timer <= 0.0:
			_release_crit_shot()
		elif current_anim != "cast" or (anim_player != null and not anim_player.is_playing()):
			_play_anim("cast", true)
	var channeling_storm := lightning_storm_timer > 0.0
	if channeling_storm:
		lightning_storm_timer = maxf(0.0, lightning_storm_timer - delta)
		lightning_storm_tick_timer -= delta
		if lightning_storm_tick_timer <= 0.0 and game != null:
			game.mage_storm_tick(self, MAGE_STORM_RADIUS, MAGE_STORM_DAMAGE)
			lightning_storm_tick_timer += 1.0
		if lightning_storm_timer <= 0.0 and lightning_storm_ring != null:
			lightning_storm_ring.visible = false
		if current_anim != "cast" or (anim_player != null and not anim_player.is_playing()):
			_play_anim("cast", true)

	var dir := Vector3.ZERO
	if not channeling_storm and not channeling_crit and stun_timer <= 0.0:
		if is_player and not afk_active:
			dir = _player_dir()
		else:
			dir = _ai_dir(delta)
		var tutorial_controller := game.get("tutorial_controller") as Node if game != null else null
		var training_abilities := game != null and bool(game.get("tutorial_mode")) and tutorial_controller != null and String(tutorial_controller.get("stage")) == "abilities"
		if not training_abilities:
			_try_auto_attack(dir)

	var speed := move_speed * (0.5 if carrying else 1.0) * (1.0 - (slow_factor if slow_timer > 0.0 else 0.0))
	var target_v := dir * speed
	if channeling_storm or channeling_crit:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var movement_acceleration := BOT_MOVE_ACCELERATION if (not is_player or afk_active) else 40.0
		velocity.x = move_toward(velocity.x, target_v.x, movement_acceleration * delta)
		velocity.z = move_toward(velocity.z, target_v.z, movement_acceleration * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.2
	move_and_slide()
	if not dead and is_on_floor() and dir.length_squared() > 0.01:
		footstep_timer -= delta
		if footstep_timer <= 0.0:
			footstep_timer = clampf(2.4 / maxf(move_speed, 1.0), 0.24, 0.5)
			if is_player:
				_play_footstep(-24.0)
			elif game.player != null and is_instance_valid(game.player) and team != game.player.team:
				var listener_distance := global_position.distance_to(game.player.global_position)
				if listener_distance < 14.0:
					_play_footstep(lerpf(-30.0, -12.0, 1.0 - listener_distance / 14.0))
	else:
		footstep_timer = 0.0
	if game != null and game.has_method("clamp_to_arena"):
		var bounded_position: Vector3 = game.clamp_to_arena(global_position)
		if absf(bounded_position.x - global_position.x) > 0.001:
			velocity.x = 0.0
		if absf(bounded_position.z - global_position.z) > 0.001:
			velocity.z = 0.0
		global_position = bounded_position

	if dir.length_squared() > 0.01:
		_face(dir, delta)
	if global_position.y < -8.0:
		global_position = _base_spawn_position() + Vector3(0.0, 0.76, 0.0)
		velocity = Vector3.ZERO

	_update_look(delta)


func _player_dir() -> Vector3:
	var x := 0.0
	var y := 0.0
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("move_left_2") or Input.is_key_pressed(KEY_LEFT):
		x -= 1.0
	if Input.is_action_pressed("move_right") or Input.is_action_pressed("move_right_2") or Input.is_key_pressed(KEY_RIGHT):
		x += 1.0
	if Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_forward_2") or Input.is_key_pressed(KEY_UP):
		y += 1.0
	if Input.is_action_pressed("move_back") or Input.is_action_pressed("move_back_2") or Input.is_key_pressed(KEY_DOWN):
		y -= 1.0
	var input := Vector2(x, y)
	if input.length() < 0.1:
		return Vector3.ZERO
	input = input.normalized()
	var cam: Camera3D = game.camera if game != null else null
	if cam == null:
		return Vector3.ZERO
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var dir := right * input.x + fwd * input.y
	return dir.normalized()


func _has_movement_input() -> bool:
	return (
		Input.is_action_pressed("move_left")
		or Input.is_action_pressed("move_left_2")
		or Input.is_key_pressed(KEY_LEFT)
		or Input.is_action_pressed("move_right")
		or Input.is_action_pressed("move_right_2")
		or Input.is_key_pressed(KEY_RIGHT)
		or Input.is_action_pressed("move_forward")
		or Input.is_action_pressed("move_forward_2")
		or Input.is_key_pressed(KEY_UP)
		or Input.is_action_pressed("move_back")
		or Input.is_action_pressed("move_back_2")
		or Input.is_key_pressed(KEY_DOWN)
	)


func notify_player_input() -> void:
	if not is_player or dead:
		return
	afk_idle_time = 0.0
	if afk_active:
		_set_afk(false)


func _update_afk(delta: float) -> void:
	if not is_player or dead:
		return
	if game == null or String(game.get("state")) != "live" or bool(game.get("tutorial_mode")):
		return
	if afk_active:
		if _has_movement_input():
			notify_player_input()
		return
	if _has_movement_input():
		afk_idle_time = 0.0
		return
	afk_idle_time += delta
	if afk_idle_time >= AFK_TIMEOUT:
		_set_afk(true)


func _set_afk(enabled: bool) -> void:
	if afk_active == enabled:
		return
	afk_active = enabled
	ai_attack_target = null
	ai_retreating = false
	ai_kiting = false
	navigation_target_set = false
	if enabled:
		afk_idle_time = AFK_TIMEOUT
		ai_think = 0.0
		ai_strafe_timer = 0.0
		_ensure_navigation_agent()
		_ensure_afk_label()
		if afk_label != null:
			afk_label.visible = not dead
		if game != null:
			if game.has_method("set_shop_open"):
				game.call("set_shop_open", false)
			if game.has_method("announce"):
				game.call("announce", "AFK: управление передано ИИ", Color(1.0, 0.76, 0.32), 3.0)
		print("[AFK] Игрок неактивен %d секунд — управление передано ИИ." % int(AFK_TIMEOUT))
	else:
		afk_idle_time = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		if afk_label != null:
			afk_label.visible = false
		if game != null and game.has_method("announce"):
			game.call("announce", "С возвращением! Управление снова у тебя", Color(0.74, 1.0, 0.78), 2.8)
		print("[AFK] Игрок снова активен — управление возвращено.")


func _ensure_navigation_agent() -> void:
	if navigation_agent != null:
		return
	navigation_agent = NavigationAgent3D.new()
	navigation_agent.name = "AfkNavigationAgent"
	navigation_agent.path_desired_distance = 0.55
	navigation_agent.target_desired_distance = 0.8
	add_child(navigation_agent)


func _ensure_afk_label() -> void:
	if afk_label != null:
		return
	afk_label = Label3D.new()
	afk_label.name = "AfkLabel"
	afk_label.text = "AFK · ИИ"
	afk_label.font = UI_FONT
	afk_label.font_size = 34
	afk_label.pixel_size = 0.0048
	afk_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	afk_label.no_depth_test = true
	afk_label.modulate = Color(1.0, 0.74, 0.3, 1.0)
	afk_label.outline_size = 7
	afk_label.outline_modulate = Color(0.06, 0.03, 0.01, 0.95)
	afk_label.position = Vector3(0.0, 3.55, 0.0)
	afk_label.visible = false
	add_child(afk_label)


func _ai_dir(delta: float) -> Vector3:
	ai_think -= delta
	ai_strafe_timer -= delta
	if ai_strafe_timer <= 0.0:
		ai_strafe_timer = randf_range(1.5, 3.0)
		ai_strafe_sign *= -1.0
	if ai_think <= 0.0:
		ai_think = randf_range(0.42, 0.62)
		_ai_pick_goal()
		ai_goal = game.clamp_to_arena(ai_goal)
		if navigation_agent != null:
			navigation_agent.target_position = Vector3(ai_goal.x, global_position.y, ai_goal.z)
			navigation_target_set = true
		if not carrying:
			_ai_abilities()
	if carrying:
		var base_goal := _base_position()
		ai_goal = base_goal
		if navigation_agent != null:
			var current_target := navigation_agent.target_position
			var target_delta := Vector2(current_target.x - base_goal.x, current_target.z - base_goal.z)
			if not navigation_target_set or target_delta.length_squared() > 0.25:
				navigation_agent.target_position = Vector3(base_goal.x, global_position.y, base_goal.z)
				navigation_target_set = true
	var to_goal := ai_goal - global_position
	to_goal.y = 0.0
	if navigation_agent != null and navigation_target_set:
		var path_position := navigation_agent.get_next_path_position()
		var path_direction := path_position - global_position
		path_direction.y = 0.0
		if path_direction.length_squared() > 0.04:
			to_goal = path_direction
		else:
			to_goal = Vector3.ZERO
	var dist := to_goal.length()
	var dir := Vector3.ZERO
	if dist > 0.12:
		dir = to_goal / dist
	var enemy := ai_attack_target
	if not carrying and enemy != null and is_instance_valid(enemy):
		var away := global_position - enemy.global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.1 and ranged:
			if not ai_kiting and d < attack_range * 0.72:
				ai_kiting = true
			elif ai_kiting and d > attack_range * 0.9:
				ai_kiting = false
			if ai_kiting:
				var strafe := Vector3(-away.z, 0.0, away.x).normalized() * ai_strafe_sign
				dir = away.normalized() * 0.2 + strafe * 0.8
	var sep := Vector3.ZERO
	if game != null and game.has_method("heroes"):
		for other in game.heroes:
			if other == self or other.dead or other.team != team:
				continue
			var delta_pos: Vector3 = global_position - other.global_position
			delta_pos.y = 0.0
			var dd := delta_pos.length()
			if dd > 0.01 and dd < 1.35:
				sep += delta_pos.normalized() * (1.35 - dd)
	if carrying and dir.length_squared() > 0.01:
		sep = sep.slide(dir.normalized())
	dir += sep * 0.35
	if stun_timer > 0.0:
		return Vector3.ZERO
	return dir.normalized() if dir.length() > 0.01 else Vector3.ZERO


func _ai_abilities() -> void:
	if dead or stun_timer > 0.0:
		return
	if game == null:
		return
	var enemy: HeroUnit = game.nearest_enemy(global_position, team, 13.0, self)
	var dist := global_position.distance_to(enemy.global_position) if enemy != null else 99.0
	var shell_target: SkyShell = game.shell
	var near_shell: bool = shell_target != null and is_instance_valid(shell_target) and shell_target.alive and global_position.distance_to(shell_target.global_position) < 8.0
	match hero_class:
		Cls.WARRIOR:
			if enemy != null and dist < 3.2 and ability_ready(1):
				use_ability(1, false)
			elif enemy != null and dist > 2.5 and ability_ready(0):
				use_ability(0, false)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.5:
				use_ability(2, false)
		Cls.MAGE:
			var ally: HeroUnit = game.lowest_ally(global_position, team, 12.0)
			if ally != null and ally.health < ally.max_health * 0.62 and ability_ready(1):
				use_ability(1, false)
			elif enemy != null and dist < 7.0 and ability_ready(0):
				use_ability(0, false)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.4:
				use_ability(2, false)
		Cls.FAIRY:
			if enemy != null and dist < 14.0 and ability_ready(0):
				use_ability(0, false)
			elif enemy != null and dist < 10.0 and ability_ready(1):
				use_ability(1, false)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.45:
				use_ability(2, false)


func _ai_pick_goal() -> void:
	if game == null:
		ai_goal = Vector3.ZERO
		return
	if not ai_retreating and health <= max_health * BOT_RETREAT_START_RATIO:
		ai_retreating = true
	elif ai_retreating and health >= max_health * BOT_RETREAT_END_RATIO:
		ai_retreating = false
	var local_enemy: HeroUnit = game.nearest_enemy(global_position, team, 30.0, self)
	var network_enemy: Node3D = null
	if game.has_method("network_nearest_enemy"):
		network_enemy = game.call("network_nearest_enemy", global_position, team, 30.0)
	var target = local_enemy
	if target == null and network_enemy != null:
		target = network_enemy
	var previous_target = ai_attack_target
	if previous_target != null and is_instance_valid(previous_target) and not previous_target.dead and previous_target.team != team:
		var previous_distance := global_position.distance_to(previous_target.global_position)
		var new_distance := global_position.distance_to(target.global_position) if target != null else INF
		if previous_distance < 30.0 and previous_distance <= new_distance * 1.18:
			target = previous_target
	ai_attack_target = target
	if carrying:
		ai_goal = _base_position()
		return
	var crystal_carrier = game.get("carrier")
	if crystal_carrier != null and is_instance_valid(crystal_carrier) and bool(crystal_carrier.get("carrying")):
		var carrier_team := int(crystal_carrier.get("team"))
		if carrier_team == team:
			ai_goal = game.clamp_to_arena(crystal_carrier.global_position) if game.has_method("clamp_to_arena") else crystal_carrier.global_position
		else:
			if crystal_carrier is HeroUnit:
				ai_attack_target = crystal_carrier
			ai_goal = crystal_carrier.global_position
		return
	if ai_retreating:
		ai_goal = _base_position()
		return
	var crystal_node: Node3D = game.crystal_node
	if game.crystal_state == "ground" and crystal_node != null and is_instance_valid(crystal_node):
		ai_goal = _crystal_approach_point(crystal_node)
		return
	var shell = game.shell
	if shell != null and is_instance_valid(shell) and shell.alive:
		ai_goal = _shell_approach_point(shell)
		return
	var enemy_distance := global_position.distance_to(target.global_position) if target != null else INF
	if enemy_distance > 16.0:
		if game.bot_has_affordable_shop_item(self):
			if game.is_hero_near_shop(self):
				game.purchase_bot_shop_item(self)
			if game.bot_has_affordable_shop_item(self):
				ai_goal = game.bot_shop_goal()
				return
		var coin: Node3D = game.nearest_gold_coin(global_position)
		if coin != null:
			ai_goal = coin.global_position
			return
	if target != null:
		var enemy_base := Vector3(0.0, 0.0, -BASE_POSITION_Z if team == 0 else BASE_POSITION_Z)
		var goal: Vector3 = target.global_position
		var from_base := goal - enemy_base
		from_base.y = 0.0
		if from_base.length() < 9.0:
			goal = enemy_base + from_base.normalized() * 9.0
		ai_goal = goal + ai_offset
	else:
		ai_goal = Vector3(0.0, 0.0, 0.0)


func _base_position() -> Vector3:
	return _base_spawn_position()


func _shell_approach_point(shell: SkyShell) -> Vector3:
	var spread := Vector2(ai_offset.x, ai_offset.z)
	var angle := atan2(spread.y, spread.x)
	if spread.length_squared() < 0.01:
		var from_shell := global_position - shell.global_position
		from_shell.y = 0.0
		angle = atan2(from_shell.z, from_shell.x)
	var approach_radius := maxf(3.0, attack_range * 0.8)
	var approach := shell.global_position + Vector3(cos(angle), 0.0, sin(angle)) * approach_radius
	approach.y = global_position.y
	if game != null and game.has_method("clamp_to_arena"):
		approach = game.clamp_to_arena(approach)
	if navigation_agent != null:
		var nav_map := navigation_agent.get_navigation_map()
		if nav_map.is_valid():
			var snapped_point := NavigationServer3D.map_get_closest_point(nav_map, approach)
			if snapped_point != Vector3.ZERO:
				approach = Vector3(snapped_point.x, global_position.y, snapped_point.z)
	return approach


func _crystal_approach_point(crystal: Node3D) -> Vector3:
	var approach_direction := Vector2(ai_offset.x, ai_offset.z)
	if approach_direction.length_squared() < 0.01:
		approach_direction = Vector2(global_position.x - crystal.global_position.x, global_position.z - crystal.global_position.z)
	if approach_direction.length_squared() < 0.01:
		approach_direction = Vector2.RIGHT
	approach_direction = approach_direction.normalized()
	var approach := crystal.global_position + Vector3(approach_direction.x, 0.0, approach_direction.y) * 2.4
	approach.y = global_position.y
	if navigation_agent != null:
		var nav_map := navigation_agent.get_navigation_map()
		if nav_map.is_valid():
			var snapped_point := NavigationServer3D.map_get_closest_point(nav_map, approach)
			if Vector2(snapped_point.x - crystal.global_position.x, snapped_point.z - crystal.global_position.z).length() <= 3.0:
				approach = Vector3(snapped_point.x, global_position.y, snapped_point.z)
	return approach


func _base_spawn_position() -> Vector3:
	var base_z := BASE_POSITION_Z if team == 0 else -BASE_POSITION_Z
	var safe_x := clampf(ai_offset.x, -2.0, 2.0)
	var spawn_position := Vector3(safe_x, 0.0, base_z)
	return game.clamp_to_arena(spawn_position) if game != null and game.has_method("clamp_to_arena") else spawn_position


func _try_auto_attack(movement_direction: Vector3) -> void:
	if attack_cd > 0.0:
		return
	if game == null:
		return
	var target := _attack_target()
	if target == null:
		return
	var d := global_position.distance_to(target.global_position)
	if d > attack_range:
		return
	var target_direction := target.global_position - global_position
	target_direction.y = 0.0
	if target_direction.length_squared() < 0.001:
		return
	target_direction = target_direction.normalized()
	if _facing_direction().dot(target_direction) < 0.0:
		return
	var planar_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var moving := movement_direction.length_squared() > 0.01 or planar_velocity.length() > 0.65
	if not moving:
		_face(target_direction, 1.0)
	_break_bush_stealth()
	attack_cd = attack_interval / attack_speed_multiplier
	attack_anim_time = attack_animation_duration
	if is_player and game != null and bool(game.get("network_play")):
		var network_target_id := int(target.peer_id) if "peer_id" in target else 0
		NetworkManager.send_attack("auto", network_target_id)
	_play_anim("attack", true)
	_play_weapon_attack_animation()
	_play_class_attack_sfx()
	var guaranteed_crit_multiplier := crit_buff_multiplier if crit_buff else 1.0
	var damage := roll_direct_damage(attack_damage * get_blessing_damage_multiplier(), guaranteed_crit_multiplier)
	if crit_buff:
		crit_buff = false
		crit_buff_timer = 0.0
		crit_buff_multiplier = 2.0
		if crit_buff_ring != null:
			crit_buff_ring.visible = false
	if ranged:
		var color: Color = CLASS_DATA[hero_class]["color"]
		game.spawn_projectile(global_position + Vector3(0.0, 1.2, 0.0), target, damage, color, self)
		var cast_position := global_position + Vector3(0.0, 0.6, 0.0)
		if weapon_attachment != null and is_instance_valid(weapon_attachment):
			cast_position = weapon_attachment.global_position - Vector3(0.0, 0.6, 0.0)
		cast_position += _facing_direction() * 0.35
		if hero_class == Cls.FAIRY:
			spawn_vfx_silent(VFX_HIT_02_SCENE, cast_position, 0.5)
		elif hero_class == Cls.MAGE:
			spawn_vfx_silent(VFX_GOLDEN_SCENE, cast_position, 0.6)
	else:
		target.take_damage(damage, self, "physical", "auto")
		spawn_attack_impact_vfx(target.global_position + Vector3(0.0, 0.9, 0.0))
		game.melee_fx(global_position + Vector3(0.0, 1.0, 0.0), target.global_position)


func _attack_target() -> Node3D:
	if game == null:
		return null
	var best_enemy: HeroUnit = null
	var best_health := INF
	var best_distance := INF
	var attackable_enemies: Array = game.enemies_of(team, self)
	for candidate in attackable_enemies:
		var enemy := candidate as HeroUnit
		if enemy == null:
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance > attack_range:
			continue
		var direction_to_enemy := enemy.global_position - global_position
		direction_to_enemy.y = 0.0
		if _facing_direction().dot(direction_to_enemy.normalized()) < 0.0:
			continue
		if enemy.health < best_health or (is_equal_approx(enemy.health, best_health) and distance < best_distance):
			best_enemy = enemy
			best_health = enemy.health
			best_distance = distance
	if best_enemy != null:
		return best_enemy
	if game.has_method("network_attack_target"):
		var network_target: Node3D = game.call("network_attack_target", global_position, team, attack_range, _facing_direction())
		if network_target != null:
			return network_target
	var shell_target: SkyShell = game.shell
	if shell_target != null and is_instance_valid(shell_target) and shell_target.alive:
		var direction_to_shell := shell_target.global_position - global_position
		direction_to_shell.y = 0.0
		if global_position.distance_to(shell_target.global_position) <= attack_range and _facing_direction().dot(direction_to_shell.normalized()) >= 0.0:
			return shell_target
	return null

func _face(dir: Vector3, _delta: float) -> void:
	if dir.length_squared() < 0.001:
		return
	var local_dir := global_transform.basis.inverse() * dir
	local_dir.y = 0.0
	if local_dir.length_squared() < 0.001:
		return
	var target_y := atan2(local_dir.x, local_dir.z) + PI
	visual.rotation.y = target_y


func _facing_direction() -> Vector3:
	var direction := -visual.global_transform.basis.z
	direction.y = 0.0
	return direction.normalized()


func _update_look(_delta: float) -> void:
	_update_health_display()
	if health_fill == null:
		return
	if lightning_storm_timer > 0.0:
		if current_anim != "cast" or (anim_player != null and not anim_player.is_playing()):
			_play_anim("cast", true)
		return
	if crit_cast_timer > 0.0:
		if current_anim != "cast" or (anim_player != null and not anim_player.is_playing()):
			_play_anim("cast", true)
		return
	if carry_light != null:
		carry_light.light_energy = 2.0 if carrying else 0.0
	if visual != null and visual.visible:
		var horizontal := Vector2(velocity.x, velocity.z).length()
		if not dead:
			if horizontal > move_speed * 0.55:
				_play_anim("run")
			elif horizontal > 0.4:
				_play_anim("walk")
			elif attack_anim_time <= 0.0:
				_play_anim("idle")


func set_bush_presence(zone: Area3D, inside: bool) -> void:
	if inside:
		if not bush_zones.has(zone):
			bush_zones.append(zone)
	else:
		bush_zones.erase(zone)
	in_bush = not bush_zones.is_empty()
	_refresh_bush_visibility()


func _break_bush_stealth() -> void:
	if not in_bush:
		return
	bush_reveal_timer = BUSH_REVEAL_DURATION
	seconds_since_damage = 0.0
	_refresh_bush_visibility()


func _is_offensive_ability(ability_type: String) -> bool:
	return ability_type in ["shadow_assassin", "fear_ult", "root", "ult_lightning_storm", "stun_shot", "crit_shot"]


func _is_bush_stealthed() -> bool:
	return in_bush and bush_reveal_timer <= 0.0


func _is_at_own_base() -> bool:
	var base_z := BASE_POSITION_Z if team == 0 else -BASE_POSITION_Z
	return Vector2(global_position.x, global_position.z - base_z).length() <= BASE_REGEN_RADIUS


func _is_under_base_shield() -> bool:
	var base_z := BASE_POSITION_Z if team == 0 else -BASE_POSITION_Z
	return Vector2(global_position.x, global_position.z - base_z).length() <= BASE_SHIELD_RADIUS


func _update_shop_proximity(_delta: float) -> void:
	if not is_player or afk_active or game == null:
		return
	if dead or game.state != "live":
		game.set_shop_open(false)
		return
	var near_shop: bool = bool(game.call("is_hero_near_shop", self))
	if near_shop != in_shop_zone:
		set_shop_zone_presence(near_shop)
	if not in_shop_zone:
		game.set_shop_open(false)
		return
	if bool(game.get("tutorial_mode")):
		var tutorial_controller := game.get("tutorial_controller") as Node
		if tutorial_controller == null or String(tutorial_controller.get("stage")) != "buy_item":
			game.set_shop_open(false)
			return
	if shop_manual_dismissed:
		game.set_shop_open(false)
		return
	game.set_shop_open(seconds_since_damage >= 5.0)


func set_shop_zone_presence(inside: bool) -> void:
	if inside and not in_shop_zone:
		shop_manual_dismissed = false
	elif not inside:
		shop_manual_dismissed = false
	in_shop_zone = inside
	if inside:
		return
	if is_player and game != null:
		game.set_shop_open(false)


func dismiss_shop() -> void:
	shop_manual_dismissed = true
	if is_player and game != null:
		game.set_shop_open(false)


func _refresh_bush_visibility() -> void:
	var hidden_now := _is_bush_stealthed()
	if hidden_now == bush_visual_hidden:
		return
	bush_visual_hidden = hidden_now
	var stack: Array[Node] = []
	if visual != null:
		stack.append(visual)
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is GeometryInstance3D:
			(current as GeometryInstance3D).transparency = 0.5 if hidden_now else 0.0
		for child in current.get_children():
			stack.append(child)
	if health_label != null:
		health_label.visible = _health_bar_visible()
	if health_back != null:
		health_back.visible = _health_bar_visible()
	if health_fill != null:
		health_fill.visible = _health_bar_visible()


func _health_bar_visible() -> bool:
	return not dead and not occluded_from_player


func is_hidden_from(observer: HeroUnit) -> bool:
	if not _is_bush_stealthed() or observer == null or observer.team == team:
		return false
	for zone in bush_zones:
		if observer.bush_zones.has(zone):
			return false
	return true


func set_occluded_from_player(occluded: bool) -> void:
	if occluded_from_player == occluded:
		return
	occluded_from_player = occluded
	if visual != null:
		visual.visible = not dead and not occluded_from_player
	_update_health_display()


func is_within_view_distance(observer: HeroUnit, view_radius: float) -> bool:
	if observer == null or not is_instance_valid(observer):
		return false
	var offset := Vector2(global_position.x - observer.global_position.x, global_position.z - observer.global_position.z)
	return offset.length_squared() <= view_radius * view_radius


func is_visible_to_player(_observer: HeroUnit) -> bool:
	return not dead and not occluded_from_player

func _update_health_display() -> void:
	var displayed_max := maxi(1, roundi(max_health))
	var displayed_health := clampi(roundi(health), 0, displayed_max)
	var hp_ratio := float(displayed_health) / float(displayed_max)
	if health_label != null:
		health_label.text = "%d" % displayed_health
		health_label.visible = _health_bar_visible()
	if health_fill != null:
		var fill_quad := health_fill.mesh as QuadMesh
		if fill_quad != null:
			fill_quad.size.x = HEALTH_BAR_FILL_WIDTH * hp_ratio
			health_fill.scale = Vector3.ONE
			health_fill.position.x = -(HEALTH_BAR_FILL_WIDTH - HEALTH_BAR_FILL_WIDTH * hp_ratio) * 0.5
			health_fill.visible = _health_bar_visible()
	if health_back != null:
		health_back.visible = _health_bar_visible()




func apply_network_damage(amount: float) -> void:
	if dead:
		return
	if is_player and amount > 0.0:
		Haptics.vibrate(50)
	health = clampf(health - maxf(amount, 0.0), 0.0, max_health)
	seconds_since_damage = 0.0
	_update_health_display()
	if is_player and game != null and game.hud != null:
		game.hud.call("flash_damage", clampf(0.22 + maxf(amount, 0.0) / 260.0, 0.22, 0.6))
	if game != null and game.has_method("damage_number"):
		game.call("damage_number", global_position + Vector3(0.0, 2.0, 0.0), amount, team)
	if health <= 0.0:
		_die()


func apply_network_heal(amount: float) -> void:
	if dead:
		return
	health = clampf(health + maxf(amount, 0.0), 0.0, max_health)
	_update_health_display()
	if game != null and game.has_method("heal_number"):
		game.call("heal_number", global_position + Vector3(0.0, 2.2, 0.0), amount)


func take_damage(amount: float, source: Node = null, damage_type: String = "physical", _skill: String = "") -> void:
	if dead or _is_under_base_shield():
		return
	if game != null and bool(game.get("tutorial_mode")) and is_player:
		return
	if game != null and bool(game.get("tutorial_mode")) and tutorial_dummy:
		var dummy_source_multiplier := HERO_OUTGOING_DAMAGE_MULTIPLIER if source is HeroUnit else 1.0
		health = maxf(1.0, health - maxf(amount, 0.0) * dummy_source_multiplier)
		_update_health_display()
		return
	if amount > 0.0:
		seconds_since_damage = 0.0
		if is_player and game != null:
			shop_manual_dismissed = false
			game.set_shop_open(false)
	var reduction := damage_reduction if damage_type == "physical" else 0.0
	var source_multiplier := HERO_OUTGOING_DAMAGE_MULTIPLIER if source is HeroUnit else 1.0
	var final_damage := maxf(amount, 0.0) * source_multiplier * (1.0 - reduction)
	if is_player and final_damage > 0.0:
		Haptics.vibrate(50)
	var applied_damage := minf(final_damage, health)
	health = clampf(health - final_damage, 0.0, max_health)
	_update_health_display()
	if is_player and game != null and game.hud != null:
		game.hud.call("flash_damage", clampf(0.22 + applied_damage / 260.0, 0.22, 0.6))
	if game != null and game.has_method("record_hero_damage"):
		game.record_hero_damage(self, source, applied_damage, health <= 0.0)
	if game != null and game.has_method("damage_number"):
		game.damage_number(global_position + Vector3(0.0, 2.0, 0.0), final_damage, team)
	if source is HeroUnit:
		var source_hero := source as HeroUnit
		if applied_damage > 0.0:
			source_hero._play_class_hit_sfx()
		(source as HeroUnit).on_damage_dealt(applied_damage)
	if health <= 0.0:
		_die()


func heal(amount: float) -> void:
	if dead:
		return
	health = clampf(health + maxf(amount, 0.0), 0.0, max_health)
	_update_health_display()
	if game != null and game.has_method("heal_number"):
		game.heal_number(global_position + Vector3(0.0, 2.2, 0.0), amount)
	if is_player and game != null and bool(game.get("network_play")):
		NetworkManager.send_stats(max_health, health, attack_damage)


func on_damage_dealt(amount: float) -> void:
	if amount > 0.0 and lifesteal_fraction > 0.0:
		heal(amount * lifesteal_fraction)


func apply_shop_item(item_id: String) -> bool:
	match item_id:
		"life_amulet":
			max_health += 150.0
			health = minf(max_health, health + 150.0)
		"revival_talisman":
			bonus_regen_per_second += 10.0
		"titan_shell":
			damage_reduction = minf(0.85, damage_reduction + 0.15)
		"power_glove":
			attack_damage += 25.0
		"vampire_fang":
			lifesteal_fraction += 0.15
		"agility_mark":
			attack_speed_multiplier *= 1.2
		"wind_boots":
			move_speed *= 1.15
		"hourglass":
			cooldown_reduction = minf(0.85, cooldown_reduction + 0.15)
		"cleansing_charm":
			stun_duration_reduction = minf(0.85, stun_duration_reduction + 0.2)
		_:
			return false
	_update_health_display()
	if is_player and game != null and bool(game.get("network_play")):
		NetworkManager.send_stats(max_health, health, attack_damage)
	return true


func stun(duration: float) -> void:
	if dead:
		return
	stun_timer = maxf(stun_timer, maxf(0.0, duration) * (1.0 - stun_duration_reduction))


func apply_slow(factor: float, duration: float) -> void:
	if dead or duration <= 0.0:
		return
	if slow_timer <= 0.0 or factor >= slow_factor:
		slow_factor = clampf(factor, 0.0, 0.8)
	slow_timer = maxf(slow_timer, duration)


func _die() -> void:
	dead = true
	if is_player:
		Haptics.vibrate(200)
	lightning_storm_timer = 0.0
	lightning_storm_tick_timer = 0.0
	if lightning_storm_ring != null:
		lightning_storm_ring.visible = false
	crit_cast_timer = 0.0
	crit_cast_target = null
	_stop_crit_cast_visuals()
	respawn_timer = game.respawn_delay_for(self) if game != null and game.has_method("respawn_delay_for") else 8.0
	velocity = Vector3.ZERO
	carrying = false
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 0.0
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	visual.visible = false
	if health_label != null:
		health_label.visible = false
	if afk_label != null:
		afk_label.visible = false
	bush_zones.clear()
	in_bush = false
	set_shop_zone_presence(false)
	_refresh_bush_visibility()
	if health_back != null:
		health_back.visible = false
	if health_fill != null:
		health_fill.visible = false
	if game != null:
		game.on_hero_died(self)
	hero_died.emit(self)


func _respawn() -> void:
	dead = false
	health = max_health
	seconds_since_damage = 0.0
	_update_health_display()
	global_position = _base_spawn_position() + Vector3(0.0, 0.76, 0.0)
	velocity = Vector3.ZERO
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	visual.visible = not occluded_from_player
	current_anim = ""
	if health_back != null:
		health_back.visible = _health_bar_visible()
	if health_fill != null:
		health_fill.visible = _health_bar_visible()
	if health_label != null:
		health_label.visible = _health_bar_visible()
	if afk_label != null:
		afk_label.visible = afk_active
	if game != null:
		game.on_hero_respawned(self)


func use_ability(index: int, manual := true) -> bool:
	if is_player and manual:
		notify_player_input()
	if dead or stun_timer > 0.0 or lightning_storm_timer > 0.0:
		return false
	if index < 0 or index >= 3:
		return false
	if ability_cds[index] > 0.0:
		return false
	if crit_cast_timer > 0.0:
		return false
	if game == null:
		return false
	if bool(game.get("tutorial_mode")) and is_player:
		var tutorial_controller := game.get("tutorial_controller") as Node
		if tutorial_controller == null or not bool(tutorial_controller.call("can_use_ability", index)):
			return false
	var data: Dictionary = CLASS_DATA[hero_class]["abilities"][index]
	var ability_type := String(data["type"])
	if _is_offensive_ability(ability_type):
		_break_bush_stealth()
	var bot_cooldown_multiplier := BOT_ABILITY_COOLDOWN_MULTIPLIER if not is_player else 1.0
	ability_cds[index] = float(data["cd"]) * (1.0 - cooldown_reduction) * bot_cooldown_multiplier
	cast_flash = 0.35
	_play_anim("cast")
	var color: Color = CLASS_DATA[hero_class]["color"]
	var origin := global_position
	match ability_type:
		"shadow_assassin":
			var target: Node3D = game.nearest_enemy(origin, team, 8.0, self)
			if target == null and game.has_method("network_nearest_enemy"):
				target = game.call("network_nearest_enemy", origin, team, 8.0)
			if target == null:
				ability_cds[index] = 0.0
				return false
			var offset := global_position - target.global_position
			offset.y = 0.0
			if offset.length_squared() < 0.001:
				offset = -_facing_direction()
			global_position = game.clamp_to_arena(target.global_position + offset.normalized() * 1.2)
			var hit_position := global_position
			target.take_damage(roll_direct_damage(attack_damage * get_blessing_damage_multiplier()), self, "physical", "shadow_assassin")
			if target.has_method("stun"):
				target.stun(1.0)
			spawn_ability_vfx(0, target.global_position)
			game.dash_fx(origin, hit_position, color)
		"crit_shot":
			var crit_target := _crit_shot_target()
			if crit_target == null:
				ability_cds[index] = 0.0
				return false
			crit_cast_target = crit_target
			crit_cast_timer = FAIRY_CRIT_CAST_TIME
			velocity.x = 0.0
			velocity.z = 0.0
			_begin_crit_cast_visuals()
			game.burst(origin + Vector3(0.0, 1.2, 0.0), CRIT_CAST_COLOR, 12)
		"crit_buff":
			crit_buff = true
			crit_buff_timer = 3.0
			crit_buff_multiplier = 3.0 if hero_class == Cls.FAIRY else 2.0
			_set_crit_buff_ring(true)
			spawn_ability_vfx(1, origin + Vector3(0.0, 0.4, 0.0))
			game.burst(origin, color, 16)
		"fear_ult":
			_play_combat_sfx("ultimate", WARRIOR_ULT_SOUND, -7.0)
			spawn_ability_vfx(2, origin)
			for enemy in game.enemies_in_radius(origin, WARRIOR_ULT_RADIUS, team, self):
				enemy.take_damage(roll_direct_damage(_outgoing_damage(60.0) * get_blessing_damage_multiplier()), self, "magic")
				enemy.stun(1.5)
			if is_player and game.has_method("network_enemies_in_radius"):
				for remote_enemy in game.call("network_enemies_in_radius", origin, WARRIOR_ULT_RADIUS, team):
					if remote_enemy == null or not is_instance_valid(remote_enemy):
						continue
					remote_enemy.take_damage(roll_direct_damage(_outgoing_damage(60.0) * get_blessing_damage_multiplier()), self, "magic", "fear_ult")
					if remote_enemy.has_method("stun"):
						remote_enemy.stun(1.5)
			game.fear_pulse_fx(origin, WARRIOR_ULT_RADIUS, color)
			game.earthquake_fx(origin, WARRIOR_ULT_RADIUS, 1.5)
		"root":
			var fwd: Vector3 = _facing_direction()
			var proj_pos := origin + Vector3(0.0, 1.2, 0.0)
			var root_target: Node3D = game.nearest_enemy(proj_pos, team, 10.0, self)
			if root_target == null and game.has_method("network_nearest_enemy"):
				root_target = game.call("network_nearest_enemy", proj_pos, team, 10.0)
			if root_target != null:
				game.spawn_projectile(proj_pos, root_target, roll_direct_damage(_outgoing_damage(20.0) * get_blessing_damage_multiplier()), color, self, 2.0, "magic", "root")
			game.burst(proj_pos, color, 14)
		"heal":
			spawn_ability_vfx(1, origin)
			game.heal_area(origin, 10.0, float(randi_range(100, 300)), team, 6, self)
			game.burst(origin, Color(0.65, 1.0, 0.75), 18)
		"ult_lightning_storm":
			lightning_storm_timer = MAGE_STORM_DURATION
			lightning_storm_tick_timer = 1.0
			velocity = Vector3.ZERO
			_set_lightning_storm_ring(true)
			game.burst(origin, Color(0.35, 0.78, 1.0), 28)
		"stun_shot":
			var target2: Node3D = game.nearest_enemy(origin, team, 14.0, self)
			if target2 == null and game.has_method("network_nearest_enemy"):
				target2 = game.call("network_nearest_enemy", origin, team, 14.0)
			if target2 != null:
				game.spawn_projectile(origin + Vector3(0.0, 1.3, 0.0), target2, roll_direct_damage(_outgoing_damage(40.0) * get_blessing_damage_multiplier()), color, self, 1.5, "physical", "stun")
			game.burst(origin, color, 10)
		"golden_blessing":
			game.bless_team(team, float(data["cd"]))
			game.golden_blessing_fx(origin, team, self)
			for enemy in game.enemies_in_radius(origin, FAIRY_ULT_RADIUS, team, self):
				enemy.take_damage(roll_direct_damage(_outgoing_damage(FAIRY_ULT_DAMAGE) * get_blessing_damage_multiplier()), self, "magic", "fairy_ult")
				enemy.apply_slow(FAIRY_ULT_SLOW, FAIRY_ULT_SLOW_DURATION)
			if is_player and game.has_method("network_enemies_in_radius"):
				for remote_enemy in game.call("network_enemies_in_radius", origin, FAIRY_ULT_RADIUS, team):
					if remote_enemy == null or not is_instance_valid(remote_enemy):
						continue
					remote_enemy.take_damage(roll_direct_damage(_outgoing_damage(FAIRY_ULT_DAMAGE) * get_blessing_damage_multiplier()), self, "magic", "fairy_ult")
					if remote_enemy.has_method("apply_slow"):
						remote_enemy.apply_slow(FAIRY_ULT_SLOW, FAIRY_ULT_SLOW_DURATION)
			game.fairy_ult_burst_fx(origin, FAIRY_ULT_RADIUS, color)
	if is_player and manual:
		_play_ability_sfx(index)
	if is_player and manual and game != null and bool(game.get("network_play")):
		NetworkManager.send_attack(ability_type)
	if bool(game.get("tutorial_mode")) and is_player:
		var tutorial_controller := game.get("tutorial_controller") as Node
		if tutorial_controller != null:
			tutorial_controller.call("on_ability_used", index)
	return true


func _set_lightning_storm_ring(active: bool) -> void:
	if lightning_storm_ring == null:
		lightning_storm_ring = FxUtils.soft_ground_glow(MAGE_STORM_RADIUS * 2.0, Color(0.35, 0.8, 1.0, 0.75), 0.9, 0.55, 0.35)
		lightning_storm_ring.name = "LightningStormRange"
		lightning_storm_ring.position.y = 0.06
		add_child(lightning_storm_ring)
	lightning_storm_ring.visible = active


func _set_crit_buff_ring(active: bool) -> void:
	if crit_buff_ring == null:
		var ring_color := Color(1.0, 0.28, 0.2) if hero_class == Cls.WARRIOR else Color(0.72, 1.0, 0.35)
		crit_buff_ring = FxUtils.soft_ground_glow(1.9, Color(ring_color.r, ring_color.g, ring_color.b, 0.9), 0.0, 0.5)
		crit_buff_ring.name = "CriticalBuffRing"
		crit_buff_ring.position.y = GROUND_Y_OFFSET
		visual.add_child(crit_buff_ring)
	crit_buff_ring.visible = active


func _crit_shot_target() -> Node3D:
	if game == null:
		return null
	var enemy: HeroUnit = game.nearest_enemy(global_position, team, attack_range, self)
	if enemy != null:
		return enemy
	if is_player and game.has_method("network_nearest_enemy"):
		var network_enemy: Node3D = game.call("network_nearest_enemy", global_position, team, attack_range)
		if network_enemy != null:
			return network_enemy
	var shell_target: SkyShell = game.shell
	if shell_target != null and is_instance_valid(shell_target) and shell_target.alive:
		if global_position.distance_to(shell_target.global_position) <= attack_range:
			return shell_target
	return null


func _aim_crit_cast(delta: float) -> void:
	if crit_cast_target == null or not is_instance_valid(crit_cast_target):
		crit_cast_target = _crit_shot_target()
	if crit_cast_target == null:
		return
	var aim := crit_cast_target.global_position - global_position
	aim.y = 0.0
	if aim.length_squared() > 0.001:
		_face(aim.normalized(), delta)


func _begin_crit_cast_visuals() -> void:
	_stop_crit_cast_visuals()
	if weapon_instance == null or not is_instance_valid(weapon_instance):
		return
	for child in weapon_instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if mesh_node.material_override is StandardMaterial3D:
			var original := mesh_node.material_override as StandardMaterial3D
			var override_tint := original.duplicate() as StandardMaterial3D
			_apply_crit_cast_material(override_tint)
			mesh_node.material_override = override_tint
			crit_cast_material_restores.append({"node": mesh_node, "surface": -1, "original": original})
			continue
		for surface in range(mesh_node.mesh.get_surface_count()):
			var active := mesh_node.get_active_material(surface)
			if active is StandardMaterial3D:
				var tinted := (active as StandardMaterial3D).duplicate() as StandardMaterial3D
				_apply_crit_cast_material(tinted)
				mesh_node.set_surface_override_material(surface, tinted)
				crit_cast_material_restores.append({"node": mesh_node, "surface": surface, "original": null})
	for child in weapon_instance.find_children("*", "CPUParticles3D", true, false):
		var existing := child as CPUParticles3D
		if existing == null:
			continue
		crit_cast_particle_restores.append({"node": existing, "emitting": existing.emitting})
		existing.emitting = false
	_build_crit_cast_particles()
	var light := OmniLight3D.new()
	light.name = "CritCastLight"
	light.position = Vector3(0.0, 0.0, 0.18)
	light.light_color = CRIT_CAST_COLOR
	light.light_energy = 1.7
	light.omni_range = 3.2
	light.shadow_enabled = false
	weapon_instance.add_child(light)
	crit_cast_light = light


func _apply_crit_cast_material(material: StandardMaterial3D) -> void:
	material.emission_enabled = true
	material.emission = CRIT_CAST_COLOR
	material.emission_energy_multiplier = 2.2


func _build_crit_cast_particles() -> void:
	var particles := CPUParticles3D.new()
	particles.name = "CritCastSparks"
	particles.position = Vector3(0.0, 0.0, 0.38)
	particles.amount = 26
	particles.lifetime = 0.5
	particles.fixed_fps = 30
	particles.local_coords = true
	particles.preprocess = 0.25
	particles.visibility_range_end = 18.0
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.direction = Vector3(0.0, 0.0, -1.0)
	particles.spread = 180.0
	particles.initial_velocity_min = 0.2
	particles.initial_velocity_max = 0.65
	particles.radial_accel_min = -2.6
	particles.radial_accel_max = -1.8
	particles.damping_min = 0.3
	particles.damping_max = 0.8
	particles.gravity = Vector3.ZERO
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	particles.color = CRIT_CAST_COLOR
	particles.color_ramp = _weapon_spark_fade()
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.16
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	particles.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = _weapon_glow_texture()
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	particles.material_override = material
	particles.emitting = true
	weapon_instance.add_child(particles)
	crit_cast_particles = particles


func _update_crit_cast_visuals() -> void:
	var energy := 2.0 + sin(float(Time.get_ticks_msec()) * 0.02) * 0.8
	for entry in crit_cast_material_restores:
		var mesh_node := entry["node"] as MeshInstance3D
		if mesh_node == null or not is_instance_valid(mesh_node):
			continue
		var surface := int(entry["surface"])
		var material: StandardMaterial3D = null
		if surface < 0:
			material = mesh_node.material_override as StandardMaterial3D
		else:
			material = mesh_node.get_surface_override_material(surface) as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = energy
	if crit_cast_light != null and is_instance_valid(crit_cast_light):
		crit_cast_light.light_energy = 1.1 + energy * 0.5


func _stop_crit_cast_visuals() -> void:
	for entry in crit_cast_material_restores:
		var mesh_node := entry["node"] as MeshInstance3D
		if mesh_node == null or not is_instance_valid(mesh_node):
			continue
		var surface := int(entry["surface"])
		if surface < 0:
			mesh_node.material_override = entry["original"]
		else:
			mesh_node.set_surface_override_material(surface, null)
	crit_cast_material_restores.clear()
	for entry in crit_cast_particle_restores:
		var existing := entry["node"] as CPUParticles3D
		if existing != null and is_instance_valid(existing):
			existing.emitting = bool(entry["emitting"])
	crit_cast_particle_restores.clear()
	if crit_cast_particles != null and is_instance_valid(crit_cast_particles):
		crit_cast_particles.queue_free()
		crit_cast_particles = null
	if crit_cast_light != null and is_instance_valid(crit_cast_light):
		crit_cast_light.queue_free()
		crit_cast_light = null


func _release_crit_shot() -> void:
	crit_cast_timer = 0.0
	var target := crit_cast_target
	crit_cast_target = null
	_stop_crit_cast_visuals()
	if game == null:
		return
	if target == null or not is_instance_valid(target) or (target is HeroUnit and (target as HeroUnit).dead):
		target = _crit_shot_target()
	if target == null:
		return
	var aim := target.global_position - global_position
	aim.y = 0.0
	if aim.length_squared() > 0.001:
		_face(aim.normalized(), 1.0)
	attack_cd = attack_interval / attack_speed_multiplier
	attack_anim_time = attack_animation_duration
	_play_anim("attack", true)
	_play_weapon_attack_animation()
	_play_class_attack_sfx()
	var color: Color = CLASS_DATA[hero_class]["color"]
	var damage := roll_direct_damage(attack_damage * get_blessing_damage_multiplier(), FAIRY_CRIT_MULTIPLIER)
	game.spawn_projectile(global_position + Vector3(0.0, 1.2, 0.0), target, damage, color, self)
	var cast_position := global_position + Vector3(0.0, 0.6, 0.0)
	if weapon_attachment != null and is_instance_valid(weapon_attachment):
		cast_position = weapon_attachment.global_position - Vector3(0.0, 0.6, 0.0)
	cast_position += _facing_direction() * 0.35
	spawn_vfx_silent(VFX_HIT_02_SCENE, cast_position, 0.5)
	game.burst(cast_position, CRIT_CAST_COLOR, 10)


func roll_direct_damage(amount: float, guaranteed_crit_multiplier: float = 1.0) -> float:
	if amount <= 0.0:
		return 0.0
	var rolled_damage := amount * randf_range(DIRECT_DAMAGE_MIN_MULTIPLIER, DIRECT_DAMAGE_MAX_MULTIPLIER)
	if guaranteed_crit_multiplier > 1.0:
		return rolled_damage * guaranteed_crit_multiplier
	if randf() < CRITICAL_CHANCE:
		return rolled_damage * CRITICAL_DAMAGE_MULTIPLIER
	return rolled_damage


func roll_ultimate_damage(amount: float) -> float:
	return maxf(amount, 0.0) * randf_range(DIRECT_DAMAGE_MIN_MULTIPLIER, DIRECT_DAMAGE_MAX_MULTIPLIER)


func _outgoing_damage(amount: float) -> float:
	return amount * BOT_DAMAGE_MULTIPLIER if not is_player else amount


func ability_data(index: int) -> Dictionary:
	return CLASS_DATA[hero_class]["abilities"][index]


func get_blessing_damage_multiplier() -> float:
	return 1.1 if blessing_timer > 0.0 else 1.0


func apply_blessing(duration: float, source_team: int = -1) -> void:
	if dead or duration <= 0.0:
		return
	if source_team >= 0 and team != source_team:
		return
	blessing_timer = maxf(blessing_timer, duration)
	if blessing_ring != null and is_instance_valid(blessing_ring):
		return
	var root := Node3D.new()
	root.name = "GoldenBlessingRing"
	root.position = Vector3(0.0, 0.05, 0.0)
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(1.0, 0.72, 0.2)
	glow.light_energy = 2.2
	glow.omni_range = 4.0
	glow.position = Vector3(0.0, 0.6, 0.0)
	root.add_child(glow)
	var rune := MeshInstance3D.new()
	rune.name = "BlessingRune"
	var rune_mesh := QuadMesh.new()
	rune_mesh.size = Vector2(2.8, 2.8)
	rune.mesh = rune_mesh
	var rune_material := StandardMaterial3D.new()
	rune_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rune_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rune_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rune_material.no_depth_test = false
	rune_material.render_priority = 2
	rune_material.albedo_texture = preload("res://ui/fx/blessing_rune.png")
	rune_material.albedo_color = Color(1.0, 0.88, 0.48, 0.9)
	rune_material.emission_enabled = true
	rune_material.emission = Color(1.0, 0.68, 0.18)
	rune_material.emission_energy_multiplier = 1.5
	rune_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rune.material_override = rune_material
	rune.rotation_degrees.x = -90.0
	rune.position = Vector3(0.0, 0.02, 0.0)
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rune)
	blessing_rune = rune
	add_child(root)
	blessing_ring = root
	blessing_ground_timer = 0.0
	_snap_blessing_to_ground()


func _update_blessing(delta: float) -> void:
	if blessing_timer <= 0.0:
		return
	blessing_timer = maxf(0.0, blessing_timer - delta)
	if blessing_ring != null and is_instance_valid(blessing_ring):
		blessing_ground_timer -= delta
		if blessing_ground_timer <= 0.0:
			blessing_ground_timer = 0.25
			_snap_blessing_to_ground()
		blessing_ring.scale = Vector3.ONE
	if blessing_rune != null and is_instance_valid(blessing_rune):
		blessing_rune.rotation.y += delta * 0.35
	if blessing_timer == 0.0 and blessing_ring != null:
		blessing_ring.queue_free()
		blessing_ring = null
		blessing_rune = null
		blessing_ground_timer = 0.0


func _snap_blessing_to_ground() -> void:
	if blessing_ring == null or not is_instance_valid(blessing_ring):
		return
	var target_y := global_position.y + 0.05
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0.0, 3.0, 0.0),
			global_position + Vector3(0.0, -3.0, 0.0),
			0xFFFFFFFF,
			[get_rid()]
		)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			target_y = float(hit["position"].y) + 0.06
	blessing_ring.global_position = Vector3(global_position.x, target_y, global_position.z)


func ability_ready(index: int) -> bool:
	return ability_cds[index] <= 0.01
