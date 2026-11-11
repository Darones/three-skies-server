extends Node

const SETTINGS_PATH := "user://settings.cfg"
const LEGACY_SETTINGS_PATH := "user://game_settings.cfg"
const SETTINGS_SECTION := "haptics"
const SETTINGS_KEY := "haptics_enabled"
const DEFAULT_ENABLED := true
const MIN_DURATION_MS := 10
const MAX_DURATION_MS := 1000

var enabled := DEFAULT_ENABLED


func _ready() -> void:
	var config := ConfigFile.new()
	var loaded := config.load(SETTINGS_PATH) == OK
	var has_setting := loaded and config.has_section_key(SETTINGS_SECTION, SETTINGS_KEY)
	if has_setting:
		enabled = bool(config.get_value(SETTINGS_SECTION, SETTINGS_KEY, DEFAULT_ENABLED))
	else:
		var legacy := ConfigFile.new()
		if legacy.load(LEGACY_SETTINGS_PATH) == OK:
			enabled = bool(legacy.get_value("mobile", "vibration", DEFAULT_ENABLED))
		else:
			enabled = DEFAULT_ENABLED
		save_settings()


func is_enabled() -> bool:
	return enabled


func set_enabled(value: bool) -> void:
	enabled = value
	save_settings()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY, enabled)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Haptics: could not save settings: %s" % error_string(error))


func vibrate(duration_ms: int) -> void:
	if not enabled:
		return
	var duration := clampi(duration_ms, MIN_DURATION_MS, MAX_DURATION_MS)
	if OS.has_feature("web"):
		var code := "if(navigator.vibrate) navigator.vibrate(" + str(duration) + ");"
		JavaScriptBridge.eval(code)
	elif OS.has_feature("mobile"):
		Input.vibrate_handheld(duration)
