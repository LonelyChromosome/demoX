extends SceneTree


func _init() -> void:
	_test_projection_round_trip_and_bounds()
	_test_semantic_gate_routes()
	_test_romance_choice_and_report()
	_test_rebellion_output_and_order_rejection()
	_test_interrogation_and_report()
	print("S12B_VISUAL_SOCIAL_INTEGRATION_TEST_OK")
	quit(0)


func _test_projection_round_trip_and_bounds() -> void:
	var view_size := Vector2(720.0, 640.0)
	var projection := BoardProjection.fit(view_size, BoardView.BOARD_SIZE)
	_check(projection.tile > 0.0, "Projection did not fit the board")
	var board := BoardView.new()
	root.add_child(board)
	board.size = view_size
	var centers := {}
	for y in range(BoardView.BOARD_SIZE):
		for x in range(BoardView.BOARD_SIZE):
			var cell := Vector2i(x, y)
			var center := projection.cell_center(cell)
			_check(
				board.screen_to_cell(center) == cell, "Projected click resolved to the wrong cell"
			)
			var plane := projection.screen_to_plane(projection.plane_to_screen(Vector2(cell)))
			_check(plane.is_equal_approx(Vector2(cell)), "Projection round-trip drifted")
			var center_key := "%0.3f,%0.3f" % [center.x, center.y]
			_check(not centers.has(center_key), "Projected cells overlap")
			centers[center_key] = true
			for point in projection.cell_polygon(cell):
				_check(
					(
						point.x >= 0.0
						and point.y >= 0.0
						and point.x <= view_size.x
						and point.y <= view_size.y
					),
					"Projected board escaped layout bounds"
				)
	_check(centers.size() == 64, "Projection did not preserve all 64 cells")


func _test_semantic_gate_routes() -> void:
	var state := GameState.new()
	state.perimeter_layout.slot_order = ["wasteland", "refugee", "forest"]
	var perimeter := PerimeterView.new()
	root.add_child(perimeter)
	perimeter.size = Vector2(1000.0, 700.0)
	var board := BoardView.new()
	perimeter.attach_board(board)
	perimeter.setup(state)
	var routes := perimeter.route_segments()
	_check(routes.size() == 3, "Gate did not connect every semantic perimeter zone")
	for route in routes:
		var zone_id := str(route.zone_id)
		_check(
			route.from_anchor == state.perimeter_layout.city_gate_anchor, "Gate anchor was ignored"
		)
		_check(
			route.to_anchor == state.perimeter_layout.anchor_for(zone_id),
			"Destination semantic anchor was ignored"
		)
		_check(
			perimeter.zone_rect_for(zone_id).grow(1.0).has_point(route.to),
			"Route ignored the semantic zone anchor"
		)


func _test_romance_choice_and_report() -> void:
	var context := _new_context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var first := _unit(state, "alpha", GameEnums.Rank.PAWN, Vector2i(0, 7))
	var second := _unit(state, "beta", GameEnums.Rank.KNIGHT, Vector2i(1, 7))
	_check(
		manager.relationship_system.shared_event(
			state,
			first.id,
			second.id,
			state.day,
			"test",
			"shared_trial",
			"relationship:test:trial",
			7,
			5
		),
		"Candidate setup failed"
	)
	var relationship := manager.relationship_system.relationship_between(
		state, first.id, second.id, false
	)
	_check(relationship.status == RelationshipState.ROMANCE_CANDIDATE, "Pair is not a candidate")
	_check(relationship.status != RelationshipState.BONDED, "Candidate auto-bonded")
	_check(manager.confirm_romance(first.id, second.id), "Explicit romance choice failed")
	_check(relationship.status == RelationshipState.BONDED, "Choice did not persist bonded state")
	_check(not manager.confirm_romance(second.id, first.id), "Bond was applied twice")
	_check(relationship.shared_history.size() == 2, "Bond history is not idempotent")
	var result := manager.end_day()
	_check(_has_report(result, "Relationship", "gắn bó"), "Bond report was not integrated")


func _test_rebellion_output_and_order_rejection() -> void:
	var state := GameState.new()
	var farm := BuildingState.new("farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[farm.id] = farm
	var worker := _unit(state, "worker", GameEnums.Rank.PAWN, Vector2i(3, 3))
	farm.manager_unit_id = worker.id
	var food_system := FoodSystem.new()
	_check(food_system.production_for_building(state, farm) == 4, "Normal Farm output changed")
	worker.loyalty = -2
	worker.rebellion_level = GameEnums.RebellionLevel.LOW_OUTPUT
	_check(food_system.production_for_building(state, farm) == 3, "LOW_OUTPUT has no real effect")
	worker.loyalty = -5
	worker.rebellion_level = GameEnums.RebellionLevel.REVOLT
	_check(food_system.production_for_building(state, farm) == 2, "REVOLT still contributes labor")
	_check(not worker.can_be_moved(), "REVOLT unit remains normally controllable")
	var workshop := BuildingState.new(
		"workshop", GameEnums.BuildingType.MATERIAL_WORKSHOP, Vector2i(5, 3)
	)
	workshop.phase = GameEnums.BuildingPhase.ACTIVE
	workshop.manager_unit_id = worker.id
	state.buildings[workshop.id] = workshop
	_check(
		MaterialSystem.new().manager_output(state, workshop) == 0,
		"REVOLT still contributes Workshop output"
	)

	var context := _new_context()
	var manager: TurnManager = context.manager
	var order_unit := _unit(context.state, "resister", GameEnums.Rank.PAWN, Vector2i(0, 7))
	_check(manager.queue_move(order_unit.id, Vector2i(0, 6)) != null, "Move setup failed")
	order_unit.loyalty = -4
	order_unit.rebellion_level = GameEnums.RebellionLevel.RESISTS
	var result := manager.end_day()
	_check(result.was_rejected("move", order_unit.id), "Resistance did not reject a queued order")
	_check(order_unit.board_cell == Vector2i(0, 7), "Resisting unit moved anyway")
	_check(
		manager.queue_move(order_unit.id, Vector2i(0, 6)) == null, "Resister accepted a new order"
	)
	_check(manager.queue_expedition([order_unit.id]) == null, "Resister accepted an expedition")


func _test_interrogation_and_report() -> void:
	var context := _new_context()
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var target := _unit(state, "dissident", GameEnums.Rank.ROOK, Vector2i(2, 7))
	target.loyalty = -4
	target.rebellion_level = GameEnums.RebellionLevel.RESISTS
	var detail_controller := ContextualBoardController.new()
	detail_controller.state = state
	detail_controller.turn_manager = manager
	var detail := detail_controller._unit_social_detail(target)
	_check("TRUNG THÀNH" in detail and "Kháng lệnh" in detail, "Unit detail hid rebellion")
	_check(manager.can_interrogate(target.id), "Eligible rebel cannot be interrogated")
	_check(manager.interrogate_unit(target.id), "Intentional interrogation failed")
	_check(target.loyalty == -4, "Interrogation magically reset loyalty")
	_check(not manager.interrogate_unit(target.id), "Interrogation repeated on the same day")
	_check(not target.memory_tags.is_empty(), "Interrogation history was not stored")
	var result := manager.end_day()
	_check(
		_has_report(result, "King interrogation", "đã xác nhận"),
		"Confirmed interrogation result did not reach reports"
	)
	for entry in result.report_entries:
		if entry.source_label == "King interrogation":
			_check(
				entry.attention_level >= GameEnums.AttentionLevel.IMPORTANT,
				"Resistance interrogation was not prioritized"
			)
	var mild := _unit(state, "mild", GameEnums.Rank.PAWN, Vector2i(3, 7))
	mild.loyalty = -1
	mild.rebellion_level = GameEnums.RebellionLevel.DISSATISFIED
	_check(not manager.can_interrogate(mild.id), "Mild dissatisfaction enabled interrogation")


func _new_context() -> Dictionary:
	var state := GameState.new()
	state.food = 100
	var king := _unit(state, "king", GameEnums.Rank.KING, Vector2i(4, 7))
	king.display_name = "Vua"
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return {"state": state, "manager": manager}


func _unit(state: GameState, unit_id: String, rank: GameEnums.Rank, cell: Vector2i) -> UnitState:
	var unit := UnitState.new(unit_id)
	unit.display_name = unit_id
	unit.rank = rank
	unit.faction = GameEnums.Faction.PLAYER
	unit.board_cell = cell
	state.units[unit.id] = unit
	return unit


func _has_report(result: TurnResolutionResult, source: String, fragment: String) -> bool:
	for entry in result.report_entries:
		if entry.source_label == source and fragment in entry.text:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)