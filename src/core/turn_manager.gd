class_name TurnManager
extends Node

signal day_started(day: int)
signal day_resolved(day: int)
signal resolution_started
signal resolution_phase_started(phase: int)
signal resolution_finished(result: TurnResolutionResult)
signal ration_requested(result: TurnResolutionResult)

var state: GameState
var order_queue := OrderQueue.new()
var resolver := TurnResolver.new()
var building_system := BuildingSystem.new()
var is_resolving := false
var _pending_snapshot: PendingOrderSnapshot
var _pending_result: TurnResolutionResult


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

func queue_building_plan(type: GameEnums.BuildingType, core_cell: Vector2i) -> BuildingState:
	if not can_edit_orders():
		return null
	var order := PlaceBuildingOrder.new(_next_building_id(), type, core_cell, state.day, [])
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

func queue_assign_builder(
	building_id: String, unit_id: String, slot_cell := Vector2i(-1, -1)
) -> AssignBuilderOrder:
	if not can_edit_orders():
		return null
	return order_queue.plan_assign_builder(building_id, unit_id, slot_cell)

func queue_remove_builder(building_id: String, unit_id: String) -> RemoveBuilderOrder:
	if not can_edit_orders():
		return null
	return order_queue.plan_remove_builder(building_id, unit_id)

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
	building_id: String,
	manager_unit_id := "",
	worker_unit_ids: Array[String] = [],
	job_slots: Dictionary = {}
) -> SetBuildingStaffOrder:
	if not can_edit_orders():
		return null
	var order := SetBuildingStaffOrder.new(
		building_id, manager_unit_id, worker_unit_ids, state.day, job_slots
	)
	order_queue.plan_staffing(order)
	return order

func cancel_staffing(building_id: String) -> void:
	if can_edit_orders():
		order_queue.cancel_staffing(building_id)

func get_planned_staffing(building_id: String) -> SetBuildingStaffOrder:
	return order_queue.get_staffing(building_id)

func plan_job_slot(building_id: String, cell: Vector2i, role: GameEnums.JobRole) -> void:
	if can_edit_orders():
		order_queue.plan_job_slot(building_id, cell, role)

func get_planned_job_slots(building_id: String) -> Dictionary:
	return order_queue.planned_job_slots(building_id)

func get_job_slot_at(cell: Vector2i) -> Dictionary:
	var planned_building := get_planned_building()
	if planned_building != null:
		var planned_slots := order_queue.planned_job_slots(planned_building.id)
		if planned_slots.has(cell):
			if planned_slots[cell] == GameEnums.JobRole.NONE:
				return {}
			return {"building_id": planned_building.id, "role": planned_slots[cell]}
	for candidate_value in state.buildings.values():
		if not (candidate_value is BuildingState):
			continue
		var candidate := candidate_value as BuildingState
		var slots: Dictionary = candidate.job_slots.duplicate(true)
		var pending_slots: Dictionary = order_queue.planned_job_slots(candidate.id)
		for pending_cell in pending_slots:
			if pending_slots[pending_cell] == GameEnums.JobRole.NONE:
				slots.erase(pending_cell)
			else:
				slots[pending_cell] = pending_slots[pending_cell]
		if slots.has(cell):
			return {"building_id": candidate.id, "role": slots[cell]}
	return {}

func plan_job_drop(unit_id: String, cell: Vector2i) -> bool:
	if not can_edit_orders():
		return false
	var slot := get_job_slot_at(cell)
	if slot.is_empty():
		order_queue.remove_planned_builder(unit_id)
		_plan_staff_unassign(unit_id)
		return false
	var building_id: String = slot.building_id
	var role: int = slot.role
	var unit := state.units.get(unit_id) as UnitState
	if unit == null or unit.faction != GameEnums.Faction.PLAYER:
		return false
	if role == GameEnums.JobRole.BUILDER and not unit.can_be_builder():
		return false
	if role in [GameEnums.JobRole.MANAGER, GameEnums.JobRole.WORKSHOP_MANAGER, GameEnums.JobRole.FARM_WORKER]:
		if unit.locked_by_construction or unit.locked_by_healing or unit.away_days_left > 0:
			return false
		if role in [GameEnums.JobRole.MANAGER, GameEnums.JobRole.WORKSHOP_MANAGER] and unit.rank == GameEnums.Rank.KING:
			return false
	if role != GameEnums.JobRole.BUILDER:
		order_queue.remove_planned_builder(unit_id)
	_plan_staff_unassign(unit_id, building_id)
	var planned_building := get_planned_building()
	if role == GameEnums.JobRole.BUILDER:
		if planned_building != null and planned_building.id == building_id:
			return order_queue.add_planned_builder(unit_id, cell)
		return queue_assign_builder(building_id, unit_id, cell) != null
	var building := state.buildings.get(building_id) as BuildingState
	if building == null:
		return false
	var staffing := _planned_or_current_staffing(building)
	var manager_id: String = staffing.manager
	var workers: Array[String] = staffing.workers
	var slots: Dictionary = staffing.slots
	if role in [GameEnums.JobRole.MANAGER, GameEnums.JobRole.WORKSHOP_MANAGER]:
		manager_id = unit_id
		workers.erase(unit_id)
		for slot_cell in slots.keys():
			if slots[slot_cell] in [GameEnums.JobRole.MANAGER, GameEnums.JobRole.WORKSHOP_MANAGER]:
				slots.erase(slot_cell)
		slots[cell] = role
	elif role == GameEnums.JobRole.FARM_WORKER:
		if not workers.has(unit_id):
			workers.append(unit_id)
		if manager_id == unit_id:
			manager_id = ""
		slots[cell] = role
	else:
		return false
	queue_staffing(building_id, manager_id, workers, slots)
	return true

func plan_clear_job_slot(building_id: String, cell: Vector2i) -> void:
	if not can_edit_orders():
		return
	var building := state.buildings.get(building_id) as BuildingState
	var planned_building := get_planned_building()
	if planned_building != null and planned_building.id == building_id:
		for unit_id in order_queue.remove_planned_builder_at(cell):
			order_queue.cancel_move(unit_id)
	if building != null and building.phase == GameEnums.BuildingPhase.BUILDING:
		for builder_id in building.builder_unit_ids:
			var builder := state.units.get(builder_id) as UnitState
			if builder != null and builder.board_cell == cell:
				queue_remove_builder(building_id, builder_id)
	order_queue.plan_job_slot(building_id, cell, GameEnums.JobRole.NONE)
	if building != null and building.phase == GameEnums.BuildingPhase.ACTIVE:
		var staffing := _planned_or_current_staffing(building)
		var manager_id: String = staffing.manager
		var workers: Array[String] = staffing.workers
		if not manager_id.is_empty():
			var manager := state.units.get(manager_id) as UnitState
			if manager != null and manager.board_cell == cell:
				manager_id = ""
		for worker_id in workers.duplicate():
			var worker := state.units.get(worker_id) as UnitState
			if worker != null and worker.board_cell == cell:
				workers.erase(worker_id)
		var slots: Dictionary = staffing.slots
		slots.erase(cell)
		queue_staffing(building_id, manager_id, workers, slots)

func _plan_staff_unassign(unit_id: String, except_building_id := "") -> void:
	var unit := state.units.get(unit_id) as UnitState
	if unit == null or unit.work_building_id.is_empty() or unit.work_building_id == except_building_id:
		return
	var building := state.buildings.get(unit.work_building_id) as BuildingState
	if building == null:
		return
	var staffing := _planned_or_current_staffing(building)
	var manager_id: String = staffing.manager
	var workers: Array[String] = staffing.workers
	if manager_id == unit_id:
		manager_id = ""
	workers.erase(unit_id)
	var slots: Dictionary = staffing.slots
	queue_staffing(building.id, manager_id, workers, slots)

func _planned_or_current_staffing(building: BuildingState) -> Dictionary:
	var planned := get_planned_staffing(building.id)
	if planned != null:
		return {
			"manager": planned.manager_unit_id,
			"workers": planned.worker_unit_ids.duplicate(),
			"slots": planned.job_slots.duplicate(true),
		}
	var slots: Dictionary = building.job_slots.duplicate(true)
	var pending_slots: Dictionary = order_queue.planned_job_slots(building.id)
	for cell in pending_slots:
		if pending_slots[cell] == GameEnums.JobRole.NONE:
			slots.erase(cell)
		else:
			slots[cell] = pending_slots[cell]
	return {
		"manager": building.manager_unit_id,
		"workers": building.worker_unit_ids.duplicate(),
		"slots": slots,
	}


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
	if result.awaiting_ration:
		_pending_snapshot = snapshot
		_pending_result = result
		ration_requested.emit(result)
		return result
	_complete_resolution(result)
	return result


func submit_ration(fed_unit_ids: Array[String]) -> TurnResolutionResult:
	if not is_resolving or _pending_result == null or not _pending_result.awaiting_ration:
		return null
	var result := resolver.resume_after_ration(
		state, _pending_snapshot, building_system, _pending_result, fed_unit_ids
	)
	if result.awaiting_ration:
		ration_requested.emit(result)
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
