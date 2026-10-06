class_name OnboardingHintPanel
extends PanelContainer

signal next_requested
signal skip_requested

var title_label: Label
var body_label: Label
var next_button: Button
var skip_button: Button
var current_hint: Dictionary = {}


func _ready() -> void:
	visible = false
	z_index = 35
	custom_minimum_size = Vector2(390, 0)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 20)
	box.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body_label)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	skip_button = Button.new()
	skip_button.pressed.connect(func(): skip_requested.emit())
	actions.add_child(skip_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	next_button = Button.new()
	next_button.pressed.connect(func(): next_requested.emit())
	actions.add_child(next_button)
	Localization.watch(_on_language_changed)
	_refresh_language()


func show_hint(hint: Dictionary) -> void:
	current_hint = hint.duplicate(true)
	if current_hint.is_empty():
		visible = false
		return
	_refresh_language()
	visible = true
	call_deferred("_place")


func close() -> void:
	visible = false


func _refresh_language() -> void:
	if title_label == null:
		return
	if not current_hint.is_empty():
		title_label.text = Localization.text(str(current_hint.title_key))
		body_label.text = Localization.text(str(current_hint.body_key))
	next_button.text = Localization.text("onboarding.dismiss")
	skip_button.text = Localization.text("onboarding.skip")


func _on_language_changed(_locale: String) -> void:
	_refresh_language()


func _place() -> void:
	var viewport_size := get_viewport_rect().size
	position = Vector2(maxf(18.0, viewport_size.x - size.x - 24.0), 76.0)


func _exit_tree() -> void:
	Localization.unwatch(_on_language_changed)
