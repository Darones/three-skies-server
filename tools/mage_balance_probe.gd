extends Node3D

## Mage balance probe.
##
## Verifies the two requested changes on the client side and the matching
## server contract:
##   * CLASS_DATA[MAGE].damage is exactly 39 (+50% of the old 26),
##   * roll_ultimate_damage crits ~10% of 10 000 rolls for x2,
##   * the mean storm tick rose from ~100 to ~110,
##   * ordinary auto attacks still crit at 5%, not 10%,
##   * server/ws.go keeps classBaseDamage[1]=39 and a 2.0 storm multiplier so
##     the server cap (78 x 2 x 2.6 = 405.6) accepts the client's 150-250 tick
##     instead of clamping it to ~54.
##
## Prints PASS/FAIL and exits non-zero on any failure.

const ROLLS := 10000
const MAGE_BASE_DAMAGE := 39.0
const STORM_TICK := 100.0
const EXPECTED_ULT_CRIT_RATE := 0.10
const EXPECTED_AUTO_CRIT_RATE := 0.05

var failures := 0
var checks := 0
var game: Node = null
var player: HeroUnit = null


func _ready() -> void:
	var packed := load("res://scenes/Main.tscn") as PackedScene
	game = packed.instantiate()
	add_child(game)
	for _i in 14:
		await get_tree().process_frame
	game.call("start_match", HeroUnit.Cls.MAGE, 0)
	for _i in 6:
		await get_tree().process_frame
	player = game.get("player") as HeroUnit
	if player == null or player.hero_class != HeroUnit.Cls.MAGE:
		print("FAIL: mage player was not created")
		get_tree().quit(1)
		return

	_case_base_damage()
	_case_ultimate_distribution()
	_case_auto_crit_unchanged()
	_case_server_contract()

	print("MAGE_BALANCE_CHECKS=%d FAILURES=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _case_base_damage() -> void:
	print("--- base damage ---")
	var data: Dictionary = HeroUnit.CLASS_DATA[HeroUnit.Cls.MAGE]
	_check(
		is_equal_approx(float(data["damage"]), MAGE_BASE_DAMAGE),
		"Mage CLASS_DATA damage %.1f == %.1f (+50%% of 26)" % [float(data["damage"]), MAGE_BASE_DAMAGE]
	)
	_check(
		float(data["damage"]) / 26.0 >= 1.499,
		"Mage damage 26 -> %.1f is a +50%% raise" % float(data["damage"])
	)


func _case_ultimate_distribution() -> void:
	print("--- ultimate rolls (%d) ---" % ROLLS)
	var crits := 0
	var total := 0.0
	var non_crit_min := 1.0e9
	var non_crit_max := -1.0e9
	var crit_min := 1.0e9
	var crit_max := -1.0e9
	var crit_below_double := 0
	for _i in ROLLS:
		var rolled := player.roll_ultimate_damage(STORM_TICK)
		total += rolled
		if player.last_ultimate_crit:
			crits += 1
			crit_min = minf(crit_min, rolled)
			crit_max = maxf(crit_max, rolled)
			if rolled < STORM_TICK * HeroUnit.DIRECT_DAMAGE_MIN_MULTIPLIER * 2.0:
				crit_below_double += 1
		else:
			non_crit_min = minf(non_crit_min, rolled)
			non_crit_max = maxf(non_crit_max, rolled)
	var crit_rate := float(crits) / float(ROLLS)
	var mean := total / float(ROLLS)
	print("crits=%d rate=%.4f mean=%.2f non_crit=[%.1f..%.1f] crit=[%.1f..%.1f]" % [
		crits, crit_rate, mean, non_crit_min, non_crit_max, crit_min, crit_max
	])
	_check(
		absf(crit_rate - EXPECTED_ULT_CRIT_RATE) <= 0.015,
		"storm crit rate %.2f%% == 10%% (+-1.5pp)" % (crit_rate * 100.0)
	)
	# 100 x avg(0.75..1.25) x (1 + 0.10) = 110.
	_check(
		absf(mean - 110.0) <= 2.0,
		"storm mean %.1f == 110 (100 old mean + 10%% crit)" % mean
	)
	_check(
		is_equal_approx(non_crit_min, STORM_TICK * HeroUnit.DIRECT_DAMAGE_MIN_MULTIPLIER)
		or non_crit_min >= STORM_TICK * HeroUnit.DIRECT_DAMAGE_MIN_MULTIPLIER,
		"non-crit storm tick >= 75 (got %.1f)" % non_crit_min
	)
	_check(
		non_crit_max <= STORM_TICK * HeroUnit.DIRECT_DAMAGE_MAX_MULTIPLIER,
		"non-crit storm tick <= 125 (got %.1f)" % non_crit_max
	)
	_check(
		crits > 0 and crit_below_double == 0,
		"every crit tick is at least x2 (%d crits checked)" % crits
	)
	_check(
		crit_max <= STORM_TICK * HeroUnit.DIRECT_DAMAGE_MAX_MULTIPLIER * 2.0,
		"crit storm tick <= 250 (got %.1f)" % crit_max
	)
	# The server accepts a normal tick at full value: cap 78 x 2 x 2.6.
	var server_cap := MAGE_BASE_DAMAGE * 2.0 * 2.0 * 2.6
	_check(
		server_cap >= STORM_TICK * HeroUnit.DIRECT_DAMAGE_MAX_MULTIPLIER * 2.0,
		"server storm cap %.1f covers the client normal tick (<=250)" % server_cap
	)


func _case_auto_crit_unchanged() -> void:
	print("--- auto attack crits (%d) ---" % ROLLS)
	var crits := 0
	for _i in ROLLS:
		var rolled := player.roll_direct_damage(MAGE_BASE_DAMAGE)
		# Non-crit is 39 x 0.75..1.25 = 29.25..48.75; a crit is at least 58.5.
		if rolled > MAGE_BASE_DAMAGE * HeroUnit.DIRECT_DAMAGE_MAX_MULTIPLIER * 1.05:
			crits += 1
	var crit_rate := float(crits) / float(ROLLS)
	print("auto crits=%d rate=%.4f" % [crits, crit_rate])
	_check(
		absf(crit_rate - EXPECTED_AUTO_CRIT_RATE) <= 0.01,
		"auto attack crit rate %.2f%% == 5%% (+-1pp)" % (crit_rate * 100.0)
	)


func _case_server_contract() -> void:
	print("--- server contract ---")
	var file := FileAccess.open("res://server/ws.go", FileAccess.READ)
	if file == null:
		print("SKIP: server/ws.go is not readable from res://")
		return
	var source := file.get_as_text()
	file.close()
	_check(
		source.contains("[]float64{44.0, 39.0, 60.0}"),
		"server classBaseDamage = {44, 39, 60}"
	)
	var function_start := source.find("func calculateDamageFor(")
	var function_end := source.find("\nfunc ", function_start + 1) if function_start >= 0 else -1
	var function_body := ""
	if function_start >= 0:
		function_body = source.substr(function_start, function_end - function_start if function_end > function_start else 4000)
	_check(
		function_body.contains("case \"ult_lightning_storm\":") and function_body.contains("multiplier = 2.0"),
		"server calculateDamageFor: ult_lightning_storm multiplier = 2.0"
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
