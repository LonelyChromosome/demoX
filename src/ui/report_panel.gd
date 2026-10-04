class_name ReportPanel
extends PanelContainer

var title_label: Label
var body_label: Label
var has_report := false


func _ready() -> void:
	visible = false
	z_index = 30
	custom_minimum_size = Vector2(470, 330)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	title_label = Label.new()
	title_label.text = "BÁO CÁO NGÀY"
	title_label.add_theme_font_size_override("font_size", 23)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "Đóng báo cáo"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 255)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	body_label = Label.new()
	body_label.custom_minimum_size.x = 410
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(body_label)
	get_viewport().size_changed.connect(_clamp_to_viewport)
	resized.connect(_clamp_to_viewport)


func show_result(state: GameState, result: TurnResolutionResult) -> void:
	has_report = true
	title_label.text = "BÁO CÁO NGÀY %02d" % result.resolved_day
	var lines: Array[String] = []
	_append_resource_lines(lines, result)
	for event in result.building_events:
		lines.append(_building_event_text(event))
	for change in result.farm_role_changes:
		lines.append(_farm_role_text(state, change))
	if not result.starved_unit_ids.is_empty():
		var names: Array[String] = []
		for unit_id in result.starved_unit_ids:
			names.append(result.starved_unit_names.get(unit_id, "một quân cờ"))
		lines.append("Chết đói: %s." % ", ".join(names))
	for rejection in result.rejected_orders:
		lines.append("Lệnh %s bị từ chối: %s." % [
			_order_name(rejection.kind), rejection.reason
		])
	if lines.is_empty():
		lines.append("Không có thay đổi đáng chú ý.")
	body_label.text = "\n".join(lines)
	open_latest()


func open_latest() -> void:
	if not has_report:
		return
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.97, 0.97)
	call_deferred("_clamp_to_viewport")
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.14)
	tween.tween_property(self, "scale", Vector2.ONE, 0.14)


func close() -> void:
	visible = false


func _append_resource_lines(lines: Array[String], result: TurnResolutionResult) -> void:
	if result.food_produced != 0:
		lines.append("Nông trại sản xuất: +%d lương thực" % result.food_produced)
	if result.food_consumed != 0:
		lines.append("Khẩu phần: -%d lương thực" % result.food_consumed)
	var food_delta := result.food_produced - result.food_consumed
	if result.food_produced != 0 or result.food_consumed != 0:
		lines.append("Thay đổi lương thực: %s%d" % [_sign(food_delta), food_delta])
	if result.materials_produced != 0:
		lines.append("Sản xuất vật tư: +%d" % result.materials_produced)
	if result.materials_spent != 0:
		lines.append("Chi xây dựng: -%d vật tư" % result.materials_spent)
	if result.refunded_materials != 0:
		lines.append("Hoàn vật tư: +%d" % result.refunded_materials)
	var material_delta := result.materials_produced - result.materials_spent + result.refunded_materials
	if result.materials_produced != 0 or result.materials_spent != 0 or result.refunded_materials != 0:
		lines.append("Thay đổi vật tư: %s%d" % [_sign(material_delta), material_delta])


func _building_event_text(event: Dictionary) -> String:
	var label := "%s tại %s" % [_building_name(event.type), _cell_name(event.core)]
	if event.kind == "blueprint_placed":
		return "%s đã được đặt bản vẽ." % label
	if event.kind == "construction_started":
		return "%s bắt đầu xây dựng." % label
	if event.kind == "completed":
		return "%s đã hoàn thành." % label
	if event.kind == "cancelled":
		return "%s đã hủy xây." % label
	return "%s đã bị phá." % label


func _farm_role_text(state: GameState, change: Dictionary) -> String:
	var building := state.buildings.get(change.building_id) as BuildingState
	var farm_name := "Nông trại"
	if building != null:
		farm_name = "Nông trại tại %s" % _cell_name(building.core_cell)
	var role := "chủ trại" if change.role == "manager" else "lao động"
	return "%s %s làm %s ở %s." % [
		change.unit_name,
		"bắt đầu" if change.started else "ngừng",
		role,
		farm_name,
	]


func _order_name(kind: String) -> String:
	var names := {
		"move": "di chuyển",
		"building": "xây dựng",
		"staffing": "phân công",
		"demolition": "phá công trình",
		"cancel_construction": "hủy xây",
		"assign_builder": "gán thợ xây",
		"remove_builder": "rút thợ xây",
	}
	return str(names.get(kind, "hành động"))


func _building_name(type: int) -> String:
	return ["Nông trại", "Xưởng vật tư", "Nhà giam", "Y xá", "Doanh trại"][type]


func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]


func _sign(value: int) -> String:
	return "+" if value > 0 else ""


func _clamp_to_viewport() -> void:
	if not visible:
		return
	var viewport_size := get_viewport_rect().size
	var target := (viewport_size - size) * 0.5
	position = Vector2(
		clampf(target.x, 12.0, maxf(12.0, viewport_size.x - size.x - 12.0)),
		clampf(target.y, 12.0, maxf(12.0, viewport_size.y - size.y - 12.0))
	)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if (
		visible
		and event is InputEventMouseButton
		and event.pressed
		and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
		and not get_global_rect().has_point(event.global_position)
	):
		close()
		if event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
