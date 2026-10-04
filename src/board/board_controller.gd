class_name BoardController
extends Node

var state: GameState
var turn_manager: TurnManager
var view: BoardView

var selected_unit_id := ""
var dragged_unit_id := ""
var input_enabled := true


func setup(game_state: GameState, manager: TurnManager, board_view: BoardView) -> void:
	state = game_state
	turn_manager = manager
	view = board_view

	view.cell_pressed.connect(_on_cell_pressed)
	view.cell_released.connect(_on_cell_released)
	turn_manager.day_resolved.connect(_on_day_resolved)
	_refresh_view()


func _on_cell_pressed(cell: Vector2i) -> void:
	if not input_enabled:
		return
	var unit := _player_unit_at(cell)
	if unit != null:
		selected_unit_id = unit.id
		dragged_unit_id = unit.id
		_refresh_view()
		return

	if not selected_unit_id.is_empty():
		_plan_move(selected_unit_id, cell)


func _on_cell_released(cell: Vector2i) -> void:
	if not input_enabled:
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
	if unit == null or not unit.can_be_moved() or not view.is_inside(target):
		return

	if target == unit.board_cell:
		turn_manager.cancel_move(unit_id)
		unit.planned_cell = Vector2i(-1, -1)
		_refresh_view()
		return

	if not _is_free_target(target, unit_id):
		view.flash_invalid_cell(target)
		return

	unit.planned_cell = target
	turn_manager.queue_move(unit_id, target)
	_refresh_view()


func _is_free_target(cell: Vector2i, moving_unit_id: String) -> bool:
	for candidate in state.units.values():
		if not (candidate is UnitState) or candidate.id == moving_unit_id:
			continue
		if candidate.board_cell == cell or candidate.planned_cell == cell:
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


func _on_day_resolved(_day: int) -> void:
	selected_unit_id = ""
	dragged_unit_id = ""
	_refresh_view()


func _refresh_view() -> void:
	if view != null:
		view.present(state.units, selected_unit_id)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		selected_unit_id = ""
		dragged_unit_id = ""
		_refresh_view()
