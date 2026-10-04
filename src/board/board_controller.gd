class_name BoardController
extends Node

signal context_requested(cell: Vector2i)
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
	view.cell_context_requested.connect(_on_context_requested)
	view.resolution_animation_finished.connect(_on_resolution_animation_finished)
	turn_manager.day_resolved.connect(_on_day_resolved)
	turn_manager.resolution_started.connect(_on_resolution_started)
	turn_manager.resolution_finished.connect(_on_resolution_finished)
	_refresh_view()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not dragged_unit_id.is_empty():
			dragged_unit_id = ""
			view.cancel_hold()
		_clear_selection()
		get_viewport().set_input_as_handled()


func _on_cell_pressed(cell: Vector2i) -> void:
	if not _can_accept_input():
		return
	var unit := _player_unit_at(cell)
	if unit != null:
		selected_unit_id = unit.id
		if turn_manager.has_pending_move(unit.id):
			dragged_unit_id = ""
		else:
			dragged_unit_id = unit.id
			view.begin_hold(unit.id)
		_refresh_view()
		return

	if not selected_unit_id.is_empty():
		_clear_selection()


func _on_cell_released(cell: Vector2i) -> void:
	if not _can_accept_input():
		dragged_unit_id = ""
		view.cancel_hold()
		return
	if dragged_unit_id.is_empty():
		return

	var unit := state.units.get(dragged_unit_id) as UnitState
	var accepted := true
	if unit != null and cell != unit.board_cell:
		accepted = _plan_move(dragged_unit_id, cell)
	dragged_unit_id = ""
	if accepted or unit == null:
		view.cancel_hold()
	else:
		view.return_hold_to(unit.board_cell)


func _plan_move(unit_id: String, target: Vector2i) -> bool:
	var unit := state.units.get(unit_id) as UnitState
	if (
		unit == null
		or not unit.can_be_moved()
		or not view.is_inside(target)
		or not turn_manager.can_edit_orders()
	):
		return false
	target = _normalize_building_drop(target, unit_id)
	if target == Vector2i(-1, -1):
		var hover_cell := view.screen_to_cell(view.get_local_mouse_position())
		if view.is_inside(hover_cell):
			view.flash_invalid_cell(hover_cell)
		return false

	if target == unit.board_cell:
		turn_manager.cancel_move(unit_id)
		_refresh_view()
		return true

	if not _is_free_target(target, unit_id):
		view.flash_invalid_cell(target)
		return false

	var construction_building := turn_manager.get_construction_building_at(target)
	var job_slot := turn_manager.get_job_slot_at(target)
	turn_manager.queue_move(unit_id, target)
	if construction_building != null:
		if not turn_manager.plan_construction_drop(unit_id, target):
			turn_manager.cancel_move(unit_id)
			view.flash_invalid_cell(target)
			return false
	elif not job_slot.is_empty():
		if not turn_manager.plan_job_drop(unit_id, target):
			turn_manager.cancel_move(unit_id)
			view.flash_invalid_cell(target)
			return false
	else:
		turn_manager.plan_job_drop(unit_id, target)
	_refresh_view()
	return true


func _is_free_target(cell: Vector2i, moving_unit_id: String) -> bool:
	var planned_building := turn_manager.get_planned_building_at_cell(cell)
	if planned_building != null and planned_building.core_cell == cell:
		return false
	if building_system.is_cell_occupied_by_building(state, cell):
		return false
	var planned_targets := turn_manager.get_planned_move_targets()
	for candidate in state.units.values():
		if not (candidate is UnitState) or candidate.id == moving_unit_id:
			continue
		if candidate.board_cell == cell or planned_targets.get(candidate.id) == cell:
			return false
	return true


func _normalize_building_drop(target: Vector2i, moving_unit_id: String) -> Vector2i:
	var building := turn_manager.get_planned_building_at_cell(target)
	if building == null:
		building = building_system.building_at_cell(state, target)
	if building == null:
		return target
	if target != building.core_cell and _is_free_target(target, moving_unit_id):
		return target
	var candidates := building_system.operational_cells(building.core_cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a := a.distance_squared_to(target)
		var distance_b := b.distance_squared_to(target)
		if distance_a != distance_b:
			return distance_a < distance_b
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for candidate in candidates:
		if _is_free_target(candidate, moving_unit_id):
			return candidate
	return Vector2i(-1, -1)


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
	_clear_selection()
	return true


func _clear_selection() -> void:
	selected_unit_id = ""
	dragged_unit_id = ""
	_refresh_view()


func _on_context_requested(cell: Vector2i) -> void:
	if _can_accept_input():
		context_requested.emit(cell)


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
	view.cancel_hold()
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
