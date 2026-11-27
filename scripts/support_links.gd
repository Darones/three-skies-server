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
