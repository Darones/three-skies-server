extends "res://scripts/platform/platform_adapter.gd"

## VK launch-param authentication. The bridge/SDK lives only in this adapter;
## the core receives a server profile and never talks to VK directly.

var _host: Node
var _launch_params: Dictionary = {}
var _profile: Dictionary = {}
var _avatar := ""
var _session_token := ""
var _authenticated := false
var _auth_in_progress := false
var _last_error := ""
var _js_launch_cb = null
var _js_user_cb = null
var _launch_ready := false
var _launch_result: Dictionary = {}
var _user_ready := false
var _user_result: Dictionary = {}
var _js_ad_cb = null
var _ad_ready := false
var _ad_result: Dictionary = {}
var _ad_busy := false
var _ad_request_seq := 0
var _ads_checked := false
var _rewarded_available := false
var _interstitial_available := false

# VK resolves the ShowNativeAds promise only after the ad is closed, so the
# wait budget must cover the whole video, not just the load. The old 20 s
# default made a watched 30 s rewarded video end as "timeout": no x2, even
# though the player had just watched the ad. 120 s is four times the longest
# VK reward video plus loading, and still bounds a stuck bridge.
const REWARDED_SHOW_TIMEOUT := 120.0
const INTERSTITIAL_SHOW_TIMEOUT := 90.0
# A concurrent show (the results screen and the availability refresh) may wait
# for the slot, but never forever: three seconds is far longer than the check
# call and short enough that a leaked _ad_busy cannot freeze the game.
const AD_BUSY_WAIT_MS := 3000


func _init() -> void:
	platform_id = "vk"
	display_name = "VK"


func initialize(host: Node) -> void:
	_host = host


func authenticate() -> bool:
	if _authenticated:
		return true
	if _auth_in_progress:
		return false
	_auth_in_progress = true
	_last_error = ""
	var launch: Dictionary = await _get_launch_params()
	if not bool(launch.get("ok", false)):
		_fail(String(launch.get("error", "vk_launch_params")))
		return false
	_launch_params = launch.get("params", {})
	var auth: Dictionary = await NetworkClient.auth_vk(_launch_params)
	if not _apply_auth(auth):
		_auth_in_progress = false
		return false
	# The display name is cosmetic; identity already comes from the signed
	# vk_user_id. Fetch it after the server has verified the launch params.
	var user: Dictionary = await _get_user_info()
	if bool(user.get("ok", false)):
		var data: Dictionary = user.get("data", {})
		var display_name_text := _display_name(data)
		_avatar = String(data.get("photo_200", data.get("photo_100", "")))
		if not display_name_text.is_empty():
			var updated: Dictionary = await NetworkClient.auth_vk(_launch_params, display_name_text, _avatar)
			if bool(updated.get("success", false)):
				_apply_auth(updated)
	_authenticated = true
	_auth_in_progress = false
	# Cache real VK ad fill before the results screen asks for it. The show
	# methods still re-check at click time.
	_refresh_ad_availability()
	return true


func is_ready() -> bool:
	return _authenticated


func is_authenticated() -> bool:
	return _authenticated


func get_auth_error() -> String:
	return _last_error


func get_user() -> Dictionary:
	return {
		"id": String(_launch_params.get("vk_user_id", "")),
		"name": String(_profile.get("nickname", "")),
		"avatar": _avatar,
		"platform": platform_id,
	}


func get_launch_token() -> String:
	return JSON.stringify(_launch_params)


func get_app_link() -> String:
	return "https://vk.com/app54906713"


## VK community group from the moderation brief. Direct link: no share dialog,
## no utm, no redirect, so it opens the group itself.
func get_support_url() -> String:
	return "https://vk.ru/club243770009"


func get_currency() -> String:
	return "votes"


func is_purchase_available() -> bool:
	return _authenticated


func purchase(sku: String) -> Dictionary:
	if not _authenticated:
		return {"success": false, "receipt": "", "error": "not_authenticated"}
	# VK and OK both open the platform order box through VK Bridge. The shards
	# are granted only by the server callback (/vk/pay or /ok/pay); the client
	# never adds currency. The payment window can stay open for minutes.
	var result := await _call_ad_bridge(
		"VKWebAppShowOrderBox", {"type": "item", "item": sku}, 300.0
	)
	if not bool(result.get("ok", false)):
		return {
			"success": false,
			"receipt": "",
			"error": String(result.get("error", "show_error")),
		}
	var data: Variant = result.get("data", {})
	var success := false
	if data is Dictionary:
		success = bool((data as Dictionary).get("success", false))
		var nested: Variant = (data as Dictionary).get("data")
		if not success and nested is Dictionary:
			success = bool((nested as Dictionary).get("success", false))
	if not success:
		return {"success": false, "receipt": "", "error": "cancelled"}
	return {"success": true, "receipt": ""}


func is_rewarded_available() -> bool:
	# The x2 button stays visible in VK. Whether an ad can actually be shown is
	# decided by VKWebAppShowNativeAds at click time; a failed check is not a
	# reason to hide the button, because ShowNativeAds may still load an ad.
	return _authenticated


func is_interstitial_available() -> bool:
	if not _authenticated:
		return false
	return _interstitial_available if _ads_checked else true


func show_rewarded_ad(placement: String) -> bool:
	# CheckNativeAds only reports preloaded inventory. ShowNativeAds still
	# requests an ad, so a failed check must not block the attempt: that was
	# hiding a working reward ad behind a false negative.
	last_ad_error = ""
	last_ad_detail = ""
	var started_ms := Time.get_ticks_msec()
	var check := await _call_ad_bridge("VKWebAppCheckNativeAds", {"ad_format": "reward", "use_waterfall": true})
	var check_ok := bool(check.get("ok", false))
	var check_result := _ad_result_flag(check)
	var check_error := String(check.get("error", ""))
	print("[Ads] check reward placement=%s ok=%s result=%s error=%s" % [
		placement, check_ok, check_result, check_error,
	])
	var shown := await _call_ad_bridge("VKWebAppShowNativeAds", {"ad_format": "reward", "use_waterfall": true}, REWARDED_SHOW_TIMEOUT)
	var shown_ok := bool(shown.get("ok", false))
	var shown_result := _ad_result_flag(shown)
	var show_error := String(shown.get("error", ""))
	var watched := shown_ok and shown_result
	var elapsed_ms := Time.get_ticks_msec() - started_ms
	print("[Ads] show reward placement=%s ok=%s result=%s error=%s ms=%d" % [
		placement, shown_ok, shown_result, show_error, elapsed_ms,
	])
	last_ad_detail = "check_ok=%s check_result=%s check_error=%s show_ok=%s show_result=%s show_error=%s ms=%d" % [
		check_ok, check_result, check_error, shown_ok, shown_result, show_error, elapsed_ms,
	]
	if not watched:
		# A rejected bridge promise keeps its raw code; a resolved promise
		# without result=true means the ad was closed early or the waterfall
		# served a format that pays nothing.
		if not shown_ok:
			last_ad_error = show_error if not show_error.is_empty() else "show_error"
		else:
			last_ad_error = "not_completed"
	_rewarded_available = watched
	_ads_checked = true
	return watched


func show_interstitial(placement: String) -> bool:
	if not _authenticated:
		return false
	var check := await _call_ad_bridge("VKWebAppCheckNativeAds", {"ad_format": "interstitial"})
	print("[Ads] check interstitial placement=%s ok=%s result=%s error=%s" % [
		placement, check.get("ok", false), _ad_result_flag(check), check.get("error", ""),
	])
	var shown := await _call_ad_bridge("VKWebAppShowNativeAds", {"ad_format": "interstitial"}, INTERSTITIAL_SHOW_TIMEOUT)
	var displayed := bool(shown.get("ok", false)) and _ad_result_flag(shown)
	print("[Ads] show interstitial placement=%s ok=%s result=%s error=%s" % [
		placement, shown.get("ok", false), displayed, shown.get("error", ""),
	])
	_interstitial_available = displayed
	_ads_checked = true
	return displayed


func _ad_result_flag(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	var data: Variant = result.get("data", {})
	# VK answers {result: bool}. Some bridge builds resolve with the bare
	# boolean or spell the flag as a string after the JSON round-trip; a
	# missing or false answer must still mean "no reward".
	if data is bool:
		return bool(data)
	if data is Dictionary:
		var payload: Dictionary = data
		if payload.has("result"):
			return _ad_flag_value(payload.get("result"))
		if payload.has("success"):
			return _ad_flag_value(payload.get("success"))
	return false


func _ad_flag_value(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int:
		return int(value) != 0
	if value is float:
		return float(value) != 0.0
	if value is String:
		# bool("false") is true in GDScript, so parse the string explicitly.
		var text := (value as String).strip_edges().to_lower()
		return text == "true" or text == "1"
	return false


func _refresh_ad_availability() -> void:
	var rewarded := await _call_ad_bridge("VKWebAppCheckNativeAds", {"ad_format": "reward", "use_waterfall": true})
	_rewarded_available = _ad_result_flag(rewarded)
	var interstitial := await _call_ad_bridge("VKWebAppCheckNativeAds", {"ad_format": "interstitial"})
	_interstitial_available = _ad_result_flag(interstitial)
	_ads_checked = true
	print("[Ads] availability reward=%s interstitial=%s" % [_rewarded_available, _interstitial_available])


## Single exit for every bridge request: no path may leave `_ad_busy` true and
## freeze every later ad (and the OK GetAuthToken) on the busy loop. Bumping the
## sequence orphans the promise of this request, so its late answer cannot be
## read as the result of the next one.
func _finish_bridge() -> void:
	_ad_busy = false
	_ad_ready = false
	_ad_result = {}
	_ad_request_seq += 1


## Called by the entry screen before restarting the platform sign-in: the old
## await chain is abandoned, so its flag must not block a new attempt.
func abort_auth() -> void:
	_auth_in_progress = false


func _call_ad_bridge(method: String, params: Dictionary, timeout := 20.0) -> Dictionary:
	# Wall-clock budget for the slot: Time.get_ticks_msec() keeps running while
	# the tab is backgrounded and at a low frame rate, unlike a frame counter.
	var busy_started := Time.get_ticks_msec()
	while _ad_busy:
		if _host == null or _host.get_tree() == null:
			return {"ok": false, "error": "busy"}
		if Time.get_ticks_msec() - busy_started >= AD_BUSY_WAIT_MS:
			return {"ok": false, "error": "busy"}
		await _host.get_tree().create_timer(0.05).timeout
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return {"ok": false, "error": "bridge_unavailable"}
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var window = bridge.call("get_interface", "window")
	if window == null:
		return {"ok": false, "error": "bridge_unavailable"}
	if _js_ad_cb == null:
		_js_ad_cb = bridge.call("create_callback", Callable(self, "_on_ad_js"))
	if _js_ad_cb == null:
		return {"ok": false, "error": "bridge_unavailable"}
	_ad_busy = true
	_ad_request_seq += 1
	var seq := _ad_request_seq
	window.__tsVKAdCB = _js_ad_cb
	_ad_ready = false
	_ad_result = {}
	var payload := JSON.stringify(params)
	var timeout_ms := maxi(1000, int(timeout * 1000.0))
	var script := """
	(function(){
		var seq = %d;
		var settled = false;
		var timer = null;
		function done(result) {
			// The bridge promise and the timeout may both fire: only the first
			// answer counts, the second is dropped.
			if (settled) return;
			settled = true;
			if (timer !== null) {
				try { clearTimeout(timer); } catch (e) {}
				timer = null;
			}
			result.seq = seq;
			try { window.__tsVKAdCB(JSON.stringify(result)); } catch (e) {}
		}
		// A stopped requestAnimationFrame or a suspended tab never runs the
		// promise continuation, so the request would stay pending forever.
		// This wall-clock timer settles it exactly like a bridge rejection.
		timer = setTimeout(function() { done({ok: false, error: 'js_timeout'}); }, %d);
		if (typeof window.vkBridge === 'undefined' || !window.vkBridge || !window.vkBridge.send) {
			done({ok: false, error: 'bridge_unavailable'});
			return;
		}
		window.vkBridge.send(%s, %s).then(function(data) {
			done({ok: true, data: data || {}});
		}).catch(function(err) {
			// Keep the bridge's error object readable: okay for VK ads, and
			// the only way to see why OK rejected GetAuthToken.
			var message = 'bridge_error';
			try { message = err && err.message ? String(err.message) : JSON.stringify(err); } catch (e) {}
			done({ok: false, error: message});
		});
	})();
	""" % [seq, timeout_ms, JSON.stringify(method), payload]
	# JavaScriptBridge.eval reports a hard failure as false; an undefined result
	# comes back as null and is a normal success.
	var eval_result: Variant = bridge.call("eval", script, true)
	if eval_result is bool and not bool(eval_result):
		_finish_bridge()
		return {"ok": false, "error": "bridge_unavailable"}
	var started := Time.get_ticks_msec()
	while not _ad_ready and Time.get_ticks_msec() - started < timeout_ms:
		if _host == null or _host.get_tree() == null:
			_finish_bridge()
			return {"ok": false, "error": "timeout"}
		await _host.get_tree().create_timer(0.05).timeout
	if not _ad_ready:
		_finish_bridge()
		return {"ok": false, "error": "timeout"}
	var result := _ad_result
	_finish_bridge()
	return result


func _on_ad_js(args: Array) -> void:
	if args.is_empty():
		return
	var parsed: Variant = JSON.parse_string(String(args[0]))
	if not parsed is Dictionary:
		return
	var result: Dictionary = parsed
	# A late promise from a timed-out show must not be mistaken for the answer
	# to the next show request.
	if int(result.get("seq", -1)) != _ad_request_seq:
		return
	_ad_result = result
	_ad_ready = true


func _fail(error: String) -> void:
	_last_error = _map_error(error)
	_auth_in_progress = false


func _apply_auth(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		_last_error = _map_error(String(result.get("error", "")))
		return false
	var profile: Dictionary = result.get("profile", {})
	var player_id := int(profile.get("player_id", 0))
	var token := String(profile.get("session_token", ""))
	if player_id <= 0 or token.is_empty():
		_last_error = "invalid_server_profile"
		return false
	_profile = profile
	_session_token = token
	_avatar = String(profile.get("avatar", _avatar))
	MetaProgression.player_id = player_id
	MetaProgression.session_token = token
	MetaProgression.account_level = maxi(1, int(profile.get("level", 1)))
	NetworkClient.session_token = token
	var wings: Array = profile.get("unlocked_wings", [])
	var weapons: Array = profile.get("unlocked_weapons", [])
	var nickname := String(profile.get("nickname", ""))
	var nickname_custom := bool(profile.get("nickname_custom", false))
	MetaProgression.apply_server_progress(profile, false)
	MetaProgression.apply_server_profile(
		player_id,
		int(profile.get("sky_shards", 0)),
		wings,
		weapons,
		nickname,
		nickname_custom,
		int(profile.get("matches_played", 0)),
		bool(profile.get("novice", false))
	)
	MetaProgression.persist_local()
	return true


func _map_error(error: String) -> String:
	match error:
		"invalid_vk_auth", "invalid_server_profile":
			return "vk_invalid_auth"
		"rate_limited":
			return "vk_rate_limited"
		"vk_auth_not_configured":
			return "vk_server_not_configured"
		"timeout", "vk_timeout":
			return "vk_network_timeout"
		"vk_missing_params":
			return "vk_missing_params"
		"vk_bridge_unavailable":
			return "vk_bridge_unavailable"
		"ok_app_id_not_configured":
			return "ok_app_id_not_configured"
		"ok_auth_not_configured":
			return "ok_auth_not_configured"
		"ok_auth_denied", "invalid_ok_auth":
			return "invalid_ok_auth"
		"ok_bridge_unavailable":
			return "ok_bridge_unavailable"
		_:
			return "vk_auth_failed"


func _get_launch_params() -> Dictionary:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return {"ok": false, "error": "vk_bridge_unavailable"}
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var window = bridge.call("get_interface", "window")
	if window == null:
		return {"ok": false, "error": "vk_bridge_unavailable"}
	_js_launch_cb = bridge.call("create_callback", Callable(self, "_on_launch_params_js"))
	if _js_launch_cb == null:
		return {"ok": false, "error": "vk_bridge_unavailable"}
	window.__tsVKLaunchCB = _js_launch_cb
	_launch_ready = false
	_launch_result = {}
	var script := """
	(function(){
		var settled = false;
		function done(payload) {
			if (settled) return;
			settled = true;
			try { window.__tsVKLaunchCB(JSON.stringify(payload)); } catch (e) {}
		}
		function urlParams() {
			var out = {};
			function add(params) {
				params.forEach(function(value, key) {
					if (key === 'sign' || key.indexOf('vk_') === 0) out[key] = value;
				});
			}
			try {
				add(new URLSearchParams(window.location.search));
				// VK can put the signed launch params in the hash. The one-build
				// redirect preserves both, so read both here as well.
				var hash = String(window.location.hash || '').replace(/^#/, '');
				if (hash) add(new URLSearchParams(hash));
			} catch (e) {}
			return out;
		}
		function normalized(source) {
			var out = {};
			for (var key in source) {
				if (source[key] !== null && source[key] !== undefined) out[key] = String(source[key]);
			}
			return out;
		}
		function chooseParams(data) {
			// Never mix URL and bridge values: each set has its own sign. A
			// mixed set is rejected even when both sources are individually
			// valid. Prefer the URL because it is exactly what VK signed.
			var url = urlParams();
			if (url.sign && url.vk_user_id && url.vk_app_id && url.vk_ts) return url;
			return normalized(data || {});
		}
		// A VK webview normally answers in well under a second. If the bridge
		// hangs (opened outside VK, blocked script), fall back to the launch
		// params VK put in the URL instead of waiting forever.
		setTimeout(function() {
			done({ok: true, params: urlParams(), source: 'url', bridge_timeout: true});
		}, 5000);
		if (typeof window.vkBridge === 'undefined' || !window.vkBridge || !window.vkBridge.send) {
			done({ok: true, params: urlParams(), source: 'url'});
			return;
		}
		// The parent VK frame may not answer before VKWebAppInit completes.
		// Wait for init (or its error) and only then ask for launch params.
		var init = window.__tsVKInit;
		if (!init) {
			try { init = window.vkBridge.send('VKWebAppInit'); } catch (e) { init = Promise.resolve(); }
		}
		Promise.resolve(init).catch(function() {}).then(function() {
			return window.vkBridge.send('VKWebAppGetLaunchParams');
		}).then(function(data) {
			done({ok: true, params: chooseParams(data), source: 'bridge'});
		}).catch(function(err) {
			done({ok: true, params: urlParams(), source: 'url', bridge_error: String(err)});
		});
	})();
	"""
	bridge.call("eval", script, true)
	var waited := 0.0
	while not _launch_ready and waited < 8.0:
		await _host.get_tree().create_timer(0.05).timeout
		waited += 0.05
	if not _launch_ready:
		return {"ok": false, "error": "vk_timeout"}
	if not bool(_launch_result.get("ok", false)):
		return {"ok": false, "error": String(_launch_result.get("error", "vk_bridge_error"))}
	var params: Dictionary = _launch_result.get("params", {})
	for required in ["vk_user_id", "vk_app_id", "vk_ts", "sign"]:
		if String(params.get(required, "")).strip_edges().is_empty():
			return {"ok": false, "error": "vk_missing_params"}
	return {"ok": true, "params": params}


func _on_launch_params_js(args: Array) -> void:
	_launch_ready = true
	if args.is_empty():
		_launch_result = {"ok": false, "error": "vk_bridge_error"}
		return
	var parsed: Variant = JSON.parse_string(String(args[0]))
	if parsed is Dictionary:
		_launch_result = parsed
	else:
		_launch_result = {"ok": false, "error": "vk_bridge_error"}


func _get_user_info() -> Dictionary:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return {"ok": false}
	var bridge := Engine.get_singleton("JavaScriptBridge")
	var window = bridge.call("get_interface", "window")
	if window == null:
		return {"ok": false}
	_js_user_cb = bridge.call("create_callback", Callable(self, "_on_user_info_js"))
	if _js_user_cb == null:
		return {"ok": false}
	window.__tsVKUserCB = _js_user_cb
	_user_ready = false
	_user_result = {}
	var script := """
	(function(){
		function done(payload) {
			try { window.__tsVKUserCB(JSON.stringify(payload)); } catch (e) {}
		}
		if (typeof window.vkBridge === 'undefined' || !window.vkBridge || !window.vkBridge.send) {
			done({ok: false, error: 'bridge_unavailable'});
			return;
		}
		window.vkBridge.send('VKWebAppGetUserInfo').then(function(data) {
			done({ok: true, data: data || {}});
		}).catch(function(err) {
			done({ok: false, error: String(err)});
		});
	})();
	"""
	bridge.call("eval", script, true)
	var waited := 0.0
	while not _user_ready and waited < 6.0:
		await _host.get_tree().create_timer(0.05).timeout
		waited += 0.05
	if not _user_ready:
		return {"ok": false, "error": "timeout"}
	return _user_result


func _on_user_info_js(args: Array) -> void:
	_user_ready = true
	if args.is_empty():
		_user_result = {"ok": false, "error": "vk_bridge_error"}
		return
	var parsed: Variant = JSON.parse_string(String(args[0]))
	if parsed is Dictionary:
		_user_result = parsed
	else:
		_user_result = {"ok": false, "error": "vk_bridge_error"}


func _display_name(data: Dictionary) -> String:
	var first := String(data.get("first_name", "")).strip_edges()
	var last := String(data.get("last_name", "")).strip_edges()
	var name := (first + " " + last).strip_edges()
	if name.is_empty():
		name = String(data.get("screen_name", "")).strip_edges()
	return name
