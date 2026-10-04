class_name TurnResolver
extends RefCounted

signal phase_started(phase: Phase)

var food_system := FoodSystem.new()
var material_system := MaterialSystem.new()

enum Phase {
	VALIDATE_ORDERS,
	COMMIT_MOVEMENT,
	COMMIT_BUILDING_PLACEMENT,
	COMMIT_CANCEL_CONSTRUCTION,
	COMMIT_DEMOLITION,
	RESOLVE_SYSTEMS,
	RESOLVE_EVENTS,
	FINALIZE_DEMOLITION,
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
	var valid_cancel := _validate_cancel(state, snapshot.cancel_construction_order, result)
	var valid_demolition := _validate_demolition(
		state, snapshot.demolish_building_order, building_system, result
	)

	_run_phase(Phase.COMMIT_MOVEMENT, result)
	_commit_moves(state, valid_moves, result)

	_run_phase(Phase.COMMIT_BUILDING_PLACEMENT, result)
	_commit_building(state, valid_building, building_system, result)

	_run_phase(Phase.COMMIT_CANCEL_CONSTRUCTION, result)
	_commit_cancel(state, valid_cancel, building_system, result)
	_commit_reassignments(state, snapshot.assign_builder_orders, building_system, result)

	_run_phase(Phase.COMMIT_DEMOLITION, result)
	_commit_demolition(state, valid_demolition, building_system, result)

	_run_phase(Phase.RESOLVE_SYSTEMS, result)
	_resolve_systems(state, building_system, result)
	_run_phase(Phase.RESOLVE_EVENTS, result)
	_resolve_events(state, result)

	_run_phase(Phase.FINALIZE_DEMOLITION, result)
	_finalize_demolition(state, building_system, result)

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
	var builders := building_system.validate_builders(state, order.builder_unit_ids)
	if not builders.valid:
		result.reject("building", order.building_id, builders.reason)
		return null
	var cost := building_system.material_cost(order.building_type)
	if state.materials < cost:
		result.reject("building", order.building_id, "Không đủ vật tư")
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
	state: GameState,
	order: PlaceBuildingOrder,
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> void:
	if order == null:
		return
	var building := order.to_blueprint()
	building_system.assign_construction(building, order.builder_unit_ids)
	state.buildings[order.building_id] = building
	state.materials -= building_system.material_cost(order.building_type)
	result.materials_spent += building_system.material_cost(order.building_type)
	result.new_building_ids.append(order.building_id)
	for builder_id in order.builder_unit_ids:
		var builder := state.units.get(builder_id) as UnitState
		if builder != null:
			builder.assigned_building_id = order.building_id
			builder.locked_by_construction = true
	result.building_committed = true


func _resolve_systems(
	state: GameState, building_system: BuildingSystem, result: TurnResolutionResult
) -> void:
	var skip_ids := {}
	for building_id in result.new_building_ids:
		skip_ids[building_id] = true
	for building_id in result.cancelled_building_ids:
		skip_ids[building_id] = true
	result.completed_building_ids = building_system.advance_construction(state, skip_ids)
	building_system.unlock_builders(state, result.completed_building_ids)
	food_system.produce(state, result)
	material_system.produce(state, result)

func _validate_cancel(
	state: GameState, order: CancelConstructionOrder, result: TurnResolutionResult
) -> CancelConstructionOrder:
	if order == null:
		return null
	var building := state.buildings.get(order.building_id) as BuildingState
	if building == null:
		result.reject("cancel_construction", order.building_id, "Building không tồn tại")
		return null
	if building.phase != GameEnums.BuildingPhase.BUILDING:
		result.reject("cancel_construction", order.building_id, "Chỉ được hủy BUILDING")
		return null
	return order

func _commit_cancel(
	state: GameState,
	order: CancelConstructionOrder,
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> void:
	if order == null:
		return
	var refund := building_system.cancel_construction(state, order.building_id)
	if refund < 0:
		result.reject("cancel_construction", order.building_id, "Construction đã thay đổi")
		return
	result.cancelled_building_ids.append(order.building_id)
	result.refunded_materials += refund

func _commit_reassignments(
	state: GameState,
	orders: Array[AssignBuilderOrder],
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> void:
	for order in orders:
		if result.cancelled_building_ids.has(order.building_id):
			result.reject("assign_builder", order.unit_id, "Building đã bị hủy trong turn")
			continue
		var assignment := building_system.reassign_builder_to_construction(
			state, order.building_id, order.unit_id
		)
		if not assignment.valid:
			result.reject("assign_builder", order.unit_id, assignment.reason)
		else:
			result.reassigned_builder_ids.append(order.unit_id)

func _validate_demolition(
	state: GameState,
	order: DemolishBuildingOrder,
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> DemolishBuildingOrder:
	if order == null:
		return null
	var validation := building_system.validate_demolition(state, order.building_id)
	if not validation.valid:
		result.reject("demolition", order.building_id, validation.reason)
		return null
	return order

func _commit_demolition(
	state: GameState,
	order: DemolishBuildingOrder,
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> void:
	if order == null:
		return
	if building_system.start_demolition(state, order.building_id):
		result.demolishing_building_ids.append(order.building_id)
	else:
		result.reject("demolition", order.building_id, "Demolition đã thay đổi")

func _finalize_demolition(
	state: GameState, building_system: BuildingSystem, result: TurnResolutionResult
) -> void:
	for building_id in result.demolishing_building_ids:
		if building_system.finalize_demolition(state, building_id):
			result.demolished_building_ids.append(building_id)


func _resolve_events(_state: GameState, _result: TurnResolutionResult) -> void:
	pass


func _start_next_day(_state: GameState, _result: TurnResolutionResult) -> void:
	pass


func _run_phase(phase: Phase, result: TurnResolutionResult) -> void:
	result.phase_trace.append(phase)
	phase_started.emit(phase)
