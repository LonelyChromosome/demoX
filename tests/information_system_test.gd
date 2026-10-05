extends SceneTree


func _init() -> void:
	_test_day_one_and_stale_knowledge()
	_test_manager_report_quality()
	_test_king_inspection_order()
	print("INFORMATION_SYSTEM_TEST_OK")
	quit(0)


func _test_day_one_and_stale_knowledge() -> void:
	var state := GameState.new()
	state.food = 100
	var building := BuildingState.new("store", GameEnums.BuildingType.BARRACKS, Vector2i(3, 3))
	building.phase = GameEnums.BuildingPhase.ACTIVE
	building.worker_unit_ids = ["worker"]
	state.buildings[building.id] = building
	var worker := _unit(state, "worker", GameEnums.Rank.ROOK, Vector2i(2, 2), 0)
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	var initial := manager.information_system.get_building_fact(building.id)
	_check(state.day_one_full_knowledge, "Day 1 did not start with full knowledge")
	_check(initial != null and initial.values.staff_count == 1, "Day 1 exact snapshot missing")
	building.worker_unit_ids.clear()
	worker.board_cell = Vector2i(7, 7)
	manager.end_day()
	_check(not state.day_one_full_knowledge, "Full knowledge remained enabled after Day 1")
	var stale := manager.information_system.get_building_fact(building.id)
	_check(stale.values.staff_count == 1, "Known state silently refreshed from true state")
	var result := manager.end_day()
	_check(stale.observed_day == 1 and stale.is_stale(state.day), "Unreported fact was not stale")
	_check("Thông tin cũ" in manager.information_system.building_detail(state, building), "Stale label missing")
	_check(_report_contains(result, "lần biết gần nhất Ngày 1"), "Daily report omitted stale information")


func _test_manager_report_quality() -> void:
	var high := _farm_context(5, "high_farm")
	var high_result: TurnResolutionResult = high.manager.end_day()
	var high_fact: KnownFact = high.manager.information_system.get_building_fact("high_farm")
	_check(high_fact != null and high_fact.values.staff_count == 1, "High-loyalty report was inaccurate")
	_check(high_fact.values.has("daily_output"), "High-loyalty report omitted complete output")
	_check(high_fact.confidence == GameEnums.FactConfidence.REPORTED, "High report confidence incorrect")
	_check(_report_contains(high_result, "Nguồn") or not high_result.report_entries.is_empty(), "Manager report missing")

	var low := _farm_context(-1, "low_farm")
	low.manager.end_day()
	var low_fact: KnownFact = low.manager.information_system.get_building_fact("low_farm")
	_check(low_fact != null, "Low-loyalty deterministic report was not generated")
	_check(low_fact.confidence == GameEnums.FactConfidence.UNCERTAIN, "Low loyalty did not lower confidence")
	_check(not low_fact.values.has("daily_output"), "Low-loyalty report leaked complete output")
	_check(low_fact.values.staff_count != 1, "Low-loyalty report did not apply deterministic distortion")


func _test_king_inspection_order() -> void:
	var state := GameState.new()
	state.day = 2
	state.day_one_full_knowledge = false
	state.food = 100
	var building := BuildingState.new("barracks", GameEnums.BuildingType.BARRACKS, Vector2i(3, 3))
	building.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[building.id] = building
	var king := _unit(state, "king", GameEnums.Rank.KING, Vector2i(2, 2), 42)
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	var order := manager.queue_building_inspection(building.id)
	_check(order != null, "King inspection did not create a planned order")
	_check(manager.information_system.get_building_fact(building.id) == null, "Inspection updated knowledge before End Day")
	manager.cancel_building_inspection()
	_check(manager.get_planned_inspection() == null, "Planned inspection could not be cancelled")
	order = manager.queue_building_inspection(building.id)
	_check(manager.queue_move(king.id, Vector2i(1, 1)) == null, "Inspection did not consume King's day opportunity")
	var result := manager.end_day()
	var fact := manager.information_system.get_building_fact(building.id)
	_check(fact != null and fact.confidence == GameEnums.FactConfidence.CONFIRMED, "Inspection was not exact")
	_check(fact.observed_day == 2 and fact.source_label == "Vua kiểm tra trực tiếp", "Inspection source/day missing")
	_check(building.id in result.inspected_building_ids, "Resolved inspection missing from result")
	_check(_report_contains(result, "Vua đã trực tiếp kiểm tra"), "Inspection missing from Daily Report")
	var controller := ContextualBoardController.new()
	controller.state = state
	controller.turn_manager = manager
	var detail := controller._unit_detail(king)
	_check("42" not in detail and "loyalty" not in detail.to_lower(), "UI leaked raw loyalty value")


func _farm_context(loyalty: int, building_id: String) -> Dictionary:
	var state := GameState.new()
	state.food = 100
	var farm := BuildingState.new(building_id, GameEnums.BuildingType.FARM, Vector2i(3, 3))
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[farm.id] = farm
	var source := _unit(state, "%s_manager" % building_id, GameEnums.Rank.ROOK, farm.core_cell, loyalty)
	farm.manager_unit_id = source.id
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return {"state": state, "manager": manager, "farm": farm}


func _unit(
	state: GameState, id: String, rank: GameEnums.Rank, cell: Vector2i, loyalty: int
) -> UnitState:
	var unit := UnitState.new(id)
	unit.display_name = "Quân %s" % id
	unit.rank = rank
	unit.board_cell = cell
	unit.loyalty = loyalty
	state.units[id] = unit
	return unit


func _report_contains(result: TurnResolutionResult, text: String) -> bool:
	for entry in result.report_entries:
		if text in entry.text or text in entry.source_label:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)