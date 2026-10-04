class_name BoardController
extends Node

var state: GameState
var turn_manager: TurnManager
var view: BoardView

var selected_unit_id := ""
var dragged_unit_id := ""
var input_enabled := true
var resolving := false
var building_system := BuildingSystem.new()
var staffing_system := StaffingSystem.new()


func setup(game_state: GameState, manager: TurnManager, board_view: BoardView) -> void:
	state = game_state
	turn_manager = manager
	view = board_view

	view.cell_pressed.connect(_on_cell_pressed)
	view.cell_released.connect(_on_cell_released)
	turn_manager.day_resolved.connect(_on_day_resolved)
	turn_manager.resolution_started.connect(_on_resolution_started)
	turn_manager.resolution_finished.connect(_on_resolution_finished)
	_refresh_view()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or selected_unit_id.is_empty():
		return

	var should_clear := false
	if event is InputEventKey:
		should_clear = event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	elif event is InputEventMouseButton:
		should_clear = event.pressed and event.button_index == MOUSE_BUTTON_RIGHT

	if should_clear:
		_clear_selection()
		get_viewport().set_input_as_handled()


func _on_cell_pressed(cell: Vector2i) -> void:
	if not _can_accept_input():
		return
	var unit := _player_unit_at(cell)
	if unit != null:
		if unit.id == selected_unit_id and turn_manager.has_pending_move(unit.id):
			turn_manager.cancel_move(unit.id)
		selected_unit_id = unit.id
		dragged_unit_id = unit.id
		_refresh_view()
		return

	if not selected_unit_id.is_empty():
		_plan_move(selected_unit_id, cell)


func _on_cell_released(cell: Vector2i) -> void:
	if not _can_accept_input():
		dragged_unit_id = ""
		return
	if dragged_unit_id.is_empty():
		return

	var unit := state.units.get(dragged_unit_id) as UnitState
	if unit != null and cell != unit.board_cell:
		_plan_move(dragged_unit_id, cell)
	dragged_unit_id = ""


func _plan_move(unit_id: String, target: Vector2i) -> void:
	var unit := state.units.get(unit_id) as UnitState
	if (
		unit == null
		or not unit.can_be_moved()
		or not view.is_inside(target)
		or not turn_manager.can_edit_orders()
	):
		return

	if target == unit.board_cell:
		turn_manager.cancel_move(unit_id)
		_refresh_view()
		return

	if not _is_free_target(target, unit_id):
		view.flash_invalid_cell(target)
		return

	turn_manager.queue_move(unit_id, target)
	_refresh_view()


func _is_free_target(cell: Vector2i, moving_unit_id: String) -> bool:
	if (
		building_system.is_cell_occupied_by_building(state, cell)
		and not staffing_system.is_operational_cell_available(state, cell)
	):
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
		turn_manager.cancel_move(selected_unit_id)

	_clear_selection()
	return true


func _clear_selection() -> void:
	selected_unit_id = ""
	dragged_unit_id = ""
	_refresh_view()


func _on_day_resolved(_day: int) -> void:
	_clear_selection()


func _refresh_view() -> void:
	if view != null:
		view.present(state.units, selected_unit_id, turn_manager.get_planned_move_targets())


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_clear_selection()


func _can_accept_input() -> bool:
	return input_enabled and not resolving and turn_manager.can_edit_orders()


func _on_resolution_started() -> void:
	resolving = true
	dragged_unit_id = ""


func _on_resolution_finished(_result: TurnResolutionResult) -> void:
	resolving = false
	_refresh_view()
