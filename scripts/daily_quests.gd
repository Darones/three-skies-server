extends Node

## Daily quests client state (docs/DAILY-QUESTS-SPEC.md, wave 2).
##
## The server is the only authority: this autoload keeps a memory snapshot of
## the last /profile `daily` block and the last /quests payload. Nothing is
## written to user://: a restart re-reads both from the server.
##
## Consumers (UI) read the fields / helpers below and listen to `changed`.
## `failed` carries a short machine-readable code ("completed", "limit",
## "shards", "pending", "network", ...) that the UI may localise itself.

signal changed
signal failed(error: String)
# Alias consumed by the quests panel (wave 3); `changed` stays the main signal.
signal quests_updated

const REFRESH_INTERVAL_MS := 60000
const DAILY_TOTAL := 3
const REROLL_COST := 1
const REROLL_PAID_MAX := 2

## Quest day key from the server ("YYYY-MM-DD", 04:00 MSK boundary).
var day := ""
## Unix seconds when the current quest day ends.
var resets_at := 0
## Full quest list from GET /quests (3 entries, normalised).
var quests: Array[Dictionary] = []
## {free, free_used, paid, paid_max, cost, remaining, total}.
var rerolls: Dictionary = {}
## Normalised weekly block: required/active_days/tier/claimable/claimed/days...
var week: Dictionary = {}
## Compact block from GET /profile: completed/total/resets_at/week.
var summary: Dictionary = {}
## True once a full /quests payload has been applied.
var loaded := false

var _last_refresh_ms := -REFRESH_INTERVAL_MS
var _request_in_flight := false
var _reroll_slot := -1
var _claim_in_flight := false
var _rollover_requested := false
var _emitting_changed := false


func _ready() -> void:
	if not NetworkClient.quests_loaded.is_connected(_on_quests_loaded):
		NetworkClient.quests_loaded.connect(_on_quests_loaded)
	if not NetworkClient.quests_rerolled.is_connected(_on_quests_rerolled):
		NetworkClient.quests_rerolled.connect(_on_quests_rerolled)
	if not NetworkClient.weekly_claimed.is_connected(_on_weekly_claimed):
		NetworkClient.weekly_claimed.connect(_on_weekly_claimed)
	if not NetworkClient.quests_summary_loaded.is_connected(_on_quests_summary_loaded):
		NetworkClient.quests_summary_loaded.connect(_on_quests_summary_loaded)


func _process(_delta: float) -> void:
	# Cheap check: refresh() owns the actual pacing, so a failed request is
	# retried at most once per REFRESH_INTERVAL_MS, not every frame.
	if resets_at > 0 and _now() > resets_at:
		refresh()


# --- Server payloads -------------------------------------------------------

## Compact `daily` block of GET /profile. Enough for the badge before the
## detailed /quests request finishes.
func apply_summary(daily: Dictionary) -> void:
	if daily.is_empty():
		return
	var before := _state_signature()
	summary["completed"] = maxi(0, _as_int(daily.get("completed", summary.get("completed", 0)), 0))
	summary["total"] = maxi(0, _as_int(daily.get("total", summary.get("total", DAILY_TOTAL)), DAILY_TOTAL))
	var parsed_day := _as_day(daily.get("day", daily.get("today", "")))
	if not parsed_day.is_empty():
		day = parsed_day
	var parsed_resets := _as_timestamp(daily.get("resets_at", 0))
	if parsed_resets > 0:
		resets_at = parsed_resets
		_rollover_requested = false
	var week_raw: Variant = daily.get("week", null)
	if week_raw is Dictionary:
		var normalised := _normalize_week(week_raw)
		if not normalised.is_empty():
			# /profile sends a shorter week block (no day list, no reward); keep
			# the richer data a previous /quests payload provided.
			week = _merge_week(normalised)
	summary["week"] = week
	if before != _state_signature():
		_emit_changed()


## Full GET /quests payload, and the payload some quest endpoints echo back.
func apply_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var before := _state_signature()
	var parsed_day := _as_day(payload.get("day", payload.get("today", "")))
	if not parsed_day.is_empty():
		day = parsed_day
	var parsed_resets := _as_timestamp(payload.get("resets_at", 0))
	if parsed_resets > 0:
		resets_at = parsed_resets
		if parsed_resets > _now():
			_rollover_requested = false
	var quests_raw: Variant = payload.get("quests", null)
	if quests_raw is Array:
		var quest_list: Array = quests_raw
		quests = _normalize_quests(quest_list)
		loaded = true
	var rerolls_raw: Variant = payload.get("rerolls", null)
	if rerolls_raw != null:
		rerolls = _normalize_rerolls(rerolls_raw)
	var week_raw: Variant = payload.get("week", null)
	if week_raw is Dictionary:
		var normalised := _normalize_week(week_raw)
		if not normalised.is_empty():
			week = normalised
	summary["completed"] = completed()
	summary["total"] = total()
	summary["resets_at"] = resets_at
	summary["week"] = week
	if before != _state_signature():
		_emit_changed()


## Ask the server for the current quest state when loaded and not throttled.
func refresh(force := false) -> void:
	# A `changed` listener must not be able to force a request from inside the
	# signal emission: that would let a UI rebuild loop hit the network.
	if force and _emitting_changed:
		force = false
	if resets_at > 0 and _now() > resets_at and not _rollover_requested:
		_rollover_requested = true
		force = true
	if not force and Time.get_ticks_msec() - _last_refresh_ms < REFRESH_INTERVAL_MS:
		return
	if _request_in_flight:
		return
	var pid := _player_id()
	if pid <= 0:
		return
	_last_refresh_ms = Time.get_ticks_msec()
	_request_in_flight = true
	NetworkClient.load_quests(pid)


func on_lobby_entered() -> void:
	if not loaded:
		refresh(true)
	else:
		refresh()


## Drops the snapshot when the local account is reset, so the next player never
## sees the previous player's badge before the server answers.
func clear() -> void:
	var before := _state_signature()
	day = ""
	resets_at = 0
	quests.clear()
	rerolls.clear()
	week.clear()
	summary.clear()
	loaded = false
	_request_in_flight = false
	_reroll_slot = -1
	_claim_in_flight = false
	_rollover_requested = false
	_last_refresh_ms = -REFRESH_INTERVAL_MS
	if before != _state_signature():
		_emit_changed()


func request_reroll(slot: int) -> bool:
	var state := reroll_state(slot)
	if not bool(state.get("enabled", false)):
		failed.emit(String(state.get("reason", "disabled")))
		return false
	var quest := _quest_by_slot(slot)
	if quest.is_empty():
		failed.emit("no_quest")
		return false
	_reroll_slot = slot
	NetworkClient.reroll_quest(_player_id(), day, slot, String(quest.get("template_id", "")))
	return true


func request_weekly_claim(item_id := 0) -> bool:
	if _claim_in_flight:
		failed.emit("pending")
		return false
	if not bool(week.get("claimable", false)):
		failed.emit("claimed" if bool(week.get("claimed", false)) else "not_claimable")
		return false
	var pid := _player_id()
	if pid <= 0:
		failed.emit("no_player")
		return false
	var week_start := String(week.get("start", ""))
	if week_start.is_empty():
		failed.emit("no_week")
		return false
	var claim_item := item_id if item_id > 0 else int(week.get("reward_item_id", 0))
	_claim_in_flight = true
	NetworkClient.claim_weekly(pid, week_start, claim_item)
	return true


# --- Read helpers for the UI ----------------------------------------------

func completed() -> int:
	if not quests.is_empty():
		var count := 0
		for quest in quests:
			if bool(quest.get("completed", false)):
				count += 1
		return count
	return maxi(0, int(summary.get("completed", 0)))


func total() -> int:
	if not quests.is_empty():
		return quests.size()
	var stated := int(summary.get("total", 0))
	return stated if stated > 0 else DAILY_TOTAL


func badge_text() -> String:
	return "%d/%d" % [completed(), total()]


## Availability of the replace button for one quest slot.
func reroll_state(slot: int) -> Dictionary:
	var quest := _quest_by_slot(slot)
	var free_available := bool(rerolls.get("free", not bool(rerolls.get("free_used", false))))
	var cost: int = 0 if free_available else maxi(1, int(rerolls.get("cost", REROLL_COST)))
	var state := {"free": free_available, "cost": cost, "enabled": false, "reason": ""}
	if quest.is_empty():
		state["reason"] = "no_quest"
		return state
	if bool(quest.get("completed", false)):
		state["reason"] = "completed"
		return state
	if _reroll_slot == slot:
		state["reason"] = "pending"
		return state
	if _reroll_slot >= 0:
		state["reason"] = "busy"
		return state
	if free_available:
		state["enabled"] = true
		return state
	if int(rerolls.get("remaining", 0)) <= 0:
		state["reason"] = "limit"
		return state
	if _shards() < cost:
		state["reason"] = "shards"
		return state
	state["enabled"] = true
	return state


## Seven booleans, Monday first. Uses the week day list when the server sends
## it (a day is closed only when all 3 quests are done), otherwise fills the
## first `active_days` entries, which the server counts the same way.
func week_dots() -> Array[bool]:
	var dots: Array[bool] = []
	var raw_days: Variant = week.get("days", [])
	if raw_days is Array and not raw_days.is_empty():
		for item in raw_days:
			if item is Dictionary:
				var day_entry: Dictionary = item
				dots.append(bool(day_entry.get("completed", false)))
		return dots
	var required := maxi(1, int(week.get("required", 7)))
	var active := clampi(int(week.get("active_days", 0)), 0, required)
	for index in required:
		dots.append(index < active)
	return dots


## "5 ч 12 мин" / "48 мин" until the quest day rolls over.
func time_left_text() -> String:
	if resets_at <= 0:
		return ""
	var seconds := resets_at - _now()
	if seconds <= 0:
		return "обновление"
	var hours := floori(float(seconds) / 3600.0)
	var minutes := floori(float(seconds % 3600) / 60.0)
	if hours > 0:
		return "%d ч %02d мин" % [hours, minutes]
	return "%d мин" % maxi(1, minutes)


# --- Network signals -------------------------------------------------------

func _on_quests_loaded(success: bool, data: Dictionary, error: String) -> void:
	_request_in_flight = false
	if not success:
		failed.emit(error if not error.is_empty() else "network")
		return
	apply_payload(data)


func _on_quests_rerolled(success: bool, slot: int, data: Dictionary, error: String) -> void:
	_reroll_slot = -1
	if not success:
		failed.emit(error if not error.is_empty() else "network")
		return
	if data.has("quests"):
		apply_payload(data)
	else:
		refresh(true)


func _on_weekly_claimed(success: bool, data: Dictionary, error: String) -> void:
	_claim_in_flight = false
	if not success:
		failed.emit(error if not error.is_empty() else "network")
		return
	var before := _state_signature()
	week["claimed"] = true
	week["claimable"] = false
	if data.has("week") and data["week"] is Dictionary:
		var normalised := _normalize_week(data["week"])
		if not normalised.is_empty():
			week = normalised
	summary["week"] = week
	if before != _state_signature():
		_emit_changed()
	# The grant response carries shards but not the full quest list; let the
	# server authoritatively refresh the week and the quest rows.
	refresh(true)


func _on_quests_summary_loaded(daily: Dictionary) -> void:
	apply_summary(daily)


# --- Normalisation ---------------------------------------------------------

func _normalize_quests(raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var index := 0
	for item in raw:
		if item is Dictionary:
			var quest_data: Dictionary = item
			out.append(_normalize_quest(quest_data, index))
		index += 1
	return out


func _normalize_quest(raw: Dictionary, index: int) -> Dictionary:
	var target := maxi(1, _as_int(raw.get("target", 1), 1))
	var progress := clampi(_as_int(raw.get("progress", 0), 0), 0, target)
	var completed_now := bool(raw.get("completed", false)) or progress >= target
	return {
		"slot": _as_int(raw.get("slot", index + 1), index + 1),
		"template_id": String(raw.get("template_id", raw.get("id", ""))),
		"title": String(raw.get("title", "")),
		"description": String(raw.get("description", raw.get("desc", ""))),
		"metric": String(raw.get("metric", "")),
		"target": target,
		"progress": progress,
		"progress_text": "%d/%d" % [progress, target],
		"reward_shards": maxi(0, _as_int(raw.get("reward_shards", raw.get("shards", 0)), 0)),
		"reward_xp": maxi(0, _as_int(raw.get("reward_xp", raw.get("xp", 0)), 0)),
		"difficulty": String(raw.get("difficulty", raw.get("diff", ""))),
		"rerolled": bool(raw.get("rerolled", false)),
		"completed": completed_now,
	}


func _normalize_rerolls(raw: Variant) -> Dictionary:
	var paid_max := REROLL_PAID_MAX
	var paid := 0
	var free_used := false
	var free_available := true
	var cost := REROLL_COST
	var total_value := 1 + REROLL_PAID_MAX
	var remaining := -1
	if raw is Dictionary:
		var data: Dictionary = raw
		paid_max = maxi(0, _as_int(data.get("paid_max", data.get("max_paid", data.get("max", REROLL_PAID_MAX))), REROLL_PAID_MAX))
		paid = clampi(_as_int(data.get("paid", data.get("paid_rerolls", data.get("paid_used", 0))), 0), 0, paid_max)
		free_used = bool(data.get("free_used", data.get("used_free", false)))
		free_available = bool(data.get("free", data.get("free_available", not free_used)))
		cost = maxi(1, _as_int(data.get("cost", data.get("paid_cost", REROLL_COST)), REROLL_COST))
		total_value = maxi(1, _as_int(data.get("total", data.get("total_rerolls", 1 + paid_max)), 1 + paid_max))
		remaining = _as_int(data.get("remaining", data.get("left", -1)), -1)
	elif raw is int or raw is float:
		remaining = maxi(0, _as_int(raw, 0))
		free_available = remaining > 0
	if remaining < 0:
		remaining = (1 if free_available else 0) + maxi(0, paid_max - paid)
	return {
		"free": free_available,
		"free_available": free_available,
		"free_used": free_used,
		"paid": paid,
		"paid_used": paid,
		"paid_left": maxi(0, paid_max - paid),
		"paid_max": paid_max,
		"cost": cost,
		"remaining": clampi(remaining, 0, total_value),
		"total": total_value,
	}


func _normalize_week(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var source: Dictionary = raw
	var data: Dictionary = source.duplicate(true)
	var required := maxi(1, _as_int(data.get("required", 7), 7))
	var active_days := _as_int(data.get("active_days", -1), -1)
	var days: Array = []
	var raw_days: Variant = data.get("days", [])
	var counted := 0
	if raw_days is Array:
		for item in raw_days:
			var entry := {"day": "", "completed": false, "today": false}
			var per_day_count := -1
			if item is Dictionary:
				entry["day"] = String(item.get("day", item.get("date", "")))
				# 7/7 rule: a week day is closed only when all 3 daily quests
				# are done. The server sends the closed flag / count; trust it
				# and never derive a closed day from partial progress.
				if item.has("closed"):
					entry["completed"] = bool(item["closed"])
				elif item.has("completed_count"):
					per_day_count = clampi(_as_int(item["completed_count"], 0), 0, DAILY_TOTAL)
					entry["completed"] = per_day_count >= DAILY_TOTAL
				else:
					var completed_value: Variant = item.get("completed", item.get("active", false))
					if completed_value is int:
						per_day_count = clampi(int(completed_value), 0, DAILY_TOTAL)
						entry["completed"] = per_day_count >= DAILY_TOTAL
					else:
						entry["completed"] = bool(completed_value)
				entry["today"] = bool(item.get("today", false))
			elif item is bool:
				entry["completed"] = bool(item)
			else:
				# A bare number is a per-day completed quest count.
				per_day_count = clampi(_as_int(item, 0), 0, DAILY_TOTAL)
				entry["completed"] = per_day_count >= DAILY_TOTAL
			# Aliases read by the wave-3 panel; `completed` stays canonical.
			entry["date"] = entry["day"]
			entry["full"] = bool(entry["completed"])
			entry["completed_count"] = per_day_count if per_day_count >= 0 else 0
			if per_day_count < 0 and bool(entry["completed"]):
				entry["completed_count"] = DAILY_TOTAL
			if bool(entry["completed"]):
				counted += 1
			days.append(entry)
	if active_days < 0:
		active_days = counted
	active_days = clampi(active_days, 0, required)
	var reward: Dictionary = {}
	var reward_raw: Variant = data.get("reward", {})
	if reward_raw is Dictionary:
		reward = reward_raw
	var out := {
		"required": required,
		"active_days": clampi(active_days, 0, required),
		"tier": maxi(0, _as_int(data.get("tier", 0), 0)),
		"claimable": bool(data.get("claimable", false)),
		"claimed": bool(data.get("claimed", false)),
		"start": String(data.get("start", data.get("week_start", ""))),
		"missed": maxi(0, _as_int(data.get("missed", required - active_days), 0)),
		"reward": reward,
		"reward_item_id": _as_int(data.get("reward_item_id", reward.get("item_id", 0)), 0),
		"reward_kind": String(data.get("reward_kind", reward.get("kind", ""))),
		"reward_label": String(data.get("reward_label", reward.get("label", ""))),
		# Aliases read by the wave-3 panel.
		"item_id": _as_int(data.get("item_id", reward.get("item_id", 0)), 0),
		"reward_name": String(data.get("reward_name", reward.get("name", reward.get("label", "")))),
		"reward_owned": bool(data.get("reward_owned", data.get("skin_owned", false))),
		"compensation": maxi(0, _as_int(data.get("compensation", 0), 0)),
	}
	if not days.is_empty():
		out["days"] = days
	if data.get("previous", null) is Dictionary:
		out["previous"] = data["previous"]
	return out


## Keeps the day dots and reward details from the last full /quests payload
## when /profile sends the compact week block for the same week.
func _merge_week(normalised: Dictionary) -> Dictionary:
	if week.is_empty():
		return normalised
	var old_start := String(week.get("start", ""))
	var new_start := String(normalised.get("start", ""))
	if not new_start.is_empty() and not old_start.is_empty() and new_start != old_start:
		return normalised
	# active_days only grows inside one week; a smaller value means the week
	# rolled over, so the old day dots must not leak into the new week.
	if int(normalised.get("active_days", 0)) < int(week.get("active_days", 0)):
		return normalised
	for key in ["start", "days", "reward", "previous"]:
		if not week.has(key):
			continue
		if normalised.has(key) and not _is_empty_value(normalised[key]):
			continue
		normalised[key] = week[key]
	for key in ["reward_item_id", "reward_kind", "reward_label"]:
		var value: Variant = normalised.get(key, 0 if key == "reward_item_id" else "")
		if not _is_empty_value(value):
			continue
		if week.has(key):
			normalised[key] = week[key]
	return normalised


func _is_empty_value(value: Variant) -> bool:
	if value == null:
		return true
	if value is String:
		return String(value).is_empty()
	if value is Array:
		return value.is_empty()
	if value is Dictionary:
		return value.is_empty()
	if value is int:
		return int(value) == 0
	return false


# --- Small helpers ---------------------------------------------------------

func _quest_by_slot(slot: int) -> Dictionary:
	for quest in quests:
		if int(quest.get("slot", -1)) == slot:
			return quest
	return {}


func _player_id() -> int:
	var meta := get_node_or_null("/root/MetaProgression")
	if meta == null:
		return 0
	return int(meta.get("player_id"))


func _shards() -> int:
	var meta := get_node_or_null("/root/MetaProgression")
	if meta == null:
		return 0
	return maxi(0, int(meta.get("sky_shards")))


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _as_int(value: Variant, fallback: int) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String:
		var text := String(value).strip_edges()
		if text.is_valid_int():
			return int(text)
		if text.is_valid_float():
			return int(float(text))
	return fallback


## Unix seconds. The server sends an integer; ISO strings are accepted too so a
## serialisation change does not blank the timer.
func _as_timestamp(value: Variant) -> int:
	if value is int or value is float:
		return maxi(0, int(value))
	if value is String:
		var text := String(value).strip_edges()
		if text.is_valid_int():
			return maxi(0, int(text))
		if text.length() >= 19:
			return maxi(0, int(Time.get_unix_time_from_datetime_string(text.substr(0, 19))))
	return 0


func _as_day(value: Variant) -> String:
	if value is String:
		return String(value).strip_edges()
	if value is Dictionary:
		var data: Dictionary = value
		return String(data.get("day", data.get("date", ""))).strip_edges()
	return ""


func _state_signature() -> String:
	return "%s|%d|%s|%s|%s" % [
		day,
		resets_at,
		JSON.stringify(quests),
		JSON.stringify(rerolls),
		JSON.stringify(week),
	]


func _emit_changed() -> void:
	_emitting_changed = true
	changed.emit()
	quests_updated.emit()
	_emitting_changed = false
