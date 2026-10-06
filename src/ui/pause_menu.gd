class_name PauseMenu
extends Control

signal resume_requested
signal main_menu_requested

var _title: Label
var _resume: Button
var _settings: Button
var _main_menu: Button

var _settings_overlay: SettingsOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Localization.watch(_refresh_language)
	_refresh_language(Localization.current_language())
	hide()


func open() -> void:
	show()
	move_to_front()


func close() -> void:
	if _settings_overlay.visible:
		_settings_overlay.close()
	else:
		hide()


func is_open() -> bool:
	return visible


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.035, 0.58)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-220, -185)
	panel.size = Vector2(440, 370)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("152239")
	style.border_color = Color("c7a76a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color("f0d796"))
	box.add_child(_title)
	_resume = _menu_button(box)
	_resume.pressed.connect(func(): resume_requested.emit())
	_settings = _menu_button(box)
	_settings.pressed.connect(func(): _settings_overlay.open())
	_main_menu = _menu_button(box)
	_main_menu.pressed.connect(func(): main_menu_requested.emit())
	_settings_overlay = SettingsOverlay.new()
	add_child(_settings_overlay)


func _menu_button(parent: Control) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 56
	button.add_theme_font_size_override("font_size", 19)
	parent.add_child(button)
	return button


func _refresh_language(_locale: String) -> void:
	_title.text = Localization.text("pause.title")
	_resume.text = Localization.text("pause.resume")
	_settings.text = Localization.text("menu.settings")
	_main_menu.text = Localization.text("pause.main_menu")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _settings_overlay.visible:
			_settings_overlay.close()
		else:
			resume_requested.emit()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	Localization.unwatch(_refresh_language)
