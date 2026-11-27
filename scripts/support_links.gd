extends RefCounted

## Support and community links (VK/OK moderation P0).
##
## One source of truth for the community group of the current platform and
## for the support e-mail fallback. The platform comes from the Platform
## adapter (runtime URL detection), not from OS.get_name().
##
## Used by the settings panel, the rules panel and the lobby ban card.
## Access through preload, there is no class_name on purpose:
##   const SUPPORT_LINKS := preload("res://scripts/support_links.gd")

const VK_COMMUNITY_URL := "https://vk.ru/club243770009"
const OK_COMMUNITY_URL := "https://ok.ru/group/70000062043632"
const SUPPORT_EMAIL := "daroness@ya.ru"
const OPERATOR_NAME := "Давлеев Андрей Вадимович"
const OPERATOR_STATUS := "самозанятый"
## Same origin as the game server: /privacy and /terms are served there
## (the welcome consent line and the loader link to these pages).
const DEFAULT_SITE_URL := "https://three-skies-server.relaxdev.ru"
const PRIVACY_PATH := "/privacy"
const TERMS_PATH := "/terms"


static func community_url() -> String:
	# Direct group links only: no share dialogs, no utm/redirect wrappers.
	match _platform_id():
		"vk":
			return VK_COMMUNITY_URL
		"ok":
			return OK_COMMUNITY_URL
	return ""


static func support_url() -> String:
	# An own community is the fast channel; the e-mail is the fallback for
	# standalone builds and for players who cannot open the group.
	var community := community_url()
	if not community.is_empty():
		return community
	return "mailto:" + SUPPORT_EMAIL


## Public site origin (no trailing slash). Comes from the same REST base the
## game already talks to, so /privacy and /terms can never point at another
## host than the API that serves them.
static func site_url() -> String:
	# Same access pattern as _platform_id(): a static helper may run before a
	# scene exists, so the autoload is looked up through the tree instead of
	# being referenced directly.
	var base := ""
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var network := tree.root.get_node_or_null("NetworkClient")
		if network != null:
			var value: Variant = network.get("api_base_url")
			if value != null:
				base = String(value)
	base = base.strip_edges().trim_suffix("/")
	if base.is_empty():
		base = DEFAULT_SITE_URL
	return base


## Full URL of the privacy policy page (opens in a new browser tab).
static func privacy_url() -> String:
	return site_url() + PRIVACY_PATH


## Full URL of the user agreement page (also carries the UGC rules).
static func terms_url() -> String:
	return site_url() + TERMS_PATH


static func open_url(url: String) -> void:
	var target := url.strip_edges()
	if target.is_empty():
		return
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		# Open on the user's click so the browser treats it as a real gesture.
		bridge.call("eval", "window.open(%s,'_blank')" % JSON.stringify(target), true)
		return
	OS.shell_open(target)


static func _platform_id() -> String:
	# Same access pattern as ArenaKit: a static helper may run before (or
	# without) a scene, so the autoload is looked up through the tree.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	var platform := tree.root.get_node_or_null("Platform")
	if platform == null:
		return ""
	var value: Variant = platform.get("platform_id")
	return String(value) if value != null else ""
