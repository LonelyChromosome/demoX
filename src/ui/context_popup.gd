class_name ContextPopup
extends PanelContainer

signal action_selected(action: String)
signal action_confirmed(action: String)
signal closed

var title_label: Label
var detail_label: Label
var actions_box: VBoxContainer
var confirm_button: Button
var selected_action := ""


func _ready() -> void:
	visible = false
	z_index = 20
	custom_minimum_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 19)
	box.add_child(title_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_label)
	actions_box = VBoxContainer.new()
	box.add_child(actions_box)
	var footer := HBoxContainer.new()
	box.add_child(footer)
	confirm_button = Button.new()
	confirm_button.text = "Xác nhận"
	confirm_button.disabled = true
	confirm_button.pressed.connect(_confirm)
	footer.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.text = "Đóng"
	cancel_button.pressed.connect(close)
	footer.add_child(cancel_button)


func open_at(screen_position: Vector2, title: String, detail: String, actions: Dictionary) -> void:
	title_label.text = title
	detail_label.text = detail
	selected_action = ""
	confirm_button.disabled = true
	for child in actions_box.get_children():
		child.queue_free()
	for action in actions:
		var button := Button.new()
		button.text = actions[action]
		button.pressed.connect(_select.bind(action))
		actions_box.add_child(button)
	global_position = screen_position + Vector2(18, -18)
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.96, 0.96)
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
	confirm_button.disabled = false
	action_selected.emit(action)


func _confirm() -> void:
	if selected_action.is_empty():
		return
	action_confirmed.emit(selected_action)
	close()


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
