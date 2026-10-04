class_name BuildingPalette
extends VBoxContainer

signal building_selected(type: GameEnums.BuildingType)
signal cancel_requested
signal builder_selection_changed(builder_ids: Array[String])
signal cancel_construction_requested
signal reassign_builder_requested
signal demolition_requested
signal demolition_cancel_requested
signal staffing_manager_requested
signal staffing_workers_requested
signal staffing_cancel_requested

const BUILDINGS := [
	["Nông trại", GameEnums.BuildingType.FARM],
	["Xưởng vật tư", GameEnums.BuildingType.MATERIAL_WORKSHOP],
	["Nhà giam", GameEnums.BuildingType.PRISON],
	["Y xá", GameEnums.BuildingType.INFIRMARY],
	["Doanh trại", GameEnums.BuildingType.BARRACKS],
]

var status_label: Label
var builder_status_label: Label
var staffing_status_label: Label
var buttons: Dictionary = {}
var builder_buttons: Dictionary = {}


func _ready() -> void:
	custom_minimum_size.x = 250
	add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "CÔNG TRÌNH 3×3"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)

	var hint := Label.new()
	hint.text = "Core ở giữa, 8 ô vận hành xung quanh"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	for entry in BUILDINGS:
		var button := Button.new()
		button.text = entry[0]
		button.toggle_mode = true
		button.pressed.connect(_on_building_pressed.bind(entry[1]))
		buttons[entry[1]] = button
		add_child(button)

	var builders_title := Label.new()
	builders_title.text = "THỢ XÂY"
	builders_title.add_theme_font_size_override("font_size", 18)
	add_child(builders_title)
	builder_status_label = Label.new()
	builder_status_label.text = "Đã chọn 0 builder"
	add_child(builder_status_label)

	var cancel_button := Button.new()
	cancel_button.text = "Hủy công trình dự kiến"
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	add_child(cancel_button)
	var cancel_construction_button := Button.new()
	cancel_construction_button.text = "Hủy xây hiện tại"
	cancel_construction_button.pressed.connect(func() -> void: cancel_construction_requested.emit())
	add_child(cancel_construction_button)
	var reassign_button := Button.new()
	reassign_button.text = "Gán builder đã chọn"
	reassign_button.pressed.connect(func() -> void: reassign_builder_requested.emit())
	add_child(reassign_button)
	var demolition_button := Button.new()
	demolition_button.text = "Phá ACTIVE hiện tại"
	demolition_button.pressed.connect(func() -> void: demolition_requested.emit())
	add_child(demolition_button)
	var demolition_cancel_button := Button.new()
	demolition_cancel_button.text = "Hủy lệnh phá"
	demolition_cancel_button.pressed.connect(func() -> void: demolition_cancel_requested.emit())
	add_child(demolition_cancel_button)
	var staffing_title := Label.new()
	staffing_title.text = "PHÂN CÔNG"
	staffing_title.add_theme_font_size_override("font_size", 18)
	add_child(staffing_title)
	var manager_button := Button.new()
	manager_button.text = "Gán quân đã chọn làm quản lý"
	manager_button.pressed.connect(func() -> void: staffing_manager_requested.emit())
	add_child(manager_button)
	var worker_button := Button.new()
	worker_button.text = "Gán quân đã chọn làm lao động"
	worker_button.pressed.connect(func() -> void: staffing_workers_requested.emit())
	add_child(worker_button)
	var staffing_cancel_button := Button.new()
	staffing_cancel_button.text = "Hủy phân công dự kiến"
	staffing_cancel_button.pressed.connect(func() -> void: staffing_cancel_requested.emit())
	add_child(staffing_cancel_button)
	staffing_status_label = Label.new()
	staffing_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(staffing_status_label)

	status_label = Label.new()
	status_label.text = "Chọn một loại công trình"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 70
	add_child(status_label)


func set_active_type(type: GameEnums.BuildingType) -> void:
	for key in buttons:
		buttons[key].button_pressed = key == type


func clear_active_type() -> void:
	for button in buttons.values():
		button.button_pressed = false


func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func set_builder_status(count: int) -> void:
	if builder_status_label != null:
		builder_status_label.text = "Đã chọn %d builder" % count


func set_staffing_status(text: String) -> void:
	if staffing_status_label != null:
		staffing_status_label.text = text


func set_available_builders(units: Dictionary) -> void:
	for button in builder_buttons.values():
		button.queue_free()
	builder_buttons.clear()
	for unit in units.values():
		if (
			not (unit is UnitState)
			or unit.faction != GameEnums.Faction.PLAYER
			or unit.rank == GameEnums.Rank.KING
		):
			continue
		var button := Button.new()
		button.text = "%s (%s)" % [unit.display_name if not unit.display_name.is_empty() else unit.id, "thợ xây"]
		button.toggle_mode = true
		button.pressed.connect(_emit_builder_selection)
		builder_buttons[unit.id] = button
		add_child(button)


func selected_builder_ids() -> Array[String]:
	var ids: Array[String] = []
	for builder_id in builder_buttons:
		if builder_buttons[builder_id].button_pressed:
			ids.append(builder_id)
	return ids


func _emit_builder_selection() -> void:
	var ids := selected_builder_ids()
	ids.sort()
	builder_selection_changed.emit(ids)


func _on_building_pressed(type: GameEnums.BuildingType) -> void:
	building_selected.emit(type)
