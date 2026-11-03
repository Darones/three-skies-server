## Main scene script — manages camera follow and arena spawning.
extends Node3D

@onready var camera: Camera3D = $Camera3D
var hero: CharacterBody3D = null


func _ready() -> void:
	# Spawn arena
	var arena_scene = load("res://scenes/Arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)

	# Spawn hero
	var hero_scene = load("res://scenes/Hero.tscn")
	hero = hero_scene.instantiate()
	add_child(hero)

	camera.make_current()


func _process(delta: float) -> void:
	if hero != null:
		# Smooth camera follow: offset from hero position
		var target_pos: Vector3 = hero.position + Vector3(0, 15, 15)
		position = position.lerp(target_pos, 5.0 * delta)
		look_at(hero.global_position, Vector3.UP)
