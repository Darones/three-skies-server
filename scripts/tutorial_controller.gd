extends Node


const OPEN_RULES_META := "open_rules_on_lobby"
const COINS_TO_COLLECT := 15
const COIN_BATCH := 5
const GOLD_PER_COIN := 100
const SHOP_ITEM_ID := "wind_boots"
const OBJECTIVE_GOLD := Color(1.0, 0.82, 0.32)
const OBJECTIVE_SHELL := Color(0.85, 0.6, 1.0)
const OBJECTIVE_CRYSTAL := Color(0.45, 0.92, 1.0)
const TEAM_FIGHT_TIME := 60.0
const FINAL_WAVE_RELEASE := 1.5
const DUEL_BOT_HP := 120.0
const SHELL_TELEGRAPH_TIME := 2.0
const SHELL_SOFT_CAP_TIME := 25.0

var game: Node
var stage := "welcome"
var coins_collected := 0
var coins_spawned := 0
var shell_telegraph_timer := 0.0
var shell_fight_timer := 0.0
var shell_hint_near := false
var completed := false
var skipped := false
var stage_timer := 0.0
var final_wave_release_timer := 0.0
var duel_kills := 0
var team_kills := 0
var final_team_kills := 0
var team_ability_used := false
var started_msec := 0


func begin() -> void:
	stage = "welcome"
	coins_collected = 0
	coins_spawned = 0
	shell_telegraph_timer = 0.0
	shell_fight_timer = 0.0
	completed = false
	skipped = false
	stage_timer = 0.0
	duel_kills = 0
	team_kills = 0
	final_team_kills = 0
	team_ability_used = false
	started_msec = Time.get_ticks_msec()
	Stats.track("tutorial_start", {"class": int(game.player.hero_class) if game.player != null else 0})
	_point_to(Vector3.ZERO, OBJECTIVE_GOLD)
	var controls_hint := "Двигайся джойстиком слева, навыки — кнопки справа." if _uses_touch_controls() else "Двигайся клавишами WASD, навыки — 1, 2 и 3."
	game.hud.call(
		"show_tutorial_card",
		"Добро пожаловать!",
		"Цель игры — разбить Оболочку, подобрать Осколок и донести его до базы. В обучении три боя и финал с Оболочкой. Ты не можешь погибнуть. Пропустить можно кнопкой сверху.\n\n%s" % controls_hint,
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
			elif stage == "team_fight_final":
				_finish_team_fight_final(true)
			return
	if game.crystal_state == "carried" and game.carrier == game.player and stage != "deliver_crystal" and stage != "complete":
		stage = "deliver_crystal"
		_point_to(_own_base_position(), OBJECTIVE_CRYSTAL)
		game.hud.call("show_tutorial_hint", "Неси Осколок на свою базу")
		return
	if stage == "reach_center":
		if _player_distance_to_center() <= 5.0:
			_start_duel()
	elif stage == "go_fountain":
		if _fountain_distance() <= 10.0:
			_start_coin_collection()
	elif stage == "collect_coins":
		if _fountain_distance() <= 10.0:
			game.hud.call("show_tutorial_side_hint", "Собери %d монет" % COINS_TO_COLLECT)
		else:
			game.hud.call("hide_tutorial_side_hint")
		# Safety net if a coin was consumed or removed by a cleanup: never leave
		# the player with an empty fountain and a task that cannot progress.
		if game.tutorial_coins_on_ground() == 0 and coins_spawned < COINS_TO_COLLECT:
			_spawn_coin_batch()
	elif stage == "go_shop":
		if game.is_hero_near_shop(game.player):
			_show_shop_hint()
	elif stage == "buy_item":
		if game.is_hero_near_shop(game.player):
			game.hud.call("show_tutorial_side_hint", "Купи «Крылатые ботинки»: +15% скорости")
		else:
			game.hud.call("hide_tutorial_side_hint")
			stage = "go_shop"
	elif stage == "team_fight_final_wait":
		final_wave_release_timer = maxf(0.0, final_wave_release_timer - delta)
		if final_wave_release_timer <= 0.0:
			_release_final_wave()
	elif stage == "shell_prepare":
		_begin_shell_telegraph()
	elif stage == "shell_telegraph":
		shell_telegraph_timer = maxf(0.0, shell_telegraph_timer - delta)
		if shell_telegraph_timer <= 0.0:
			_spawn_shell_for_lesson()
	elif stage == "destroy_shell":
		shell_fight_timer += delta
		if shell_fight_timer >= SHELL_SOFT_CAP_TIME:
			var active_shell = game.shell
			if active_shell != null and is_instance_valid(active_shell) and active_shell.alive and active_shell.max_health > 700.0:
				active_shell.max_health = 700.0
				active_shell.health = minf(active_shell.health, 700.0)
				active_shell._refresh_health_bar()
				game.call("announce", "Оболочка слабеет", Color(0.85, 0.62, 1.0), 2.0)
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
	elif (stage == "shell_telegraph" or stage == "destroy_shell") and index == 2:
		game.hud.call("set_tutorial_ability", -1)


func on_coin_collected() -> void:
	if stage != "collect_coins":
		return
	coins_collected += 1
	if coins_collected < COINS_TO_COLLECT:
		if game.tutorial_coins_on_ground() == 0 and coins_spawned < COINS_TO_COLLECT:
			_spawn_coin_batch()
		return
	if game.gold < COINS_TO_COLLECT * GOLD_PER_COIN:
		push_error("Tutorial fountain did not award the expected match gold")
		return
	game.hud.call("hide_tutorial_side_hint")
	stage = "go_shop"
	_point_to(_shop_position(), OBJECTIVE_GOLD)
	game.hud.call("show_tutorial_hint", "Монеты собраны. Иди в магазин")


func can_buy_item(item_id: String) -> bool:
	return stage == "buy_item" and item_id == SHOP_ITEM_ID


func on_shop_item_bought(item_id: String) -> void:
	if stage != "buy_item" or item_id != SHOP_ITEM_ID:
		return
	game.hud.call("hide_tutorial_side_hint")
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
	game.hud.call("hide_tutorial_side_hint")
	game.hud.call("hide_ui_highlight")
	game.hud.call("set_tutorial_ability", -1)
	Stats.track("tutorial_complete", {
		"elapsed_ms": Time.get_ticks_msec() - started_msec,
		"skipped": false,
	})
	game.hud.call(
		"show_tutorial_victory",
		"Обучение пройдено!",
		"Ты прошёл дуэль, пару, команду и Оболочку. В первых матчах будут такие же лёгкие боты.",
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
	# Compatibility for the old probes: there is no modal card any more.
	_start_coin_collection()


func _start_coin_collection() -> void:
	if stage == "collect_coins":
		return
	if stage != "go_fountain":
		return
	game.hud.call("hide_ui_highlight")
	stage = "collect_coins"
	coins_collected = 0
	coins_spawned = 0
	_spawn_coin_batch()
	game.hud.call("show_tutorial_side_hint", "Собери %d монет" % COINS_TO_COLLECT)


func _spawn_coin_batch() -> void:
	var remaining := COINS_TO_COLLECT - coins_spawned
	if remaining <= 0:
		return
	var batch := mini(COIN_BATCH, remaining)
	game.call("spawn_tutorial_coins", batch, GOLD_PER_COIN)
	coins_spawned += batch


func _show_shop_card() -> void:
	# Compatibility for the old probes: there is no modal card any more.
	_show_shop_hint()


func _show_shop_hint() -> void:
	if stage != "go_shop":
		return
	stage = "buy_item"
	game.hud.call("hide_ui_highlight")
	game.hud.call("set_tutorial_shop_item", SHOP_ITEM_ID)
	game.hud.call("show_tutorial_side_hint", "Купи «Крылатые ботинки»: +15% скорости")


func _open_shop_for_tutorial() -> void:
	# Compatibility: the shop opens by proximity when the stage is buy_item;
	# there is no teleport/fade and no modal card.
	if stage == "buy_item":
		game.hud.call("show_tutorial_side_hint", "Купи «Крылатые ботинки»: +15% скорости")
		return
	if stage == "shop_intro":
		stage = "go_shop"
	_show_shop_hint()


func _start_duel() -> void:
	if stage != "reach_center":
		return
	stage = "duel"
	duel_kills = 0
	stage_timer = 60.0
	game.clear_tutorial_bots()
	game.player.reset_for_tutorial_stage()
	var bot: HeroUnit = game.spawn_tutorial_bot(
		HeroUnit.Cls.FAIRY,
		1 - int(game.player.team),
		Vector3(0.0, 0.76, -4.0),
		"easy",
		"Тренировочный бот"
	)
	# Duel target: stands still, turns to the player and shoots weak bolts.
	bot.tutorial_stationary = true
	bot.move_speed = 0.0
	bot.attack_damage = 10.0
	bot.max_health = DUEL_BOT_HP
	bot.health = DUEL_BOT_HP
	bot.ability_cds = [99.0, 99.0, 99.0]
	bot.call("_update_health_display")
	var to_player: Vector3 = game.player.global_position - bot.global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.001:
		bot.rotation.y = atan2(to_player.x, to_player.z)
	game.hud.call("hide_ui_highlight")
	game.hud.call("show_tutorial_hint", "Этап 1/3 · Дуэль: победи тренировочного бота")
	game.hud.call("set_tutorial_ability", 0)
	_point_to(bot.global_position, OBJECTIVE_GOLD)
	Stats.track("tutorial_stage", {"stage": "duel", "index": 1})


func _finish_duel(_timed_out := false) -> void:
	if stage != "duel":
		return
	stage = "duel_done"
	stage_timer = 0.0
	game.clear_tutorial_bots()
	game.player.reset_for_tutorial_stage()
	game.hud.call("set_tutorial_ability", -1)
	_clear_target()
	var body := "Дуэль пройдена. Дальше — фонтан и лавка: собери золото и купи улучшение."
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
	stage_timer = TEAM_FIGHT_TIME
	game.clear_tutorial_bots()
	game.player.reset_for_tutorial_stage()
	var ally_pos: Vector3 = game.clamp_to_arena(game.player.global_position + Vector3(3.0, 0.0, 0.0))
	ally_pos.y = 0.76
	game.spawn_tutorial_bot(HeroUnit.Cls.FAIRY, int(game.player.team), ally_pos, "easy", "Союзник")
	var enemy_one: HeroUnit = game.spawn_tutorial_bot(
		HeroUnit.Cls.MAGE,
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


func _finish_team_fight(_timed_out := false) -> void:
	if stage != "team_fight":
		return
	stage = "team_fight_done"
	stage_timer = 0.0
	game.clear_tutorial_bots()
	game.player.reset_for_tutorial_stage()
	game.hud.call("set_tutorial_ability", -1)
	_clear_target()
	var body := "Пара пройдена. Сейчас 3 на 3, без Оболочки. Оболочка будет в финале."
	game.hud.call("show_tutorial_card", "Этап 2/3 пройден", body, "К команде", Callable(self, "_start_team_fight_final"))


func _start_team_fight_final() -> void:
	if stage != "team_fight_done":
		return
	game.hud.call("hide_tutorial_card")
	game.hud.call("hide_ui_highlight")
	stage = "team_fight_final"
	stage_timer = TEAM_FIGHT_TIME
	final_team_kills = 0
	game.clear_tutorial_bots()
	game.player.reset_for_tutorial_stage()
	Stats.track("tutorial_stage", {"stage": "team_fight_final", "index": 3})
	_spawn_final_wave()


func _spawn_final_wave() -> void:
	stage = "team_fight_final_wait"
	final_team_kills = 0
	final_wave_release_timer = FINAL_WAVE_RELEASE
	game.clear_tutorial_bots()
	var spots := _enemy_base_spots()
	var enemy_team := 1 - int(game.player.team)
	for index in 3:
		var bot: HeroUnit = game.spawn_tutorial_bot(
			[HeroUnit.Cls.WARRIOR, HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY][index],
			enemy_team,
			spots[index],
			"easy",
			"Тренировочный бот"
		)
		bot.tutorial_hold = true
		bot.rotation.y = PI if enemy_team == 1 else 0.0
	var player_pos: Vector3 = game.player.global_position
	var ally_classes := [HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY]
	var ally_offsets := [Vector3(2.5, 0.0, 2.0), Vector3(-2.5, 0.0, 2.0)]
	for index in 2:
		var ally_pos: Vector3 = game.clamp_to_arena(player_pos + ally_offsets[index])
		ally_pos.y = 0.76
		var ally: HeroUnit = game.spawn_tutorial_bot(
			ally_classes[index],
			int(game.player.team),
			ally_pos,
			"easy",
			"Союзник"
		)
		ally.tutorial_hold = true
	var enemy_base := _enemy_base_position()
	game.hud.call("show_tutorial_hint", "Этап 3/3 · Враги выходят с базы")
	_point_to(enemy_base, OBJECTIVE_GOLD)
	game.hud.call("minimap_ping", enemy_base, OBJECTIVE_GOLD, 3.0)
	Stats.track("tutorial_stage", {"stage": "team_fight_final_wait", "index": 3})


func _release_final_wave() -> void:
	if stage != "team_fight_final_wait":
		return
	stage = "team_fight_final"
	for bot in game.tutorial_bots:
		if bot != null and is_instance_valid(bot):
			bot.release_tutorial_hold()
	game.hud.call("show_tutorial_hint", "Враги вышли с базы")
	game.hud.call("minimap_ping", Vector3.ZERO, OBJECTIVE_SHELL, 2.5)
	game.call("announce", "Враги вышли с базы", Color(1.0, 0.72, 0.42), 2.5)
	Stats.track("tutorial_stage", {"stage": "team_fight_final_start", "index": 3})


func _finish_team_fight_final(_timed_out := false) -> void:
	if stage != "team_fight_final":
		return
	stage = "team_fight_final_done"
	stage_timer = 0.0
	game.clear_tutorial_bots()
	game.player.reset_for_tutorial_stage()
	game.hud.call("set_tutorial_ability", -1)
	_clear_target()
	var body := "Команда прошла. Теперь финал: Оболочка, осколок и база. В обучении она не атакует."
	game.hud.call("show_tutorial_card", "Этап 3/3 пройден", body, "К финалу", Callable(self, "_start_shell_lesson"))


func _start_shell_lesson() -> void:
	if stage != "team_fight_final_done":
		return
	stage = "shell_intro"
	game.hud.call("hide_ui_highlight")
	game.clear_tutorial_bots()
	game.player.reset_for_tutorial_stage()
	game.hud.call(
		"show_tutorial_card",
		"Финал · Оболочка",
		"Разбей Оболочку, забери Осколок и донеси его на базу. В обучении она не атакует.",
		"Начать финал",
		Callable(self, "_begin_shell_prepare")
	)
	Stats.track("tutorial_stage", {"stage": "shell", "index": 4})


func _begin_shell_prepare() -> void:
	if stage != "shell_intro":
		return
	game.hud.call("hide_tutorial_card")
	stage = "shell_prepare"
	shell_telegraph_timer = 0.0
	shell_fight_timer = 0.0
	game.hud.call("show_tutorial_hint", "Финал · Оболочка")
	_point_to(Vector3.ZERO, OBJECTIVE_SHELL)
	game.hud.call("minimap_ping", Vector3.ZERO, OBJECTIVE_SHELL, 3.0)
	_begin_shell_telegraph()


func _begin_shell_telegraph() -> void:
	if stage != "shell_prepare":
		return
	stage = "shell_telegraph"
	shell_telegraph_timer = SHELL_TELEGRAPH_TIME
	game.hud.call("show_tutorial_hint", "Оболочка пробуждается")
	game.call("announce", "Оболочка пробуждается", Color(0.8, 0.5, 1.0), SHELL_TELEGRAPH_TIME)
	game.call("telegraph", Vector3.ZERO, 3.0, SHELL_TELEGRAPH_TIME, Color(0.8, 0.5, 1.0))
	_point_to(Vector3.ZERO, OBJECTIVE_SHELL)


func _spawn_shell_for_lesson() -> void:
	stage = "destroy_shell"
	shell_hint_near = false
	shell_fight_timer = 0.0
	game.call("_spawn_shell")
	game.hud.call("show_tutorial_hint", "Уничтожь Оболочку — внутри неё Небесный Осколок")
	game.hud.call("set_tutorial_ability", 2)
	_point_to(Vector3.ZERO, OBJECTIVE_SHELL)


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
	elif stage == "team_fight_final":
		final_team_kills += 1
		if final_team_kills >= 3:
			_finish_team_fight_final()


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
		"team_fight_final_wait":
			return "Этап 3/3 · Враги выходят с базы"
		"team_fight_final":
			return "Этап 3/3 · Враги вышли с базы"
		"shell_prepare":
			return "Финал · Оболочка"
		"shell_telegraph":
			return "Оболочка пробуждается"
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
	MetaProgression.tutorial_completed = true
	MetaProgression.tutorial_skipped = false
	MetaProgression.save_progress()


func _save_skip() -> void:
	MetaProgression.tutorial_completed = false
	MetaProgression.tutorial_skipped = true
	MetaProgression.save_progress()


func _uses_touch_controls() -> bool:
	return DeviceProfile.touch_controls


func _player_distance_to_center() -> float:
	if game.player == null or not is_instance_valid(game.player):
		return INF
	var position: Vector3 = game.player.global_position
	return Vector2(position.x, position.z).length()


func _enemy_base_position() -> Vector3:
	var base_z := -float(game.BASE_POSITION_Z) if int(game.player.team) == 0 else float(game.BASE_POSITION_Z)
	return Vector3(0.0, 0.0, base_z)


func _enemy_base_spots() -> Array[Vector3]:
	var base_z := _enemy_base_position().z
	var inward := -signf(base_z)
	# Just outside the base shield: the normal match spawns bots inside the
	# dome and they immediately walk out, but a tutorial wave that waits there
	# would be hidden by the dome. The exit is still the enemy base.
	return [
		Vector3(3.0, 0.76, base_z + inward * 5.5),
		Vector3(0.0, 0.76, base_z + inward * 5.2),
		Vector3(-3.0, 0.76, base_z + inward * 5.5),
	]


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


func _fountain_distance() -> float:
	if game.player == null or not is_instance_valid(game.player):
		return INF
	var fountain := _fountain_position()
	var position: Vector3 = game.player.global_position
	return Vector2(position.x - fountain.x, position.z - fountain.z).length()


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
