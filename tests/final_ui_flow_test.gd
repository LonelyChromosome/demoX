extends SceneTree


func _init() -> void:
	_test_ration_cards()
	_test_report_breakdown()
	print("FINAL_UI_FLOW_TEST_OK")
	quit(0)


func _test_ration_cards() -> void:
	var state := GameState.new()
	var result := TurnResolutionResult.new()
	result.ration_food_available = 2
	result.ration_need = 4
	for index in range(4):
		var unit := UnitState.new("unit_%d" % index)
		unit.display_name = "Quân %d" % index
		unit.rank = index
		unit.hunger_streak = index % 3
		state.units[unit.id] = unit
		result.ration_candidate_ids.append(unit.id)
	var overlay := RationOverlay.new()
	root.add_child(overlay)
	overlay.show_request(state, result)
	_check(overlay.card_flow is HFlowContainer, "Ration choices are not horizontal wrapping cards")
	_check(overlay.card_flow.get_child_count() == 4, "Ration cards missing")
	var first := overlay.cards["unit_0"].button as Button
	var second := overlay.cards["unit_1"].button as Button
	var third := overlay.cards["unit_2"].button as Button
	overlay._toggle(true, "unit_0", first)
	_check(overlay.cards["unit_0"].check.text == "✓", "Selected ration card has no check mark")
	overlay._toggle(true, "unit_1", second)
	_check(not overlay.confirm.disabled, "Exact ration selection did not enable confirmation")
	overlay._toggle(true, "unit_2", third)
	_check(overlay.selected.size() == 2, "Ration card allowed over-selection")
	overlay._toggle(false, "unit_0", first)
	_check(overlay.confirm.disabled and overlay.selected.size() == 1, "Ration card deselection failed")


func _test_report_breakdown() -> void:
	var state := GameState.new()
	var result := TurnResolutionResult.new()
	result.resolved_day = 4
	result.next_day = 5
	result.food_produced = 4
	result.food_consumed = 2
	result.materials_produced = 2
	var report := ReportPanel.new()
	root.add_child(report)
	report.show_result(state, result)
	_check("Nông trại sản xuất: +4" in report.body_label.text, "Report hid gross Farm production")
	_check("Khẩu phần: -2" in report.body_label.text, "Report hid food consumption")
	_check("Thay đổi lương thực: +2" in report.body_label.text, "Report hid net food change")
	_check("Sản xuất vật tư: +2" in report.body_label.text, "Report hid material production")
	_check(report.visible, "Daily report did not open automatically")
	report.close()
	_check(not report.visible and report.has_report, "Report could not close and reopen safely")
	report.open_latest()
	_check(report.visible, "Header report action could not reopen latest report")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
