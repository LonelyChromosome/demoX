class_name BoardController
extends Node

signal context_requested(cell: Vector2i)
signal unit_context_requested(unit_id: String, cell: Vector2i)
signal view_changed

var state: GameState
var turn_manager: TurnManager
var view: BoardView

var selected_unit_id := ""
var dragged_unit_id := ""
var input_enabled := true
var resolving := false
var building_system := BuildingSystem.new()
var staffing_system := StaffingSystem.new()
var resolution_unit_snapshot: Dictionary = {}
var resolution_building_snapshot: Dictionary = {}


func setup(game_state: GameState, manager: TurnManager, board_view: BoardView) -> void:
	state = game_state
	turn_manager = manager
	view = board_view

	view.cell_pressed.connect(_on_cell_pressed)
	view.cell_released.connect(_on_cell_released)
	view.cell_hovered.connect(_on_cell_hovered)
	view.resolution_animation_finished.connect(_on_resolution_animation_finished)
	turn_manager.order_queue.changed.connect(_refresh_view)
	turn_manager.day_resolved.connect(_on_day_resolved)
	turn_manager.resolution_started.connect(_on_resolution_started)
	turn_manager.resolution_finished.connect(_on_resolution_finished)
	_refresh_view()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	var should_clear := false
	if event is InputEventKey:
		should_clear = event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	elif event is InputEventMouseButton:
		should_clear = event.pressed and event.button_index == MOUSE_BUTTON_RIGHT

	if should_clear and (not selected_unit_id.is_empty() or not dragged_unit_id.is_empty()):
		_clear_selection()
		get_viewport().set_input_as_handled()


func _on_cell_pressed(cell: Vector2i) -> void:
	if not _can_accept_input():
		return

	var unit := _player_unit_at(cell)
	if unit != null:
		if turn_manager.has_pending_move(unit.id):
			view.end_piece_hold()
			dragged_unit_id = ""
			selected_unit_id = unit.id
			_refresh_view()
			unit_context_requested.emit(unit.id, cell)
			return

		selected_unit_id = unit.id
		dragged_unit_id = unit.id
		view.begin_piece_hold(unit.id)
		view.set_piece_hold_preview(cell, true)
		_refresh_view()
		return

	# Clicking the world is always a cell/building action. It never moves a selected piece.
	view.end_piece_hold()
	dragged_unit_id = ""
	selected_unit_id = ""
	_refresh_view()
	context_requested.emit(cell)


func _on_cell_released(cell: Vector2i) -> void:
	if dragged_unit_id.is_empty():
		return

	var unit_id := dragged_unit_id
	var unit := state.units.get(unit_id) as UnitState
	var was_dragged := view.piece_hold_moved()
	dragged_unit_id = ""

	if not _can_accept_input() or unit == null:
		view.end_piece_hold()
		selected_unit_id = ""
		_refresh_view()
		return

	var target := _resolve_drop_target(cell, unit_id)
	var same_origin := target == unit.board_cell
	var valid := view.is_inside(target) and (same_origin or _is_free_target(target, unit_id))
	view.end_piece_hold()

	if same_origin:
		# A click selects the piece; an actual drag dropped back on origin ends the manipulation.
		selected_unit_id = unit_id if not was_dragged else ""
		_refresh_view()
		return

	if not valid:
		view.flash_invalid_cell(cell)
		selected_unit_id = ""
		_refresh_view()
		return

	if not _plan_move(unit_id, target):
		view.flash_invalid_cell(target)
	selected_unit_id = ""
	_refresh_view()


func _on_cell_hovered(cell: Vector2i) -> void:
	if dragged_unit_id.is_empty():
		return
	var unit := state.units.get(dragged_unit_id) as UnitState
	if unit == null or not view.is_inside(cell):
		view.set_piece_hold_preview(Vector2i(-1, -1), false)
		return
	var target := _resolve_drop_target(cell, dragged_unit_id)
	var valid := target == unit.board_cell or _is_free_target(target, dragged_unit_id)
	view.set_piece_hold_preview(target, valid)


func _plan_move(unit_id: String, target: Vector2i) -> bool:
	var unit := state.units.get(unit_id) as UnitState
	if (
		unit == null
		or not unit.can_be_moved()
		or not view.is_inside(target)
		or not turn_manager.can_edit_orders()
	):
		return false

	if target == unit.board_cell:
		return false

	if not _is_free_target(target, unit_id):
		return false

	var job_slot := turn_manager.get_job_slot_at(target)
	turn_manager.queue_move(unit_id, target)
	if not job_slot.is_empty() and not turn_manager.plan_job_drop(unit_id, target):
		turn_manager.cancel_unit_plan(unit_id)
		return false
	if job_slot.is_empty():
		# Empty operational/world cells may still mean leaving an old job.
		turn_manager.plan_job_drop(unit_id, target)
	return true


func _resolve_drop_target(raw_target: Vector2i, moving_unit_id: String) -> Vector2i:
	if not view.is_inside(raw_target):
		return raw_target

	var building := _building_at_drop(raw_target)
	if building == null:
		return raw_target

	# Dropping directly on a free operational square keeps that exact square.
	if raw_target != building.core_cell and _is_free_target(raw_target, moving_unit_id):
		return raw_target

	# Dropping on the core/occupied part of a building auto-arranges the piece
	# into the nearest free one of the eight operational squares.
	var best := Vector2i(-1, -1)
	var best_distance := 999
	for cell in building_system.footprint(building.core_cell):
		if cell == building.core_cell or not view.is_inside(cell):
			continue
		if not _is_free_target(cell, moving_unit_id):
			continue
		var distance := absi(cell.x - raw_target.x) + absi(cell.y - raw_target.y)
		if (
			best == Vector2i(-1, -1)
			or distance < best_distance
			or (
				distance == best_distance
				and (cell.y < best.y or (cell.y == best.y and cell.x < best.x))
			)
		):
			best = cell
			best_distance = distance
	return best if best != Vector2i(-1, -1) else raw_target


func _building_at_drop(cell: Vector2i) -> BuildingState:
	var planned := turn_manager.get_planned_building()
	if planned != null and cell in building_system.footprint(planned.core_cell):
		return planned
	return building_system.building_at_cell(state, cell)


func _is_free_target(cell: Vector2i, moving_unit_id: String) -> bool:
	var building := _building_at_drop(cell)
	if building != null:
		if cell == building.core_cell:
			return false
		if cell not in building_system.footprint(building.core_cell):
			return false
	elif building_system.is_cell_occupied_by_building(state, cell):
		return false

	var planned_targets := turn_manager.get_planned_move_targets()
	for candidate in state.units.values():
		if not (candidate is UnitState) or candidate.id == moving_unit_id:
			continue
		if candidate.board_cell == cell or planned_targets.get(candidate.id) == cell:
			return false
	return true


func _player_unit_at(cell: Vector2i) -> UnitState:
	for candidate in state.units.values():
		if (
			candidate is UnitState
			and candidate.faction == GameEnums.Faction.PLAYER
			and candidate.board_cell == cell
		):
			return candidate
	return null


func undo_current() -> bool:
	if selected_unit_id.is_empty():
		return false

	if turn_manager.has_pending_move(selected_unit_id):
		turn_manager.cancel_unit_plan(selected_unit_id)

	_clear_selection()
	return true


func _clear_selection() -> void:
	selected_unit_id = ""
	dragged_unit_id = ""
	if view != null:
		view.end_piece_hold()
	_refresh_view()


func _on_day_resolved(_day: int) -> void:
	_clear_selection()


func _refresh_view() -> void:
	if view != null:
		view.present(state.units, selected_unit_id, turn_manager.get_planned_move_targets())
		view_changed.emit()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_clear_selection()


func _can_accept_input() -> bool:
	return input_enabled and not resolving and turn_manager.can_edit_orders()


func _on_resolution_started() -> void:
	resolving = true
	dragged_unit_id = ""
	view.end_piece_hold()
	resolution_unit_snapshot.clear()
	resolution_building_snapshot.clear()
	for candidate in state.units.values():
		if candidate is UnitState:
			resolution_unit_snapshot[candidate.id] = {
				"cell": candidate.board_cell,
				"rank": candidate.rank,
				"faction": candidate.faction,
			}
	for candidate in state.buildings.values():
		if candidate is BuildingState:
			resolution_building_snapshot[candidate.id] = {
				"core": candidate.core_cell,
				"type": candidate.type,
			}


func _on_resolution_finished(result: TurnResolutionResult) -> void:
	_refresh_view()
	view.play_resolution(result, resolution_unit_snapshot, resolution_building_snapshot)


func _on_resolution_animation_finished() -> void:
	resolving = false
