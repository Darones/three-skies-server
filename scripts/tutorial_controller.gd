extends Node

const SAVE_PATH := "user://tutorial.cfg"
const COINS_TO_COLLECT := 5
const GOLD_PER_COIN := 100
const SHOP_ITEM_ID := "wind_boots"

var game: Node
var stage := "welcome"
var expected_ability := 0
var coins_collected := 0
var shell_spawn_countdown := 0.0
var completed := false


func begin() -> void:
	stage = "welcome"
	coins_collected = 0
	shell_spawn_countdown = 0.0
	completed = false
	game.hud.call(
		"show_tutorial_card",
		"Добро пожаловать!",
		"Цель игры — разбить Оболочку, подобрать Осколок и донести его до базы.\n\nДвигайся клавишами WASD, навыки — 1, 2 и 3. В этом обучении ты не можешь погибнуть.",
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
				stage = "collect_coins"
				game.call("spawn_tutorial_coin_batch", COINS_TO_COLLECT, GOLD_PER_COIN)
				game.hud.call("show_tutorial_hint", "Собери монеты у фонтана: 0 / 5")
	elif stage == "go_shop":
		if game.is_hero_near_shop(game.player):
			stage = "buy_item"
			game.player.seconds_since_damage = 5.0
			game.player.shop_manual_dismissed = false
			game.player._update_shop_proximity(0.0)
			game.hud.call("show_tutorial_hint", "Купи учебный товар в магазине")
	elif stage == "shell_warning":
		shell_spawn_countdown = maxf(0.0, shell_spawn_countdown - delta)
		if shell_spawn_countdown <= 0.0:
			stage = "destroy_shell"
			game.call("_spawn_shell")
			game.hud.call("show_tutorial_hint", "Уничтожь Оболочку")
	elif stage == "pick_crystal":
		if game.crystal_state == "carried" and game.carrier == game.player:
			stage = "deliver_crystal"
			game.hud.call("show_tutorial_hint", "Неси Осколок на свою базу")


func can_use_ability(index: int) -> bool:
	return stage == "abilities" and index == expected_ability


func on_ability_used(index: int) -> void:
	if not can_use_ability(index):
		return
	if game.tutorial_dummy != null and is_instance_valid(game.tutorial_dummy):
		game.tutorial_dummy.take_damage(100.0, game.player)
	expected_ability += 1
	if expected_ability < 3:
		game.hud.call("set_tutorial_ability", expected_ability)
		game.hud.call("show_tutorial_hint", "Нажми навык %d" % (expected_ability + 1))
		return
	game.call("remove_tutorial_dummy")
	stage = "go_fountain"
	game.hud.call("set_tutorial_ability", -1)
	game.hud.call("show_tutorial_hint", "Сходи к фонтану и собери 500 монет")


func on_coin_collected() -> void:
	if stage != "collect_coins":
		return
	coins_collected += 1
	game.hud.call("show_tutorial_hint", "Собери монеты у фонтана: %d / %d" % [coins_collected, COINS_TO_COLLECT])
	if coins_collected < COINS_TO_COLLECT:
		return
	if game.gold < COINS_TO_COLLECT * GOLD_PER_COIN:
		push_error("Tutorial fountain did not award the expected match gold")
		return
	stage = "go_shop"
	game.hud.call("show_tutorial_hint", "500 монет собраны. Иди в магазин")


func can_buy_item(item_id: String) -> bool:
	return stage == "buy_item" and item_id == SHOP_ITEM_ID


func on_shop_item_bought(item_id: String) -> void:
	if stage != "buy_item" or item_id != SHOP_ITEM_ID:
		return
	game.call("set_shop_open", false)
	stage = "shell_warning"
	shell_spawn_countdown = 10.0
	game.hud.call("show_tutorial_hint", "Через 10 секунд появится Оболочка")
	game.call("announce", "Через 10 секунд появится Оболочка", Color(0.78, 0.6, 1.0), 10.0)


func on_shell_destroyed() -> void:
	if stage != "destroy_shell":
		return
	stage = "pick_crystal"
	game.hud.call("show_tutorial_hint", "Подбери появившийся Осколок")


func on_delivery() -> void:
	if stage != "deliver_crystal":
		return
	completed = true
	stage = "complete"
	game.state = "tutorial_complete"
	game.call("set_shop_open", false)
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


func _start_ability_training() -> void:
	if stage != "reach_center":
		return
	game.call("spawn_tutorial_dummy")
	stage = "abilities"
	expected_ability = 0
	game.hud.call("set_tutorial_ability", expected_ability)
	game.hud.call("show_tutorial_hint", "Нажми навык 1")


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
