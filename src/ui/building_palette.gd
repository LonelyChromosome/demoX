class_name BuildingPalette
extends VBoxContainer

signal building_selected(type: GameEnums.BuildingType)
signal cancel_requested

const BUILDINGS := [
	["Farm", GameEnums.BuildingType.FARM],
	["Material Workshop", GameEnums.BuildingType.MATERIAL_WORKSHOP],
	["Prison", GameEnums.BuildingType.PRISON],
	["Infirmary / Y", GameEnums.BuildingType.INFIRMARY],
	["Barracks", GameEnums.BuildingType.BARRACKS],
]

var status_label: Label
var buttons: Dictionary = {}


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


func _on_building_pressed(type: GameEnums.BuildingType) -> void:
	building_selected.emit(type)
