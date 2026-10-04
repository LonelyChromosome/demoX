extends SceneTree


func _init() -> void:
	_test_empty_farm()
	_test_position_roles_and_unassign()
	_test_capacity_and_manager_replacement()
	_test_rank_independence_and_two_farms()
	print("FARM_POSITION_ROLE_TEST_OK")
	quit(0)


func _test_empty_farm() -> void:
	var context := _context()
	_add_farm(context.state, "farm", Vector2i(3, 3))
	_check(context.manager.end_day().food_produced == 2, "Empty ACTIVE Farm did not produce 2")


func _test_position_roles_and_unassign() -> void:
	var context := _context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var farm := _add_farm(state, "farm", Vector2i(3, 3))
	var pawn := _unit(state, "pawn", GameEnums.Rank.PAWN, Vector2i(0, 0))
	var knight := _unit(state, "knight", GameEnums.Rank.KNIGHT, Vector2i(0, 1))
	var rook := _unit(state, "rook", GameEnums.Rank.ROOK, Vector2i(0, 2))
	manager.queue_move(pawn.id, farm.core_cell)
	var manager_result := manager.end_day()
	_check(farm.manager_unit_id == pawn.id and pawn.is_manager, "Core position did not become Farm manager")
	_check(manager_result.food_produced == 4, "Manager did not affect same-day Farm output")
	manager.queue_move(knight.id, Vector2i(2, 2))
	var first_worker := manager.end_day()
	_check(knight.id in farm.worker_unit_ids, "Operational position did not become Farm worker")
	_check(first_worker.food_produced == 6, "Manager + worker output was not 6")
	manager.queue_move(rook.id, Vector2i(3, 2))
	_check(manager.end_day().food_produced == 8, "Three Farm staff did not produce 8")
	manager.queue_move(pawn.id, Vector2i(7, 7))
	var manager_left := manager.end_day()
	_check(farm.manager_unit_id.is_empty() and pawn.work_building_id.is_empty(), "Leaving core left stale manager state")
	_check(manager_left.food_produced == 6, "Manager removal did not reduce output")
	manager.queue_move(knight.id, Vector2i(7, 6))
	manager.end_day()
	_check(knight.id not in farm.worker_unit_ids and knight.work_building_id.is_empty(), "Leaving area left stale worker state")


func _test_capacity_and_manager_replacement() -> void:
	var context := _context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var farm := _add_farm(state, "farm", Vector2i(3, 3))
	var occupied := [
		Vector2i(3, 3), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(4, 2), Vector2i(2, 3), Vector2i(4, 3),
	]
	for index in range(occupied.size()):
		_unit(state, "staff_%d" % index, GameEnums.Rank.PAWN, occupied[index])
	var entrant := _unit(state, "entrant", GameEnums.Rank.ROOK, Vector2i(7, 7))
	manager.queue_move(entrant.id, Vector2i(2, 4))
	var full_result := manager.end_day()
	_check(full_result.was_rejected("move", entrant.id), "Seventh Farm person was not rejected")
	_check(full_result.food_produced == 14, "Six-person Farm did not clamp at 14")
	var replacement := _unit(state, "replacement", GameEnums.Rank.KNIGHT, Vector2i(7, 6))
	manager.queue_move(replacement.id, farm.core_cell)
	var replacement_result := manager.end_day()
	_check(replacement_result.was_rejected("move", replacement.id), "Occupied manager core silently replaced manager")
	manager.queue_move("staff_0", Vector2i(7, 5))
	manager.queue_move(replacement.id, farm.core_cell)
	var explicit_replacement := manager.end_day()
	_check(not explicit_replacement.was_rejected("move", replacement.id), "Manager could not be replaced after planning the old manager's exit")
	_check(farm.manager_unit_id == replacement.id, "Core position did not assign the replacement manager")


func _test_rank_independence_and_two_farms() -> void:
	var context := _context()
	var state: GameState = context.state
	var first := _add_farm(state, "farm_a", Vector2i(1, 1))
	var second := _add_farm(state, "farm_b", Vector2i(6, 6))
	_unit(state, "bishop", GameEnums.Rank.BISHOP, first.core_cell)
	_unit(state, "queen", GameEnums.Rank.QUEEN, Vector2i(5, 5))
	var result := context.manager.end_day()
	_check(result.food_produced == 8, "Two Farms did not calculate independently by person count")
	_check(first.manager_unit_id == "bishop", "Bishop was not accepted as Farm manager")
	_check(second.worker_unit_ids == ["queen"], "Queen did not count as one Farm worker")


func _context() -> Dictionary:
	var state := GameState.new()
	state.food = 100
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return {"state": state, "manager": manager}


func _add_farm(state: GameState, id: String, core: Vector2i) -> BuildingState:
	var farm := BuildingState.new(id, GameEnums.BuildingType.FARM, core)
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[id] = farm
	return farm


func _unit(state: GameState, id: String, rank: int, cell: Vector2i) -> UnitState:
	var unit := UnitState.new(id)
	unit.display_name = id
	unit.rank = rank
	unit.board_cell = cell
	state.units[id] = unit
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
