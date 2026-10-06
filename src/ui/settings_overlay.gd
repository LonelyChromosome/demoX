class_name SettingsOverlay
extends Control

signal closed

const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

var _title: Label
var _resolution_label: Label
var _resolution: OptionButton
var _mute: CheckButton
var _slider_labels: Dictionary = {}
var _sliders: Dictionary = {}
var _close_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Localization.watch(_refresh_language)
	_refresh_language(Localization.current_language())
	hide()


func open() -> void:
	_sync_values()
	show()
	move_to_front()


func close() -> void:
	hide()
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.035, 0.055, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-270, -260)
	panel.size = Vector2(540, 520)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18243a")
	style.border_color = Color("c7a76a")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color("f0d796"))
	box.add_child(_title)

	_resolution_label = Label.new()
	_resolution_label.add_theme_font_size_override("font_size", 17)
	box.add_child(_resolution_label)
	_resolution = OptionButton.new()
	for size in RESOLUTIONS:
		_resolution.add_item("%d × %d" % [size.x, size.y])
	_resolution.item_selected.connect(_on_resolution_selected)
	box.add_child(_resolution)

	for bus_name in ["Master", "BGM", "SFX", "Ambience"]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size.x = 120
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_bus_value_changed.bind(bus_name))
		row.add_child(slider)
		_slider_labels[bus_name] = label
		_sliders[bus_name] = slider
		box.add_child(row)

	_mute = CheckButton.new()
	_mute.toggled.connect(AppAudio.set_master_muted)
	box.add_child(_mute)

	_close_button = Button.new()
	_close_button.custom_minimum_size.y = 48
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


func _on_bus_value_changed(value: float, bus_name: String) -> void:
	AppAudio.set_bus_level(bus_name, value / 100.0)


func _sync_values() -> void:
	var saved := AppAudio.saved_resolution()
	for i in range(RESOLUTIONS.size()):
		if RESOLUTIONS[i] == saved:
			_resolution.select(i)
	for bus_name in _sliders:
		(_sliders[bus_name] as HSlider).value = AppAudio.bus_level(bus_name) * 100.0
	_mute.button_pressed = AppAudio.master_muted()


func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < RESOLUTIONS.size():
		AppAudio.set_resolution(RESOLUTIONS[index])


func _refresh_language(_locale: String) -> void:
	_title.text = Localization.text("settings.title")
	_resolution_label.text = Localization.text("settings.resolution")
	_slider_labels["Master"].text = Localization.text("settings.master")
	_slider_labels["BGM"].text = Localization.text("settings.bgm")
	_slider_labels["SFX"].text = Localization.text("settings.sfx")
	_slider_labels["Ambience"].text = Localization.text("settings.ambience")
	_mute.text = Localization.text("settings.mute")
	_close_button.text = Localization.text("common.close")


func _exit_tree() -> void:
	Localization.unwatch(_refresh_language)
