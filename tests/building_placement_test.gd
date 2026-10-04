extends SceneTree


func _init() -> void:
	var state := GameState.new()
	var turn_manager := TurnManager.new()
	root.add_child(turn_manager)
	turn_manager.setup(state)

	var board := BoardView.new()
	board.size = Vector2(900, 900)
	root.add_child(board)

	var palette := BuildingPalette.new()
	root.add_child(palette)

	var controller := BuildingPlacementController.new()
	root.add_child(controller)
	controller.setup(state, turn_manager, board, palette)

	var system := BuildingSystem.new()
	_check(not system.validate_placement(state, Vector2i(0, 0)).valid, "edge placement accepted")

	var king := UnitState.new("king")
	king.board_cell = Vector2i(4, 7)
	state.units[king.id] = king
	_check(
		not system.validate_placement(state, Vector2i(4, 6)).valid,
		"placement overlapping a chess piece accepted"
	)

	controller.select_building(GameEnums.BuildingType.FARM)
	controller._on_cell_hovered(Vector2i(3, 3))
	_check(controller.placement.hover_valid, "valid 3x3 preview marked invalid")
	controller._on_cell_pressed(Vector2i(3, 3))
	_check(state.buildings.is_empty(), "planned building committed before End Day")
	_check(controller.placement.planned_building != null, "planned ghost was not created")

	controller._on_cell_pressed(Vector2i(5, 3))
	_check(
		controller.placement.planned_building.core_cell == Vector2i(5, 3),
		"planned position did not change"
	)

	controller.cancel()
	_check(controller.placement.planned_building == null, "cancel left planned building behind")
	_check(turn_manager.pending_building == null, "cancel left queued building behind")

	controller.select_building(GameEnums.BuildingType.FARM)
	controller._on_cell_pressed(Vector2i(3, 3))
	turn_manager.end_day()
	_check(state.buildings.size() == 1, "End Day did not commit blueprint")

	controller.select_building(GameEnums.BuildingType.PRISON)
	controller._on_cell_hovered(Vector2i(3, 3))
	_check(not controller.placement.hover_valid, "overlapping building preview marked valid")
	controller._on_cell_pressed(Vector2i(3, 3))
	_check(turn_manager.pending_building == null, "overlapping building was queued")

	print("BUILDING_PLACEMENT_TEST_OK")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
