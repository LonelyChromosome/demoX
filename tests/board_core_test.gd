extends SceneTree


func _init() -> void:
	var state := GameState.new()
	var turn_manager := TurnManager.new()
	root.add_child(turn_manager)
	turn_manager.setup(state)

	var board := BoardView.new()
	board.size = Vector2(900, 900)
	root.add_child(board)

	var controller := BoardController.new()
	root.add_child(controller)

	var king := UnitState.new("king")
	king.rank = GameEnums.Rank.KING
	king.board_cell = Vector2i(4, 7)
	state.units[king.id] = king
	controller.setup(state, turn_manager, board)

	controller._on_cell_pressed(Vector2i(4, 7))
	controller._on_cell_pressed(Vector2i(4, 4))
	_check(king.board_cell == Vector2i(4, 7), "click order moved the real piece early")
	_check(king.planned_cell == Vector2i(4, 4), "click order did not create a ghost")

	controller._on_cell_pressed(Vector2i(4, 7))
	controller._on_cell_released(Vector2i(2, 4))
	_check(king.board_cell == Vector2i(4, 7), "drag order moved the real piece early")
	_check(king.planned_cell == Vector2i(2, 4), "drag order did not replace the ghost")
	_check(turn_manager.pending_moves.size() == 1, "multiple orders were kept for one unit")

	turn_manager.end_day()
	_check(king.board_cell == Vector2i(2, 4), "End Day did not commit the final order")
	_check(king.planned_cell == Vector2i(-1, -1), "ghost remained after End Day")
	_check(turn_manager.pending_moves.is_empty(), "move queue remained after End Day")

	print("BOARD_CORE_TEST_OK")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
