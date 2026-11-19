extends Node

# Warms up the heavy match assets while the player is still on the search
# screen: shaders, textures and particle materials compile here instead of
# freezing the first seconds of the battle (especially Shell destruction).

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
	"res://assets/audio/Soundza_Game_SFX_Pack/hits_impacts/deep_punch_impact.wav",
	"res://assets/audio/Soundza_Game_SFX_Pack/explosions/fireball_explosion.wav",
	"res://assets/audio/Soundza_Game_SFX_Pack/magic/spell_2.wav",
	"res://assets/audio/Soundza_Game_SFX_Pack/pickups_powerups/synth_power_up_ascending.wav",
	"res://audio/sfx/warrior_attack_sword_01.wav",
	"res://audio/sfx/warrior_hit.wav",
	"res://audio/sfx/mage_ice_ball.wav",
	"res://audio/sfx/mage_hit.wav",
	"res://audio/sfx/fairy_bow_release_01.wav",
	"res://audio/sfx/fairy_hit.wav",
]

var viewport: SubViewport
var camera: Camera3D


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
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	viewport.add_child(camera)
	camera.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	light.light_energy = 1.2
	viewport.add_child(light)

	for path in SCENES:
		if not is_inside_tree():
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

	if is_instance_valid(viewport):
		viewport.queue_free()
