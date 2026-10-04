extends SceneTree


func _init() -> void:
	_test_planned_and_cancel()
	_test_operational_validation()
	_test_limits_and_workshop()
	_test_reassign_and_movement_timing()
	_test_demolition_and_construction_cleanup()
	print("RESOURCE_STAFFING_TEST_OK")
	quit(0)


func _test_planned_and_cancel() -> void:
	var context := _new_context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var farm := _add_building(state, "farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
	var worker := _add_unit(state, "worker", GameEnums.Rank.PAWN, Vector2i(2, 2))
	var boss := _add_unit(state, "boss", GameEnums.Rank.ROOK, Vector2i(4, 3))
	manager.queue_staffing(farm.id, boss.id, [worker.id])
	_check(farm.manager_unit_id.is_empty(), "Planned manager changed authoritative state")
	_check(farm.worker_unit_ids.is_empty(), "Planned worker changed authoritative state")
	_check(worker.work_building_id.is_empty(), "Planned staffing changed unit state")
	manager.cancel_staffing(farm.id)
	manager.end_day()
	_check(farm.manager_unit_id.is_empty(), "Cancelled staffing committed manager")
	_check(farm.worker_unit_ids.is_empty(), "Cancelled staffing committed worker")

	manager.queue_staffing(farm.id, boss.id, [worker.id])
	manager.queue_staffing(farm.id, worker.id, [])
	var first_result := manager.end_day()
	_check(first_result.food_produced == 2, "New staffing affected current-day production")
	_check(farm.manager_unit_id == worker.id, "Last staffing order was not committed")
	_check(farm.worker_unit_ids.is_empty(), "Replaced staffing order kept old workers")
	_check(worker.work_building_id == farm.id and boss.work_building_id.is_empty(), "work_building_id missing")
	_check(manager.end_day().food_produced == 4, "Staffing did not affect following day production")


func _test_operational_validation() -> void:
	var cases := [
		["outside", Vector2i(1, 1), GameEnums.Faction.PLAYER, GameEnums.Rank.PAWN, false],
		["core", Vector2i(3, 3), GameEnums.Faction.PLAYER, GameEnums.Rank.PAWN, false],
		["enemy", Vector2i(2, 2), GameEnums.Faction.ENEMY, GameEnums.Rank.PAWN, false],
		["king", Vector2i(2, 2), GameEnums.Faction.PLAYER, GameEnums.Rank.KING, false],
		["locked", Vector2i(2, 2), GameEnums.Faction.PLAYER, GameEnums.Rank.PAWN, false],
	]
	for entry in cases:
		var context := _new_context()
		var farm := _add_building(context.state, "farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
		var unit := _add_unit(context.state, entry[0], entry[3], entry[1])
		unit.faction = entry[2]
		if entry[0] == "locked":
			unit.locked_by_construction = true
		context.manager.queue_staffing(farm.id, unit.id, [])
		var result := context.manager.end_day()
		_check(result.was_rejected("staffing", farm.id), "Invalid operational staffing was accepted")

	var worker_context := _new_context()
	var farm := _add_building(worker_context.state, "farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
	var worker := _add_unit(worker_context.state, "worker", GameEnums.Rank.PAWN, Vector2i(2, 2))
	worker_context.manager.queue_staffing(farm.id, "", [worker.id])
	_check(not worker_context.manager.end_day().was_rejected("staffing", farm.id), "Valid worker was rejected")

	var invalid_worker_context := _new_context()
	var invalid_worker_farm := _add_building(
		invalid_worker_context.state, "farm", GameEnums.BuildingType.FARM, Vector2i(3, 3)
	)
	var invalid_worker := _add_unit(
		invalid_worker_context.state, "worker", GameEnums.Rank.PAWN, Vector2i(1, 1)
	)
	invalid_worker_context.manager.queue_staffing(invalid_worker_farm.id, "", [invalid_worker.id])
	_check(
		invalid_worker_context.manager.end_day().was_rejected("staffing", invalid_worker_farm.id),
		"Worker outside operational squares was accepted"
	)


func _test_limits_and_workshop() -> void:
	var context := _new_context()
	var farm := _add_building(context.state, "farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
	var manager := _add_unit(context.state, "manager", GameEnums.Rank.QUEEN, Vector2i(2, 2))
	var workers: Array[String] = []
	var worker_cells := [Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(4, 3), Vector2i(2, 4), Vector2i(3, 4)]
	for index in range(6):
		var worker := _add_unit(context.state, "worker_%d" % index, GameEnums.Rank.PAWN, worker_cells[index])
		workers.append(worker.id)
	context.manager.queue_staffing(farm.id, manager.id, workers)
	_check(context.manager.end_day().was_rejected("staffing", farm.id), "Farm accepted more than six staff")

	var duplicate_context := _new_context()
	var duplicate_farm := _add_building(
		duplicate_context.state, "farm", GameEnums.BuildingType.FARM, Vector2i(3, 3)
	)
	var duplicate_manager := _add_unit(duplicate_context.state, "manager", GameEnums.Rank.ROOK, Vector2i(2, 2))
	duplicate_context.manager.queue_staffing(duplicate_farm.id, duplicate_manager.id, [duplicate_manager.id])
	duplicate_context.manager.end_day()
	_check(duplicate_farm.worker_unit_ids.is_empty(), "Farm manager was double-counted as worker")

	var workshop_context := _new_context()
	var workshop := _add_building(
		workshop_context.state, "workshop", GameEnums.BuildingType.MATERIAL_WORKSHOP, Vector2i(3, 3)
	)
	var workshop_manager := _add_unit(workshop_context.state, "manager", GameEnums.Rank.QUEEN, Vector2i(2, 2))
	var ignored_worker := _add_unit(workshop_context.state, "worker", GameEnums.Rank.PAWN, Vector2i(4, 3))
	workshop_context.manager.queue_staffing(workshop.id, workshop_manager.id, [ignored_worker.id])
	workshop_context.manager.end_day()
	_check(workshop.worker_unit_ids.is_empty(), "Workshop retained worker staffing")
	_check(workshop_context.manager.end_day().materials_produced == 3, "Workshop manager output changed")


func _test_reassign_and_movement_timing() -> void:
	var context := _new_context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var farm_a := _add_building(state, "farm_a", GameEnums.BuildingType.FARM, Vector2i(1, 1))
	var farm_b := _add_building(state, "farm_b", GameEnums.BuildingType.FARM, Vector2i(5, 5))
	var unit := _add_unit(state, "unit", GameEnums.Rank.ROOK, Vector2i(4, 4))
	farm_a.manager_unit_id = unit.id
	unit.work_building_id = farm_a.id
	manager.queue_staffing(farm_b.id, unit.id, [])
	var result := manager.end_day()
	_check(result.food_produced == 4, "Reassignment changed current-day Farm production")
	_check(farm_a.manager_unit_id.is_empty(), "Old Farm kept reassigned manager")
	_check(farm_b.manager_unit_id == unit.id, "New Farm did not receive manager")
	_check(unit.work_building_id == farm_b.id, "Reassignment did not update work_building_id")

	var move_context := _new_context()
	var move_farm := _add_building(
		move_context.state, "farm", GameEnums.BuildingType.FARM, Vector2i(3, 3)
	)
	var moving := _add_unit(move_context.state, "moving", GameEnums.Rank.PAWN, Vector2i(0, 0))
	move_context.manager.queue_move(moving.id, Vector2i(2, 2))
	move_context.manager.queue_staffing(move_farm.id, moving.id, [])
	var move_result := move_context.manager.end_day()
	_check(moving.board_cell == Vector2i(2, 2), "Movement did not commit before staffing")
	_check(move_result.food_produced == 2, "Move + staffing used new staff too early")
	_check(move_context.manager.end_day().food_produced == 4, "Move + staffing did not apply next day")

	var conflict_context := _new_context()
	var first := _add_building(conflict_context.state, "a", GameEnums.BuildingType.FARM, Vector2i(2, 2))
	var second := _add_building(conflict_context.state, "b", GameEnums.BuildingType.FARM, Vector2i(4, 2))
	var shared := _add_unit(conflict_context.state, "shared", GameEnums.Rank.ROOK, Vector2i(3, 1))
	conflict_context.manager.queue_staffing(first.id, shared.id, [])
	conflict_context.manager.queue_staffing(second.id, shared.id, [])
	var conflict_result := conflict_context.manager.end_day()
	_check(conflict_result.was_rejected("staffing", second.id), "One unit staffed two buildings")


func _test_demolition_and_construction_cleanup() -> void:
	var demolition_context := _new_context()
	var farm := _add_building(
		demolition_context.state, "farm", GameEnums.BuildingType.FARM, Vector2i(3, 3)
	)
	var worker := _add_unit(demolition_context.state, "worker", GameEnums.Rank.ROOK, Vector2i(2, 2))
	farm.manager_unit_id = worker.id
	worker.work_building_id = farm.id
	demolition_context.manager.queue_demolition(farm.id)
	demolition_context.manager.queue_staffing(farm.id, "", [])
	var demolition_result := demolition_context.manager.end_day()
	_check(demolition_result.food_produced == 4, "Demolished Farm did not use old staffing")
	_check(not demolition_context.state.buildings.has(farm.id), "Demolished Farm remained")
	_check(worker.work_building_id.is_empty(), "Demolition left dangling work_building_id")
	_check(demolition_result.was_rejected("staffing", farm.id), "Staffing removed building was committed")

	var construction_context := _new_context()
	construction_context.state.materials = 1
	var builder := _add_unit(construction_context.state, "builder", GameEnums.Rank.ROOK, Vector2i(0, 0))
	construction_context.manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), [builder.id])
	construction_context.manager.end_day()
	construction_context.manager.end_day()
	var completion_result := construction_context.manager.end_day()
	_check(completion_result.food_produced == 2, "Construction builder became production worker")


func _new_context() -> Dictionary:
	var state := GameState.new()
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return {"state": state, "manager": manager}


func _add_unit(
	state: GameState, unit_id: String, rank: GameEnums.Rank, cell: Vector2i
) -> UnitState:
	var unit := UnitState.new(unit_id)
	unit.rank = rank
	unit.board_cell = cell
	state.units[unit_id] = unit
	return unit


func _add_building(
	state: GameState, building_id: String, type: GameEnums.BuildingType, cell: Vector2i
) -> BuildingState:
	var building := BuildingState.new(building_id, type, cell)
	building.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[building_id] = building
	return building


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
