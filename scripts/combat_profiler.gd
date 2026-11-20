extends Node

## Lightweight combat hitch profiler.
##
## Disabled by default. Enable with the `profile=1` URL parameter or
## `--profile` on the command line, reproduce the fight, and read the
## `[HITCH]` lines in the console. It records the last 24 combat events
## (VFX, sound, damage, projectile, shell) so a frame spike can be tied to
## what happened just before it.

var enabled := false
var _last_usec := 0
var _events: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = DeviceProfile.profile_mode or OS.get_cmdline_user_args().has("--profile")
	if enabled:
		print("[PROFILE] Combat profiler enabled")


func mark(kind: String, detail := "") -> void:
	if not enabled:
		return
	_events.append("%d %s %s" % [Time.get_ticks_msec(), kind, detail])
	if _events.size() > 24:
		_events.pop_front()


func _process(_delta: float) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		var ms := float(now - _last_usec) / 1000.0
		if ms >= 80.0:
			var scene := get_tree().current_scene
			var extra := ""
			if scene != null and scene.has_method("debug_state"):
				extra = str(scene.call("debug_state"))
			var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			print("[HITCH] %.1fms nodes=%d draws=%d %s | events=%s" % [ms, nodes, draws, extra, str(_events)])
			_events.clear()
	_last_usec = now
