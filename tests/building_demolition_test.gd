extends SceneTree

func _init() -> void:
	_test_active_demolition_lifecycle()
	_test_validation_and_queue_cancel()
	print("BUILDING_DEMOLITION_TEST_OK")
	quit(0)

func _test_active_demolition_lifecycle() -> void:
	var context := _new_context(1)
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	manager.end_day()
	manager.end_day()
	manager.end_day()
	var farm := state.buildings["building_1"] as BuildingState
	_check(farm.phase == GameEnums.BuildingPhase.ACTIVE, "Farm did not become ACTIVE")
	_check(manager.building_system.is_cell_occupied_by_building(state, Vector2i(3, 3)), "Active footprint missing")
	_check(not state.units["builder_0"].locked_by_construction, "Completed builder stayed construction-locked")
	manager.queue_demolition(farm.id)
	_check(state.buildings.has(farm.id), "Planned demolition changed state early")
	_check(farm.phase == GameEnums.BuildingPhase.ACTIVE, "Planned demolition changed phase early")
	var visible_during_systems := false
	manager.resolution_phase_started.connect(func(phase: int) -> void:
		if phase == TurnResolver.Phase.RESOLVE_SYSTEMS:
			visible_during_systems = state.buildings.has(farm.id) and farm.phase == GameEnums.BuildingPhase.DEMOLISHING
	)
	var result := manager.end_day()
	_check(visible_during_systems, "Demolishing building was removed before RESOLVE_SYSTEMS")
	_check(result.demolishing_building_ids.has(farm.id), "ACTIVE building did not enter DEMOLISHING")
	_check(result.demolished_building_ids.has(farm.id), "Demolition did not finalize in one End Day")
	_check(not state.buildings.has(farm.id), "Demolition did not remove building")
	_check(not manager.building_system.is_cell_occupied_by_building(state, Vector2i(3, 3)), "Footprint stayed occupied")
	_check(state.materials == 0, "Demolition refunded materials")

func _test_validation_and_queue_cancel() -> void:
	var context := _new_context(1)
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	manager.end_day()
	var building := state.buildings["building_1"] as BuildingState
	manager.queue_demolition(building.id)
	var building_result := manager.end_day()
	_check(building_result.was_rejected("demolition", building.id), "BUILDING demolition was accepted")
	_check(state.buildings.has(building.id), "BUILDING was removed by demolition")
	manager.queue_demolition("missing")
	var invalid_result := manager.end_day()
	_check(invalid_result.was_rejected("demolition", "missing"), "Invalid demolition id was unsafe")

	manager.queue_demolition(building.id)
	manager.queue_demolition(building.id)
	_check(manager.get_planned_demolition() != null, "Demolition order was not queued")
	manager.cancel_demolition()
	_check(manager.get_planned_demolition() == null, "Duplicate/cancelled demolition remained queued")
	_check(building.phase == GameEnums.BuildingPhase.BUILDING, "Cancelled demolition changed state")

	var active_context := _new_context(1)
	var active_manager: TurnManager = active_context.manager
	active_manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	active_manager.end_day()
	active_manager.end_day()
	active_manager.end_day()
	var active := active_context.state.buildings["building_1"] as BuildingState
	active_manager.queue_demolition(active.id)
	var active_result := active_manager.end_day()
	_check(active_result.demolished_building_ids.has(active.id), "Active demolition did not finalize")

func _new_context(materials: int) -> Dictionary:
	var state := GameState.new()
	state.materials = materials
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	state.food = 100
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
