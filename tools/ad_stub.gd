extends "res://scripts/platform/platform_adapter.gd"

## Test-only rewarded adapter. It never talks to VK; it only returns a
## configured result and the same error strings a real adapter would.

var rewarded_result := false
var rewarded_calls := 0


func _init() -> void:
	platform_id = "vk"
	display_name = "AdStub"


func is_rewarded_available() -> bool:
	return true


func is_interstitial_available() -> bool:
	return false


func show_rewarded_ad(_placement: String) -> bool:
	rewarded_calls += 1
	last_ad_error = "" if rewarded_result else "no_fill"
	last_ad_detail = "stub_detail"
	return rewarded_result
