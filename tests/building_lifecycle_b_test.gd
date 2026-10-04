extends SceneTree

func _init() -> void:
	_test_cancel_and_refund()
	_test_loss_pause_reset_and_reassign()
	_test_cancel_validation_and_same_turn_priority()
	print("BUILDING_LIFECYCLE_B_TEST_OK")
	quit(0)

func _test_cancel_and_refund() -> void:
	var context := _new_context(1)
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	manager.end_day()
	var builder := state.units["builder_0"] as UnitState
	manager.queue_cancel_construction("building_1")
	_check(state.buildings.has("building_1"), "Cancel changed state before End Day")
	_check(builder.locked_by_construction, "Cancel unlocked builder before End Day")
	var result := manager.end_day()
	_check(not state.buildings.has("building_1"), "Cancel did not remove construction")
	_check(not builder.locked_by_construction, "Cancel did not unlock builder")
	_check(builder.assigned_building_id.is_empty(), "Cancel left assigned_building_id")
	_check(result.refunded_materials == 0 and state.materials == 0, "Farm refund was not floor(1 * 0.5)")

	var workshop := _new_context(0)
	var workshop_manager: TurnManager = workshop.manager
	workshop_manager.queue_building(GameEnums.BuildingType.MATERIAL_WORKSHOP, Vector2i(3, 3), ["builder_0"])
	workshop_manager.end_day()
	var workshop_result := workshop_manager.end_day()
	_check(workshop_result.refunded_materials == 0, "Workshop refund was not zero")

func _test_loss_pause_reset_and_reassign() -> void:
	var context := _new_context(1)
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	manager.end_day()
	var farm := state.buildings["building_1"] as BuildingState
	manager.end_day()
	_check(farm.days_left == 1, "Farm did not progress before builder loss")
	_check(manager.building_system.remove_builder_from_construction(state, farm.id, "builder_0"), "Builder removal API failed")
	_check(farm.days_left == 2, "Single builder loss did not reset Farm to 2")
	manager.end_day()
	_check(farm.days_left == 2, "Construction without builder did not pause")
	manager.queue_assign_builder(farm.id, "builder_1")
	manager.end_day()
	_check(farm.builder_unit_ids.has("builder_1"), "Reassign did not attach builder")
	_check((state.units["builder_1"] as UnitState).locked_by_construction, "Reassigned builder was not locked")
	_check(farm.days_left == 1, "Reassigned construction did not continue")

	var barracks_context := _new_context(1)
	var barracks_manager: TurnManager = barracks_context.manager
	barracks_manager.queue_building(GameEnums.BuildingType.BARRACKS, Vector2i(6, 3), ["builder_0", "builder_1"])
	barracks_manager.end_day()
	barracks_manager.end_day()
	var barracks := barracks_context.state.buildings["building_1"] as BuildingState
	_check(barracks.days_left == 2, "Barracks did not reach expected progress")
	_check(barracks_manager.building_system.remove_builder_from_construction(barracks_context.state, barracks.id, "builder_0"), "Multi-builder removal failed")
	_check(barracks.days_left == 2, "Removing one of 2 builders reset progress")
	barracks_manager.end_day()
	_check(barracks.days_left == 1, "Remaining builder did not continue construction")

func _test_cancel_validation_and_same_turn_priority() -> void:
	var context := _new_context(1)
	var manager: TurnManager = context.manager
	manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	manager.end_day()
	manager.end_day()
	manager.end_day()
	manager.queue_cancel_construction("building_1")
	var active_result := manager.end_day()
	_check(active_result.was_rejected("cancel_construction", "building_1"), "ACTIVE cancel was accepted")
	_check(context.state.buildings.has("building_1"), "ACTIVE building was removed")
	manager.queue_cancel_construction("missing")
	var invalid_result := manager.end_day()
	_check(invalid_result.was_rejected("cancel_construction", "missing"), "Invalid cancel id crashed or was accepted")

	var same_turn := _new_context(1)
	var same_manager: TurnManager = same_turn.manager
	same_manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	same_manager.end_day()
	same_manager.end_day()
	same_manager.queue_cancel_construction("building_1")
	var cancel_result := same_manager.end_day()
	_check(cancel_result.cancelled_building_ids.has("building_1"), "Same-turn cancel did not commit")
	_check(cancel_result.completed_building_ids.is_empty(), "Cancelled construction completed in same turn")
	_check(not same_turn.state.buildings.has("building_1"), "Same-turn cancel kept building")

	var lock_context := _new_context(2)
	var lock_manager: TurnManager = lock_context.manager
	lock_manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(3, 3), ["builder_0"])
	lock_manager.end_day()
	lock_manager.queue_assign_builder("building_1", "builder_0")
	var locked_result := lock_manager.end_day()
	_check(locked_result.was_rejected("assign_builder", "builder_0"), "Locked builder was reassigned")
	var king := UnitState.new("king")
	king.rank = GameEnums.Rank.KING
	lock_context.state.units[king.id] = king
	lock_manager.queue_assign_builder("building_1", "king")
	var king_result := lock_manager.end_day()
	_check(king_result.was_rejected("assign_builder", "king"), "King was reassigned")

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
