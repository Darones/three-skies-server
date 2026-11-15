extends Node

signal rewarded_ad_completed

const SAVE_PATH := "user://ads.cfg"
const MIN_BATTLES_BEFORE_INTERSTITIAL := 5
const BATTLES_WITHOUT_REWARDED_TO_ENABLE := 2

var ad_showing := false
var battles_played := 0
var battles_since_rewarded := 0
var last_rewarded_battle := -1
var last_ad_type := ""
var last_ad_battle := -1
var last_interstitial_battle := -1


func _ready() -> void:
	_load_state()


func register_battle_completed() -> void:
	battles_played += 1
	if last_rewarded_battle >= 0:
		battles_since_rewarded = maxi(0, battles_played - last_rewarded_battle)
	else:
		battles_since_rewarded = battles_played
	_save_state()


func register_rewarded_watched() -> void:
	last_rewarded_battle = battles_played
	battles_since_rewarded = 0
	last_ad_type = "rewarded"
	last_ad_battle = battles_played
	_save_state()


func can_show_interstitial() -> bool:
	if ad_showing:
		return false
	if battles_played < MIN_BATTLES_BEFORE_INTERSTITIAL:
		return false
	if battles_since_rewarded < BATTLES_WITHOUT_REWARDED_TO_ENABLE:
		return false
	if last_interstitial_battle == battles_played:
		return false
	if last_ad_type == "rewarded" and last_ad_battle == battles_played:
		return false
	return true


func maybe_show_interstitial() -> bool:
	if not can_show_interstitial():
		return false
	return await show_interstitial_ad()


func show_interstitial_ad() -> bool:
	if ad_showing:
		return false
	ad_showing = true
	print("[Реклама] Межуровневая реклама...")
	await get_tree().create_timer(1.5).timeout
	print("[Реклама] Межуровневая реклама завершена")
	ad_showing = false
	last_ad_type = "interstitial"
	last_ad_battle = battles_played
	last_interstitial_battle = battles_played
	_save_state()
	return true


func show_rewarded_ad() -> void:
	if ad_showing:
		return
	ad_showing = true
	print("[Реклама] Начало показа...")
	await get_tree().create_timer(1.5).timeout
	print("[Реклама] Просмотр завершен!")
	ad_showing = false
	register_rewarded_watched()
	rewarded_ad_completed.emit()


func _load_state() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	battles_played = maxi(0, int(config.get_value("ads", "battles_played", 0)))
	battles_since_rewarded = maxi(0, int(config.get_value("ads", "battles_since_rewarded", 0)))
	last_rewarded_battle = int(config.get_value("ads", "last_rewarded_battle", -1))
	last_ad_type = String(config.get_value("ads", "last_ad_type", ""))
	last_ad_battle = int(config.get_value("ads", "last_ad_battle", -1))
	last_interstitial_battle = int(config.get_value("ads", "last_interstitial_battle", -1))


func _save_state() -> void:
	var config := ConfigFile.new()
	config.set_value("ads", "battles_played", battles_played)
	config.set_value("ads", "battles_since_rewarded", battles_since_rewarded)
	config.set_value("ads", "last_rewarded_battle", last_rewarded_battle)
	config.set_value("ads", "last_ad_type", last_ad_type)
	config.set_value("ads", "last_ad_battle", last_ad_battle)
	config.set_value("ads", "last_interstitial_battle", last_interstitial_battle)
	config.save(SAVE_PATH)
