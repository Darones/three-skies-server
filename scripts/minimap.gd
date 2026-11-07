extends Control

const MINIMAP_SIZE := Vector2(132.0, 132.0)
const ARENA_HALF_X := 52.0
const ARENA_HALF_Z := 37.0
const MAP_FONT: Font = preload("res://assets/fonts/Philosopher-Regular.ttf")

const PANEL_COLOR := Color(0.018, 0.025, 0.045, 0.4)
const ARENA_COLOR := Color(0.09, 0.13, 0.19, 0.96)
const ARENA_LINE := Color(0.58, 0.66, 0.78, 0.8)
const ALLY_COLOR := Color(0.2, 0.92, 0.46, 1.0)
const ENEMY_COLOR := Color(1.0, 0.2, 0.23, 1.0)
const CARRIER_COLOR := Color(1.0, 0.82, 0.24, 1.0)
const CRYSTAL_COLOR := Color(0.44, 0.92, 1.0, 1.0)

var game: Node
var refresh_elapsed := 0.0
var pulse_time := 0.0
var panel_style: StyleBoxFlat
var arena_style: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = MINIMAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	panel_style = StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.border_color = Color(0.68, 0.72, 0.82, 0.6)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	arena_style = StyleBoxFlat.new()
	arena_style.bg_color = ARENA_COLOR
	arena_style.border_color = ARENA_LINE
	arena_style.set_border_width_all(1)
	arena_style.set_corner_radius_all(5)


func configure(game_instance: Node) -> void:
	game = game_instance
	name = "MiniMap"
	anchor_left = 0.5
	anchor_top = 1.0
	anchor_right = 0.5
	anchor_bottom = 1.0
	offset_left = -66.0
	offset_top = -144.0
	offset_right = 66.0
	offset_bottom = -12.0


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game):
		visible = false
		return
	var match_active: bool = game.state == "live"
	if visible != match_active:
		visible = match_active
		if match_active:
			queue_redraw()
	if not match_active:
		return
	pulse_time += delta
	refresh_elapsed += delta
	if refresh_elapsed >= 0.08:
		refresh_elapsed = 0.0
		queue_redraw()


func _draw() -> void:
	if game == null or game.player == null:
		return
	draw_style_box(panel_style, Rect2(Vector2.ZERO, size))

	var map_rect := Rect2(Vector2(6.0, 6.0), Vector2(120.0, 120.0))
	var map_center := map_rect.get_center()
	draw_style_box(arena_style, map_rect)
	draw_line(Vector2(map_rect.position.x + 3.0, map_center.y), Vector2(map_rect.end.x - 3.0, map_center.y), Color(0.52, 0.6, 0.73, 0.24), 1.0, true)

	var player_team := int(game.player.team)
	var own_base_z := float(game.BASE_POSITION_Z) if player_team == 0 else -float(game.BASE_POSITION_Z)
	var enemy_base_z := -own_base_z
	draw_circle(_world_to_map(Vector3(0.0, 0.0, own_base_z), map_rect), 3.2, Color(0.36, 0.76, 1.0, 0.9))
	draw_circle(_world_to_map(Vector3(0.0, 0.0, enemy_base_z), map_rect), 3.2, Color(0.72, 0.43, 1.0, 0.9))

	_draw_shop_icon(_world_to_map(game.SHOP_INTERACTION_POINT, map_rect))
	var fountain_position := Vector3(37.0, 0.0, 0.0)
	if game.gold_fountain != null and is_instance_valid(game.gold_fountain):
		fountain_position = game.gold_fountain.global_position
	_draw_coin_icon(_world_to_map(fountain_position, map_rect))
	_draw_shell_marker(map_rect)
	_draw_ground_crystal(map_rect)
	_draw_heroes(map_rect, player_team)


func _world_to_map(world_position: Vector3, map_rect: Rect2) -> Vector2:
	var map_x := world_position.x
	var map_z := world_position.z
	if game.player != null and int(game.player.team) == 1:
		map_x = -map_x
		map_z = -map_z
	var normalized_x := clampf(map_x / ARENA_HALF_X, -1.0, 1.0)
	var normalized_z := clampf(map_z / ARENA_HALF_Z, -1.0, 1.0)
	return Vector2(
		map_rect.position.x + (normalized_x + 1.0) * 0.5 * map_rect.size.x,
		map_rect.position.y + (normalized_z + 1.0) * 0.5 * map_rect.size.y
	)


func _draw_shop_icon(point: Vector2) -> void:
	draw_circle(point, 6.2, Color(0.1, 0.075, 0.035, 0.96))
	var bag := PackedVector2Array([
		point + Vector2(-3.8, -1.8),
		point + Vector2(3.8, -1.8),
		point + Vector2(3.2, 3.7),
		point + Vector2(-3.2, 3.7),
	])
	draw_colored_polygon(bag, Color(0.96, 0.69, 0.18, 1.0))
	draw_arc(point + Vector2(0.0, -1.8), 2.3, PI, TAU, 12, Color(1.0, 0.86, 0.48, 1.0), 1.1, true)
	draw_circle(point, 1.0, Color(0.32, 0.18, 0.045, 1.0))


func _draw_coin_icon(point: Vector2) -> void:
	draw_circle(point, 5.4, Color(0.98, 0.77, 0.2, 1.0))
	draw_arc(point, 3.6, 0.0, TAU, 20, Color(0.45, 0.26, 0.055, 1.0), 1.0, true)
	draw_line(point + Vector2(-1.8, 0.0), point + Vector2(1.8, 0.0), Color(0.45, 0.26, 0.055, 1.0), 1.0, true)


func _draw_shell_marker(map_rect: Rect2) -> void:
	var shell_position := Vector3.ZERO
	if game.shell_phase == "active" and game.shell != null and is_instance_valid(game.shell):
		shell_position = game.shell.global_position
	var point := _world_to_map(shell_position, map_rect)
	if game.shell_phase == "warning":
		var pulse := 0.5 + 0.5 * sin(pulse_time * 7.0)
		draw_circle(point, 4.2 + pulse * 2.0, Color(1.0, 0.72, 0.28, 0.18 + pulse * 0.16))
		draw_arc(point, 6.0 + pulse * 2.0, 0.0, TAU, 24, Color(1.0, 0.75, 0.3, 0.9), 1.3, true)
		draw_string(MAP_FONT, point + Vector2(5.0, 3.0), "%d" % int(ceil(float(game.shell_timer))), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.86, 0.55, 1.0))
	elif game.shell_phase == "active":
		draw_circle(point, 5.0, Color(0.82, 0.62, 1.0, 0.28))
		draw_arc(point, 5.8, 0.0, TAU, 24, Color(0.89, 0.7, 1.0, 1.0), 1.4, true)
		draw_circle(point, 2.7, Color(0.78, 0.52, 1.0, 1.0))
	else:
		draw_circle(point, 2.2, Color(0.95, 0.83, 0.54, 0.68))


func _draw_ground_crystal(map_rect: Rect2) -> void:
	if game.crystal_state != "ground" or game.crystal_node == null or not is_instance_valid(game.crystal_node):
		return
	var point := _world_to_map(game.crystal_node.global_position, map_rect)
	var diamond := PackedVector2Array([
		point + Vector2(0.0, -5.0),
		point + Vector2(4.0, 0.0),
		point + Vector2(0.0, 5.0),
		point + Vector2(-4.0, 0.0),
	])
	draw_colored_polygon(diamond, CRYSTAL_COLOR)
	draw_arc(point, 6.2, 0.0, TAU, 20, Color(CRYSTAL_COLOR.r, CRYSTAL_COLOR.g, CRYSTAL_COLOR.b, 0.72), 1.0, true)


func _draw_heroes(map_rect: Rect2, player_team: int) -> void:
	for hero in game.heroes:
		if hero == null or not is_instance_valid(hero) or int(hero.team) != player_team:
			continue
		_draw_hero_marker(hero, map_rect, ALLY_COLOR, hero == game.player)
	if game.player == null or not is_instance_valid(game.player):
		return
	for enemy in game.enemies_of(player_team, game.player):
		if enemy == null or not is_instance_valid(enemy):
			continue
		_draw_hero_marker(enemy, map_rect, ENEMY_COLOR, false)


func _draw_hero_marker(hero: Node3D, map_rect: Rect2, team_color: Color, is_local_player: bool) -> void:
	var point := _world_to_map(hero.global_position, map_rect)
	var alpha := 0.42 if hero.dead else 1.0
	if hero == game.carrier:
		draw_circle(point, 7.5, Color(CARRIER_COLOR.r, CARRIER_COLOR.g, CARRIER_COLOR.b, 0.18))
		draw_arc(point, 7.5, 0.0, TAU, 24, CARRIER_COLOR, 1.6, true)
	var marker_color := Color(team_color.r, team_color.g, team_color.b, alpha)
	draw_circle(point, 3.7 if is_local_player else 3.1, marker_color)
	if is_local_player:
		draw_arc(point, 5.0, 0.0, TAU, 20, Color(1.0, 0.95, 0.75, 0.95), 1.0, true)
