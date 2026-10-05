class_name TurnManager
extends Node

signal day_started(day: int)
signal day_resolved(day: int)
signal resolution_started
signal resolution_phase_started(phase: int)
signal resolution_finished(result: TurnResolutionResult)
signal ration_requested(result: TurnResolutionResult)
signal prisoner_decision_requested(unit_id: String)

var state: GameState
var order_queue := OrderQueue.new()
var resolver := TurnResolver.new()
var building_system := BuildingSystem.new()
var information_system := InformationSystem.new()
var prison_system := PrisonSystem.new()
var is_resolving := false
var _pending_snapshot: PendingOrderSnapshot
var _pending_result: TurnResolutionResult


func setup(game_state: GameState) -> void:
	state = game_state
	information_system.initialize_day_one(state)
	if not resolver.phase_started.is_connected(_on_resolution_phase_started):
		resolver.phase_started.connect(_on_resolution_phase_started)


func queue_move(unit_id: String, target: Vector2i) -> MoveUnitOrder:
	if not can_edit_orders():
		return null
	if order_queue.has_inspection_for_unit(unit_id):
		return null
	var unit := state.units.get(unit_id) as UnitState
	if unit == null:
		return null
	return order_queue.plan_move(unit_id, unit.board_cell, target, state.day)


func queue_building_inspection(building_id: String) -> InspectBuildingOrder:
	if not can_edit_orders():
		return null
	var king := _player_king()
	var building := state.buildings.get(building_id) as BuildingState
	if king == null or building == null or not king.can_be_moved():
		return null
	if order_queue.get_move(king.id) != null:
		return null
	if king.board_cell not in building_system.footprint(building.core_cell):
		return null
	return order_queue.plan_inspection(building_id, king.id, state.day)


func cancel_building_inspection() -> void:
	if can_edit_orders():
		order_queue.cancel_inspection()


func get_planned_inspection() -> InspectBuildingOrder:
	return order_queue.get_inspection()


func has_planned_inspection_for_unit(unit_id: String) -> bool:
	return order_queue.has_inspection_for_unit(unit_id)


func can_plan_inspection(building_id: String) -> bool:
	if not can_edit_orders():
		return false
	var king := _player_king()
	var building := state.buildings.get(building_id) as BuildingState
	return (
		king != null
		and building != null
		and king.can_be_moved()
		and order_queue.get_move(king.id) == null
		and king.board_cell in building_system.footprint(building.core_cell)
	)


func queue_prisoner_labor(prisoner_id: String, building_id: String) -> AssignPrisonerLaborOrder:
	if not can_edit_orders():
		return null
	return order_queue.plan_prisoner_labor(prisoner_id, building_id, state.day)


func cancel_prisoner_labor(prisoner_id: String) -> void:
	if can_edit_orders():
		order_queue.cancel_prisoner_labor(prisoner_id)


func queue_prisoner_action(
	prisoner_id: String, action: GameEnums.PrisonerAction
) -> PrisonerActionOrder:
	if not can_edit_orders():
		return null
	return order_queue.plan_prisoner_action(prisoner_id, action, state.day)


func cancel_prisoner_action(prisoner_id: String) -> void:
	if can_edit_orders():
		order_queue.cancel_prisoner_action(prisoner_id)


func request_prisoner_escape(unit_id: String) -> bool:
	if not prison_system.request_escape_attempt(state, unit_id):
		return false
	prisoner_decision_requested.emit(unit_id)
	return true


func request_prisoner_submission(unit_id: String) -> bool:
	return prison_system.request_submission(state, unit_id)


func cancel_move(unit_id: String) -> void:
	if can_edit_orders():
		order_queue.cancel_move(unit_id)


func cancel_unit_plan(unit_id: String) -> void:
	if not can_edit_orders():
		return
	var move := order_queue.get_move(unit_id)
	if move == null:
		return

	var target_slot := get_job_slot_at(move.target)
	if not target_slot.is_empty():
		var target_building_id: String = target_slot.building_id
		var target_role: int = target_slot.role
		if target_role == GameEnums.JobRole.BUILDER:
			var planned_building := get_planned_building(target_building_id)
			if planned_building != null and planned_building.id == target_building_id:
				order_queue.remove_planned_builder(unit_id)
			else:
				order_queue.cancel_assign_builder(target_building_id, unit_id)
		else:
			var planned_target := get_planned_staffing(target_building_id)
			if planned_target != null:
				var target_manager := planned_target.manager_unit_id
				var target_workers: Array[String] = planned_target.worker_unit_ids.duplicate()
				if target_manager == unit_id:
					target_manager = ""
				target_workers.erase(unit_id)
				queue_staffing(
					target_building_id,
					target_manager,
					target_workers,
					planned_target.job_slots
				)

	# If this move was leaving an authoritative job, restore that job in the
	# planned staffing snapshot without touching other planned workers.
	var unit := state.units.get(unit_id) as UnitState
	if unit != null and not unit.work_building_id.is_empty():
		var old_building := state.buildings.get(unit.work_building_id) as BuildingState
		if old_building != null:
			var planned_old := get_planned_staffing(old_building.id)
			if planned_old != null:
				var old_manager := planned_old.manager_unit_id
				var old_workers: Array[String] = planned_old.worker_unit_ids.duplicate()
				var old_slots: Dictionary = planned_old.job_slots.duplicate(true)
				var old_role: int = old_building.job_slots.get(
					unit.board_cell, GameEnums.JobRole.NONE
				)
				if old_role in [GameEnums.JobRole.MANAGER, GameEnums.JobRole.WORKSHOP_MANAGER]:
					old_manager = unit_id
					old_workers.erase(unit_id)
				elif old_role == GameEnums.JobRole.FARM_WORKER:
					if not old_workers.has(unit_id):
						old_workers.append(unit_id)
					if old_manager == unit_id:
						old_manager = ""
				if old_role != GameEnums.JobRole.NONE:
					old_slots[unit.board_cell] = old_role
				queue_staffing(old_building.id, old_manager, old_workers, old_slots)

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
	_update_order_placement_validation(order, _planned_cores())
	order_queue.plan_building(order)
	return order.to_blueprint()

func queue_building_plan(type: GameEnums.BuildingType, core_cell: Vector2i) -> BuildingState:
	if not can_edit_orders():
		return null
	var order := PlaceBuildingOrder.new(_next_building_id(), type, core_cell, state.day, [])
	_update_order_placement_validation(order, _planned_cores())
	order_queue.plan_building(order)
	return order.to_blueprint()


func cancel_building(building_id: String) -> void:
	if can_edit_orders():
		order_queue.cancel_building(building_id)

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
	for planned_building in get_planned_buildings():
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

func get_construction_building_at(cell: Vector2i) -> BuildingState:
	var planned := get_planned_building_at_cell(cell)
	if (
		planned != null
		and cell != planned.core_cell
		and planned.phase == GameEnums.BuildingPhase.BLUEPRINT
	):
		return planned
	var committed := building_system.building_at_cell(state, cell)
	if (
		committed != null
		and cell != committed.core_cell
		and committed.phase in [GameEnums.BuildingPhase.BLUEPRINT, GameEnums.BuildingPhase.BUILDING]
	):
		return committed
	return null


func plan_construction_drop(unit_id: String, cell: Vector2i) -> bool:
	if not can_edit_orders():
		return false
	var building := get_construction_building_at(cell)
	var unit := state.units.get(unit_id) as UnitState
	if building == null or unit == null or not unit.can_be_builder():
		return false
	order_queue.plan_job_slot(building.id, cell, GameEnums.JobRole.BUILDER)
	var planned := get_planned_building(building.id)
	if planned != null:
		return order_queue.add_planned_builder(building.id, unit_id, cell)
	return queue_assign_builder(building.id, unit_id, cell) != null


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
	if role in [
		GameEnums.JobRole.MANAGER,
		GameEnums.JobRole.WORKSHOP_MANAGER,
		GameEnums.JobRole.FARM_WORKER,
		GameEnums.JobRole.TREATMENT,
		GameEnums.JobRole.PRISON_MANAGER,
		GameEnums.JobRole.PRISON_GUARD,
	]:
		if unit.locked_by_construction or unit.locked_by_healing or unit.away_days_left > 0:
			return false
		if role == GameEnums.JobRole.TREATMENT and not unit.injured:
			return false
		if role in [GameEnums.JobRole.MANAGER, GameEnums.JobRole.WORKSHOP_MANAGER] and unit.rank == GameEnums.Rank.KING:
			return false
	if role != GameEnums.JobRole.BUILDER:
		order_queue.remove_planned_builder(unit_id)
	_plan_staff_unassign(unit_id, building_id)
	if role in [GameEnums.JobRole.TREATMENT, GameEnums.JobRole.PRISON_MANAGER, GameEnums.JobRole.PRISON_GUARD]:
		return true
	var planned_building := get_planned_building(building_id)
	if role == GameEnums.JobRole.BUILDER:
		if planned_building != null:
			return order_queue.add_planned_builder(building_id, unit_id, cell)
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
	var planned_building := get_planned_building(building_id)
	if planned_building != null:
		for unit_id in order_queue.remove_planned_builder_at(building_id, cell):
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
	if building.type not in [GameEnums.BuildingType.FARM, GameEnums.BuildingType.MATERIAL_WORKSHOP]:
		return
	var staffing := _planned_or_current_staffing(building)
	var manager_id: String = staffing.manager
	var workers: Array[String] = staffing.workers
	if manager_id == unit_id:
		manager_id = ""
	workers.erase(unit_id)
	var slots: Dictionary = staffing.slots
	queue_staffing(building.id, manager_id, workers, slots)


func plan_work_unassign(unit_id: String, except_building_id := "") -> void:
	if can_edit_orders():
		_plan_staff_unassign(unit_id, except_building_id)

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
		return result
	_complete_resolution(result)
	return result


func _complete_resolution(result: TurnResolutionResult) -> void:
	information_system.resolve_daily_information(state, result)
	order_queue.clear()
	_pending_snapshot = null
	_pending_result = null
	is_resolving = false
	day_resolved.emit(result.resolved_day)
	if result.next_day > result.resolved_day:
		day_started.emit(result.next_day)
	resolution_finished.emit(result)


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


func get_planned_building(building_id: String) -> BuildingState:
	var order := order_queue.get_building(building_id)
	return order.to_blueprint() if order != null else null


func get_planned_buildings() -> Array[BuildingState]:
	var buildings: Array[BuildingState] = []
	var reserved_cores: Array[Vector2i] = []
	for order in order_queue.get_buildings():
		_update_order_placement_validation(order, reserved_cores)
		if order.placement_valid:
			reserved_cores.append(order.core_cell)
		buildings.append(order.to_blueprint())
	return buildings


func _planned_cores() -> Array[Vector2i]:
	var cores: Array[Vector2i] = []
	for order in order_queue.get_buildings():
		_update_order_placement_validation(order, cores)
		if order.placement_valid:
			cores.append(order.core_cell)
	return cores


func _update_order_placement_validation(
	order: PlaceBuildingOrder, reserved_cores: Array[Vector2i]
) -> void:
	var validation := building_system.validate_placement(
		state, order.core_cell, get_planned_move_targets().values(), reserved_cores
	)
	order.placement_valid = validation.valid
	order.placement_reason = validation.reason


func get_planned_building_at_cell(cell: Vector2i) -> BuildingState:
	for building in get_planned_buildings():
		if cell in building_system.footprint(building.core_cell):
			return building
	return null


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
	var index := state.buildings.size() + get_planned_buildings().size() + 1
	var candidate := "building_%d" % index
	while state.buildings.has(candidate) or order_queue.get_building(candidate) != null:
		index += 1
		candidate = "building_%d" % index
	return candidate


func _on_resolution_phase_started(phase: int) -> void:
	resolution_phase_started.emit(phase)


func _player_king() -> UnitState:
	for candidate in state.units.values():
		if (
			candidate is UnitState
			and candidate.faction == GameEnums.Faction.PLAYER
			and candidate.rank == GameEnums.Rank.KING
		):
			return candidate
	return null


func _player_king() -> UnitState:
	for candidate in state.units.values():
		if (
			candidate is UnitState
			and candidate.faction == GameEnums.Faction.PLAYER
			and candidate.rank == GameEnums.Rank.KING
		):
			return candidate
	return null
