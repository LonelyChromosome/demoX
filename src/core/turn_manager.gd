class_name TurnManager
extends Node

signal day_started(day: int)
signal day_resolved(day: int)

var state: GameState
var pending_orders: Array[Dictionary] = []
var pending_moves: Dictionary = {}


func setup(game_state: GameState) -> void:
	state = game_state


func queue_order(order: Dictionary) -> void:
	pending_orders.append(order)


func queue_move(unit_id: String, target: Vector2i) -> void:
	pending_moves[unit_id] = target


func cancel_move(unit_id: String) -> void:
	pending_moves.erase(unit_id)


func clear_orders() -> void:
	pending_orders.clear()
	pending_moves.clear()


func end_day() -> void:
	if state == null:
		return

	_commit_moves()
	pending_orders.clear()
	day_resolved.emit(state.day)

	if state.day < GameState.MAX_DAYS:
		state.day += 1
		state.day_one_full_knowledge = false
		day_started.emit(state.day)


func _commit_moves() -> void:
	for unit_id in pending_moves:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		unit.board_cell = pending_moves[unit_id]
		unit.planned_cell = Vector2i(-1, -1)
	pending_moves.clear()
