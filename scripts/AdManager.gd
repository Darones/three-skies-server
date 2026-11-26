extends Node

## Results-screen ad flow. All real ad work goes through Platform; the core
## never waits on a fake timer and never grants a reward without a completed
## adapter callback.

signal rewarded_ad_completed

const MIN_MATCHES_FOR_ADS := 3
const NOVICE_INTERSTITIAL_COOLDOWN := 30 * 60

var ad_showing := false
var rewarded_watched_this_results := false
# Set as soon as a rewarded ad is requested, before the adapter answers. A
# failed or timed-out rewarded still means the player already sat through one
# ad screen: the results screen must not show an interstitial on top of it.
var rewarded_attempted_this_results := false
var interstitial_shown_this_results := false


func begin_results() -> void:
	rewarded_watched_this_results = false
	rewarded_attempted_this_results = false
	interstitial_shown_this_results = false


func register_rewarded_watched() -> void:
	rewarded_watched_this_results = true
	rewarded_attempted_this_results = true


func can_show_interstitial_after_results() -> bool:
	if ad_showing:
		return false
	# One ad screen per results. A rewarded x2 that was watched, or only
	# attempted, already took that slot.
	if rewarded_watched_this_results or rewarded_attempted_this_results:
		return false
	if interstitial_shown_this_results:
		return false
	# The first two fights never show ads.
	if MetaProgression.known_matches() < MIN_MATCHES_FOR_ADS:
		return false
	# Novice: at most once per 30 minutes. The timestamp is server-owned and
	# shared by all devices; the local value is only a UI cache.
	if MetaProgression.novice and MetaProgression.last_interstitial_at > 0:
		var elapsed := int(Time.get_unix_time_from_system()) - MetaProgression.last_interstitial_at
		if elapsed < NOVICE_INTERSTITIAL_COOLDOWN:
			return false
	if not Platform.is_interstitial_available():
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
	if not Platform.is_interstitial_available():
		return false
	ad_showing = true
	var shown: bool = await Platform.show_interstitial("results")
	ad_showing = false
	if shown:
		MetaProgression.last_interstitial_at = int(Time.get_unix_time_from_system())
		NetworkClient.record_interstitial_shown(MetaProgression.player_id)
	print("[Ads] interstitial results shown=%s" % shown)
	return shown


func show_rewarded_ad() -> bool:
	if ad_showing:
		return false
	if not Platform.is_rewarded_available():
		return false
	ad_showing = true
	# Marked before the adapter runs: whether VK filled the ad, timed out or
	# the player closed it early, the results screen already had its ad.
	rewarded_attempted_this_results = true
	var rewarded: bool = await Platform.show_rewarded_ad("results_double")
	ad_showing = false
	var ad_error := Platform.get_last_ad_error()
	var ad_detail := Platform.get_last_ad_detail()
	Stats.track("ad_reward", {
		"ok": rewarded,
		"placement": "results_double",
		"error": ad_error,
		"detail": ad_detail,
	})
	if not rewarded:
		print("[Ads] rewarded results_double not completed error=%s detail=%s" % [ad_error, ad_detail])
		return false
	register_rewarded_watched()
	rewarded_ad_completed.emit()
	return true
