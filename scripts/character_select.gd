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

func _on_card_hovered(index: int, hovered: bool) -> void:
	var card := $CardsContainer.get_child(index) as TextureButton
	card.scale = Vector2(1.025, 1.025) if hovered else Vector2.ONE
	card.modulate = Color(1.08, 1.08, 1.08, 1.0) if hovered else Color.WHITE

func _on_card_selected(index: int) -> void:
	if selection_locked:
		return
	selection_locked = true
	get_tree().set_meta("selected_class", index)
	# NetworkClient.connect_and_join(index + 1) # +1, если индексы идут с 0, а классы с 1
	get_tree().change_scene_to_file("res://scenes/LoadingScreen.tscn")
