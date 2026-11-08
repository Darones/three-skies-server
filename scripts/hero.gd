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
const UI_FONT := preload("res://assets/fonts/Philosopher-Regular.ttf")
const WARRIOR_SWING_SOUNDS := [
	preload("res://assets/audio/Soundza_Game_SFX_Pack/swords_melee/sword_slash.wav"),
	preload("res://assets/audio/Soundza_Game_SFX_Pack/swords_melee/weapon_swing_1.wav"),
	preload("res://assets/audio/Soundza_Game_SFX_Pack/swords_melee/sword_attack_3.wav"),
]
const WARRIOR_HIT_SOUNDS := [
	preload("res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_industrial_impact.wav"),
	preload("res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_punch_impact.wav"),
	preload("res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/cinematic_impact_hit.wav"),
]
const MAGE_ATTACK_SOUNDS := [
	preload("res://assets/audio/Soundza_Game_SFX_Pack/magic/sparkle_magic_spell.wav"),
	preload("res://assets/audio/Soundza_Game_SFX_Pack/magic/spell_2.wav"),
]
const FAIRY_ATTACK_SOUNDS := [
	preload("res://assets/audio/Soundza_Game_SFX_Pack/whooshes_swings/fast_air_whoosh.wav"),
	preload("res://assets/audio/Soundza_Game_SFX_Pack/whooshes_swings/quick_air_whoosh.wav"),
]
const WARRIOR_ULT_SOUND := [
	preload("res://assets/audio/Soundza_Game_SFX_Pack/explosions/fireball_explosion.wav"),
]
const VFX_HIT_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_01.tscn")
const VFX_HIT_02_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_02.tscn")
const VFX_BIG_IMPACT_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn")
const VFX_BIG_IMPACT_02_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_02.tscn")
const VFX_LIGHTNING_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_01.tscn")
const VFX_GOLDEN_SCENE: PackedScene = preload("res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_02.tscn")
const VFX_HIT_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_punch_impact.wav")
const VFX_BIG_IMPACT_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/explosions/fireball_explosion.wav")
const VFX_LIGHTNING_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/magic/spell_2.wav")
const VFX_GOLDEN_SOUND: AudioStream = preload("res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/synth_power_up_ascending.wav")
const MAGE_STORM_DURATION := 5.0
const MAGE_STORM_RADIUS := 10.0
const WARRIOR_ULT_RADIUS := 8.0
const MAGE_STORM_DAMAGE := 100.0

const CLASS_DATA := {
	Cls.WARRIOR: {
		"name": "Воин",
		"title": "Воин Света",
		"hp": 550.0,
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
		"hp": 500.0,
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
		"hp": 450.0,
		"speed": 4.5,
		"range": 11.0,
		"damage": 30.0,
		"interval": 0.75,
		"ranged": true,
		"color": Color(0.72, 0.95, 0.55),
		"abilities": [
			{"name": "Оглушающий выстрел", "cd": 12.0, "type": "stun_shot"},
			{"name": "100% Крит", "cd": 15.0, "type": "crit_buff"},
			{"name": "Золотое благословение", "cd": 24.0, "type": "golden_blessing"},
		],
	},
}

var game: Node = null
var team := 0
var hero_class: int = Cls.WARRIOR
var is_player := false
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
var bot_gold := 0
var match_coins_collected := 0
var match_gold_spent := 0
var bot_purchased_shop_items: Array[String] = []
var stun_timer := 0.0
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
var blessing_timer := 0.0
var blessing_ring: MeshInstance3D = null

var ai_goal := Vector3.ZERO
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
	_build_body()
	_build_visual()
	update_wings()
	_update_health_display()


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

	var wing_color := Color(0.92, 0.95, 1.0, 0.78)
	var emission_color := Color(0.82, 0.9, 1.0)
	var emission_energy := 0.35
	match wing_id:
		2:
			wing_color = Color(0.075, 0.065, 0.09, 0.92)
			emission_energy = 0.0
		3:
			wing_color = Color(0.34, 0.025, 0.055, 0.84)
			emission_color = Color(1.0, 0.025, 0.045)
			emission_energy = 2.2
		4:
			wing_color = Color(0.95, 0.62, 0.08, 0.86)
			emission_color = Color(1.0, 0.67, 0.12)
			emission_energy = 2.5

	var wing_material := StandardMaterial3D.new()
	wing_material.albedo_color = wing_color
	wing_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wing_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission_energy > 0.0:
		wing_material.emission_enabled = true
		wing_material.emission = emission_color
		wing_material.emission_energy_multiplier = emission_energy
	var wing_mesh := QuadMesh.new()
	wing_mesh.size = Vector2(0.66, 0.98)
	for side in [-1, 1]:
		var wing := MeshInstance3D.new()
		wing.name = "WingLeft" if side < 0 else "WingRight"
		wing.mesh = wing_mesh
		wing.material_override = wing_material
		wing.position = Vector3(float(side) * 0.31, 0.04, 0.0)
		wing.rotation_degrees = Vector3(0.0, float(side) * -12.0, float(side) * -24.0)
		wing_attachment.add_child(wing)
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
	if wing_attachment_fallback:
		wing_attachment.rotation.x = lerp(wing_attachment.rotation.x, -clampf(velocity.length() * 0.015, 0.0, 0.35), 0.15)
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

	var ring := MeshInstance3D.new()
	ring.name = "TeamRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.76
	torus.outer_radius = 0.92
	torus.rings = 40
	torus.ring_segments = 10
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	var local_player: HeroUnit = game.get("player") as HeroUnit if game != null else null
	var is_ally := is_player or (local_player != null and local_player.team == team)
	var ring_color := Color(0.18, 1.0, 0.52) if is_ally else Color(1.0, 0.2, 0.16)
	ring_mat.albedo_color = ring_color
	ring_mat.emission_enabled = true
	ring_mat.emission = ring_color
	ring_mat.emission_energy_multiplier = 2.8
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 0.12, 0.0)
	visual.add_child(ring)

	_build_health_bar()
	_build_health_label()

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
		player.max_polyphony = 1
		player.max_distance = 42.0
		player.unit_size = 8.0
		player.volume_db = -10.0
		add_child(player)
		combat_audio_players[channel] = player


func _play_combat_sfx(channel: String, sounds: Array, volume_db: float) -> void:
	var player := combat_audio_players.get(channel) as AudioStreamPlayer3D
	if player == null or player.is_playing() or sounds.is_empty():
		return
	player.stream = sounds[randi_range(0, sounds.size() - 1)] as AudioStream
	player.volume_db = volume_db
	player.play()


func _play_class_attack_sfx() -> void:
	match hero_class:
		Cls.WARRIOR:
			_play_combat_sfx("attack", WARRIOR_SWING_SOUNDS, -8.0)
		Cls.MAGE:
			_play_combat_sfx("attack", MAGE_ATTACK_SOUNDS, -11.0)
		Cls.FAIRY:
			_play_combat_sfx("attack", FAIRY_ATTACK_SOUNDS, -10.0)


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
			scene = VFX_HIT_02_SCENE
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
	light_tint: Color = Color(1.0, 0.8, 0.4)
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
	var audio_player := effect.get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if audio_player != null:
		if audio_player.stream == null:
			audio_player.stream = _vfx_audio_for_scene(vfx_scene)
		audio_player.max_polyphony = 1
		audio_player.max_distance = 42.0
		audio_player.unit_size = 8.0
		audio_player.volume_db = -12.0
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
	get_tree().create_timer(lifetime).timeout.connect(Callable(effect, "queue_free"), CONNECT_ONE_SHOT)


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


func _build_visual() -> void:
	var model := _load_model()
	if model != null:
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
			weapon_path = "res://addons/low_poly_rpg_items/props/longsword.tscn"
			weapon_scale = 0.72
			hand_offset = Vector3(0.06, 0.0, -0.12)
			weapon_rotation = Vector3(0.0, 0.0, -12.0)
		Cls.MAGE:
			weapon_path = "res://addons/low_poly_rpg_items/props/staff_wizard.tscn"
			weapon_scale = 0.62
			hand_offset = Vector3(0.04, 0.0, -0.1)
		Cls.FAIRY:
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
	if dead:
		_update_shop_proximity(delta)
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return

	seconds_since_damage = minf(5.0, seconds_since_damage + delta)
	_update_shop_proximity(delta)
	bush_reveal_timer = maxf(0.0, bush_reveal_timer - delta)
	_refresh_bush_visibility()
	if seconds_since_damage >= 5.0 and health < max_health:
		var regen_multiplier := 2.0 if (_is_bush_stealthed() or _is_at_own_base()) else 1.0
		if blessing_timer > 0.0:
			regen_multiplier *= 2.0
		health = minf(max_health, health + (HEALTH_REGEN_PER_SECOND + bonus_regen_per_second) * regen_multiplier * delta)

	stun_timer = maxf(0.0, stun_timer - delta)
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
	if not channeling_storm and stun_timer <= 0.0:
		if is_player:
			dir = _player_dir()
		else:
			dir = _ai_dir(delta)
		_try_auto_attack(dir)

	var speed := move_speed * (0.5 if carrying else 1.0)
	var target_v := dir * speed
	if channeling_storm:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var movement_acceleration := BOT_MOVE_ACCELERATION if not is_player else 40.0
		velocity.x = move_toward(velocity.x, target_v.x, movement_acceleration * delta)
		velocity.z = move_toward(velocity.z, target_v.z, movement_acceleration * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.2
	move_and_slide()
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
		global_position = _base_position() + Vector3(0.0, 0.76, 0.0)
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
		_ai_abilities()
	var to_goal := ai_goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	var dir := Vector3.ZERO
	if dist > 0.8:
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
				use_ability(1)
			elif enemy != null and dist > 2.5 and ability_ready(0):
				use_ability(0)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.5:
				use_ability(2)
		Cls.MAGE:
			var ally: HeroUnit = game.lowest_ally(global_position, team, 12.0)
			if ally != null and ally.health < ally.max_health * 0.62 and ability_ready(1):
				use_ability(1)
			elif enemy != null and dist < 7.0 and ability_ready(0):
				use_ability(0)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.4:
				use_ability(2)
		Cls.FAIRY:
			if enemy != null and dist < 14.0 and ability_ready(0):
				use_ability(0)
			elif enemy != null and dist < 10.0 and ability_ready(1):
				use_ability(1)
			elif near_shell and ability_ready(2) and game.shell != null and game.shell.health < game.shell.max_health * 0.45:
				use_ability(2)


func _ai_pick_goal() -> void:
	if game == null:
		ai_goal = Vector3.ZERO
		return
	if not ai_retreating and health <= max_health * BOT_RETREAT_START_RATIO:
		ai_retreating = true
	elif ai_retreating and health >= max_health * BOT_RETREAT_END_RATIO:
		ai_retreating = false
	var enemy: HeroUnit = game.nearest_enemy(global_position, team, 30.0, self)
	var previous_target := ai_attack_target as HeroUnit
	if previous_target != null and is_instance_valid(previous_target) and not previous_target.dead and previous_target.team != team:
		var previous_distance := global_position.distance_to(previous_target.global_position)
		var new_distance := global_position.distance_to(enemy.global_position) if enemy != null else INF
		if previous_distance < 30.0 and previous_distance <= new_distance * 1.18:
			enemy = previous_target
	ai_attack_target = enemy
	if carrying:
		ai_goal = _base_position()
		return
	if ai_retreating:
		ai_goal = _base_position()
		return
	var crystal_node: Node3D = game.crystal_node
	if game.crystal_state == "ground" and crystal_node != null and is_instance_valid(crystal_node):
		ai_goal = crystal_node.global_position
		return
	var shell = game.shell
	if shell != null and is_instance_valid(shell) and shell.alive:
		ai_goal = shell.global_position
		return
	var enemy_distance := global_position.distance_to(enemy.global_position) if enemy != null else INF
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
	if enemy != null:
		var enemy_base := Vector3(0.0, 0.0, -BASE_POSITION_Z if team == 0 else BASE_POSITION_Z)
		var goal := enemy.global_position
		var from_base := goal - enemy_base
		from_base.y = 0.0
		if from_base.length() < 9.0:
			goal = enemy_base + from_base.normalized() * 9.0
		ai_goal = goal + ai_offset
	else:
		ai_goal = Vector3(0.0, 0.0, 0.0)


func _base_position() -> Vector3:
	var z := BASE_POSITION_Z - 1.5 if team == 0 else -BASE_POSITION_Z + 1.5
	var safe_x := clampf(ai_offset.x, -2.5, 2.5)
	var base_position := Vector3(safe_x, 0.0, z)
	return game.clamp_to_arena(base_position) if game != null and game.has_method("clamp_to_arena") else base_position


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
	else:
		target.take_damage(damage, self, "physical")
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
	return ability_type in ["shadow_assassin", "fear_ult", "root", "ult_lightning_storm", "stun_shot"]


func _is_bush_stealthed() -> bool:
	return in_bush and bush_reveal_timer <= 0.0


func _is_at_own_base() -> bool:
	var base_z := BASE_POSITION_Z if team == 0 else -BASE_POSITION_Z
	return Vector2(global_position.x, global_position.z - base_z).length() <= BASE_REGEN_RADIUS


func _is_under_base_shield() -> bool:
	var base_z := BASE_POSITION_Z if team == 0 else -BASE_POSITION_Z
	return Vector2(global_position.x, global_position.z - base_z).length() <= BASE_SHIELD_RADIUS


func _update_shop_proximity(_delta: float) -> void:
	if not is_player or game == null:
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




func take_damage(amount: float, source: Node = null, damage_type: String = "physical") -> void:
	if dead or _is_under_base_shield():
		return
	if amount > 0.0:
		seconds_since_damage = 0.0
		if is_player and game != null:
			shop_manual_dismissed = false
			game.set_shop_open(false)
	var reduction := damage_reduction if damage_type == "physical" else 0.0
	var source_multiplier := HERO_OUTGOING_DAMAGE_MULTIPLIER if source is HeroUnit else 1.0
	var final_damage := maxf(amount, 0.0) * source_multiplier * (1.0 - reduction)
	var applied_damage := minf(final_damage, health)
	health = clampf(health - final_damage, 0.0, max_health)
	_update_health_display()
	if game != null and game.has_method("record_hero_damage"):
		game.record_hero_damage(self, source, applied_damage, health <= 0.0)
	if game != null and game.has_method("damage_number"):
		game.damage_number(global_position + Vector3(0.0, 2.0, 0.0), final_damage, team)
	if source is HeroUnit:
		var source_hero := source as HeroUnit
		if source_hero.hero_class == Cls.WARRIOR and applied_damage > 0.0:
			source_hero._play_combat_sfx("impact", WARRIOR_HIT_SOUNDS, -11.0)
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
	return true


func stun(duration: float) -> void:
	if dead:
		return
	stun_timer = maxf(stun_timer, maxf(0.0, duration) * (1.0 - stun_duration_reduction))


func _die() -> void:
	dead = true
	lightning_storm_timer = 0.0
	lightning_storm_tick_timer = 0.0
	if lightning_storm_ring != null:
		lightning_storm_ring.visible = false
	respawn_timer = game.respawn_delay_for(self) if game != null and game.has_method("respawn_delay_for") else 8.0
	velocity = Vector3.ZERO
	carrying = false
	stun_timer = 0.0
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	visual.visible = false
	if health_label != null:
		health_label.visible = false
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
	global_position = _base_position() + Vector3(0.0, 0.76, 0.0)
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
	if game != null:
		game.on_hero_respawned(self)


func use_ability(index: int) -> bool:
	if dead or stun_timer > 0.0 or lightning_storm_timer > 0.0:
		return false
	if index < 0 or index >= 3:
		return false
	if ability_cds[index] > 0.0:
		return false
	if game == null:
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
			var target: HeroUnit = game.nearest_enemy(origin, team, 8.0, self)
			if target == null:
				ability_cds[index] = 0.0
				return false
			var offset := global_position - target.global_position
			offset.y = 0.0
			if offset.length_squared() < 0.001:
				offset = -_facing_direction()
			global_position = game.clamp_to_arena(target.global_position + offset.normalized() * 1.2)
			var hit_position := global_position
			target.take_damage(roll_direct_damage(attack_damage * get_blessing_damage_multiplier()), self, "physical")
			target.stun(1.0)
			spawn_ability_vfx(0, target.global_position)
			game.dash_fx(origin, hit_position, color)
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
			game.fear_pulse_fx(origin, WARRIOR_ULT_RADIUS, color)
			game.earthquake_fx(origin, WARRIOR_ULT_RADIUS, 1.5)
		"root":
			var fwd: Vector3 = _facing_direction()
			var proj_pos := origin + Vector3(0.0, 1.2, 0.0)
			var root_target: HeroUnit = game.nearest_enemy(proj_pos, team, 10.0, self)
			if root_target != null:
				game.spawn_projectile(proj_pos, root_target, roll_direct_damage(_outgoing_damage(20.0) * get_blessing_damage_multiplier()), color, self, 2.0, "magic", "root")
			game.burst(proj_pos, color, 14)
		"heal":
			spawn_ability_vfx(1, origin)
			game.heal_area(origin, 10.0, float(randi_range(100, 300)), team, 6)
			game.burst(origin, Color(0.65, 1.0, 0.75), 18)
		"ult_lightning_storm":
			lightning_storm_timer = MAGE_STORM_DURATION
			lightning_storm_tick_timer = 1.0
			velocity = Vector3.ZERO
			_set_lightning_storm_ring(true)
			game.burst(origin, Color(0.35, 0.78, 1.0), 28)
		"stun_shot":
			var target2: HeroUnit = game.nearest_enemy(origin, team, 14.0, self)
			if target2 != null:
				game.spawn_projectile(origin + Vector3(0.0, 1.3, 0.0), target2, roll_direct_damage(_outgoing_damage(40.0) * get_blessing_damage_multiplier()), color, self, 1.5, "physical", "stun")
			game.burst(origin, color, 10)
		"golden_blessing":
			game.bless_team(team, float(data["cd"]))
			game.golden_blessing_fx(origin, team, self)
	return true


func _set_lightning_storm_ring(active: bool) -> void:
	if lightning_storm_ring == null:
		lightning_storm_ring = MeshInstance3D.new()
		lightning_storm_ring.name = "LightningStormRange"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.97
		torus.outer_radius = 1.0
		torus.rings = 48
		torus.ring_segments = 8
		lightning_storm_ring.mesh = torus
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.28, 0.76, 1.0, 0.48)
		material.emission_enabled = true
		material.emission = Color(0.2, 0.65, 1.0)
		material.emission_energy_multiplier = 1.6
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lightning_storm_ring.material_override = material
		lightning_storm_ring.scale = Vector3(MAGE_STORM_RADIUS, 1.0, MAGE_STORM_RADIUS)
		lightning_storm_ring.position.y = 0.14
		add_child(lightning_storm_ring)
	lightning_storm_ring.visible = active


func _set_crit_buff_ring(active: bool) -> void:
	if crit_buff_ring == null:
		crit_buff_ring = MeshInstance3D.new()
		crit_buff_ring.name = "CriticalBuffRing"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.72
		torus.outer_radius = 0.84
		torus.rings = 32
		torus.ring_segments = 8
		crit_buff_ring.mesh = torus
		var ring_color := Color(1.0, 0.28, 0.2) if hero_class == Cls.WARRIOR else Color(0.72, 1.0, 0.35)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.9)
		material.emission_enabled = true
		material.emission = ring_color
		material.emission_energy_multiplier = 2.2
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		crit_buff_ring.material_override = material
		crit_buff_ring.position.y = 0.18
		visual.add_child(crit_buff_ring)
	crit_buff_ring.visible = active


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


func apply_blessing(duration: float) -> void:
	if dead or duration <= 0.0:
		return
	blessing_timer = maxf(blessing_timer, duration)
	if blessing_ring != null and is_instance_valid(blessing_ring):
		return
	var ring := MeshInstance3D.new()
	ring.name = "GoldenBlessingRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.98
	torus.outer_radius = 1.1
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.78, 0.18)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.68, 0.12)
	material.emission_energy_multiplier = 2.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material
	ring.position.y = 0.16
	visual.add_child(ring)
	blessing_ring = ring


func _update_blessing(delta: float) -> void:
	if blessing_timer <= 0.0:
		return
	blessing_timer = maxf(0.0, blessing_timer - delta)
	if blessing_ring != null and is_instance_valid(blessing_ring):
		var pulse := 1.0 + sin(float(Time.get_ticks_msec()) * 0.008) * 0.08
		blessing_ring.scale = Vector3.ONE * pulse
	if blessing_timer == 0.0 and blessing_ring != null:
		blessing_ring.queue_free()
		blessing_ring = null


func ability_ready(index: int) -> bool:
	return ability_cds[index] <= 0.01 