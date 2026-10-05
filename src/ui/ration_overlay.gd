class_name RationOverlay
extends ColorRect

signal submitted(unit_ids: Array[String])

var state: GameState
var required_count := 0
var selected := {}
var cards := {}
var card_flow: HFlowContainer
var hint: Label
var confirm: Button


func _ready() -> void:
	visible = false
	color = Color(0.03, 0.04, 0.04, 0.82)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 280)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "PHÂN KHẨU PHẦN"
	title.add_theme_font_size_override("font_size", 25)
	box.add_child(title)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 150
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	card_flow = HFlowContainer.new()
	card_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_flow.add_theme_constant_override("h_separation", 10)
	card_flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(card_flow)
	confirm = Button.new()
	confirm.text = "Xác nhận khẩu phần"
	confirm.pressed.connect(_submit)
	box.add_child(confirm)


func show_request(game_state: GameState, result: TurnResolutionResult) -> void:
	state = game_state
	required_count = result.ration_food_available
	selected.clear()
	cards.clear()
	for child in card_flow.get_children():
		child.queue_free()
	for unit_id in result.ration_candidate_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			_create_card(unit)
	visible = true
	_update_hint()


func _create_card(unit: UnitState) -> void:
	var card := Button.new()
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(158, 82)
	card.focus_mode = Control.FOCUS_NONE
	card.add_theme_stylebox_override("normal", _card_style(false))
	card.add_theme_stylebox_override("hover", _card_style(false, true))
	card.add_theme_stylebox_override("pressed", _card_style(true))
	card.add_theme_stylebox_override("hover_pressed", _card_style(true, true))
	card.toggled.connect(_toggle.bind(unit.id, card))
	card_flow.add_child(card)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(content)
	var main := Label.new()
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.text = "%s  %s" % [_glyph(unit.rank), _unit_name(unit)]
	main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_theme_font_size_override("font_size", 18)
	content.add_child(main)
	var hunger := Label.new()
	hunger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hunger.text = "Đói %d/3" % unit.hunger_streak
	hunger.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hunger.add_theme_font_size_override("font_size", 13)
	hunger.add_theme_color_override("font_color", Color("b9c1bd"))
	content.add_child(hunger)
	var check := Label.new()
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.position = Vector2(9, 5)
	check.add_theme_font_size_override("font_size", 18)
	card.add_child(check)
	cards[unit.id] = {"button": card, "check": check}


func _toggle(enabled: bool, unit_id: String, card: Button) -> void:
	if enabled and selected.size() >= required_count:
		card.set_pressed_no_signal(false)
		return
	if enabled:
		selected[unit_id] = true
	else:
		selected.erase(unit_id)
	_update_card(unit_id)
	_update_hint()


func _update_card(unit_id: String) -> void:
	if not cards.has(unit_id):
		return
	var card_data: Dictionary = cards[unit_id]
	var button := card_data.button as Button
	var check := card_data.check as Label
	var is_selected := selected.has(unit_id)
	check.text = "✓" if is_selected else ""
	button.add_theme_stylebox_override("normal", _card_style(is_selected))


func _update_hint() -> void:
	hint.text = "Còn %d khẩu phần · Đã chọn %d/%d\nQuân nhịn đủ 3 ngày chỉ chết sau khi kết thúc ngày đói thứ ba." % [
		required_count, selected.size(), required_count
	]
	confirm.disabled = selected.size() != required_count


func _submit() -> void:
	var ids: Array[String] = []
	for unit_id in selected:
		ids.append(unit_id)
	ids.sort()
	visible = false
	submitted.emit(ids)


func _card_style(is_selected: bool, hovered := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("263b36") if is_selected else Color("1b2422")
	if hovered:
		style.bg_color = style.bg_color.lightened(0.06)
	style.border_color = Color("7dd7ae") if is_selected else Color("4d615a")
	style.set_border_width_all(3 if is_selected else 1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _unit_name(unit: UnitState) -> String:
	if unit.is_prisoner:
		return "Tù binh %s" % (
			unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank)
		)
	return unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank)


func _glyph(rank: int) -> String:
	return ["♟", "♞", "♜", "♝", "♛", "♚"][rank]


func _rank_name(rank: int) -> String:
	return ["Tốt", "Mã", "Xe", "Tịnh", "Hậu", "Vua"][rank]
