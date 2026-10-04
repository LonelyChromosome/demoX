extends SceneTree


func _init() -> void:
	_test_farm_staffing()
	_test_workshop_manager_output()
	_test_building_and_completion_timing()
	_test_demolition_produces_before_removal()
	_test_one_production_per_end_day()
	print("RESOURCE_PRODUCTION_TEST_OK")
	quit(0)


func _test_farm_staffing() -> void:
	var cases := [
		[[], 2],
		[["u0"], 4],
		[["u0", "u1", "u2"], 8],
		[["u0", "u1", "u2", "u3", "u4", "u5"], 14],
		[["u0", "u1", "u2", "u3", "u4", "u5", "u6", "u7"], 14],
	]
	for entry in cases:
		var context := _new_context()
		var state: GameState = context.state
		var manager: TurnManager = context.manager
		var farm := _add_building(state, "farm", GameEnums.BuildingType.FARM, GameEnums.BuildingPhase.ACTIVE)
		var ids: Array = entry[0]
		for unit_id in ids:
			_add_unit(state, unit_id, GameEnums.Rank.PAWN)
		if not ids.is_empty():
			farm.manager_unit_id = ids[0]
			farm.worker_unit_ids.assign(ids)
		var before := state.food
		var result := manager.end_day()
		_check(state.food - before == entry[1], "Farm staff output mismatch")
		_check(result.food_produced == entry[1], "Farm result output mismatch")

	var duplicate_context := _new_context()
	var duplicate_farm := _add_building(
		duplicate_context.state, "farm", GameEnums.BuildingType.FARM, GameEnums.BuildingPhase.ACTIVE
	)
	_add_unit(duplicate_context.state, "manager", GameEnums.Rank.QUEEN)
	duplicate_farm.manager_unit_id = "manager"
	duplicate_farm.worker_unit_ids = ["manager", "manager"]
	_check(duplicate_context.manager.end_day().food_produced == 4, "Farm manager was double-counted")

	var invalid_context := _new_context()
	var invalid_farm := _add_building(
		invalid_context.state, "farm", GameEnums.BuildingType.FARM, GameEnums.BuildingPhase.ACTIVE
	)
	var enemy := _add_unit(invalid_context.state, "enemy", GameEnums.Rank.PAWN)
	enemy.faction = GameEnums.Faction.ENEMY
	invalid_farm.manager_unit_id = "missing"
	invalid_farm.worker_unit_ids = ["enemy", "missing"]
	_check(invalid_context.manager.end_day().food_produced == 2, "Invalid Farm staff was counted")


func _test_workshop_manager_output() -> void:
	var ranks := [
		[GameEnums.Rank.PAWN, 1],
		[GameEnums.Rank.KNIGHT, 2],
		[GameEnums.Rank.ROOK, 2],
		[GameEnums.Rank.BISHOP, 2],
		[GameEnums.Rank.QUEEN, 3],
		[GameEnums.Rank.KING, 0],
	]
	for entry in ranks:
		var context := _new_context()
		var workshop := _add_building(
			context.state,
			"workshop",
			GameEnums.BuildingType.MATERIAL_WORKSHOP,
			GameEnums.BuildingPhase.ACTIVE
		)
		var manager := _add_unit(context.state, "manager", entry[0])
		workshop.manager_unit_id = manager.id
		workshop.worker_unit_ids = ["worker_should_not_count"]
		var result := context.manager.end_day()
		_check(result.materials_produced == entry[1], "Workshop manager output mismatch")
	_check(
		_new_context().manager.building_system.material_cost(GameEnums.BuildingType.MATERIAL_WORKSHOP) == 0,
		"Workshop material cost changed"
	)

	var no_manager := _new_context()
	_add_building(
		no_manager.state,
		"workshop",
		GameEnums.BuildingType.MATERIAL_WORKSHOP,
		GameEnums.BuildingPhase.ACTIVE
	)
	_check(no_manager.manager.end_day().materials_produced == 0, "Workshop without manager produced material")


func _test_building_and_completion_timing() -> void:
	var building_context := _new_context()
	_add_building(
		building_context.state, "farm", GameEnums.BuildingType.FARM, GameEnums.BuildingPhase.BUILDING
	)
	_add_building(
		building_context.state,
		"workshop",
		GameEnums.BuildingType.MATERIAL_WORKSHOP,
		GameEnums.BuildingPhase.BUILDING
	)
	var no_output := building_context.manager.end_day()
	_check(no_output.food_produced == 0, "BUILDING Farm produced food")
	_check(no_output.materials_produced == 0, "BUILDING Workshop produced materials")

	var farm_context := _new_context()
	var farm := _add_building(
		farm_context.state, "farm", GameEnums.BuildingType.FARM, GameEnums.BuildingPhase.BUILDING
	)
	farm.days_left = 1
	var builder := _add_unit(farm_context.state, "builder", GameEnums.Rank.ROOK)
	farm.builder_unit_ids = [builder.id]
	builder.locked_by_construction = true
	var farm_result := farm_context.manager.end_day()
	_check(farm.phase == GameEnums.BuildingPhase.ACTIVE, "Farm did not complete in resolution")
	_check(farm_result.food_produced == 2, "Newly completed Farm did not produce immediately")

	var workshop_context := _new_context()
	var workshop := _add_building(
		workshop_context.state,
		"workshop", GameEnums.BuildingType.MATERIAL_WORKSHOP, GameEnums.BuildingPhase.BUILDING
	)
	workshop.days_left = 1
	var workshop_manager := _add_unit(workshop_context.state, "manager", GameEnums.Rank.PAWN)
	workshop.manager_unit_id = workshop_manager.id
	workshop.builder_unit_ids = [workshop_manager.id]
	workshop_manager.locked_by_construction = true
	var workshop_result := workshop_context.manager.end_day()
	_check(workshop.phase == GameEnums.BuildingPhase.ACTIVE, "Newly completed Workshop did not activate")
	_check(workshop_result.materials_produced == 1, "Newly completed Workshop did not produce immediately")


func _test_demolition_produces_before_removal() -> void:
	var farm_context := _new_context()
	var farm := _add_building(
		farm_context.state, "farm", GameEnums.BuildingType.FARM, GameEnums.BuildingPhase.ACTIVE
	)
	farm_context.manager.queue_demolition(farm.id)
	var farm_result := farm_context.manager.end_day()
	_check(farm_result.food_produced == 2, "DEMOLISHING Farm did not produce before removal")
	_check(not farm_context.state.buildings.has(farm.id), "Farm demolition did not finalize")

	var workshop_context := _new_context()
	var workshop := _add_building(
		workshop_context.state,
		"workshop", GameEnums.BuildingType.MATERIAL_WORKSHOP, GameEnums.BuildingPhase.ACTIVE
	)
	var manager := _add_unit(workshop_context.state, "manager", GameEnums.Rank.ROOK)
	workshop.manager_unit_id = manager.id
	workshop_context.manager.queue_demolition(workshop.id)
	var workshop_result := workshop_context.manager.end_day()
	_check(workshop_result.materials_produced == 2, "DEMOLISHING Workshop did not produce before removal")
	_check(not workshop_context.state.buildings.has(workshop.id), "Workshop demolition did not finalize")


func _test_one_production_per_end_day() -> void:
	var context := _new_context()
	_add_building(context.state, "farm", GameEnums.BuildingType.FARM, GameEnums.BuildingPhase.ACTIVE)
	_check(context.manager.end_day().food_produced == 2, "First End Day output mismatch")
	_check(context.manager.end_day().food_produced == 2, "Production ran more than once per End Day")
	_check(context.state.food == 4, "Farm production total mismatch")


func _new_context() -> Dictionary:
	var state := GameState.new()
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return {"state": state, "manager": manager}


func _add_unit(state: GameState, unit_id: String, rank: GameEnums.Rank) -> UnitState:
	var unit := UnitState.new(unit_id)
	unit.rank = rank
	state.units[unit_id] = unit
	return unit


func _add_building(
	state: GameState, building_id: String, type: GameEnums.BuildingType, phase: GameEnums.BuildingPhase
) -> BuildingState:
	var building := BuildingState.new(building_id, type, Vector2i(3, 3))
	building.phase = phase
	state.buildings[building_id] = building
	return building


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
