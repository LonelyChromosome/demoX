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


func show_result(result: TurnResolutionResult) -> void:
	has_report = true
	title_label.text = "BÁO CÁO NGÀY %02d" % result.resolved_day
	var lines: Array[String] = []
	for entry in result.report_entries:
		lines.append(_entry_text(entry, result.next_day))
	if lines.is_empty():
		lines.append("Chưa nhận được báo cáo cho ngày này.")
	body_label.text = "\n\n".join(lines)
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


func _entry_text(entry: ReportEntry, current_day: int) -> String:
	var metadata: Array[String] = []
	if not entry.source_label.is_empty():
		metadata.append("Nguồn: %s" % entry.source_label)
	metadata.append("Độ tin cậy: %s" % _confidence_label(
		entry.confidence, entry.observed_day < current_day - 1
	))
	metadata.append("Cập nhật: Ngày %d" % entry.observed_day)
	return "%s\n%s" % [entry.text, " · ".join(metadata)]


func _confidence_label(confidence: int, stale: bool) -> String:
	if stale:
		return "Thông tin cũ"
	if confidence == GameEnums.FactConfidence.CONFIRMED:
		return "Đã xác nhận"
	if confidence == GameEnums.FactConfidence.REPORTED:
		return "Theo báo cáo"
	return "Chưa chắc chắn"


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
