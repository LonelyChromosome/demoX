class_name RationOverlay
extends ColorRect

signal submitted(unit_ids: Array[String])

var state: GameState
var required_count := 0
var need_count := 0
var selected := {}
var list: VBoxContainer
var hint: Label
var confirm: Button


func _ready() -> void:
	visible = false
	color = Color(0.03, 0.04, 0.04, 0.82)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-230, -210)
	panel.custom_minimum_size = Vector2(460, 420)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "PHÂN KHẨU PHẦN"
	title.add_theme_font_size_override("font_size", 25)
	box.add_child(title)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	list = VBoxContainer.new()
	box.add_child(list)
	confirm = Button.new()
	confirm.text = "Xác nhận khẩu phần"
	confirm.pressed.connect(_submit)
	box.add_child(confirm)


func show_request(game_state: GameState, result: TurnResolutionResult) -> void:
	state = game_state
	required_count = result.ration_food_available
	need_count = result.ration_need
	selected.clear()
	for child in list.get_children():
		child.queue_free()
	for unit_id in result.ration_candidate_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		var choice := CheckButton.new()
		choice.text = "%s  %s · đói %d/3" % [_glyph(unit.rank), unit.display_name, unit.hunger_streak]
		choice.toggled.connect(_toggle.bind(unit_id))
		list.add_child(choice)
	visible = true
	_update_hint()


func _toggle(enabled: bool, unit_id: String) -> void:
	if enabled:
		selected[unit_id] = true
	else:
		selected.erase(unit_id)
	_update_hint()


func _update_hint() -> void:
	hint.text = "Lương thực hiện có: %d · Số người cần ăn: %d\nĐã chọn %d/%d. Quân nhịn đủ 3 ngày và hết ngày thứ 3 sẽ chết." % [required_count, need_count, selected.size(), required_count]
	confirm.disabled = selected.size() != required_count


func _submit() -> void:
	var ids: Array[String] = []
	for unit_id in selected:
		ids.append(unit_id)
	ids.sort()
	visible = false
	submitted.emit(ids)


func _glyph(rank: int) -> String:
	return ["♟", "♞", "♜", "♝", "♛", "♚"][rank]
