extends SceneTree


func _init() -> void:
	_test_core_and_operational_rules()
	_test_operational_movement()
	_test_multiple_plans_and_exact_cancel()
	_test_deterministic_material_budget()
	_test_overlap_conflicts()
	_test_drop_auto_arrangement()
	_test_day_color_progression()
	print("BUILDING_ARCHITECTURE_TEST_OK")
	quit(0)


func _test_core_and_operational_rules() -> void:
	var state := GameState.new()
	var system := BuildingSystem.new()
	var unit := _unit(state, "unit", Vector2i(2, 2))
	_check(system.validate_placement(state, Vector2i(3, 3)).valid, "Operational unit blocked placement")
	unit.board_cell = Vector2i(3, 3)
	_check(not system.validate_placement(state, Vector2i(3, 3)).valid, "Unit on core did not block placement")
	unit.board_cell = Vector2i(7, 7)
	_check(
		system.validate_placement(state, Vector2i(3, 3), [Vector2i(2, 2)]).valid,
		"Planned move on operational cell blocked placement"
	)
	_check(
		not system.validate_placement(state, Vector2i(3, 3), [Vector2i(3, 3)]).valid,
		"Planned move on core did not block placement"
	)
	var farm := BuildingState.new("farm", GameEnums.BuildingType.FARM, Vector2i(1, 1))
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[farm.id] = farm
	_check(system.is_cell_occupied_by_building(state, farm.core_cell), "Core is not physically occupied")
	_check(not system.is_cell_occupied_by_building(state, Vector2i(2, 2)), "Operational cell became physically occupied")
	_check(system.is_cell_reserved_by_building(state, Vector2i(2, 2)), "Operational cell is not reserved for overlap")
	_check(
		not system.validate_placement(state, Vector2i(3, 1)).valid,
		"Reserved 3x3 overlap with committed building was accepted"
	)


func _test_operational_movement() -> void:
	var context := _context(10)
	var state: GameState = context.state
	var manager: TurnManager = context.manager
	var farm := BuildingState.new("farm", GameEnums.BuildingType.FARM, Vector2i(6, 6))
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[farm.id] = farm
	var mover := _unit(state, "mover", Vector2i(7, 7))
	manager.queue_move(mover.id, Vector2i(5, 5))
	manager.end_day()
	_check(mover.board_cell == Vector2i(5, 5), "Move onto operational cell was rejected")
	manager.queue_move(mover.id, farm.core_cell)
	var result := manager.end_day()
	_check(mover.board_cell == Vector2i(5, 5), "Move onto physical core committed")
	_check(result.was_rejected("move", mover.id), "Physical core move rejection was not reported")


func _test_multiple_plans_and_exact_cancel() -> void:
	var context := _context(10)
	var manager: TurnManager = context.manager
	var state: GameState = context.state
	var first := manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(1, 1), ["builder_0"])
	var second := manager.queue_building(GameEnums.BuildingType.PRISON, Vector2i(4, 1), ["builder_1"])
	var third := manager.queue_building(GameEnums.BuildingType.BARRACKS, Vector2i(1, 4), ["builder_2"])
	_check(manager.get_planned_buildings().size() == 3, "Later blueprint replaced an earlier blueprint")
	_check(first.id != second.id and second.id != third.id, "Planned building ids are not unique")
	manager.cancel_building(second.id)
	var remaining := manager.get_planned_buildings()
	_check(remaining.size() == 2, "Exact cancel removed more than one blueprint")
	_check(remaining[0].id == first.id and remaining[1].id == third.id, "Exact cancel changed plan order")
	manager.end_day()
	_check(state.buildings.has(first.id) and state.buildings.has(third.id), "Remaining blueprints did not commit")
	_check(not state.buildings.has(second.id), "Cancelled blueprint committed")


func _test_deterministic_material_budget() -> void:
	var context := _context(2)
	var manager: TurnManager = context.manager
	var state: GameState = context.state
	var first := manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(1, 1), ["builder_0"])
	var second := manager.queue_building(GameEnums.BuildingType.PRISON, Vector2i(4, 1), ["builder_1"])
	var rejected := manager.queue_building(GameEnums.BuildingType.BARRACKS, Vector2i(1, 4), ["builder_2"])
	var free := manager.queue_building(GameEnums.BuildingType.MATERIAL_WORKSHOP, Vector2i(4, 4), ["builder_3"])
	var result := manager.end_day()
	_check(state.materials == 0, "Material budget became negative or was charged incorrectly")
	_check(state.buildings.has(first.id) and state.buildings.has(second.id), "Affordable plans did not commit in order")
	_check(not state.buildings.has(rejected.id), "Unaffordable plan committed")
	_check(state.buildings.has(free.id), "Zero-cost Workshop was rejected after budget exhaustion")
	_check(result.was_rejected("building", rejected.id), "Material rejection was not reported")


func _test_overlap_conflicts() -> void:
	var context := _context(10)
	var manager: TurnManager = context.manager
	var state: GameState = context.state
	var first := manager.queue_building(GameEnums.BuildingType.FARM, Vector2i(1, 1), ["builder_0"])
	var overlapping := manager.queue_building(GameEnums.BuildingType.PRISON, Vector2i(2, 1), ["builder_1"])
	var previews := manager.get_planned_buildings()
	_check(previews[0].placement_valid, "First blueprint lost its independent validation state")
	_check(not previews[1].placement_valid, "Overlapping blueprint did not retain its validation failure")
	_check(not previews[1].placement_reason.is_empty(), "Invalid blueprint has no validation reason")
	var result := manager.end_day()
	_check(state.buildings.has(first.id), "First valid overlapping candidate did not commit")
	_check(not state.buildings.has(overlapping.id), "Later planned 3x3 overlap committed")
	_check(result.was_rejected("building", overlapping.id), "Planned overlap was not reported")


func _test_drop_auto_arrangement() -> void:
	var state := GameState.new()
	state.food = 100
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	var board := BoardView.new()
	board.size = Vector2(800, 800)
	root.add_child(board)
	var controller := BoardController.new()
	root.add_child(controller)
	controller.setup(state, manager, board)
	var farm := BuildingState.new("farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[farm.id] = farm
	var mover := _unit(state, "mover", Vector2i(7, 7))
	for cell in BuildingSystem.new().operational_cells(farm.core_cell):
		if cell != Vector2i(4, 4):
			_unit(state, "block_%d_%d" % [cell.x, cell.y], cell)
	_check(
		controller._normalize_building_drop(farm.core_cell, mover.id) == Vector2i(4, 4),
		"Drop on core did not auto-arrange to the nearest free operational cell"
	)
	_check(
		controller._normalize_building_drop(Vector2i(6, 6), mover.id) == Vector2i(6, 6),
		"Free direct drop was not preserved"
	)
	_unit(state, "last_block", Vector2i(4, 4))
	_check(
		controller._normalize_building_drop(farm.core_cell, mover.id) == Vector2i(-1, -1),
		"Full operational area did not reject the drop"
	)


func _test_day_color_progression() -> void:
	var board := BoardView.new()
	_check(board.day_color_progress(1) == 0.0, "Day 1 is not the desaturated endpoint")
	_check(board.day_color_progress(16) > 0.0 and board.day_color_progress(16) < 1.0, "Mid-game color is not gradual")
	_check(board.day_color_progress(32) == 1.0, "Day 32 is not the full-color endpoint")


func _context(materials: int) -> Dictionary:
	var state := GameState.new()
	state.food = 100
	state.materials = materials
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	var cells := [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]
	for index in range(cells.size()):
		var builder := _unit(state, "builder_%d" % index, cells[index])
		builder.rank = GameEnums.Rank.ROOK
	return {"state": state, "manager": manager}


func _unit(state: GameState, id: String, cell: Vector2i) -> UnitState:
	var unit := UnitState.new(id)
	unit.display_name = id
	unit.rank = GameEnums.Rank.PAWN
	unit.board_cell = cell
	state.units[id] = unit
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
