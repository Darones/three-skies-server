extends RefCounted

## Where the match audio comes from, for the loading screen.
##
## game.gd reads the battle theme, the arena ambience and every SFX with a
## synchronous `load()` inside `_setup_audio()` — which runs in Main's `_ready`,
## i.e. inside the one scene-switch frame the player sees as the start of the
## match. Measured cold on this machine: music 4.9 ms + ambience 1.8 ms + SFX
## 20 ms ≈ 27 ms of that frame, plus the first play() has to wait for the
## stream. The loading screen preloads the same list while the warmup runs, and
## keeps the references until the match has started, so those `load()` calls
## are cache hits.
##
## The SFX list is read from game.gd's own `SFX_PATHS` constant, so it can never
## drift from the real game. Everything here is defensive: a game.gd that fails
## to parse, or a renamed constant, only means "nothing extra to preload".

const MUSIC_PATH := "res://audio/music/dread/6adcd384-a1c6-4d03-ab8f-2885c6220fd5_music_dark_fantasy_arena_battle_them__1793744175999.mp3"
const AMBIENT_PATH := "res://audio/ambient/arena_wind.mp3"
const GAME_SCRIPT_PATH := "res://scripts/game.gd"


## Every audio resource `game.gd._setup_audio()` loads, in load order:
## battle theme, arena ambience, then the game's SFX dictionary.
static func stream_paths() -> Array[String]:
	var paths: Array[String] = [MUSIC_PATH, AMBIENT_PATH]
	for path in game_sfx_paths():
		if not paths.has(path):
			paths.append(path)
	return paths


## The values of `SFX_PATHS` in game.gd (empty if they cannot be read).
static func game_sfx_paths() -> Array[String]:
	var paths: Array[String] = []
	var script := load(GAME_SCRIPT_PATH) as GDScript
	if script == null:
		return paths
	var constants: Dictionary = script.get_script_constant_map()
	if not constants.has("SFX_PATHS"):
		return paths
	var sfx: Variant = constants["SFX_PATHS"]
	if not sfx is Dictionary:
		return paths
	for key in (sfx as Dictionary).keys():
		var path := String((sfx as Dictionary)[key])
		if path.is_empty():
			continue
		paths.append(path)
	return paths
