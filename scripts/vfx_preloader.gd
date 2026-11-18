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
		# A few rendered frames compile the shaders and upload textures.
		for _frame in 3:
			await get_tree().process_frame
		await get_tree().create_timer(0.04).timeout
		if is_instance_valid(instance):
			instance.queue_free()
		await get_tree().process_frame

	if is_instance_valid(viewport):
		viewport.queue_free()
