extends Node

const SAVE_PATH := "user://tutorial.cfg"
const COINS_TO_COLLECT := 15
const GOLD_PER_COIN := 100
const SHOP_ITEM_ID := "wind_boots"
const OBJECTIVE_GOLD := Color(1.0, 0.82, 0.32)
const OBJECTIVE_SHELL := Color(0.85, 0.6, 1.0)
const OBJECTIVE_CRYSTAL := Color(0.45, 0.92, 1.0)
const COIN_SPAWN_DELAY := 0.6
const FOUNTAIN_TITLE := "Фонтан Осколков"
const FOUNTAIN_TEXT := "Фонтан щедро рассыпает золото: новые монеты появляются сами, одна за другой. Подойди ближе — они потянутся к тебе.\n\nЭто золото боя. Оно не переносится в следующий поединок, зато здесь превращается в снаряжение.\n\nТвоё задание: собери %d монет."
const SHOP_TITLE := "Лавка снаряжения"
const SHOP_TEXT := "Здесь золото становится силой. Каждый предмет меняет характеристики героя: запас здоровья, урон, скорость или лечение.\n\nСнаряжение действует до конца поединка. Один удачный предмет может решить исход боя.\n\nВозьми «Крылатые ботинки»: они добавят 15% к скорости бега. Быстрее доберёшься до Оболочки — быстрее унесёшь Осколок."

var game: Node
var stage := "welcome"
var expected_ability := 0
var coins_collected := 0
var coins_spawned := 0
var coin_spawn_timer := 0.0
var shell_spawn_countdown := 0.0
var completed := false


func begin() -> void:
	stage = "welcome"
	coins_collected = 0
	coins_spawned = 0
	coin_spawn_timer = 0.0
	shell_spawn_countdown = 0.0
	completed = false
	_point_to(Vector3.ZERO, OBJECTIVE_GOLD)
	var controls_hint := "Двигайся джойстиком слева, навыки — кнопки справа." if _uses_touch_controls() else "Двигайся клавишами WASD, навыки — 1, 2 и 3."
	game.hud.call(
		"show_tutorial_card",
		"Добро пожаловать!",
		"Цель игры — разбить Оболочку, подобрать Осколок и донести его до базы.\n\n%s В этом обучении ты не можешь погибнуть." % controls_hint,
		"Продолжить",
		Callable(self, "_continue_intro")
	)


func process(delta: float) -> void:
	if completed or game.player == null or not is_instance_valid(game.player):
		return
	if stage == "reach_center":
		if Vector2(game.player.global_position.x, game.player.global_position.z).length() <= 5.0:
			_start_ability_training()
	elif stage == "go_fountain":
		if game.gold_fountain != null and is_instance_valid(game.gold_fountain):
			var distance := Vector2(game.player.global_position.x - game.gold_fountain.global_position.x, game.player.global_position.z - game.gold_fountain.global_position.z).length()
			if distance <= 10.0:
				_show_fountain_card()
	elif stage == "collect_coins":
		coin_spawn_timer = maxf(0.0, coin_spawn_timer - delta)
		if coin_spawn_timer <= 0.0 and coins_spawned < COINS_TO_COLLECT:
			game.call("spawn_tutorial_coin", GOLD_PER_COIN)
			coins_spawned += 1
			coin_spawn_timer = COIN_SPAWN_DELAY
	elif stage == "go_shop":
		if game.is_hero_near_shop(game.player):
			_show_shop_card()
	elif stage == "shell_warning":
		shell_spawn_countdown = maxf(0.0, shell_spawn_countdown - delta)
		if shell_spawn_countdown <= 0.0:
			stage = "destroy_shell"
			game.call("_spawn_shell")
			game.hud.call("show_tutorial_hint", "Уничтожь Оболочку — внутри неё Небесный Осколок")
	elif stage == "pick_crystal":
		if game.crystal_state == "carried" and game.carrier == game.player:
			stage = "deliver_crystal"
			_point_to(_own_base_position(), OBJECTIVE_CRYSTAL)
			game.hud.call("show_tutorial_hint", "Неси Осколок на свою базу")


func can_use_ability(index: int) -> bool:
	if stage == "abilities":
		return index == expected_ability
	return true


func on_ability_used(index: int) -> void:
	if not can_use_ability(index):
		return
	if game.tutorial_dummy != null and is_instance_valid(game.tutorial_dummy):
		game.tutorial_dummy.take_damage(100.0, game.player)
	expected_ability += 1
	if expected_ability < 3:
		game.hud.call("set_tutorial_ability", expected_ability)
		game.hud.call("show_tutorial_hint", "Нажми «%s»" % _ability_name(expected_ability))
		return
	game.call("remove_tutorial_dummy")
	stage = "go_fountain"
	game.hud.call("set_tutorial_ability", -1)
	_point_to(_fountain_position(), OBJECTIVE_GOLD)
	game.hud.call("show_tutorial_hint", "Сходи к фонтану и собери %d монет" % COINS_TO_COLLECT)


func on_coin_collected() -> void:
	if stage != "collect_coins":
		return
	coins_collected += 1
	game.hud.call("show_tutorial_hint", "Задание: собери монеты — %d / %d" % [coins_collected, COINS_TO_COLLECT])
	if coins_collected < COINS_TO_COLLECT:
		return
	if game.gold < COINS_TO_COLLECT * GOLD_PER_COIN:
		push_error("Tutorial fountain did not award the expected match gold")
		return
	stage = "go_shop"
	_point_to(_shop_position(), OBJECTIVE_GOLD)
	game.hud.call("show_tutorial_hint", "Монеты собраны. Иди в магазин")


func can_buy_item(item_id: String) -> bool:
	return stage == "buy_item" and item_id == SHOP_ITEM_ID


func on_shop_item_bought(item_id: String) -> void:
	if stage != "buy_item" or item_id != SHOP_ITEM_ID:
		return
	game.call("set_shop_open", false)
	stage = "shell_warning"
	shell_spawn_countdown = 10.0
	_point_to(Vector3.ZERO, OBJECTIVE_SHELL)
	game.hud.call("show_tutorial_hint", "Через 10 секунд появится Оболочка")
	game.call("announce", "Через 10 секунд появится Оболочка", Color(0.78, 0.6, 1.0), 10.0)


func on_shell_destroyed() -> void:
	if stage != "destroy_shell":
		return
	stage = "pick_crystal"
	_point_to(_crystal_position(), OBJECTIVE_CRYSTAL)
	game.hud.call("show_tutorial_hint", "Подбери появившийся Осколок")


func on_delivery() -> void:
	# Доставка осколка всегда завершает обучение, на каком бы шаге игрок ни был:
	# игрок может дойти до базы раньше, чем пройдёт фонтан и лавку.
	if completed:
		return
	completed = true
	stage = "complete"
	game.state = "tutorial_complete"
	game.call("set_shop_open", false)
	_clear_target()
	_save_completion()
	game.hud.call("set_tutorial_ability", -1)
	game.hud.call(
		"show_tutorial_victory",
		"Победа!",
		"Отлично! Теперь ты знаешь основу боя.\n\nСоветы: собирай монеты у фонтана, покупай улучшения до схватки и следи, чтобы Осколок оказался на базе.",
		Callable(self, "return_to_lobby"),
		Callable(self, "repeat_tutorial")
	)


func _continue_intro() -> void:
	if stage != "welcome":
		return
	stage = "reach_center"
	game.hud.call("hide_tutorial_card")
	game.hud.call("show_tutorial_hint", "Беги вперёд — к центру арены")


func _show_fountain_card() -> void:
	if stage != "go_fountain":
		return
	stage = "fountain_intro"
	game.hud.call(
		"show_tutorial_card",
		FOUNTAIN_TITLE,
		FOUNTAIN_TEXT % COINS_TO_COLLECT,
		"Собрать монеты",
		Callable(self, "_start_coin_collection")
	)


func _start_coin_collection() -> void:
	if stage != "fountain_intro":
		return
	game.hud.call("hide_tutorial_card")
	stage = "collect_coins"
	coins_spawned = 0
	coin_spawn_timer = 0.0
	game.hud.call("show_tutorial_hint", "Задание: собери монеты у фонтана — 0 / %d" % COINS_TO_COLLECT)


func _show_shop_card() -> void:
	if stage != "go_shop":
		return
	stage = "shop_intro"
	game.hud.call(
		"show_tutorial_card",
		SHOP_TITLE,
		SHOP_TEXT,
		"Открыть лавку",
		Callable(self, "_open_shop_for_tutorial")
	)


func _open_shop_for_tutorial() -> void:
	if stage != "shop_intro":
		return
	game.hud.call("hide_tutorial_card")
	stage = "buy_item"
	if game.player != null and is_instance_valid(game.player):
		game.player.seconds_since_damage = 5.0
		game.player.shop_manual_dismissed = false
		game.player._update_shop_proximity(0.0)
	game.hud.call("show_tutorial_hint", "Купи учебный товар в магазине")


func _start_ability_training() -> void:
	if stage != "reach_center":
		return
	game.call("spawn_tutorial_dummy")
	stage = "abilities"
	expected_ability = 0
	if game.tutorial_dummy != null and is_instance_valid(game.tutorial_dummy):
		_point_to(game.tutorial_dummy.global_position, OBJECTIVE_GOLD)
	game.hud.call("set_tutorial_ability", expected_ability)
	game.hud.call("show_tutorial_hint", "Нажми «%s»" % _ability_name(0))


func return_to_lobby() -> void:
	get_tree().paused = false
	get_tree().set_meta("tutorial_mode", false)
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func repeat_tutorial() -> void:
	get_tree().paused = false
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("selected_class", game.player.hero_class if game.player != null else HeroUnit.Cls.WARRIOR)
	get_tree().set_meta("selected_team", 0)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _save_completion() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("tutorial", "completed", true)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить прохождение обучения: %s" % error_string(error))


func _uses_touch_controls() -> bool:
	return OS.has_feature("mobile") or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())


func _ability_name(index: int) -> String:
	if game == null or game.player == null or not is_instance_valid(game.player):
		return "навык %d" % (index + 1)
	return String(HeroUnit.CLASS_DATA[int(game.player.hero_class)]["abilities"][index]["name"])


func _point_to(world_position: Vector3, color: Color) -> void:
	if game != null and game.has_method("set_tutorial_target"):
		game.call("set_tutorial_target", world_position, color)


func _clear_target() -> void:
	if game != null and game.has_method("clear_tutorial_target"):
		game.call("clear_tutorial_target")


func _fountain_position() -> Vector3:
	if game.gold_fountain != null and is_instance_valid(game.gold_fountain):
		return game.gold_fountain.global_position
	return Vector3(37.0, 0.0, 0.0)


func _shop_position() -> Vector3:
	return game.SHOP_INTERACTION_POINT


func _crystal_position() -> Vector3:
	if game.crystal_node != null and is_instance_valid(game.crystal_node):
		return game.crystal_node.global_position
	return Vector3.ZERO


func _own_base_position() -> Vector3:
	var base_z := float(game.BASE_POSITION_Z)
	if game.player != null and int(game.player.team) == 1:
		base_z = -base_z
	return Vector3(0.0, 0.0, base_z)
