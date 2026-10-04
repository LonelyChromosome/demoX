extends SceneTree


func _init() -> void:
	_test_automatic_consumption()
	_test_manual_ration_and_starvation()
	_test_three_consecutive_days_and_reset()
	_test_exempt_and_away_units()
	print("FOOD_CONSUMPTION_TEST_OK")
	quit(0)


func _test_automatic_consumption() -> void:
	var context := _context(2)
	var pawn := _unit(context.state, "pawn", GameEnums.Rank.PAWN)
	var knight := _unit(context.state, "knight", GameEnums.Rank.KNIGHT)
	pawn.hunger_streak = 2
	knight.hunger_streak = 1
	var result: TurnResolutionResult = context.manager.end_day()
	_check(not result.awaiting_ration, "Enough food requested manual ration")
	_check(result.food_consumed == 2 and context.state.food == 0, "Food was not consumed once")
	_check(pawn.hunger_streak == 0 and knight.hunger_streak == 0, "Fed hunger was not reset")


func _test_manual_ration_and_starvation() -> void:
	var context := _context(1)
	var fed := _unit(context.state, "fed", GameEnums.Rank.ROOK)
	var hungry := _unit(context.state, "hungry", GameEnums.Rank.PAWN)
	fed.hunger_streak = 2
	hungry.hunger_streak = 2
	var construction := BuildingState.new("prison", GameEnums.BuildingType.PRISON, Vector2i(3, 3))
	construction.phase = GameEnums.BuildingPhase.BUILDING
	construction.days_left = 2
	construction.builder_unit_ids = [hungry.id]
	construction.manager_unit_id = hungry.id
	construction.worker_unit_ids = [hungry.id]
	construction.job_slots[hungry.board_cell] = GameEnums.JobRole.BUILDER
	context.state.buildings[construction.id] = construction
	hungry.assigned_building_id = construction.id
	hungry.locked_by_construction = true
	var paused: TurnResolutionResult = context.manager.end_day()
	_check(paused.awaiting_ration and context.state.day == 1, "Shortage did not pause End Day")
	_check(context.manager.is_resolving, "Orders unlocked while ration decision was pending")
	var result: TurnResolutionResult = context.manager.submit_ration([fed.id])
	_check(not result.awaiting_ration and context.state.day == 2, "Ration did not resume resolution")
	_check(not context.state.units.has(hungry.id), "Third unfed day did not remove unit")
	_check(result.starved_unit_ids == [hungry.id], "Starvation result missing death")
	_check(fed.hunger_streak == 0, "Manual feeding did not reset hunger")
	_check(construction.builder_unit_ids.is_empty(), "Death left construction builder reference")
	_check(construction.manager_unit_id.is_empty() and construction.worker_unit_ids.is_empty(), "Death left staffing references")
	_check(construction.job_slots.is_empty(), "Death left job slot reference")
	_check(not context.manager.has_pending_orders(), "Death resolution left pending references")


func _test_exempt_and_away_units() -> void:
	var context := _context(0)
	_unit(context.state, "king", GameEnums.Rank.KING)
	_unit(context.state, "queen", GameEnums.Rank.QUEEN)
	var away := _unit(context.state, "away", GameEnums.Rank.PAWN)
	away.away_days_left = 1
	var result: TurnResolutionResult = context.manager.end_day()
	_check(not result.awaiting_ration, "Exempt/away units requested food")
	_check(result.food_consumed == 0, "Exempt/away units consumed food")


func _test_three_consecutive_days_and_reset() -> void:
	var context := _context(0)
	var pawn := _unit(context.state, "pawn", GameEnums.Rank.PAWN)
	context.manager.end_day()
	context.manager.submit_ration([])
	_check(pawn.hunger_streak == 1, "First unfed day did not increment hunger")
	context.state.food = 1
	context.manager.end_day()
	_check(pawn.hunger_streak == 0, "Eating again did not reset hunger")
	for expected in [1, 2]:
		context.manager.end_day()
		context.manager.submit_ration([])
		_check(pawn.hunger_streak == expected, "Consecutive hunger count is wrong")
	context.manager.end_day()
	var death: TurnResolutionResult = context.manager.submit_ration([])
	_check(death.starved_unit_ids == [pawn.id], "Exactly three consecutive unfed days did not kill")


func _context(food: int) -> Dictionary:
	var state := GameState.new()
	state.food = food
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return {"state": state, "manager": manager}


func _unit(state: GameState, id: String, rank: int) -> UnitState:
	var unit := UnitState.new(id)
	unit.rank = rank
	unit.display_name = id
	state.units[id] = unit
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
