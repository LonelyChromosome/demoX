class_name ReportPanel
extends PanelContainer

var title_label: Label
var body_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(330, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	title_label = Label.new()
	title_label.text = "BÁO CÁO"
	title_label.add_theme_font_size_override("font_size", 24)
	box.add_child(title_label)

	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.text = "Ngày 1: tình hình ban đầu được biết chính xác.\n\nTừ ngày sau, thông tin phụ thuộc vào bộ máy đã dựng."
	box.add_child(body_label)
