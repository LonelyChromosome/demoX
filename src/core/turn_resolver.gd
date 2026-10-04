class_name TurnResolver
extends RefCounted

signal phase_started(phase: Phase)

enum Phase {
	VALIDATE_ORDERS,
	COMMIT_MOVEMENT,
	COMMIT_BUILDING_PLACEMENT,
	RESOLVE_SYSTEMS,
	RESOLVE_EVENTS,
	FINALIZE_DAY,
	START_NEXT_DAY,
}


func resolve(
	state: GameState, snapshot: PendingOrderSnapshot, building_system: BuildingSystem
) -> TurnResolutionResult:
	var result := TurnResolutionResult.new()
	result.resolved_day = state.day
	_run_phase(Phase.VALIDATE_ORDERS, result)
	var valid_moves := _validate_moves(state, snapshot.move_orders, building_system, result)
	var valid_building := _validate_building(
		state, snapshot.building_order, valid_moves, building_system, result
	)

	_run_phase(Phase.COMMIT_MOVEMENT, result)
	_commit_moves(state, valid_moves, result)

	_run_phase(Phase.COMMIT_BUILDING_PLACEMENT, result)
	_commit_building(state, valid_building, result)

	_run_phase(Phase.RESOLVE_SYSTEMS, result)
	_resolve_systems(state, result)
	_run_phase(Phase.RESOLVE_EVENTS, result)
	_resolve_events(state, result)

	_run_phase(Phase.FINALIZE_DAY, result)
	state.day_one_full_knowledge = false
	if state.day < GameState.MAX_DAYS:
		state.day += 1
	result.next_day = state.day

	_run_phase(Phase.START_NEXT_DAY, result)
	_start_next_day(state, result)
	return result


func _validate_moves(
	state: GameState,
	orders: Array[MoveUnitOrder],
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> Array[MoveUnitOrder]:
	var preliminary: Array[MoveUnitOrder] = []
	for order in orders:
		if order == null:
			result.reject("move", "", "Order is missing")
			continue
		var unit := state.units.get(order.unit_id) as UnitState
		if unit == null:
			result.reject("move", order.unit_id, "Unit no longer exists")
			continue
		if not unit.can_be_moved():
			result.reject("move", order.unit_id, "Unit is locked")
			continue
		if unit.board_cell != order.origin:
			result.reject("move", order.unit_id, "Unit origin changed")
			continue
		if not building_system.is_inside_board(order.target):
			result.reject("move", order.unit_id, "Target is outside board")
			continue
		if _occupied_by_other_unit(state, order.target, order.unit_id):
			result.reject("move", order.unit_id, "Target is occupied")
			continue
		if building_system.is_cell_occupied_by_building(state, order.target):
			result.reject("move", order.unit_id, "Target is inside a building area")
			continue
		preliminary.append(order)

	var destination_counts := {}
	for order in preliminary:
		destination_counts[order.target] = int(destination_counts.get(order.target, 0)) + 1

	var valid: Array[MoveUnitOrder] = []
	for order in preliminary:
		if destination_counts[order.target] > 1:
			result.reject("move", order.unit_id, "Multiple units target the same cell")
		else:
			valid.append(order)
	return valid


func _validate_building(
	state: GameState,
	order: PlaceBuildingOrder,
	valid_moves: Array[MoveUnitOrder],
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> PlaceBuildingOrder:
	if order == null:
		return null
	var targets: Array = []
	for move in valid_moves:
		targets.append(move.target)
	var validation := building_system.validate_placement(state, order.core_cell, targets)
	if not validation.valid:
		result.reject("building", order.building_id, validation.reason)
		return null
	if state.buildings.has(order.building_id):
		result.reject("building", order.building_id, "Building id already exists")
		return null
	return order


func _occupied_by_other_unit(state: GameState, cell: Vector2i, moving_unit_id: String) -> bool:
	for candidate in state.units.values():
		if candidate is UnitState and candidate.id != moving_unit_id and candidate.board_cell == cell:
			return true
	return false


func _commit_moves(
	state: GameState, orders: Array[MoveUnitOrder], result: TurnResolutionResult
) -> void:
	for order in orders:
		var unit := state.units.get(order.unit_id) as UnitState
		if unit == null:
			result.reject("move", order.unit_id, "Unit disappeared before commit")
			continue
		unit.board_cell = order.target
		result.committed_move_ids.append(order.unit_id)


func _commit_building(
	state: GameState, order: PlaceBuildingOrder, result: TurnResolutionResult
) -> void:
	if order == null:
		return
	state.buildings[order.building_id] = order.to_blueprint()
	result.building_committed = true


func _resolve_systems(_state: GameState, _result: TurnResolutionResult) -> void:
	pass


func _resolve_events(_state: GameState, _result: TurnResolutionResult) -> void:
	pass


func _start_next_day(_state: GameState, _result: TurnResolutionResult) -> void:
	pass


func _run_phase(phase: Phase, result: TurnResolutionResult) -> void:
	result.phase_trace.append(phase)
	phase_started.emit(phase)
