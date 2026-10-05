class_name OutsideRail
extends PanelContainer

var state: GameState
var turn_manager: TurnManager
var content: VBoxContainer
var selected_units: Array[String] = []
var outside_system := OutsideSystem.new()


func _ready() -> void:
	custom_minimum_size = Vector2(240, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)


func setup(game_state: GameState, manager: TurnManager) -> void:
	state = game_state
	turn_manager = manager
	turn_manager.order_queue.changed.connect(refresh)
	turn_manager.resolution_finished.connect(func(_result): refresh())
	refresh()


func refresh() -> void:
	if content == null or state == null:
		return
	for child in content.get_children():
		child.queue_free()
	var retained_units: Array[String] = []
	for unit_id in selected_units:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null and unit.can_be_moved() and unit.faction == GameEnums.Faction.PLAYER:
			retained_units.append(unit_id)
	selected_units = retained_units
	_add_title("NGOÀI THÀNH")
	_add_team_picker()
	_add_expeditions()
	_add_outsider_groups()


func _add_team_picker() -> void:
	var planned := turn_manager.get_planned_expedition()
	if planned != null:
		_add_text("DỰ KIẾN THÁM HIỂM\n%s" % _unit_list(planned.unit_ids))
		_add_button("Hủy chuyến đi dự kiến", func(): turn_manager.cancel_expedition())
		return
	_add_text("Chọn đúng 2 quân cho chuyến đi hoặc hộ tống:")
	var ids := state.units.keys()
	ids.sort()
	for unit_id in ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or unit.faction != GameEnums.Faction.PLAYER or not unit.can_be_moved():
			continue
		var check := CheckButton.new()
		check.text = "%s %s" % [_glyph(unit.rank), _unit_name(unit)]
		check.button_pressed = unit.id in selected_units
		check.toggled.connect(_toggle_unit.bind(unit.id, check))
		content.add_child(check)
	var expedition_button := Button.new()
	expedition_button.text = "Thám hiểm"
	expedition_button.disabled = selected_units.size() != ExpeditionSystem.TEAM_SIZE
	expedition_button.pressed.connect(_queue_expedition)
	content.add_child(expedition_button)


func _add_expeditions() -> void:
	var ids := state.expeditions.keys()
	ids.sort()
	for expedition_id in ids:
		var expedition := state.expeditions.get(expedition_id) as ExpeditionState
		if expedition == null or expedition.status == GameEnums.ExpeditionStatus.COMPLETE:
			continue
		_add_separator()
		_add_title("ĐOÀN THÁM HIỂM")
		_add_text(_unit_list(expedition.unit_ids))
		var status := "Đang chờ chỗ trở về" if expedition.status == GameEnums.ExpeditionStatus.RETURN_PENDING else "Ngoài thành · Ngày thứ %d" % (expedition.elapsed_days + 1)
		_add_text("%s\nChưa có tin." % status)


func _add_outsider_groups() -> void:
	var ids := state.outsider_groups.keys()
	ids.sort()
	for group_id in ids:
		var group := state.outsider_groups.get(group_id) as OutsiderGroupState
		if group == null:
			continue
		_add_separator()
		_add_title(group.name.to_upper())
		_add_text("%s\n%d người\nTrạng thái: %s" % [
			_group_glyphs(group), group.member_count(), outside_system.pressure_label(group)
		])
		if group.is_resettling() or group.resettlement_complete:
			_add_text("Đang tái định cư · còn %d ngày" % group.resettlement_days_left)
			continue
		_add_text(
			"Đang được hỗ trợ · %d Lương thực/ngày" % group.member_count()
			if group.support_active else "Chưa được hỗ trợ"
		)
		var planned := turn_manager.get_planned_outsider_action(group.id)
		if planned != null:
			_add_text("DỰ KIẾN: %s" % _outside_action_name(planned.action))
			_add_button("Hủy quyết định dự kiến", _cancel_group_action.bind(group.id))
			continue
		if group.support_active:
			_add_button(
				"Ngừng hỗ trợ",
				_queue_group_action.bind(group.id, GameEnums.OutsiderAction.STOP_SUPPORT)
			)
		else:
			_add_button(
				"Hỗ trợ lương thực",
				_queue_group_action.bind(group.id, GameEnums.OutsiderAction.START_SUPPORT)
			)
		if not group.trade_offer.is_empty():
			_add_text("Đề nghị: 1 Vật tư ↔ 1 Lương thực")
			_add_button(
				"Chấp thuận trao đổi",
				_queue_group_action.bind(group.id, GameEnums.OutsiderAction.ACCEPT_TRADE)
			)
			_add_button(
				"Từ chối trao đổi",
				_queue_group_action.bind(group.id, GameEnums.OutsiderAction.REJECT_TRADE)
			)
		var resettle := Button.new()
		resettle.text = "Tái định cư"
		resettle.disabled = selected_units.size() != OutsideSystem.ESCORT_COUNT
		resettle.pressed.connect(_queue_resettlement.bind(group.id))
		content.add_child(resettle)


func _queue_group_action(group_id: String, action: GameEnums.OutsiderAction) -> void:
	turn_manager.queue_outsider_action(group_id, action)


func _cancel_group_action(group_id: String) -> void:
	turn_manager.cancel_outsider_action(group_id)


func _queue_resettlement(group_id: String) -> void:
	turn_manager.queue_outsider_action(
		group_id, GameEnums.OutsiderAction.RESETTLE, selected_units.duplicate()
	)
	selected_units.clear()


func _toggle_unit(enabled: bool, unit_id: String, check: CheckButton) -> void:
	if enabled and selected_units.size() >= ExpeditionSystem.TEAM_SIZE:
		check.set_pressed_no_signal(false)
		return
	if enabled:
		selected_units.append(unit_id)
	else:
		selected_units.erase(unit_id)
	refresh()


func _queue_expedition() -> void:
	var team := selected_units.duplicate()
	selected_units.clear()
	turn_manager.queue_expedition(team)


func _add_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	content.add_child(label)


func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)


func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	content.add_child(button)


func _add_separator() -> void:
	content.add_child(HSeparator.new())


func _unit_list(unit_ids: Array[String]) -> String:
	var lines: Array[String] = []
	for unit_id in unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			lines.append("%s %s" % [_glyph(unit.rank), _unit_name(unit)])
	return "\n".join(lines)


func _group_glyphs(group: OutsiderGroupState) -> String:
	var counts := {}
	for unit_id in group.member_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			counts[unit.rank] = int(counts.get(unit.rank, 0)) + 1
	var labels: Array[String] = []
	var ranks := counts.keys()
	ranks.sort()
	for rank in ranks:
		labels.append("%s ×%d" % [_glyph(rank), counts[rank]])
	return " · ".join(labels)


func _outside_action_name(action: GameEnums.OutsiderAction) -> String:
	return ["hỗ trợ", "ngừng hỗ trợ", "chấp thuận trao đổi", "từ chối trao đổi", "tái định cư"][action]


func _unit_name(unit: UnitState) -> String:
	return unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank)


func _rank_name(rank: int) -> String:
	return ["Tốt", "Mã", "Xe", "Tịnh", "Hậu", "Vua"][rank]


func _glyph(rank: int) -> String:
	return ["♟", "♞", "♜", "♝", "♛", "♚"][rank]