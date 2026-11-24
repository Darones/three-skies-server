extends Node

const SAVE_PATH := "user://tutorial.cfg"
const OPEN_RULES_META := "open_rules_on_lobby"
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
var coins_collected := 0
var coins_spawned := 0
var coin_spawn_timer := 0.0
var shell_spawn_countdown := 0.0
var shell_hint_near := false
var completed := false
var skipped := false
var stage_timer := 0.0
var duel_kills := 0
var team_kills := 0
var team_ability_used := false
var started_msec := 0


func begin() -> void:
	stage = "welcome"
	coins_collected = 0
	coins_spawned = 0
	coin_spawn_timer = 0.0
	shell_spawn_countdown = 0.0
	completed = false
	skipped = false
	stage_timer = 0.0
	duel_kills = 0
	team_kills = 0
	team_ability_used = false
	started_msec = Time.get_ticks_msec()
	Stats.track("tutorial_start", {"class": int(game.player.hero_class) if game.player != null else 0})
	_point_to(Vector3.ZERO, OBJECTIVE_GOLD)
	var controls_hint := "Двигайся джойстиком слева, навыки — кнопки справа." if _uses_touch_controls() else "Двигайся клавишами WASD, навыки — 1, 2 и 3."
	game.hud.call(
		"show_tutorial_card",
		"Добро пожаловать!",
		"Цель игры — разбить Оболочку, подобрать Осколок и донести его до базы.\n\n%s В обучении три этапа: дуэль, пара и команда. Ты не можешь погибнуть, а пропустить обучение можно кнопкой сверху.\n\nЕсли стоять на месте 1 минуту, за тебя начнёт играть ИИ." % controls_hint,
		"Продолжить",
		Callable(self, "_continue_intro")
	)


func process(delta: float) -> void:
	if completed or game.player == null or not is_instance_valid(game.player):
		return
	if stage_timer > 0.0:
		stage_timer = maxf(0.0, stage_timer - delta)
		if stage_timer <= 0.0:
			if stage == "duel":
				_finish_duel(true)
			elif stage == "team_fight":
				_finish_team_fight(true)
			return
	if game.crystal_state == "carried" and game.carrier == game.player and stage != "deliver_crystal" and stage != "complete":
		stage = "deliver_crystal"
		_point_to(_own_base_position(), OBJECTIVE_CRYSTAL)
		game.hud.call("show_tutorial_hint", "Неси Осколок на свою базу")
		return
	if stage == "reach_center":
		if Vector2(game.player.global_position.x, game.player.global_position.z).length() <= 5.0:
			_start_duel()
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
			shell_hint_near = false
			game.call("_spawn_shell")
			game.hud.call("show_tutorial_hint", "Уничтожь Оболочку — внутри неё Небесный Осколок")
	elif stage == "destroy_shell":
		# Drop the hint strip when the player is close enough to fight the
		# Shell; otherwise it covers the Shell's own name and HP bar.
		var shell_node = game.shell
		var near: bool = shell_node != null and is_instance_valid(shell_node) and shell_node.alive and game.player.global_position.distance_to(shell_node.global_position) <= 10.0
		if near != shell_hint_near:
			shell_hint_near = near
			game.hud.call(
				"show_tutorial_hint",
				"" if near else "Уничтожь Оболочку — внутри неё Небесный Осколок"
			)
	elif stage == "pick_crystal":
		if game.crystal_state == "carried" and game.carrier == game.player:
			stage = "deliver_crystal"
			_point_to(_own_base_position(), OBJECTIVE_CRYSTAL)
			game.hud.call("show_tutorial_hint", "Неси Осколок на свою базу")


func can_use_ability(_index: int) -> bool:
	# The tutorial highlights the next ability but never blocks the others:
	# a new player pressing the wrong button should still see what it does.
	return true


func on_ability_used(index: int) -> void:
	if stage == "duel" and index == 0:
		game.hud.call("show_tutorial_hint", "Первый навык применён. Добей тренировочного бота.")
		game.hud.call("set_tutorial_ability", -1)
	elif stage == "team_fight" and index == 1:
		team_ability_used = true
		game.hud.call("show_tutorial_hint", "Второй навык применён. Победи двух врагов.")
		game.hud.call("set_tutorial_ability", -1)
	elif stage == "shell_warning" and index == 2:
		game.hud.call("set_tutorial_ability", -1)


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
	_start_team_fight_intro()


func on_shell_destroyed() -> void:
	if stage != "destroy_shell":
		return
	stage = "pick_crystal"
	game.hud.call("hide_ui_highlight")
	_point_to(_crystal_position(), OBJECTIVE_CRYSTAL)
	game.hud.call("show_tutorial_hint", "Возьми осколок")


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
	game.clear_tutorial_bots()
	game.hud.call("set_tutorial_skip_visible", false)
	game.hud.call("show_tutorial_hint", "")
	game.hud.call("hide_ui_highlight")
	game.hud.call("set_tutorial_ability", -1)
	Stats.track("tutorial_complete", {
		"elapsed_ms": Time.get_ticks_msec() - started_msec,
		"skipped": false,
	})
	game.hud.call(
		"show_tutorial_victory",
		"Обучение пройдено!",
		"Отлично! Ты прошёл дуэль, бой в паре и команде 3 на 3.\n\nСоветы: собирай монеты у фонтана, покупай улучшения до схватки и следи, чтобы Осколок оказался на базе.",
		Callable(self, "return_to_lobby"),
		Callable(self, "repeat_tutorial")
	)


func _continue_intro() -> void:
	if stage != "welcome":
		return
	stage = "ui_tour"
	game.hud.call("hide_tutorial_card")
	_clear_target()
	_run_ui_tour()


func _run_ui_tour() -> void:
	game.hud.call("show_ui_highlight", "minimap", "Это миникарта: на ней видно союзников, врагов и осколок.")
	await get_tree().create_timer(3.4).timeout
	if not is_inside_tree() or stage != "ui_tour":
		return
	game.hud.call("show_ui_highlight", "skills", "Это ваши скиллы — кнопки 1, 2 и 3 справа.")
	await get_tree().create_timer(3.4).timeout
	if not is_inside_tree() or stage != "ui_tour":
		return
	game.hud.call("show_ui_highlight", "avatar", "Это меню: звук и настройки. Пауза в онлайне недоступна.")
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree() or stage != "ui_tour":
		return
	game.hud.call("hide_ui_highlight")
	stage = "reach_center"
	_point_to(Vector3.ZERO, OBJECTIVE_GOLD)
	game.hud.call("show_tutorial_hint", "Беги вперёд — к центру арены")


func _show_fountain_card() -> void:
	if stage != "go_fountain":
		return
	stage = "fountain_intro"
	game.hud.call("hide_ui_highlight")
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
	game.hud.call("hide_ui_highlight")
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
		# The shop tent has a collision box. Put the player on its
		# centre-facing side so they cannot get pinned under the canopy.
		var shop_point: Vector3 = game.SHOP_INTERACTION_POINT
		game.player.global_position = game.clamp_to_arena(shop_point + Vector3(3.5, 0.0, 0.0))
		game.player.velocity = Vector3.ZERO
		game.player.seconds_since_damage = 5.0
		game.player.shop_manual_dismissed = false
		game.player._update_shop_proximity(0.0)
	game.hud.call("show_tutorial_hint", "Купи учебный товар в магазине")
	game.hud.call("set_tutorial_shop_item", SHOP_ITEM_ID)


func _start_duel() -> void:
	if stage != "reach_center":
		return
	stage = "duel"
	duel_kills = 0
	stage_timer = 60.0
	game.clear_tutorial_bots()
	var bot: HeroUnit = game.spawn_tutorial_bot(
		HeroUnit.Cls.WARRIOR,
		1 - int(game.player.team),
		Vector3(0.0, 0.76, -4.0),
		"easy",
		"Тренировочный бот"
	)
	game.hud.call("hide_ui_highlight")
	game.hud.call("show_tutorial_hint", "Этап 1/3 · Дуэль: победи тренировочного бота")
	game.hud.call("set_tutorial_ability", 0)
	_point_to(bot.global_position, OBJECTIVE_GOLD)
	Stats.track("tutorial_stage", {"stage": "duel", "index": 1})


func _finish_duel(timed_out := false) -> void:
	if stage != "duel":
		return
	stage = "duel_done"
	stage_timer = 0.0
	game.clear_tutorial_bots()
	game.hud.call("set_tutorial_ability", -1)
	_clear_target()
	var body := "Дуэль пройдена. Дальше — фонтан и лавка: собери золото и купи улучшение."
	if timed_out:
		body = "Время дуэли вышло, но это тренировка. Дальше — фонтан и лавка: собери золото и купи улучшение."
	game.hud.call("show_tutorial_card", "Этап 1/3 пройден", body, "К фонтану", Callable(self, "_begin_fountain"))


func _begin_fountain() -> void:
	game.hud.call("hide_tutorial_card")
	stage = "go_fountain"
	_point_to(_fountain_position(), OBJECTIVE_GOLD)
	game.hud.call("show_tutorial_hint", "Сходи к фонтану и собери %d монет" % COINS_TO_COLLECT)


func _start_team_fight_intro() -> void:
	if stage != "buy_item":
		return
	stage = "team_fight_intro"
	game.hud.call("hide_ui_highlight")
	game.hud.call(
		"show_tutorial_card",
		"Этап 2/3 · Пара",
		"Теперь с тобой союзный бот. Примени второй навык и победи двух врагов — так ты научишься менять цель и отходить на базу.",
		"В бой",
		Callable(self, "_start_team_fight")
	)


func _start_team_fight() -> void:
	if stage != "team_fight_intro":
		return
	game.hud.call("hide_tutorial_card")
	stage = "team_fight"
	team_kills = 0
	team_ability_used = false
	stage_timer = 75.0
	game.clear_tutorial_bots()
	var ally_pos: Vector3 = game.clamp_to_arena(game.player.global_position + Vector3(3.0, 0.0, 0.0))
	ally_pos.y = 0.76
	game.spawn_tutorial_bot(HeroUnit.Cls.MAGE, int(game.player.team), ally_pos, "easy", "Союзник")
	var enemy_one: HeroUnit = game.spawn_tutorial_bot(
		HeroUnit.Cls.WARRIOR,
		1 - int(game.player.team),
		Vector3(0.0, 0.76, -2.0),
		"easy",
		"Тренировочный бот"
	)
	game.spawn_tutorial_bot(
		HeroUnit.Cls.FAIRY,
		1 - int(game.player.team),
		Vector3(-3.0, 0.76, 0.0),
		"easy",
		"Тренировочный бот"
	)
	game.hud.call("show_tutorial_hint", "Этап 2/3 · Примени второй навык и победи двух врагов")
	game.hud.call("set_tutorial_ability", 1)
	_point_to(enemy_one.global_position, OBJECTIVE_GOLD)
	Stats.track("tutorial_stage", {"stage": "team_fight", "index": 2})


func _finish_team_fight(timed_out := false) -> void:
	if stage != "team_fight":
		return
	stage = "team_fight_done"
	stage_timer = 0.0
	game.clear_tutorial_bots()
	game.hud.call("set_tutorial_ability", -1)
	_clear_target()
	var body := "Пара пройдена. Теперь команда 3 на 3: разбей Оболочку, забери Осколок и донеси его на базу."
	if timed_out:
		body = "Время вышло, но это тренировка. Теперь команда 3 на 3: разбей Оболочку, забери Осколок и донеси его на базу."
	game.hud.call("show_tutorial_card", "Этап 2/3 пройден", body, "К Оболочке", Callable(self, "_start_final"))


func _start_final() -> void:
	game.hud.call("hide_tutorial_card")
	stage = "shell_warning"
	shell_spawn_countdown = 10.0
	shell_hint_near = false
	game.clear_tutorial_bots()
	var player_pos: Vector3 = game.player.global_position
	var ally_one: Vector3 = game.clamp_to_arena(player_pos + Vector3(2.5, 0.0, 2.0))
	ally_one.y = 0.76
	var ally_two: Vector3 = game.clamp_to_arena(player_pos + Vector3(-2.5, 0.0, 2.0))
	ally_two.y = 0.76
	game.spawn_tutorial_bot(HeroUnit.Cls.WARRIOR, int(game.player.team), ally_one, "easy", "Союзник")
	game.spawn_tutorial_bot(HeroUnit.Cls.MAGE, int(game.player.team), ally_two, "easy", "Союзник")
	game.spawn_tutorial_bot(HeroUnit.Cls.WARRIOR, 1 - int(game.player.team), Vector3(0.0, 0.76, -3.0), "easy", "Тренировочный бот")
	game.spawn_tutorial_bot(HeroUnit.Cls.MAGE, 1 - int(game.player.team), Vector3(3.0, 0.76, -5.0), "easy", "Тренировочный бот")
	game.spawn_tutorial_bot(HeroUnit.Cls.FAIRY, 1 - int(game.player.team), Vector3(-3.0, 0.76, -5.0), "easy", "Тренировочный бот")
	game.hud.call("hide_ui_highlight")
	_point_to(Vector3.ZERO, OBJECTIVE_SHELL)
	game.hud.call("show_tutorial_hint", "Этап 3/3 · Через 10 секунд появится Оболочка")
	game.call("announce", "Через 10 секунд появится Оболочка", Color(0.78, 0.6, 1.0), 10.0)
	game.hud.call("set_tutorial_ability", 2)
	Stats.track("tutorial_stage", {"stage": "final", "index": 3})


func on_tutorial_hero_died(hero: HeroUnit) -> void:
	if hero == null or not is_instance_valid(hero) or game.player == null:
		return
	if hero == game.player or hero.team == game.player.team:
		return
	if stage == "duel":
		duel_kills += 1
		if duel_kills >= 1:
			_finish_duel()
	elif stage == "team_fight":
		team_kills += 1
		if team_kills >= 2:
			_finish_team_fight()


func request_skip() -> void:
	if completed or skipped:
		return
	game.hud.call("set_tutorial_skip_visible", false)
	game.hud.call(
		"show_tutorial_choice",
		"Пропустить обучение?",
		"Ты сможешь посмотреть правила в лобби. Обучение можно пройти позже кнопкой «Обучение».",
		"Продолжить",
		Callable(self, "_cancel_skip"),
		"Пропустить",
		Callable(self, "_skip_tutorial")
	)


func _cancel_skip() -> void:
	game.hud.call("hide_tutorial_card")
	game.hud.call("set_tutorial_skip_visible", true)
	game.hud.call("show_tutorial_hint", _stage_hint())


func _stage_hint() -> String:
	match stage:
		"duel":
			return "Этап 1/3 · Победи тренировочного бота"
		"team_fight":
			return "Этап 2/3 · Примени второй навык и победи двух врагов"
		"shell_warning":
			return "Этап 3/3 · Через %d секунд появится Оболочка" % int(ceil(shell_spawn_countdown))
		"destroy_shell":
			return "Уничтожь Оболочку — внутри неё Небесный Осколок"
		"pick_crystal":
			return "Возьми осколок"
		"deliver_crystal":
			return "Неси Осколок на свою базу"
		_:
			return ""


func _skip_tutorial() -> void:
	if completed or skipped:
		return
	skipped = true
	_save_skip()
	game.hud.call("set_tutorial_skip_visible", false)
	game.clear_tutorial_bots()
	Stats.track("tutorial_skip", {
		"elapsed_ms": Time.get_ticks_msec() - started_msec,
		"stage": stage,
	})
	get_tree().set_meta(OPEN_RULES_META, true)
	return_to_lobby()


func return_to_lobby() -> void:
	get_tree().paused = false
	if game != null and game.hud != null:
		game.hud.call("set_tutorial_skip_visible", false)
	get_tree().set_meta("tutorial_mode", false)
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func repeat_tutorial() -> void:
	get_tree().paused = false
	if game != null and game.hud != null:
		game.hud.call("set_tutorial_skip_visible", false)
	get_tree().set_meta("tutorial_mode", true)
	get_tree().set_meta("selected_class", game.player.hero_class if game.player != null else HeroUnit.Cls.WARRIOR)
	get_tree().set_meta("selected_team", 0)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _save_completion() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("tutorial", "completed", true)
	config.set_value("tutorial", "skipped", false)
	config.set_value("tutorial", "completed_at", int(Time.get_unix_time_from_system()))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить прохождение обучения: %s" % error_string(error))


func _save_skip() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("tutorial", "completed", false)
	config.set_value("tutorial", "skipped", true)
	config.set_value("tutorial", "skipped_at", int(Time.get_unix_time_from_system()))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Не удалось сохранить пропуск обучения: %s" % error_string(error))


func _uses_touch_controls() -> bool:
	return DeviceProfile.touch_controls


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
