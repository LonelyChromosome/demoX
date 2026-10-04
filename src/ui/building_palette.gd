class_name BuildingPalette
extends VBoxContainer

signal building_selected(type: GameEnums.BuildingType)
signal cancel_requested
signal builder_selection_changed(builder_ids: Array[String])

const BUILDINGS := [
	["Farm", GameEnums.BuildingType.FARM],
	["Material Workshop", GameEnums.BuildingType.MATERIAL_WORKSHOP],
	["Prison", GameEnums.BuildingType.PRISON],
	["Infirmary / Y", GameEnums.BuildingType.INFIRMARY],
	["Barracks", GameEnums.BuildingType.BARRACKS],
]

var status_label: Label
var builder_status_label: Label
var buttons: Dictionary = {}
var builder_buttons: Dictionary = {}


func _ready() -> void:
	custom_minimum_size.x = 250
	add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "BUILDING 3x3"
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
	builders_title.text = "BUILDERS"
	builders_title.add_theme_font_size_override("font_size", 18)
	add_child(builders_title)
	builder_status_label = Label.new()
	builder_status_label.text = "Đã chọn 0 builder"
	add_child(builder_status_label)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel planned building"
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	add_child(cancel_button)

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
		button.text = "%s (%s)" % [unit.display_name if not unit.display_name.is_empty() else unit.id, "builder"]
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
