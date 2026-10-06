class_name EndingPanel
extends ColorRect

var state: GameState
var title_label: Label
var outcome_label: Label
var body_label: Label
var close_button: Button


func _ready() -> void:
	visible = false
	z_index = 60
	color = Color(0.03, 0.035, 0.04, 0.96)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 30)
	box.add_child(title_label)
	outcome_label = Label.new()
	outcome_label.add_theme_font_size_override("font_size", 23)
	box.add_child(outcome_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body_label)
	close_button = Button.new()
	close_button.pressed.connect(func(): visible = false)
	box.add_child(close_button)
	Localization.watch(_on_language_changed)


func show_ending(game_state: GameState) -> void:
	state = game_state
	_refresh_language()
	visible = true


func _refresh_language() -> void:
	if state == null or title_label == null:
		return
	var recap := EndingSystem.new().localized_recap(state)
	title_label.text = str(recap.get("title", ""))
	outcome_label.text = "%s\n%s" % [recap.get("outcome_title", ""), recap.get("outcome_body", "")]
	var blocks: Array[String] = []
	for section in recap.get("sections", []):
		var lines: Array[String] = []
		for line in section.get("lines", []):
			lines.append("• %s" % line)
		blocks.append("%s\n%s" % [section.title, "\n".join(lines)])
	body_label.text = "\n\n".join(blocks)
	close_button.text = Localization.text("ending.close")


func _on_language_changed(_locale: String) -> void:
	_refresh_language()


func _exit_tree() -> void:
	Localization.unwatch(_on_language_changed)
