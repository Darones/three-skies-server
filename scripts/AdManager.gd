extends Node

signal rewarded_ad_completed

var ad_showing := false


func show_rewarded_ad() -> void:
	if ad_showing:
		return
	ad_showing = true
	print("[Реклама] Начало показа...")
	await get_tree().create_timer(1.5).timeout
	print("[Реклама] Просмотр завершен!")
	ad_showing = false
	rewarded_ad_completed.emit()
