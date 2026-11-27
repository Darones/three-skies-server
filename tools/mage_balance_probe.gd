extends Node3D

## Mage balance probe.
##
## Verifies option 5A on the client side and the matching server contract:
##   * CLASS_DATA[MAGE].damage is exactly 39 (+50% of the old 26),
##   * the storm tick is MAGE_STORM_DAMAGE = 70,
##   * roll_ultimate_damage crits ~10% of 10 000 rolls for x2,
##   * a non-crit tick rolls 52.5-87.5, a crit tick 105-175,
##   * the mean storm tick is ~77 (70 x (0.9 + 0.1 x 2)),
##   * ordinary auto attacks still crit at 5%, not 10%,
##   * server/ws.go keeps classBaseDamage[1]=39 and the 1.4
##     ult_lightning_storm multiplier (54.6 base), so a normal network tick
##     (x2 outgoing = 105-175) passes in full, and mageUltDamageCap = 250 clips
##     the x2 crit (210-350) instead of the generic 2.6x roll cap (~284).
##
## Prints PASS/FAIL and exits non-zero on any failure.

const ROLLS := 10000
const MAGE_BASE_DAMAGE := 39.0
const STORM_TICK := 70.0
const EXPECTED_ULT_CRIT_RATE := 0.10
const EXPECTED_AUTO_CRIT_RATE := 0.05
const EXPECTED_STORM_MEAN := 77.0
# Server contract for the storm (server/ws.go).
const SERVER_STORM_MULTIPLIER := 1.4
const SERVER_STORM_CAP := 250.0
const SERVER_ROLL_TOLERANCE := 2.6

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
	_case_storm_constant()
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


func _case_storm_constant() -> void:
	print("--- storm constant ---")
	_check(
		is_equal_approx(HeroUnit.MAGE_STORM_DAMAGE, STORM_TICK),
		"MAGE_STORM_DAMAGE %.1f == %.1f (was 100)" % [HeroUnit.MAGE_STORM_DAMAGE, STORM_TICK]
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
	var non_crit_expected_min := STORM_TICK * HeroUnit.DIRECT_DAMAGE_MIN_MULTIPLIER
	var non_crit_expected_max := STORM_TICK * HeroUnit.DIRECT_DAMAGE_MAX_MULTIPLIER
	for _i in ROLLS:
		var rolled := player.roll_ultimate_damage(STORM_TICK)
		total += rolled
		if player.last_ultimate_crit:
			crits += 1
			crit_min = minf(crit_min, rolled)
			crit_max = maxf(crit_max, rolled)
			if rolled < non_crit_expected_min * HeroUnit.CRITICAL_DAMAGE_MULTIPLIER:
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
	# 70 x avg(0.75..1.25) x (1 + 0.10) = 77.
	_check(
		absf(mean - EXPECTED_STORM_MEAN) <= 2.0,
		"storm mean %.1f == 77 (70 x 0.75-1.25 x 10%% crit)" % mean
	)
	_check(
		non_crit_min >= non_crit_expected_min,
		"non-crit storm tick >= 52.5 (got %.1f)" % non_crit_min
	)
	_check(
		non_crit_max <= non_crit_expected_max,
		"non-crit storm tick <= 87.5 (got %.1f)" % non_crit_max
	)
	_check(
		crits > 0 and crit_below_double == 0,
		"every crit tick is at least x2 (%d crits checked)" % crits
	)
	_check(
		crit_min >= non_crit_expected_min * HeroUnit.CRITICAL_DAMAGE_MULTIPLIER,
		"crit storm tick >= 105 (got %.1f)" % crit_min
	)
	_check(
		crit_max <= non_crit_expected_max * HeroUnit.CRITICAL_DAMAGE_MULTIPLIER,
		"crit storm tick <= 175 (got %.1f)" % crit_max
	)
	# Network: take_damage budgets the x2 outgoing hit, 105-175 normal and
	# 210-350 on a crit; the server's storm cap has to absorb both.
	var network_normal_max := non_crit_expected_max * HeroUnit.HERO_OUTGOING_DAMAGE_MULTIPLIER
	var network_crit_max := non_crit_expected_max * HeroUnit.CRITICAL_DAMAGE_MULTIPLIER \
		* HeroUnit.HERO_OUTGOING_DAMAGE_MULTIPLIER
	print("network normal <= %.1f, crit <= %.1f" % [network_normal_max, network_crit_max])
	_check(
		network_crit_max > SERVER_STORM_CAP,
		"the 250 storm cap is what clips a x2 crit (%.1f)" % network_crit_max
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
	_check(
		source.contains("const mageUltDamageCap = 250.0"),
		"server mageUltDamageCap = 250"
	)
	var function_start := source.find("func calculateDamageFor(")
	var function_end := source.find("\nfunc ", function_start + 1) if function_start >= 0 else -1
	var function_body := ""
	if function_start >= 0:
		function_body = source.substr(function_start, function_end - function_start if function_end > function_start else 4000)
	var case_pos := function_body.find("case \"ult_lightning_storm\":")
	var case_block := function_body.substr(case_pos, 400) if case_pos >= 0 else ""
	_check(
		case_block.contains("multiplier = 1.4"),
		"server calculateDamageFor: ult_lightning_storm multiplier = 1.4"
	)
	# 39 x 1.4 = 54.6; the generic roll cap is 54.6 x 2 x 2.6 = 283.92, and the
	# explicit storm cap is 250. A normal x2 tick (105-175) passes untouched,
	# a x2 crit (210-350) is cut to 250 instead of ~284.
	var server_storm_base := MAGE_BASE_DAMAGE * SERVER_STORM_MULTIPLIER
	var generic_cap := server_storm_base * 2.0 * SERVER_ROLL_TOLERANCE
	var network_normal_max := STORM_TICK * HeroUnit.DIRECT_DAMAGE_MAX_MULTIPLIER \
		* HeroUnit.HERO_OUTGOING_DAMAGE_MULTIPLIER
	print("server storm base=%.1f generic cap=%.2f storm cap=%.0f" % [
		server_storm_base, generic_cap, SERVER_STORM_CAP
	])
	_check(
		is_equal_approx(server_storm_base, 54.6),
		"server storm base 39 x 1.4 = 54.6 (got %.1f)" % server_storm_base
	)
	_check(
		generic_cap >= network_normal_max,
		"server generic cap %.1f accepts the normal x2 tick (<=%.1f)" % [generic_cap, network_normal_max]
	)
	_check(
		SERVER_STORM_CAP < generic_cap,
		"storm cap 250 is the binding limit below the generic %.1f" % generic_cap
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
