extends Node3D

# Проверяет анимацию смерти: играет Dead, тело видно, затем скрывается.

var game: Node = null


func _ready() -> void:
	game = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.FAIRY, 0)
	for i in 10:
		await get_tree().process_frame
	var player = game.get("player")
	if player == null:
		print("DEATH_PROBE_FAIL no player")
		get_tree().quit()
		return
	print("BEFORE anim=", player.current_anim, " visible=", player.visual.visible)
	player.call("_die")
	await get_tree().create_timer(0.7).timeout
	print("DURING anim=", player.current_anim, " visible=", player.visual.visible, " dead=", player.dead)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/death_mid.png")
	await get_tree().create_timer(3.2).timeout
	print("AFTER anim=", player.current_anim, " visible=", player.visual.visible, " dead=", player.dead)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://ui_shots/death_after.png")
	print("DEATH_PROBE_DONE")
	get_tree().quit()
