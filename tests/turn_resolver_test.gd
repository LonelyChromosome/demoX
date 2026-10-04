extends SceneTree


func _init() -> void:
	_test_move_commit_replace_cancel_and_ghost_clear()
	_test_building_commit_cancel_and_replace()
	_test_invalid_and_conflicting_orders()
	_test_day_progression_and_cap()
	print("TURN_RESOLVER_TEST_OK")
	quit(0)


func _test_move_commit_replace_cancel_and_ghost_clear() -> void:
	var context := _new_context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var king := _add_unit(state, "king", Vector2i(4, 7))

	manager.queue_move("king", Vector2i(4, 5))
	_check(king.board_cell == Vector2i(4, 7), "move changed authoritative state before End Day")
	_check(manager.get_planned_move_target("king") == Vector2i(4, 5), "move ghost missing")
	manager.queue_move("king", Vector2i(2, 5))
	_check(manager.get_pending_move_count() == 1, "move replacement kept multiple orders")
	manager.end_day()
	_check(king.board_cell == Vector2i(2, 5), "final move destination was not committed")
	_check(not manager.has_pending_orders(), "ghost/pending state survived End Day")
	var expected_phases := [
		TurnResolver.Phase.VALIDATE_ORDERS,
		TurnResolver.Phase.COMMIT_MOVEMENT,
		TurnResolver.Phase.COMMIT_BUILDING_PLACEMENT,
		TurnResolver.Phase.COMMIT_CANCEL_CONSTRUCTION,
		TurnResolver.Phase.COMMIT_DEMOLITION,
		TurnResolver.Phase.RESOLVE_SYSTEMS,
		TurnResolver.Phase.RESOLVE_EVENTS,
		TurnResolver.Phase.FINALIZE_DEMOLITION,
		TurnResolver.Phase.FINALIZE_DAY,
		TurnResolver.Phase.START_NEXT_DAY,
	]
	var phase_context := _new_context()
	var phase_result: TurnResolutionResult = phase_context.manager.end_day()
	_check(phase_result.phase_trace == expected_phases, "resolver phase order changed")

	manager.queue_move("king", Vector2i(1, 5))
	manager.cancel_move("king")
	manager.end_day()
	_check(king.board_cell == Vector2i(2, 5), "cancelled move was committed")


func _test_building_commit_cancel_and_replace() -> void:
	var context := _new_context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager

	manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3))
	_check(state.buildings.is_empty(), "planned building changed authoritative state")
	manager.end_day()
	_check(state.buildings.size() == 1, "planned blueprint was not committed")
	var farm := state.buildings.values()[0] as BuildingState
	_check(farm.phase == GameEnums.BuildingPhase.BUILDING, "building did not enter construction")

	manager.queue_building(GameEnums.BuildingType.PRISON, Vector2i(6, 6))
	manager.cancel_building()
	manager.end_day()
	_check(state.buildings.size() == 1, "cancelled building was committed")

	manager.queue_building(GameEnums.BuildingType.INFIRMARY, Vector2i(1, 5))
	manager.queue_building(GameEnums.BuildingType.BARRACKS, Vector2i(6, 1))
	manager.end_day()
	_check(state.buildings.size() == 2, "replaced building order committed wrong count")
	var barracks_found := false
	for candidate in state.buildings.values():
		if candidate is BuildingState and candidate.type == GameEnums.BuildingType.BARRACKS:
			barracks_found = candidate.core_cell == Vector2i(6, 1)
	_check(barracks_found, "only the last building position/type should commit")


func _test_invalid_and_conflicting_orders() -> void:
	var context := _new_context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var rook := _add_unit(state, "rook", Vector2i(0, 7))
	var knight := _add_unit(state, "knight", Vector2i(1, 7))

	manager.queue_move("rook", Vector2i(3, 4))
	manager.queue_move("knight", Vector2i(3, 4))
	var conflict_result := manager.end_day()
	_check(rook.board_cell == Vector2i(0, 7), "conflicting rook move committed")
	_check(knight.board_cell == Vector2i(1, 7), "conflicting knight move committed")
	_check(conflict_result.rejected_orders.size() == 2, "move conflict was not rejected")

	manager.queue_move("rook", Vector2i(2, 4))
	state.units.erase("rook")
	var missing_result := manager.end_day()
	_check(missing_result.was_rejected("move", "rook"), "missing unit order did not fail safely")

	var locked := _add_unit(state, "locked", Vector2i(5, 7))
	locked.locked_by_construction = true
	manager.queue_move("locked", Vector2i(5, 5))
	var locked_result := manager.end_day()
	_check(locked.board_cell == Vector2i(5, 7), "locked unit moved")
	_check(locked_result.was_rejected("move", "locked"), "locked unit order was not rejected")

	manager.queue_building(GameEnums.BuildingType.PRISON, Vector2i(3, 3))
	_add_unit(state, "late_unit", Vector2i(3, 3))
	var building_result := manager.end_day()
	_check(not building_result.building_committed, "building invalidated before End Day committed")
	_check(building_result.rejected_orders.size() == 1, "invalid building was not rejected")

	var cross_context := _new_context()
	var cross_state: GameState = cross_context.state
	var cross_manager: TurnManager = cross_context.manager
	var mover := _add_unit(cross_state, "mover", Vector2i(7, 7))
	cross_manager.queue_move("mover", Vector2i(3, 3))
	cross_manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3))
	var cross_result := cross_manager.end_day()
	_check(mover.board_cell == Vector2i(3, 3), "valid move in cross-action conflict was lost")
	_check(not cross_result.building_committed, "building conflicting with planned move committed")


func _test_day_progression_and_cap() -> void:
	var context := _new_context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	_check(state.day == 1, "game did not start on Day 1")
	manager.end_day()
	_check(state.day == 2, "End Day did not increment exactly once")
	state.day = 31
	manager.end_day()
	_check(state.day == 32, "Day 31 did not become Day 32")
	manager.end_day()
	_check(state.day == 32, "Day 32 advanced to Day 33")


func _new_context() -> Dictionary:
	var state := GameState.new()
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	state.materials = 20
	for index in range(4):
		var builder := UnitState.new("builder_%d" % index)
		builder.rank = GameEnums.Rank.ROOK
		builder.board_cell = Vector2i(index, 0)
		state.units[builder.id] = builder
	return {"state": state, "manager": manager}


func _add_unit(state: GameState, unit_id: String, cell: Vector2i) -> UnitState:
	var unit := UnitState.new(unit_id)
	unit.board_cell = cell
	state.units[unit_id] = unit
	return unit


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
