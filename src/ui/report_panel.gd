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


func show_result(result: TurnResolutionResult) -> void:
	var lines: Array[String] = []
	lines.append("Ngày %d → %d" % [result.resolved_day, result.next_day])
	var food_delta := result.food_produced - result.food_consumed
	var material_delta := result.materials_produced - result.materials_spent + result.refunded_materials
	if food_delta != 0:
		lines.append("Lương thực: %s%d" % ["+" if food_delta > 0 else "", food_delta])
	if material_delta != 0:
		lines.append("Vật tư: %s%d" % ["+" if material_delta > 0 else "", material_delta])
	if food_delta == 0 and material_delta == 0:
		lines.append("Tài nguyên: không đổi")
	if not result.starved_unit_ids.is_empty():
		lines.append("Chết đói: %s" % ", ".join(result.starved_unit_ids))
	if not result.rejected_orders.is_empty():
		lines.append("Lệnh bị từ chối: %d" % result.rejected_orders.size())
		for rejection in result.rejected_orders:
			lines.append(
				"• %s %s: %s" % [_kind_name(rejection.kind), rejection.id, rejection.reason]
			)
	body_label.text = "\n".join(lines)


func _kind_name(kind: String) -> String:
	var names := {
		"move": "Di chuyển",
		"building": "Xây dựng",
		"cancel_construction": "Hủy xây",
		"assign_builder": "Phân thợ xây",
		"remove_builder": "Rút thợ xây",
		"demolition": "Phá dỡ",
		"staffing": "Phân công",
	}
	return names.get(kind, kind)
