extends Node

signal rewarded_ad_completed

var ad_showing := false
var rewarded_watched_this_results := false
var interstitial_shown_this_results := false


func begin_results() -> void:
	rewarded_watched_this_results = false
	interstitial_shown_this_results = false


func register_rewarded_watched() -> void:
	rewarded_watched_this_results = true


func can_show_interstitial_after_results() -> bool:
	if ad_showing:
		return false
	if rewarded_watched_this_results:
		return false
	if interstitial_shown_this_results:
		return false
	return true


func maybe_show_interstitial_after_results() -> bool:
	if not can_show_interstitial_after_results():
		return false
	interstitial_shown_this_results = true
	return await show_interstitial_ad()


func show_interstitial_ad() -> bool:
	if ad_showing:
		return false
	ad_showing = true
	print("[Реклама] Межуровневая реклама...")
	await get_tree().create_timer(1.5).timeout
	print("[Реклама] Межуровневая реклама завершена")
	ad_showing = false
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
