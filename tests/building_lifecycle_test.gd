extends SceneTree


func _init() -> void:
	_test_build_durations()
	_test_costs_and_validation()
	_test_lock_progress_unlock_and_planning()
	print("BUILDING_LIFECYCLE_TEST_OK")
	quit(0)


func _test_build_durations() -> void:
	var farm_one := _build_once(GameEnums.BuildingType.FARM, ["builder_0"])
	_check(farm_one.days_left == 2, "Farm with one builder did not start at 2 days")
	var farm_two := _build_once(GameEnums.BuildingType.FARM, ["builder_0", "builder_1"])
	_check(farm_two.days_left == 1, "Farm with two builders did not start at 1 day")
	var barracks_one := _build_once(GameEnums.BuildingType.BARRACKS, ["builder_0"])
	_check(barracks_one.days_left == 4, "Barracks with one builder did not start at 4 days")
	var barracks_two := _build_once(
		GameEnums.BuildingType.BARRACKS, ["builder_0", "builder_1", "builder_2"]
	)
	_check(barracks_two.days_left == 3, "Barracks with 2+ builders did not start at 3 days")
	var barracks_three := _build_once(
		GameEnums.BuildingType.BARRACKS, ["builder_0", "builder_1", "builder_2", "builder_3"]
	)
	_check(barracks_three.days_left == 3, "3+ builders reduced duration more than once")


func _test_costs_and_validation() -> void:
	var workshop_context := _new_context(0)
	var workshop_manager: TurnManager = workshop_context.manager
	workshop_manager.queue_building(
		GameEnums.BuildingType.MATERIAL_WORKSHOP, Vector2i(3, 3), ["builder_0"]
	)
	var workshop_result := workshop_manager.end_day()
	_check(workshop_result.building_committed, "Workshop with zero cost was rejected")
	_check(workshop_context.state.materials == 0, "Workshop consumed materials")

	for type in [
		GameEnums.BuildingType.FARM,
		GameEnums.BuildingType.PRISON,
		GameEnums.BuildingType.INFIRMARY,
		GameEnums.BuildingType.BARRACKS,
	]:
		var cost_context := _new_context(1)
		var cost_manager: TurnManager = cost_context.manager
		cost_manager.queue_building(type, Vector2i(3, 3), ["builder_0"])
		var cost_result := cost_manager.end_day()
		_check(cost_result.building_committed, "Costed building was not committed")
		_check(cost_context.state.materials == 0, "Costed building did not consume one material")

	var missing_context := _new_context(0)
	var missing_manager: TurnManager = missing_context.manager
	missing_manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	var missing_result := missing_manager.end_day()
	_check(not missing_result.building_committed, "Missing materials committed a building")
	_check(missing_context.state.buildings.is_empty(), "Missing materials changed building state")
	_check(not (missing_context.state.units["builder_0"] as UnitState).locked_by_construction, "Rejected build locked builder")

	var king_context := _new_context(1)
	var king := UnitState.new("king")
	king.rank = GameEnums.Rank.KING
	king.board_cell = Vector2i(7, 7)
	king_context.state.units[king.id] = king
	var king_manager: TurnManager = king_context.manager
	king_manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["king"])
	var king_result := king_manager.end_day()
	_check(not king_result.building_committed, "King was accepted as builder")
	_check(king_result.was_rejected("building", "building_1"), "King builder rejection missing")


func _test_lock_progress_unlock_and_planning() -> void:
	var context := _new_context(1)
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var builder := state.units["builder_0"] as UnitState
	var planned := manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	_check(state.buildings.is_empty(), "Planned building changed authoritative state")
	_check(not builder.locked_by_construction, "Planned building locked builder early")
	_check(planned.builder_unit_ids.size() == 1, "Planned builder was not retained")

	manager.end_day()
	var farm := state.buildings["building_1"] as BuildingState
	_check(farm.phase == GameEnums.BuildingPhase.BUILDING, "Committed building did not enter BUILDING")
	_check(farm.days_left == 2, "New construction advanced on its start day")
	_check(builder.locked_by_construction, "Builder was not locked after commit")

	manager.queue_move("builder_0", Vector2i(0, 2))
	var move_result := manager.end_day()
	_check(builder.board_cell == Vector2i(0, 0), "Construction-locked builder moved")
	_check(move_result.was_rejected("move", "builder_0"), "Locked builder move was not rejected")
	_check(farm.days_left == 1, "Construction did not decrease by exactly one day")

	manager.queue_building(GameEnums.BuildingType.PRISON, Vector2i(6, 3), ["builder_0"])
	var second_build_result := manager.end_day()
	_check(not second_build_result.building_committed, "Locked builder assigned to another building")
	_check(farm.phase == GameEnums.BuildingPhase.ACTIVE, "Construction did not become ACTIVE at zero")
	_check(farm.days_left == 0, "Completed construction kept days_left")
	_check(not builder.locked_by_construction, "Completed construction did not unlock builder")
	_check(builder.assigned_building_id.is_empty(), "Completed construction kept builder assignment")


func _build_once(type: GameEnums.BuildingType, builders: Array[String]) -> BuildingState:
	var context := _new_context(1)
	var manager: TurnManager = context.manager
	manager.queue_building(type, Vector2i(3, 3), builders)
	var result := manager.end_day()
	_check(result.building_committed, "Duration test building did not commit")
	return context.state.buildings.values()[0] as BuildingState


func _new_context(materials: int) -> Dictionary:
	var state := GameState.new()
	state.materials = materials
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	for index in range(4):
		var builder := UnitState.new("builder_%d" % index)
		builder.rank = GameEnums.Rank.ROOK
		builder.board_cell = Vector2i(index, 0)
		state.units[builder.id] = builder
	return {"state": state, "manager": manager}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
