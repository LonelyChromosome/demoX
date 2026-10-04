class_name TurnManager
extends Node

signal day_started(day: int)
signal day_resolved(day: int)

var state: GameState
var pending_orders: Array[Dictionary] = []

func setup(game_state: GameState) -> void:
	state = game_state

func queue_order(order: Dictionary) -> void:
	pending_orders.append(order)

func clear_orders() -> void:
	pending_orders.clear()

func end_day() -> void:
	if state == null:
		return

	# Systems will consume pending_orders here.
	# Authoritative state changes only at End Day.
	pending_orders.clear()
	day_resolved.emit(state.day)

	if state.day < GameState.MAX_DAYS:
		state.day += 1
		state.day_one_full_knowledge = false
		day_started.emit(state.day)
