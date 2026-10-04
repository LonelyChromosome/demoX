class_name TurnManager
extends Node

signal day_started(day: int)
signal day_resolved(day: int)
signal resolution_started
signal resolution_phase_started(phase: int)
signal resolution_finished(result: TurnResolutionResult)

var state: GameState
var order_queue := OrderQueue.new()
var resolver := TurnResolver.new()
var building_system := BuildingSystem.new()
var is_resolving := false


func setup(game_state: GameState) -> void:
	state = game_state
	if not resolver.phase_started.is_connected(_on_resolution_phase_started):
		resolver.phase_started.connect(_on_resolution_phase_started)


func queue_move(unit_id: String, target: Vector2i) -> MoveUnitOrder:
	if not can_edit_orders():
		return null
	var unit := state.units.get(unit_id) as UnitState
	if unit == null:
		return null
	return order_queue.plan_move(unit_id, unit.board_cell, target, state.day)


func cancel_move(unit_id: String) -> void:
	if can_edit_orders():
		order_queue.cancel_move(unit_id)


func queue_building(
	type: GameEnums.BuildingType, core_cell: Vector2i, builder_ids: Array[String] = []
) -> BuildingState:
	if not can_edit_orders():
		return null
	if builder_ids.is_empty():
		builder_ids = get_default_builder_ids()
	var order := PlaceBuildingOrder.new(
		_next_building_id(), type, core_cell, state.day, builder_ids
	)
	order_queue.plan_building(order)
	return order.to_blueprint()


func cancel_building() -> void:
	if can_edit_orders():
		order_queue.cancel_building()

func queue_cancel_construction(building_id: String) -> CancelConstructionOrder:
	if not can_edit_orders():
		return null
	return order_queue.plan_cancel_construction(building_id)

func cancel_cancel_construction() -> void:
	if can_edit_orders():
		order_queue.cancel_cancel_construction()

func get_planned_cancel_construction() -> CancelConstructionOrder:
	return order_queue.get_cancel_construction()

func queue_assign_builder(building_id: String, unit_id: String) -> AssignBuilderOrder:
	if not can_edit_orders():
		return null
	return order_queue.plan_assign_builder(building_id, unit_id)

func queue_demolition(building_id: String) -> DemolishBuildingOrder:
	if not can_edit_orders():
		return null
	return order_queue.plan_demolition(building_id)

func cancel_demolition() -> void:
	if can_edit_orders():
		order_queue.cancel_demolition()

func get_planned_demolition() -> DemolishBuildingOrder:
	return order_queue.get_demolition()

func queue_staffing(
	building_id: String, manager_unit_id := "", worker_unit_ids: Array[String] = []
) -> SetBuildingStaffOrder:
	if not can_edit_orders():
		return null
	var order := SetBuildingStaffOrder.new(
		building_id, manager_unit_id, worker_unit_ids, state.day
	)
	order_queue.plan_staffing(order)
	return order

func cancel_staffing(building_id: String) -> void:
	if can_edit_orders():
		order_queue.cancel_staffing(building_id)

func get_planned_staffing(building_id: String) -> SetBuildingStaffOrder:
	return order_queue.get_staffing(building_id)


func clear_orders() -> void:
	if can_edit_orders():
		order_queue.clear()


func end_day() -> TurnResolutionResult:
	if state == null or is_resolving:
		return null
	is_resolving = true
	resolution_started.emit()
	var snapshot := order_queue.snapshot()
	var result := resolver.resolve(state, snapshot, building_system)
	order_queue.clear()
	is_resolving = false
	day_resolved.emit(result.resolved_day)
	if result.next_day > result.resolved_day:
		day_started.emit(result.next_day)
	resolution_finished.emit(result)
	return result


func can_edit_orders() -> bool:
	return state != null and not is_resolving


func has_pending_move(unit_id: String) -> bool:
	return order_queue.get_move(unit_id) != null


func get_planned_move_target(unit_id: String) -> Vector2i:
	var order := order_queue.get_move(unit_id)
	return order.target if order != null else Vector2i(-1, -1)


func get_planned_move_targets() -> Dictionary:
	return order_queue.move_targets()


func get_pending_move_count() -> int:
	return order_queue.move_count()


func get_planned_building() -> BuildingState:
	var order := order_queue.get_building()
	return order.to_blueprint() if order != null else null


func get_default_builder_ids() -> Array[String]:
	var ids: Array[String] = []
	for candidate in state.units.values():
		if candidate is UnitState and candidate.can_be_builder():
			ids.append(candidate.id)
	ids.sort()
	return ids.slice(0, 1)


func has_pending_orders() -> bool:
	return not order_queue.is_empty()


func _next_building_id() -> String:
	var index := state.buildings.size() + 1
	var candidate := "building_%d" % index
	while state.buildings.has(candidate):
		index += 1
		candidate = "building_%d" % index
	return candidate


func _on_resolution_phase_started(phase: int) -> void:
	resolution_phase_started.emit(phase)
