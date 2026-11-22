extends Node

## Fire-and-forget player analytics. One small queue, its own HTTPRequest, so
## gameplay REST calls in NetworkClient never wait for stats.
## Junk traffic (VK crawlers, previews, headless) is classified on the server
## from the user agent and page views; this node only sends real client events.

const DEFAULT_API := "https://three-skies-server.relaxdev.ru"
const FLUSH_SECONDS := 6.0
const HEARTBEAT_SECONDS := 45.0

var session_id := ""
var platform := "Web/Desktop"
var user_agent := ""
var events: Array[Dictionary] = []
var http: HTTPRequest
var busy := false
var heartbeat_timer := 0.0
var flush_timer := 0.0
var started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	session_id = _new_session_id()
	_detect_platform()
	http = HTTPRequest.new()
	http.name = "StatsHTTP"
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(_on_request_completed)
	call_deferred("_start_session")


func _new_session_id() -> String:
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	return "%x%04x" % [stamp, randi() & 0xffff]


func _detect_platform() -> void:
	var device := "Desktop"
	if OS.has_feature("mobile"):
		device = OS.get_name()
	user_agent = OS.get_name()
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		var ua := String(bridge.call("eval", "navigator.userAgent", true))
		if not ua.is_empty():
			user_agent = ua
		var search := String(bridge.call("eval", "window.location.search", true))
		var lower := user_agent.to_lower()
		if lower.contains("iphone") or lower.contains("ipad") or lower.contains("ipod"):
			device = "iOS"
		elif lower.contains("android"):
			device = "Android"
		if search.contains("vk_client=ok"):
			platform = "OK/" + device
			return
		if search.contains("vk_app_id") or search.contains("vk_platform"):
			platform = "VK/" + device
			return
		platform = "Web/" + device
		return
	if OS.has_feature("mobile"):
		platform = "App/" + device
	else:
		platform = "Desktop/" + device


func _start_session() -> void:
	if started:
		return
	started = true
	await get_tree().create_timer(0.8).timeout
	var class_id := 0
	if get_tree().has_meta("selected_class"):
		class_id = int(get_tree().get_meta("selected_class"))
	var hero_class_name := _class_name(class_id)
	track("session_start", {"class": hero_class_name})


func _class_name(class_id: int) -> String:
	match class_id:
		0:
			return "warrior"
		1:
			return "mage"
		2:
			return "fairy"
	return "unknown"


func track(event: String, payload: Dictionary = {}) -> void:
	if event.is_empty():
		return
	events.append({
		"ts": Time.get_unix_time_from_system(),
		"event": event,
		"player_id": _player_id(),
		"session": session_id,
		"platform": platform,
		"screen": _screen_name(),
		"ua": user_agent,
		"payload": payload,
	})
	if events.size() >= 8:
		flush()


func _player_id() -> int:
	return int(MetaProgression.player_id)


func _screen_name() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	return String(scene.name)


func _process(delta: float) -> void:
	flush_timer += delta
	heartbeat_timer += delta
	if flush_timer >= FLUSH_SECONDS:
		flush_timer = 0.0
		flush()
	if heartbeat_timer >= HEARTBEAT_SECONDS:
		heartbeat_timer = 0.0
		track("heartbeat", {})


func flush() -> void:
	if busy or events.is_empty() or http == null:
		return
	var batch := events.duplicate(true)
	events.clear()
	busy = true
	var body := JSON.stringify({"events": batch})
	var base := DEFAULT_API
	base = String(NetworkClient.api_base_url)
	if base.is_empty():
		base = String(ProjectSettings.get_setting("network/api_base_url", DEFAULT_API))
	base = base.trim_suffix("/")
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := http.request(base + "/stats/event", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		busy = false


func _on_request_completed(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	busy = false
	if not events.is_empty():
		flush()
