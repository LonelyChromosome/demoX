extends SceneTree

var failures := 0


func _init() -> void:
	_test_balance_and_weather()
	_test_seed_and_pacing()
	_test_storm(false)
	_test_storm(true)
	_test_repair_turn_flow()
	_test_unaffordable_and_timeout()
	_test_projection_and_locales()
	if failures == 0:
		print("S14_BALANCE_CRISIS_TEST_OK")
	quit(1 if failures else 0)


func _state() -> GameState:
	var state := GameState.new()
	state.day = 12
	state.food = 20
	state.materials = 6
	for index in range(2):
		var type := GameEnums.BuildingType.FARM if index == 0 else GameEnums.BuildingType.MATERIAL_WORKSHOP
		var building := BuildingState.new("building_%d" % index, type, Vector2i(2 + index * 3, 2))
		building.phase = GameEnums.BuildingPhase.ACTIVE
		state.buildings[building.id] = building
	return state


func _engine() -> EventSystem:
	var engine := EventSystem.new()
	# Keep default definitions but isolate manual storm progression from auto-spawning.
	for id in engine.definitions:
		engine.definitions[id].condition = "never"
	return engine


func _test_balance_and_weather() -> void:
	var state := GameSession.start_new_game()
	var food := FoodSystem.new()
	_check(food.eligible_unit_ids(state).size() == 4, "Opening consumers changed")
	_check(state.food == 8 and state.materials == 3, "Opening stockpile contract changed")
	for day in [1, 2]:
		state.day = day
		_check(food.resolve_consumption(state, TurnResolutionResult.new(), BuildingSystem.new()), "Opening has no two-day planning buffer")
	_check(food.farm_output(0) == 2 and food.farm_output(2) == 6, "Farm output balance changed")
	_check(food.farm_output(100) == 14, "Farm cap changed")
	_check(FoodSystem.STARVATION_DAYS == 3, "Starvation grace changed")
	_check(MaterialSystem.WORKSHOP_OUTPUT[GameEnums.Rank.PAWN] == 1, "Pawn workshop output changed")
	_check(MaterialSystem.WORKSHOP_OUTPUT[GameEnums.Rank.QUEEN] == 3, "Workshop output ceiling changed")
	var world := WorldState.new()
	for weather in [GameEnums.Weather.CLEAR, GameEnums.Weather.STORM, GameEnums.Weather.COLD, GameEnums.Weather.HEAT]:
		world.weather = weather
		_check(WorldSystem.new().food_production_multiplier(world) == 1.0, "Passive weather production modifier remains")
	_check(RunBalance.stage(8) == "early" and RunBalance.stage(9) == "mid", "Early transition wrong")
	_check(RunBalance.stage(22) == "mid" and RunBalance.stage(23) == "late", "Late transition wrong")


func _test_seed_and_pacing() -> void:
	var variants := {}
	for seed_value in range(16):
		var value := RunBalance.roll(seed_value, 12, "storm_target")
		_check(value == RunBalance.roll(seed_value, 12, "storm_target"), "Seed is not deterministic")
		variants[value % 2] = true
	_check(variants.size() == 2, "Different seeds cannot vary target")
	var state := GameState.new()
	var engine := EventSystem.new()
	engine.definitions.clear()
	for id in ["a", "b"]:
		engine.register_definition({"id": id, "condition": "always", "duration": 1, "stages": [{"effects": []}]})
	engine.register_definition({"id": "invalid", "condition": "missing", "stages": []})
	engine.advance(state, TurnResolutionResult.new())
	_check(state.events.size() == 1, "More than one event opened at once")
	state.day = 2
	engine.advance(state, TurnResolutionResult.new())
	_check(state.events.size() == 1, "Cooldown ignored")
	state.day = 4
	engine.advance(state, TurnResolutionResult.new())
	_check(state.events.size() == 2, "Eligible event did not open after cooldown")
	state.day = 8
	engine.advance(state, TurnResolutionResult.new())
	_check(state.events.size() == 2, "Resolved or invalid event duplicated")


func _test_storm(reinforce: bool) -> void:
	var state := _state()
	var engine := _engine()
	var event := engine.create_event(state, "storm_crisis")
	_check(event.status == GameEnums.EventStatus.WAITING_CHOICE, "Storm has no warning choice")
	_check(engine.choose_event(state, event.id, "reinforce" if reinforce else "wait"), "Storm choice rejected")
	_check(state.materials == 6, "Choice spent resources outside turn advancement")
	var result := TurnResolutionResult.new()
	state.day = 13
	engine.advance(state, result)
	_check(state.materials == (4 if reinforce else 6), "Reinforcement cost wrong")
	var reports_before := result.event_reports.size()
	engine.advance(state, result)
	_check(result.event_reports.size() == reports_before, "Choice/report duplicated on same day")
	state.day = 14
	engine.advance(state, result)
	var damaged: Array[String] = []
	for building in state.buildings.values():
		if building.damaged:
			damaged.append(building.id)
	_check(damaged.size() == (0 if reinforce else 1), "Storm impact does not match preparation")
	if not reinforce:
		var duplicate := _state()
		var other_engine := _engine()
		var other := other_engine.create_event(duplicate, "storm_crisis")
		other_engine.choose_event(duplicate, other.id, "wait")
		for day in [13, 14]:
			duplicate.day = day
			other_engine.advance(duplicate, TurnResolutionResult.new())
		_check(duplicate.buildings[damaged[0]].damaged, "Same seed selected a different storm target")
	state.day = 15
	engine.advance(state, result)
	_check(event.resolved, "Storm did not resolve")
	var follow_up: EventState
	for candidate in state.events.values():
		if candidate.definition_id == "storm_recovery":
			follow_up = candidate
	_check(follow_up != null and follow_up.source == "Building", "Recovery source or follow-up missing")
	state.day = 16
	engine.advance(state, result)
	_check(follow_up != null and follow_up.resolved, "Recovery did not finish")
	var count := result.event_reports.size()
	state.day = 17
	engine.advance(state, result)
	_check(result.event_reports.size() == count, "Resolved storm reported twice")
	_check(state.materials == (4 if reinforce else 6), "Choice effect spent materials twice")
	InformationSystem.new().resolve_daily_information(state, result)
	_check(not result.report_entries.is_empty(), "Crisis reports did not enter S10 information flow")


func _test_repair_turn_flow() -> void:
	var state := _state()
	var system := BuildingSystem.new()
	var farm: BuildingState = state.buildings.building_0
	var workshop: BuildingState = state.buildings.building_1
	var manager_unit := UnitState.new("worker")
	manager_unit.rank = GameEnums.Rank.ROOK
	manager_unit.board_cell = Vector2i(5, 3)
	state.units[manager_unit.id] = manager_unit
	workshop.manager_unit_id = manager_unit.id
	_check(system.damage(state, farm.id, "storm"), "Farm damage failed")
	_check(system.damage(state, workshop.id, "storm"), "Workshop damage failed")
	_check(not system.damage(state, farm.id, "storm"), "Damage applied twice")
	_check(FoodSystem.new().production_for_building(state, farm) == 0, "Damaged farm still produces")
	_check(MaterialSystem.new().manager_output(state, workshop) == 0, "Damaged workshop still produces")
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	_check(manager.queue_repair(farm.id) != null, "Repair could not be queued")
	_check(farm.damaged and state.materials == 6, "Queuing repair mutated resources or damage")
	var result := manager.end_day()
	_check(result != null and not farm.damaged, "Repair did not commit through TurnResolver")
	_check(farm.repair_history.size() == 1 and state.materials == 4, "Repair cost/history wrong")
	_check(result.farm_food_produced == 2, "Repaired farm did not resume production")
	var retry: Array[RepairBuildingOrder] = [RepairBuildingOrder.new(farm.id, state.day)]
	system.commit_repairs(state, retry, TurnResolutionResult.new())
	_check(state.materials == 4 and farm.repair_history.size() == 1, "Repair duplicated")
	manager.queue_free()


func _test_unaffordable_and_timeout() -> void:
	var state := _state()
	state.materials = 0
	var engine := _engine()
	var event := engine.create_event(state, "storm_crisis")
	_check(not engine.choose_event(state, event.id, "reinforce"), "Unaffordable reinforcement accepted")
	state.day += 1
	engine.advance(state, TurnResolutionResult.new())
	_check(event.chosen_choice == "wait", "Unanswered storm did not use documented fallback")
	var farm: BuildingState = state.buildings.building_0
	BuildingSystem.new().damage(state, farm.id, event.id)
	var orders: Array[RepairBuildingOrder] = [RepairBuildingOrder.new(farm.id, state.day)]
	BuildingSystem.new().commit_repairs(state, orders, TurnResolutionResult.new())
	_check(farm.damaged and state.materials == 0, "Unaffordable repair changed state")


func _test_projection_and_locales() -> void:
	var view := BoardView.new()
	root.add_child(view)
	view.size = Vector2(900, 690)
	var projection := BoardProjection.fit(view.size)
	var centers := {}
	for y in range(8):
		for x in range(8):
			var cell := Vector2i(x, y)
			var center := projection.cell_center(cell)
			centers[center] = true
			_check(view.screen_to_cell(center) == cell, "Polished board changed click mapping")
			for point in projection.cell_polygon(cell):
				_check(Rect2(Vector2.ZERO, view.size).has_point(point), "Board cell escaped viewport")
	_check(centers.size() == 64, "Polish merged playable cells")
	_check(Localization.keys_for("vi") == Localization.keys_for("en"), "Locale parity failed")
	for key in Localization.keys_for("vi"):
		_check(Localization.placeholders_for(key, "vi") == Localization.placeholders_for(key, "en"), "Placeholder mismatch: " + key)
	view.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
