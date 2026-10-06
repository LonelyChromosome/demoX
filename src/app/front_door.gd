extends Control

const GAME_SCENE := "res://src/app/main.tscn"
const INTRO_STREAM := preload("res://assets/intro/after_checkmate_intro.ogv")
const MENU_BACKGROUND := preload("res://assets/menu/main_menu_bg.jpg")

var _video: VideoStreamPlayer
var _menu_layer: Control
var _title: Label
var _subtitle: Label
var _play: Button
var _about: Button
var _settings: Button
var _quit: Button
var _vi: Button
var _en: Button
var _about_overlay: Control
var _about_title: Label
var _about_body: Label
var _about_close: Button
var _settings_overlay: SettingsOverlay
var _intro_hold: ColorRect
var _intro_finished := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Localization.load_saved_language()
	_build_menu()
	Localization.watch(_refresh_language)
	_refresh_language(Localization.current_language())
	if AppAudio.intro_played:
		_show_menu_immediate()
		AppAudio.ensure_menu_music()
	else:
		_play_intro()


func _play_intro() -> void:
	_menu_layer.hide()
	_intro_finished = false
	_video = VideoStreamPlayer.new()
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.stream = INTRO_STREAM
	_video.autoplay = false
	_video.finished.connect(_on_intro_finished)
	add_child(_video)
	_intro_hold = ColorRect.new()
	_intro_hold.color = Color.BLACK
	_intro_hold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_hold.hide()
	add_child(_intro_hold)
	AppAudio.begin_intro_opening()
	_video.play()


func _on_intro_finished() -> void:
	# The Godot/Theora transcode can report a few frames shorter than the 11.0s
	# master. Hold the already-black final image until the *audio clock* reaches
	# 11.0s. The pre-cut Opening starts at original 1.25s, therefore the menu
	# appears exactly at original 12.25s without restarting or seeking the music.
	_intro_finished = true
	if _intro_hold != null:
		_intro_hold.show()
	_try_finish_intro_sync()


func _process(_delta: float) -> void:
	if _intro_finished:
		_try_finish_intro_sync()


func _try_finish_intro_sync() -> void:
	if AppAudio.opening_position() + 0.001 < 11.0:
		return
	_intro_finished = false
	if _video != null:
		_video.queue_free()
		_video = null
	if _intro_hold != null:
		_intro_hold.queue_free()
		_intro_hold = null
	_show_menu_immediate()


func _show_menu_immediate() -> void:
	_menu_layer.show()
	_menu_layer.modulate.a = 1.0


func _build_menu() -> void:
	_menu_layer = Control.new()
	_menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_layer)

	var background := TextureRect.new()
	background.texture = MENU_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_layer.add_child(background)

	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.035, 0.07, 0.36)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_layer.add_child(shade)

	var left := VBoxContainer.new()
	left.anchor_left = 0.07
	left.anchor_top = 0.12
	left.anchor_right = 0.43
	left.anchor_bottom = 0.86
	left.add_theme_constant_override("separation", 15)
	_menu_layer.add_child(left)

	_title = Label.new()
	_title.text = "AFTER CHECKMATE"
	_title.add_theme_font_size_override("font_size", 54)
	_title.add_theme_color_override("font_color", Color("f3d791"))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	left.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 18)
	_subtitle.add_theme_color_override("font_color", Color("e8dcc2"))
	left.add_child(_subtitle)

	var gap := Control.new()
	gap.custom_minimum_size.y = 36
	left.add_child(gap)
	_play = _menu_button(left)
	_play.pressed.connect(_start_game)
	_about = _menu_button(left)
	_about.pressed.connect(func(): _about_overlay.show(); _about_overlay.move_to_front())
	_settings = _menu_button(left)
	_settings.pressed.connect(func(): _settings_overlay.open())
	_quit = _menu_button(left)
	_quit.pressed.connect(func(): get_tree().quit())

	var language_row := HBoxContainer.new()
	language_row.anchor_left = 0.84
	language_row.anchor_top = 0.035
	language_row.anchor_right = 0.965
	language_row.anchor_bottom = 0.105
	language_row.add_theme_constant_override("separation", 6)
	_menu_layer.add_child(language_row)
	_vi = Button.new()
	_vi.text = "VI"
	_vi.pressed.connect(func(): GameSession.set_language("vi"))
	language_row.add_child(_vi)
	var separator := Label.new()
	separator.text = "|"
	separator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	language_row.add_child(separator)
	_en = Button.new()
	_en.text = "EN"
	_en.pressed.connect(func(): GameSession.set_language("en"))
	language_row.add_child(_en)

	_settings_overlay = SettingsOverlay.new()
	_menu_layer.add_child(_settings_overlay)
	_build_about_overlay()


func _menu_button(parent: Control) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(360, 58)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override("font_size", 21)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.035, 0.09, 0.17, 0.88)
	normal.border_color = Color("a98a50")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(7)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.06, 0.14, 0.24, 0.96)
	hover.border_color = Color("e0bd73")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	parent.add_child(button)
	return button


func _build_about_overlay() -> void:
	_about_overlay = Control.new()
	_about_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_about_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_layer.add_child(_about_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_about_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-310, -205)
	panel.size = Vector2(620, 410)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17253a")
	style.border_color = Color("c7a76a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 38
	style.content_margin_right = 38
	style.content_margin_top = 32
	style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", style)
	_about_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)
	_about_title = Label.new()
	_about_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_about_title.add_theme_font_size_override("font_size", 30)
	_about_title.add_theme_color_override("font_color", Color("f0d796"))
	box.add_child(_about_title)
	_about_body = Label.new()
	_about_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about_body.add_theme_font_size_override("font_size", 19)
	_about_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_about_body)
	_about_close = Button.new()
	_about_close.custom_minimum_size.y = 48
	_about_close.pressed.connect(func(): _about_overlay.hide())
	box.add_child(_about_close)
	_about_overlay.hide()


func _start_game() -> void:
	AppAudio.stop_bgm()
	get_tree().change_scene_to_file(GAME_SCENE)


func _refresh_language(locale: String) -> void:
	_subtitle.text = "TÀN CUỘC" if locale == "vi" else Localization.text("menu.subtitle")
	_play.text = Localization.text("menu.play")
	_about.text = Localization.text("menu.about")
	_settings.text = Localization.text("menu.settings")
	_quit.text = Localization.text("menu.quit")
	_about_title.text = Localization.text("menu.about_title")
	_about_body.text = Localization.text("menu.about_body")
	_about_close.text = Localization.text("common.close")
	_vi.disabled = locale == "vi"
	_en.disabled = locale == "en"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _settings_overlay.visible:
			_settings_overlay.close()
		elif _about_overlay.visible:
			_about_overlay.hide()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	Localization.unwatch(_refresh_language)
