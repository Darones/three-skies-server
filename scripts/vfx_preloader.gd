extends Node

# Warms up the heavy match assets while the player is still on the search
# screen: shaders, textures and particle materials compile here instead of
# freezing the first seconds of the battle (especially Shell destruction).
# WarmupFlow also reuses this node before the tutorial and follows
# step_progress/finished, so the progress bar has real steps to show.

signal step_progress(done: int, total: int)
signal finished

const SCENES := [
	"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_01.tscn",
	"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/hit/vfx_hit_02.tscn",
	"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn",
	"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_02.tscn",
	"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_01.tscn",
	"res://assets/hit_fx/BinbunVFX_Vol2/StylizedHitFX/effects/impact/vfx_impact_02.tscn",
	"res://art/generated/shell/3d_1793744338028.glb",
	"res://art/generated/warrior/character.tscn",
	"res://art/generated/mage/character.tscn",
	"res://art/generated/fairy/character.tscn",
]

const SOUNDS := [
	"res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_punch_impact.mp3",
	"res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_sub_impact.mp3",
	"res://assets/audio/Soundza_Game_SFX_Pack/explosions/fireball_explosion.mp3",
	"res://assets/audio/Soundza_Game_SFX_Pack/magic/spell_2.mp3",
	"res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/synth_power_up_ascending.mp3",
	"res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/coins_1.mp3",
	"res://assets/audio/Soundza_Game_SFX_Pack/jingles_stingers/level_up_chime.mp3",
	"res://audio/sfx/warrior_attack_sword_01.mp3",
	"res://audio/sfx/warrior_hit.mp3",
	"res://audio/sfx/warrior_quake_ult.mp3",
	"res://audio/sfx/warrior_dash_shadow.mp3",
	"res://audio/sfx/warrior_bloodthirst.mp3",
	"res://audio/sfx/mage_ice_ball.mp3",
	"res://audio/sfx/mage_hit.mp3",
	"res://audio/sfx/mage_root_vines_short.mp3",
	"res://audio/sfx/mage_heal_chime.mp3",
	"res://audio/sfx/mage_storm_ult.mp3",
	"res://audio/sfx/fairy_bow_release_01.mp3",
	"res://audio/sfx/fairy_hit.mp3",
	"res://audio/sfx/fairy_stun_shot.mp3",
	"res://audio/sfx/fairy_crit_draw_release.mp3",
	"res://audio/sfx/fairy_blessing.mp3",
	"res://audio/sfx/fairy_blessing_free/sfx_magical_fairy_chime_bell_brig_.mp3",
	"res://audio/sfx/sword_hit.mp3",
	"res://audio/sfx/magic_burst.mp3",
	"res://audio/sfx/shell_thunder.mp3",
	"res://audio/sfx/misc_shell_hit.mp3",
	"res://audio/sfx/misc_shell_destroyed.mp3",
	"res://audio/sfx/misc_shard_pickup.mp3",
	"res://audio/sfx/misc_shard_delivery.mp3",
	"res://audio/sfx/misc_coin_wallet.mp3",
	"res://audio/sfx/death_soft_thud.mp3",
	"res://audio/sfx/fairy_death_scream.mp3",
	"res://assets/audio/kenney_rpg/footstep_0.ogg",
	"res://assets/audio/kenney_rpg/footstep_1.ogg",
	"res://assets/audio/kenney_rpg/footstep_2.ogg",
	"res://assets/audio/kenney_rpg/footstep_3.ogg",
	"res://assets/audio/kenney_rpg/footstep_4.ogg",
]

var viewport: SubViewport
var camera: Camera3D
var scenes_warmed := 0
var sounds_warmed := 0
var steps_done := 0
var steps_total := SCENES.size() + 6
var completed := false


func _report_step() -> void:
	steps_done = mini(steps_done + 1, steps_total)
	step_progress.emit(steps_done, steps_total)


func _finish() -> void:
	if completed:
		return
	completed = true
	finished.emit()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	viewport = SubViewport.new()
	viewport.name = "WarmupViewport"
	viewport.size = Vector2i(96, 96)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.0, 4.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	camera.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	light.light_energy = 1.2
	viewport.add_child(light)

	for path in SCENES:
		if not is_inside_tree():
			_finish()
			return
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate()
		if instance == null:
			continue
		viewport.add_child(instance)
		# Hero.spawn_vfx applies emission to every geometry; reproduce it
		# so the exact shader variant is compiled here, not at the first hit.
		for node in instance.find_children("*", "GeometryInstance3D", true, false):
			var material := node.get("material_override") as StandardMaterial3D
			if material != null:
				material.emission_enabled = true
				material.emission = Color.WHITE
				material.emission_energy_multiplier = 1.6
		for node in instance.find_children("*", "Light3D", true, false):
			(node as Light3D).light_energy = 2.0
		# A few rendered frames compile the shaders and upload textures.
		for _frame in 3:
			await get_tree().process_frame
		await get_tree().create_timer(0.04).timeout
		if is_instance_valid(instance):
			instance.queue_free()
		await get_tree().process_frame
		scenes_warmed += 1
		_report_step()

	# Generic ability visuals: projectile spheres/bolts, telegraph rings and
	# ground glows use materials that are created at runtime, not in a scene.
	for mesh in [SphereMesh.new(), QuadMesh.new(), BoxMesh.new(), CylinderMesh.new()]:
		var probe := MeshInstance3D.new()
		probe.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_enabled = true
		material.emission = Color(1.0, 0.8, 0.4)
		material.emission_energy_multiplier = 2.0
		probe.material_override = material
		viewport.add_child(probe)
		for _frame in 2:
			await get_tree().process_frame
		probe.queue_free()
	var glow := FxUtils.soft_ground_glow(3.0, Color(1.0, 0.8, 0.4, 0.7), 0.0, 0.4)
	viewport.add_child(glow)
	for _frame in 2:
		await get_tree().process_frame
	glow.queue_free()
	await get_tree().process_frame
	_report_step()

	# Damage numbers are Label3D; warm the font atlas before the first hit.
	var label := Label3D.new()
	label.text = "1050"
	label.font = preload("res://assets/fonts/Philosopher-Regular.ttf")
	label.font_size = 64
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	viewport.add_child(label)
	for _frame in 2:
		await get_tree().process_frame
	label.queue_free()
	_report_step()

	# Player names use the larger fallback font with a heavy black outline.
	# Warm it so the first visible enemy nameplate does not compile mid-fight.
	var name_probe := Label3D.new()
	name_probe.text = "Северный Ветер"
	name_probe.font = ThemeDB.fallback_font
	name_probe.font_size = 56
	name_probe.outline_size = 10
	name_probe.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	viewport.add_child(name_probe)
	for _frame in 2:
		await get_tree().process_frame
	name_probe.queue_free()
	_report_step()

	# Stun indicator: the "СТАН" Label3D and the torus ring. They are created
	# per hero and first drawn at the first stun, which used to hitch the clash.
	var stun_probe := Label3D.new()
	stun_probe.text = "СТАН"
	stun_probe.font = ThemeDB.fallback_font
	stun_probe.font_size = 44
	stun_probe.outline_size = 12
	stun_probe.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stun_probe.no_depth_test = true
	viewport.add_child(stun_probe)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.72
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	var ring_probe := MeshInstance3D.new()
	ring_probe.mesh = ring_mesh
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(1.0, 0.8, 0.25)
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.emission_enabled = true
	ring_material.emission = Color(1.0, 0.65, 0.15)
	ring_material.emission_energy_multiplier = 2.0
	ring_probe.material_override = ring_material
	viewport.add_child(ring_probe)
	for _frame in 2:
		await get_tree().process_frame
	stun_probe.queue_free()
	ring_probe.queue_free()
	_report_step()

	# Weapon glow orbs/sparks and skill particles are built at runtime.
	var glow_probe := MeshInstance3D.new()
	glow_probe.mesh = QuadMesh.new()
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.albedo_texture = preload("res://ui/fx/blessing_rune.png")
	glow_material.albedo_color = Color(1.0, 0.85, 0.4, 0.9)
	glow_material.emission_enabled = true
	glow_material.emission = Color(1.0, 0.7, 0.25)
	glow_material.emission_energy_multiplier = 1.8
	glow_probe.material_override = glow_material
	glow_probe.scale = Vector3(2.8, 2.8, 1.0)
	viewport.add_child(glow_probe)
	var spark_probe := CPUParticles3D.new()
	spark_probe.amount = 12
	spark_probe.lifetime = 0.5
	spark_probe.emitting = true
	spark_probe.mesh = QuadMesh.new()
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_material.albedo_color = Color(1.0, 0.8, 0.35, 0.9)
	spark_material.emission_enabled = true
	spark_material.emission = Color(1.0, 0.72, 0.25)
	spark_probe.material_override = spark_material
	viewport.add_child(spark_probe)
	for _frame in 3:
		await get_tree().process_frame
	glow_probe.queue_free()
	spark_probe.queue_free()
	_report_step()

	# Decode the first-clash sounds while the search screen is still visible.
	for path in SOUNDS:
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -80.0
		add_child(player)
		player.play()
		await get_tree().process_frame
		player.stop()
		player.queue_free()
		sounds_warmed += 1
	_report_step()

	if is_instance_valid(viewport):
		viewport.queue_free()
	viewport = null
	_finish()
