extends SceneTree


func _init() -> void:
	_test_progression_ui_and_report()
	print("S11_PROGRESSION_UI_TEST_OK")
	quit(0)


func _test_progression_ui_and_report() -> void:
	var state := GameState.new()
	state.food = 20
	var barracks := BuildingState.new(
		"barracks", GameEnums.BuildingType.BARRACKS, Vector2i(4, 4)
	)
	barracks.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[barracks.id] = barracks
	var unit := UnitState.new("trainee")
	unit.display_name = "Tốt thử nghiệm"
	unit.rank = GameEnums.Rank.PAWN
	unit.faction = GameEnums.Faction.PLAYER
	unit.board_cell = Vector2i(0, 7)
	unit.merit = 6
	unit.lifetime_merit = 6
	state.units[unit.id] = unit

	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	var controller := ContextualBoardController.new()
	root.add_child(controller)
	controller.state = state
	controller.turn_manager = manager

	var actions := {}
	var barracks_detail := controller._barracks_progression_detail(barracks, actions, true)
	var promotion_action := "promotion:%s:%d" % [unit.id, GameEnums.Rank.ROOK]
	_check(
		"Tốt thử nghiệm · Tốt · 6 Chiến công" in barracks_detail,
		"Barracks omitted unit progression"
	)
	_check(
		"cần 6 · 1 ngày · SẴN SÀNG" in barracks_detail,
		"Barracks omitted promotion requirements"
	)
	_check(actions.has(promotion_action), "Barracks did not expose a valid training action")
	_check(
		"SẴN SÀNG" in controller._unit_progression_detail(unit),
		"Unit info omitted promotion-ready state"
	)

	_check(
		manager.queue_promotion(unit.id, barracks.id, GameEnums.Rank.ROOK) != null,
		"UI promotion order could not be queued"
	)
	_check(
		"DỰ KIẾN HUẤN LUYỆN" in controller._unit_progression_detail(unit),
		"Queued feedback was not visible"
	)
	var start_result := manager.end_day()
	_check(unit.is_in_promotion_training(), "Training did not start through turn flow")
	_check(
		"ĐANG HUẤN LUYỆN" in controller._unit_progression_detail(unit),
		"Training state was not visible"
	)
	_check(
		"còn 1 ngày" in controller._unit_progression_detail(unit),
		"Training progress omitted remaining days"
	)
	var finish_result := manager.end_day()
	_check(unit.rank == GameEnums.Rank.ROOK, "Completed rank was not reflected in unit state")
	_check(
		"TIẾN TRIỂN · Xe" in controller._unit_progression_detail(unit),
		"Completed rank was not reflected in unit UI"
	)
	_check(not start_result.report_entries.is_empty(), "Training start was not reported")

	var ready_result := TurnResolutionResult.new()
	ready_result.resolved_day = state.day
	ready_result.next_day = state.day + 1
	ready_result.promotion_events.append({
		"kind": "promotion_ready",
		"unit_id": unit.id,
		"text": "Tốt thử nghiệm đã sẵn sàng huấn luyện.",
		"attention": GameEnums.AttentionLevel.IMPORTANT,
	})
	InformationSystem.new().resolve_daily_information(state, ready_result)
	var panel := ReportPanel.new()
	root.add_child(panel)
	panel.show_result(ready_result)
	var body := panel.body_label.text
	_check(
		body.find("CẦN CHÚ Ý") < body.find("TODAY SUMMARY"),
		"Promotion attention was not prioritized"
	)
	_check("Tốt thử nghiệm đã sẵn sàng huấn luyện." in body, "Promotion-ready report was missing")
	_check("Nguồn: Barracks" in body, "Progression report lost its Barracks source")
	panel.close()
	panel.open_latest()
	_check("Không có mục chưa đọc." in panel.body_label.text, "Read attention did not reduce")
	_check(
		"Tốt thử nghiệm đã sẵn sàng huấn luyện." in panel.body_label.text,
		"Read history left FULL LOG"
	)

	var completed_report := false
	for entry in finish_result.report_entries:
		if entry.source_label == "Barracks" and "hoàn tất" in entry.text:
			completed_report = entry.category == "summary"
	_check(completed_report, "Promotion completion did not reach TODAY SUMMARY")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
