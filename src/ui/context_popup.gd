class_name ContextPopup
extends PanelContainer

signal action_selected(action: String)
signal action_confirmed(action: String)
signal closed

var title_label: Label
var detail_label: Label
var actions_box: HBoxContainer
var confirm_button: Button
var selected_action := ""
var anchor_position := Vector2.ZERO
var confirm_enabled_for_menu := true
var cancel_button: Button


func _ready() -> void:
	visible = false
	z_index = 20
	custom_minimum_size = Vector2(0, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 19)
	box.add_child(title_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_label)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	box.add_child(action_row)
	actions_box = HBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 6)
	action_row.add_child(actions_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(spacer)
	confirm_button = Button.new()
	confirm_button.text = Localization.text("common.confirm")
	confirm_button.disabled = true
	confirm_button.pressed.connect(_confirm)
	action_row.add_child(confirm_button)
	cancel_button = Button.new()
	cancel_button.text = "×"
	cancel_button.tooltip_text = Localization.text("common.close")
	cancel_button.custom_minimum_size = Vector2(38, 32)
	cancel_button.pressed.connect(close)
	action_row.add_child(cancel_button)
	Localization.watch(_on_language_changed)


func refresh_language() -> void:
	if confirm_button != null:
		confirm_button.text = Localization.text("common.confirm")
		cancel_button.tooltip_text = Localization.text("common.close")


func _on_language_changed(_locale: String) -> void:
	refresh_language()


func _exit_tree() -> void:
	Localization.unwatch(_on_language_changed)


func open_at(
	screen_position: Vector2,
	title: String,
	detail: String,
	actions: Dictionary,
	show_confirm := true
) -> void:
	anchor_position = screen_position
	title_label.text = title
	title_label.visible = not title.is_empty()
	detail_label.text = detail
	detail_label.visible = not detail.is_empty()
	selected_action = ""
	confirm_enabled_for_menu = show_confirm
	confirm_button.visible = show_confirm and not actions.is_empty()
	confirm_button.disabled = true
	for child in actions_box.get_children():
		child.queue_free()
	for action in actions:
		var button := Button.new()
		button.text = actions[action]
		button.custom_minimum_size = Vector2(108, 34)
		button.pressed.connect(_select.bind(action))
		actions_box.add_child(button)
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.96, 0.96)
	call_deferred("_place_clamped")
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12)


func close() -> void:
	if not visible:
		return
	visible = false
	selected_action = ""
	closed.emit()


func _select(action: String) -> void:
	selected_action = action
	if confirm_enabled_for_menu:
		confirm_button.disabled = false
	action_selected.emit(action)


func _confirm() -> void:
	if selected_action.is_empty():
		return
	action_confirmed.emit(selected_action)
	close()


func _place_clamped() -> void:
	if not visible:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var popup_size: Vector2 = size
	var margin := 12.0
	var x := clampf(
		anchor_position.x - popup_size.x * 0.5,
		margin,
		maxf(margin, viewport_size.x - popup_size.x - margin)
	)
	var y := anchor_position.y + 22.0
	if y + popup_size.y > viewport_size.y - margin:
		y = anchor_position.y - popup_size.y - 22.0
	y = clampf(y, margin, maxf(margin, viewport_size.y - popup_size.y - margin))
	global_position = Vector2(x, y)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
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
