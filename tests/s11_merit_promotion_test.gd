extends SceneTree


func _init() -> void:
	_test_merit_trace_and_idempotence()
	_test_data_driven_validation()
	_test_turn_training_and_completion()
	_test_expedition_merit_hook()
	print("S11_MERIT_PROMOTION_TEST_OK")
	quit(0)


func _test_merit_trace_and_idempotence() -> void:
	var system := PromotionSystem.new()
	var unit := UnitState.new("pawn")
	unit.display_name = "Tốt A"
	var result := TurnResolutionResult.new()
	_check(
		system.grant_merit(unit, 2, "expedition", 3, "successful_food", "expedition:e1:food:pawn", result),
		"Valid merit grant was rejected"
	)
	_check(unit.merit == 2 and unit.lifetime_merit == 2, "Merit totals were not updated")
	_check(unit.merit_history.size() == 1, "Merit history was not recorded")
	_check(unit.merit_history[0].unit_id == unit.id, "Merit trace lost unit id")
	_check(unit.merit_history[0].source == "expedition", "Merit trace lost source")
	_check(
		not system.grant_merit(unit, 2, "expedition", 3, "successful_food", "expedition:e1:food:pawn", result),
		"Duplicate merit grant was accepted"
	)
	_check(
		not system.grant_merit(unit, 0, "expedition", 3, "invalid", "invalid", result),
		"Invalid merit amount was accepted"
	)
	_check(unit.merit == 2 and unit.merit_history.size() == 1, "Rejected merit changed state")


func _test_data_driven_validation() -> void:
	var system := PromotionSystem.new()
	_check(
		not system.register_definition({
			"from_rank": GameEnums.Rank.PAWN,
			"to_rank": GameEnums.Rank.KING,
			"merit_required": 1,
			"training_days": 1,
		}),
		"King was accepted as a promotion target"
	)
	_check(
		(
			system
			. register_definition(
				{
					"from_rank": GameEnums.Rank.KNIGHT,
					"to_rank": GameEnums.Rank.BISHOP,
					"merit_required": 9,
					"barracks_required": true,
					"training_days": 2,
					"condition": "always",
				}
			)
		),
		"New promotion definition was not registered"
	)
	_check(
		int(system.promotion_requirement(GameEnums.Rank.KNIGHT, GameEnums.Rank.BISHOP).training_days) == 2,
		"Promotion requirement was not read from its definition"
	)
	var state := GameState.new()
	var barracks := _barracks(state, GameEnums.BuildingPhase.ACTIVE)
	var pawn := _unit(state, "pawn", GameEnums.Rank.PAWN)
	pawn.merit = 6
	_check(system.can_promote(state, pawn, GameEnums.Rank.ROOK, barracks.id), "Valid promotion was rejected")
	var ready_result := TurnResolutionResult.new()
	system.append_ready_notice(state, pawn, ready_result)
	_check(
		(
			not ready_result.promotion_events.is_empty()
			and ready_result.promotion_events[0].attention == GameEnums.AttentionLevel.IMPORTANT
		),
		"Promotion-ready notice was not prioritized"
	)
	_check(not system.can_promote(state, pawn, GameEnums.Rank.QUEEN, barracks.id), "Undefined target rank was accepted")
	pawn.merit = 0
	_check(
		not system.can_promote(state, pawn, GameEnums.Rank.KNIGHT, barracks.id), "Promotion without merit was accepted"
	)
	pawn.merit = 6
	barracks.phase = GameEnums.BuildingPhase.BUILDING
	_check(not system.can_promote(state, pawn, GameEnums.Rank.KNIGHT, barracks.id), "Inactive Barracks was accepted")
	barracks.phase = GameEnums.BuildingPhase.ACTIVE
	pawn.work_building_id = "farm"
	_check(
		not system.can_promote(state, pawn, GameEnums.Rank.KNIGHT, barracks.id), "Conflicting work state was accepted"
	)
	var king := _unit(state, "king", GameEnums.Rank.KING)
	king.merit = 99
	_check(not system.can_promote(state, king, GameEnums.Rank.QUEEN, barracks.id), "King was accepted for promotion")


func _test_turn_training_and_completion() -> void:
	var state := GameState.new()
	state.food = 20
	var barracks := _barracks(state, GameEnums.BuildingPhase.ACTIVE)
	var pawn := _unit(state, "trainee", GameEnums.Rank.PAWN)
	pawn.display_name = "Tốt B"
	pawn.board_cell = Vector2i(0, 7)
	pawn.merit = 6
	pawn.lifetime_merit = 6
	var original_id := pawn.id
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	var order := manager.queue_promotion(pawn.id, barracks.id, GameEnums.Rank.ROOK)
	_check(order != null, "Valid promotion order was not queued")
	manager.queue_move(pawn.id, Vector2i(1, 7))
	var conflict_result := manager.end_day()
	_check(conflict_result.was_rejected("promotion", pawn.id), "Conflicting order was not rejected")
	_check(not pawn.is_in_promotion_training(), "Rejected promotion started training")

	manager.queue_promotion(pawn.id, barracks.id, GameEnums.Rank.ROOK)
	var start_result := manager.end_day()
	_check(not start_result.was_rejected("promotion", pawn.id), "Valid promotion was rejected")
	_check(pawn.is_in_promotion_training(), "Training state was not committed")
	_check(pawn.rank == GameEnums.Rank.PAWN, "Rank changed on training start day")
	_check(not pawn.can_be_moved() and not pawn.can_be_builder(), "Trainee was not locked")
	var finish_result := manager.end_day()
	_check(pawn.rank == GameEnums.Rank.ROOK, "Promotion did not complete on the configured day")
	_check(pawn.id == original_id, "Promotion replaced the unit")
	_check(pawn.merit == 6, "Promotion spent threshold merit")
	_check(pawn.promotion_history.size() == 1, "Promotion history was not recorded once")
	_check(finish_result.promoted_unit_ids == [pawn.id], "Completion result was not recorded")
	manager.end_day()
	_check(pawn.promotion_history.size() == 1, "Completed promotion ran again")
	var found_report := false
	for entry in finish_result.report_entries:
		if entry.source_label == "Barracks" and "hoàn tất" in entry.text:
			found_report = true
	_check(found_report, "Promotion completion did not use the S10 report")


func _test_expedition_merit_hook() -> void:
	var state := GameState.new()
	state.food = 30
	var first := _unit(state, "scout_a", GameEnums.Rank.PAWN)
	var second := _unit(state, "scout_b", GameEnums.Rank.PAWN)
	first.board_cell = Vector2i(0, 7)
	second.board_cell = Vector2i(1, 7)
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	manager.queue_expedition([first.id, second.id])
	manager.end_day()
	var expedition := state.expeditions.values()[0] as ExpeditionState
	expedition.outcome_kind = ExpeditionSystem.OUTCOME_FOOD
	expedition.days_left = 1
	first.away_days_left = 1
	second.away_days_left = 1
	var result := manager.end_day()
	_check(first.merit == PromotionSystem.EXPEDITION_SUCCESS_MERIT, "Expedition merit missing")
	_check(second.merit == PromotionSystem.EXPEDITION_SUCCESS_MERIT, "Team merit missing")
	_check(result.merit_grants.size() == 2, "Expedition merit trace count is wrong")
	manager.end_day()
	_check(first.merit_history.size() == 1, "Expedition merit was duplicated")


func _barracks(state: GameState, phase: GameEnums.BuildingPhase) -> BuildingState:
	var barracks := BuildingState.new("barracks", GameEnums.BuildingType.BARRACKS, Vector2i(4, 4))
	barracks.phase = phase
	state.buildings[barracks.id] = barracks
	return barracks


func _unit(state: GameState, id: String, rank: GameEnums.Rank) -> UnitState:
	var unit := UnitState.new(id)
	unit.display_name = id
	unit.rank = rank
	unit.faction = GameEnums.Faction.PLAYER
	state.units[id] = unit
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
