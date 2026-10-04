extends SceneTree


func _init() -> void:
	_test_planned_build_and_builder_drop()
	_test_cancel_planned_building()
	_test_staff_slot_move_and_unassign()
	_test_exact_building_target()
	print("BOARD_FIRST_FLOW_TEST_OK")
	quit(0)


func _test_planned_build_and_builder_drop() -> void:
	var context := _context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var builder := _unit(state, "rook", GameEnums.Rank.ROOK, Vector2i(0, 0))
	var blueprint := manager.queue_building_plan(GameEnums.BuildingType.FARM, Vector2i(3, 3))
	manager.plan_job_slot(blueprint.id, Vector2i(2, 2), GameEnums.JobRole.BUILDER)
	manager.queue_move(builder.id, Vector2i(2, 2))
	_check(manager.plan_job_drop(builder.id, Vector2i(2, 2)), "Drop did not assign planned builder")
	_check(state.buildings.is_empty(), "Planning mutated authoritative buildings")
	var result := manager.end_day()
	_check(result.building_committed, "Board-first building did not commit")
	var farm := state.buildings.get(blueprint.id) as BuildingState
	_check(farm != null and farm.phase == GameEnums.BuildingPhase.BUILDING, "Construction did not start")
	_check(builder.locked_by_construction, "Dropped builder was not locked")


func _test_staff_slot_move_and_unassign() -> void:
	var context := _context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var farm := BuildingState.new("farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[farm.id] = farm
	var worker := _unit(state, "pawn", GameEnums.Rank.PAWN, Vector2i(0, 0))
	manager.plan_job_slot(farm.id, Vector2i(2, 2), GameEnums.JobRole.FARM_WORKER)
	manager.queue_move(worker.id, Vector2i(2, 2))
	_check(manager.plan_job_drop(worker.id, Vector2i(2, 2)), "Drop did not queue Farm worker")
	manager.end_day()
	_check(worker.work_building_id == farm.id, "Staff assignment did not commit")
	manager.queue_move(worker.id, Vector2i(7, 7))
	manager.plan_job_drop(worker.id, Vector2i(7, 7))
	manager.end_day()
	_check(worker.work_building_id.is_empty(), "Moving out did not clear job")


func _test_cancel_planned_building() -> void:
	var context := _context()
	var farm := context.manager.queue_building_plan(GameEnums.BuildingType.FARM, Vector2i(3, 3))
	context.manager.cancel_building(farm.id)
	context.manager.end_day()
	_check(context.state.buildings.is_empty(), "Cancelled contextual Farm committed")


func _test_exact_building_target() -> void:
	var context := _context()
	var farm_a := BuildingState.new("farm_a", GameEnums.BuildingType.FARM, Vector2i(1, 1))
	var farm_b := BuildingState.new("farm_b", GameEnums.BuildingType.FARM, Vector2i(5, 5))
	farm_a.phase = GameEnums.BuildingPhase.ACTIVE
	farm_b.phase = GameEnums.BuildingPhase.ACTIVE
	farm_a.job_slots[Vector2i(0, 0)] = GameEnums.JobRole.FARM_WORKER
	farm_b.job_slots[Vector2i(4, 4)] = GameEnums.JobRole.FARM_WORKER
	context.state.buildings[farm_a.id] = farm_a
	context.state.buildings[farm_b.id] = farm_b
	context.manager.plan_clear_job_slot(farm_b.id, Vector2i(4, 4))
	context.manager.end_day()
	_check(farm_a.job_slots.has(Vector2i(0, 0)), "Action on building B changed building A")
	_check(not farm_b.job_slots.has(Vector2i(4, 4)), "Action did not target building B")


func _context() -> Dictionary:
	var state := GameState.new()
	state.food = 100
	state.materials = 5
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return {"state": state, "manager": manager}


func _unit(state: GameState, id: String, rank: int, cell: Vector2i) -> UnitState:
	var unit := UnitState.new(id)
	unit.rank = rank
	unit.board_cell = cell
	state.units[id] = unit
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
