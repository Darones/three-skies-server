extends Control

var selection_locked := false

func _ready() -> void:
	var cards := $CardsContainer
	for index in range(cards.get_child_count()):
		var card := cards.get_child(index) as TextureButton
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.mouse_entered.connect(_on_card_hovered.bind(index, true))
		card.mouse_exited.connect(_on_card_hovered.bind(index, false))
		card.pressed.connect(_on_card_selected.bind(index))
	if DeviceProfile.mobile_ui:
		_apply_mobile_layout()


func _apply_mobile_layout() -> void:
	var container := $CardsContainer as HBoxContainer
	container.anchor_top = 0.20
	container.anchor_bottom = 0.95
	container.add_theme_constant_override("separation", 16)
	for card in container.get_children():
		if card is Control:
			card.custom_minimum_size = Vector2(210.0, 360.0)
			card.pivot_offset = card.custom_minimum_size * 0.5
	var title := get_node_or_null("Title") as Label
	if title != null:
		title.add_theme_font_size_override("font_size", 34)
	var subtitle := get_node_or_null("Subtitle") as Label
	if subtitle != null:
		subtitle.add_theme_font_size_override("font_size", 18)

func _on_card_hovered(index: int, hovered: bool) -> void:
	var card := $CardsContainer.get_child(index) as TextureButton
	card.scale = Vector2(1.025, 1.025) if hovered else Vector2.ONE
	card.modulate = Color(1.08, 1.08, 1.08, 1.0) if hovered else Color.WHITE

func _on_card_selected(index: int) -> void:
	if selection_locked:
		return
	selection_locked = true
	get_tree().set_meta("selected_class", index)
	get_tree().change_scene_to_file("res://scenes/LoadingScreen.tscn")
