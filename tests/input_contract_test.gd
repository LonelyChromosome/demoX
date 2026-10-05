extends SceneTree

var context_route_seen := false


func _init() -> void:
	var state := GameState.new()
	state.food = 100
	state.materials = 5
	var unit := UnitState.new("rook")
	unit.display_name = "Xe Trắng"
	unit.rank = GameEnums.Rank.ROOK
	unit.board_cell = Vector2i(0, 0)
	unit.backstory = ["Giữ cổng phía Tây.", "Gia nhập đội hình từ Ngày 1."]
	state.units[unit.id] = unit

	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	var board := BoardView.new()
	board.size = Vector2(800, 800)
	root.add_child(board)
	var board_controller := BoardController.new()
	root.add_child(board_controller)
	board_controller.setup(state, manager, board)
	var popup := ContextPopup.new()
	root.add_child(popup)
	var contextual := ContextualBoardController.new()
	root.add_child(contextual)
	contextual.setup(state, manager, board, popup)
	board_controller.context_requested.connect(contextual.open_for_cell)

	_test_left_drag_contract(state, manager, board, board_controller, popup, unit)
	_test_right_click_unit_panel(manager, board, board_controller, contextual, popup, unit)
	_test_normal_build_flow(state, manager, board, board_controller, contextual, popup, unit)
	print("INPUT_CONTRACT_TEST_OK")
	quit(0)


func _test_left_drag_contract(
	state: GameState,
	manager: TurnManager,
	board: BoardView,
	controller: BoardController,
	popup: ContextPopup,
	unit: UnitState
) -> void:
	controller._on_cell_pressed(unit.board_cell)
	_check(controller.dragged_unit_id == unit.id and board.held_unit_id == unit.id, "Left press did not begin held ghost")
	controller._on_cell_released(Vector2i(2, 2))
	_check(unit.board_cell == Vector2i(0, 0), "Drag changed authoritative unit position")
	_check(manager.get_planned_move_target(unit.id) == Vector2i(2, 2), "Drag did not create planned move")
	controller._on_cell_pressed(unit.board_cell)
	_check(controller.dragged_unit_id.is_empty(), "Unit with planned move could be dragged again implicitly")
	controller._on_cell_released(Vector2i(3, 3))
	_check(manager.get_planned_move_target(unit.id) == Vector2i(2, 2), "Second drag implicitly replaced planned move")
	controller._on_cell_pressed(Vector2i(7, 7))
	_check(manager.has_pending_move(unit.id), "Left click on empty cell cancelled gameplay order")
	popup.open_at(Vector2(30, 30), "Test", "Panel", {})
	popup.close()
	_check(manager.has_pending_move(unit.id), "Closing panel cancelled gameplay order")
	_check(state.units.has(unit.id), "Input contract mutated roster")


func _test_right_click_unit_panel(
	manager: TurnManager,
	board: BoardView,
	controller: BoardController,
	contextual: ContextualBoardController,
	popup: ContextPopup,
	unit: UnitState
) -> void:
	context_route_seen = false
	controller.context_requested.connect(_mark_context_route)
	board.cell_context_requested.emit(unit.board_cell)
	_check(context_route_seen, "Right-click context signal was not routed")
	_check(contextual.current_unit_id == unit.id, "Unit did not win right-click target priority")
	_check(popup.visible and popup.title_label.text == unit.display_name, "Unit panel did not open")
	_check("TIỂU SỬ" in popup.detail_label.text, "Unit panel omitted backstory")
	_check("Dự kiến đến" in popup.detail_label.text, "Unit panel omitted planned destination state")
	_check(board.context_unit_id == unit.id, "Unit panel highlight was not set")
	popup.close()
	_check(manager.has_pending_move(unit.id), "Closing Unit panel cancelled planned move")
	contextual.open_for_cell(unit.board_cell)
	contextual._on_action_confirmed("cancel_move")
	_check(not manager.has_pending_move(unit.id), "Explicit Hủy nước đi did not cancel planned move")
	popup.close()
	controller._on_cell_pressed(unit.board_cell)
	_check(not popup.visible, "Left click incorrectly opened a context panel")
	controller._on_cell_released(unit.board_cell)


func _test_normal_build_flow(
	state: GameState,
	manager: TurnManager,
	board: BoardView,
	controller: BoardController,
	contextual: ContextualBoardController,
	popup: ContextPopup,
	unit: UnitState
) -> void:
	contextual.open_for_cell(Vector2i(3, 3))
	_check(popup.visible, "Right-click empty cell panel did not open")
	contextual._on_action_selected("build_farm")
	contextual._on_action_confirmed("build_farm")
	_check(state.buildings.is_empty(), "Build confirmation changed authoritative state before End Day")
	var plans := manager.get_planned_buildings()
	_check(plans.size() == 1, "Normal DEV_MODE=false flow did not create blueprint")
	var farm: BuildingState = plans[0]
	contextual.open_for_cell(Vector2i(2, 2))
	contextual._on_action_confirmed("builder_slot")
	manager.queue_move(unit.id, Vector2i(2, 2))
	_check(manager.plan_job_drop(unit.id, Vector2i(2, 2)), "Builder could not be assigned through operational cell")
	popup.close()
	_check(manager.get_planned_buildings().size() == 1, "Closing panel cancelled planned building")
	var result := manager.end_day()
	_check(result.building_committed and state.buildings.has(farm.id), "Normal player build path failed at End Day")
	_check(unit.board_cell == Vector2i(2, 2), "Builder move did not commit")
	_check(unit.locked_by_construction, "Committed construction did not lock builder")
	board.resolution_animation_finished.emit()
	contextual.open_for_cell(unit.board_cell)
	_check(contextual.current_unit_id == unit.id, "Unit on operational area did not keep context priority")
	_check(board.context_unit_id == unit.id, "Operational-area unit highlight was not applied")


func _mark_context_route(_cell: Vector2i) -> void:
	context_route_seen = true


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
