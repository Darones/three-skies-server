extends Node

## D1 client/server contract: bot profile values and the match_start field.

var failures := 0


func _ready() -> void:
	var easy: Dictionary = HeroUnit.BOT_PROFILES["easy"]
	var normal: Dictionary = HeroUnit.BOT_PROFILES["normal"]
	var hard: Dictionary = HeroUnit.BOT_PROFILES["hard"]
	_check(float(normal["damage"]) == 0.8 and float(normal["hp"]) == 1.0, "normal bot profile keeps old values")
	_check(float(easy["damage"]) == 0.6 and float(easy["hp"]) == 0.8, "easy bot profile matches server")
	_check(float(hard["damage"]) == 1.0 and float(hard["hp"]) == 1.1, "hard bot profile matches server")

	NetworkManager.call("_handle_match_start", {
		"room_id": 1,
		"host_id": 0,
		"match_players": [],
		"bot_difficulty": "easy",
	})
	_check(NetworkManager.bot_difficulty == "easy", "match_start parses easy difficulty")
	NetworkManager.call("_handle_match_start", {
		"room_id": 1,
		"host_id": 0,
		"match_players": [],
		"bot_difficulty": "unknown",
	})
	_check(NetworkManager.bot_difficulty == "normal", "unknown difficulty falls back to normal")
	NetworkManager.bot_difficulty = "normal"

	_check(MetaProgression.get("matches_played") != null, "profile exposes matches_played")
	_check(MetaProgression.get("novice") != null, "profile exposes novice")
	print("D1_CONTRACT_FAILURES=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
