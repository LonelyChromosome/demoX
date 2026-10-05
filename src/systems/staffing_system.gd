class_name StaffingSystem
extends RefCounted

const MAX_FARM_STAFF := 6
var building_system := BuildingSystem.new()


func operational_cells(core_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(core_cell.y - 1, core_cell.y + 2):
		for x in range(core_cell.x - 1, core_cell.x + 2):
			var cell := Vector2i(x, y)
			if cell != core_cell:
				cells.append(cell)
	return cells


func is_operational_square(building: BuildingState, cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < BuildingSystem.BOARD_SIZE
		and cell.y < BuildingSystem.BOARD_SIZE
		and cell in operational_cells(building.core_cell)
	)


func is_operational_cell_available(state: GameState, cell: Vector2i) -> bool:
	for candidate in state.buildings.values():
		if not (candidate is BuildingState):
			continue
		if candidate.phase in [GameEnums.BuildingPhase.ACTIVE, GameEnums.BuildingPhase.DEMOLISHING]:
			if is_operational_square(candidate, cell):
				return true
	return false


func active_farm_at(state: GameState, cell: Vector2i) -> BuildingState:
	for candidate in state.buildings.values():
		if (
			candidate is BuildingState
			and candidate.type == GameEnums.BuildingType.FARM
			and candidate.phase in [
				GameEnums.BuildingPhase.ACTIVE, GameEnums.BuildingPhase.DEMOLISHING
			]
			and cell in building_system.footprint(candidate.core_cell)
		):
			return candidate
	return null


func can_plan_farm_move(
	state: GameState,
	farm: BuildingState,
	unit_id: String,
	target: Vector2i,
	planned_targets: Dictionary
) -> bool:
	var count := 0
	var footprint := building_system.footprint(farm.core_cell)
	for candidate in state.units.values():
		if not _is_valid_farm_person(candidate):
			continue
		var final_cell: Vector2i = planned_targets.get(candidate.id, candidate.board_cell)
		if candidate.id == unit_id:
			final_cell = target
		if final_cell in footprint:
			count += 1
	return count <= MAX_FARM_STAFF


func sync_active_farms_from_positions(state: GameState, result: TurnResolutionResult) -> void:
	var farm_ids: Array[String] = []
	var old_roles := {}
	for candidate in state.buildings.values():
		if (
			candidate is BuildingState
			and candidate.type == GameEnums.BuildingType.FARM
			and candidate.phase in [
				GameEnums.BuildingPhase.ACTIVE, GameEnums.BuildingPhase.DEMOLISHING
			]
		):
			farm_ids.append(candidate.id)
			if not candidate.manager_unit_id.is_empty():
				old_roles[candidate.manager_unit_id] = {"building_id": candidate.id, "role": "manager"}
			for worker_id in candidate.worker_unit_ids:
				old_roles[worker_id] = {"building_id": candidate.id, "role": "worker"}
	farm_ids.sort()

	for unit in state.units.values():
		if unit is UnitState and (old_roles.has(unit.id) or unit.work_building_id in farm_ids):
			unit.work_building_id = ""
			unit.is_manager = false

	var new_roles := {}
	for farm_id in farm_ids:
		var farm := state.buildings.get(farm_id) as BuildingState
		farm.manager_unit_id = ""
		farm.worker_unit_ids.clear()
		farm.job_slots.clear()

		var core_unit := _valid_unit_at(state, farm.core_cell)
		if core_unit != null:
			farm.manager_unit_id = core_unit.id
			farm.job_slots[farm.core_cell] = GameEnums.JobRole.MANAGER
			core_unit.work_building_id = farm.id
			core_unit.is_manager = true
			new_roles[core_unit.id] = {"building_id": farm.id, "role": "manager"}

		var worker_ids: Array[String] = []
		for cell in operational_cells(farm.core_cell):
			var worker := _valid_unit_at(state, cell)
			if worker != null:
				worker_ids.append(worker.id)
		worker_ids.sort()
		var remaining := MAX_FARM_STAFF - (1 if core_unit != null else 0)
		for worker_index in range(mini(remaining, worker_ids.size())):
			var worker_id := worker_ids[worker_index]
			var worker := state.units.get(worker_id) as UnitState
			farm.worker_unit_ids.append(worker_id)
			farm.job_slots[worker.board_cell] = GameEnums.JobRole.FARM_WORKER
			worker.work_building_id = farm.id
			worker.is_manager = false
			new_roles[worker_id] = {"building_id": farm.id, "role": "worker"}

	_record_farm_role_changes(state, old_roles, new_roles, result)


func _record_farm_role_changes(
	state: GameState, old_roles: Dictionary, new_roles: Dictionary, result: TurnResolutionResult
) -> void:
	for unit_id in old_roles:
		if not new_roles.has(unit_id) or new_roles[unit_id] != old_roles[unit_id]:
			var unit := state.units.get(unit_id) as UnitState
			result.farm_role_changes.append({
				"unit_id": unit_id,
				"unit_name": _unit_name(unit, unit_id),
				"building_id": old_roles[unit_id].building_id,
				"role": old_roles[unit_id].role,
				"started": false,
			})
	for unit_id in new_roles:
		if not old_roles.has(unit_id) or old_roles[unit_id] != new_roles[unit_id]:
			var unit := state.units.get(unit_id) as UnitState
			result.farm_role_changes.append({
				"unit_id": unit_id,
				"unit_name": _unit_name(unit, unit_id),
				"building_id": new_roles[unit_id].building_id,
				"role": new_roles[unit_id].role,
				"started": true,
			})


func _valid_unit_at(state: GameState, cell: Vector2i) -> UnitState:
	for candidate in state.units.values():
		if _is_valid_farm_person(candidate) and candidate.board_cell == cell:
			return candidate
	return null


func _is_valid_farm_person(candidate: Variant) -> bool:
	return (
		candidate is UnitState
		and candidate.faction == GameEnums.Faction.PLAYER
		and not candidate.locked_by_construction
		and not candidate.locked_by_healing
		and candidate.away_days_left <= 0
		and candidate.away_assignment_id.is_empty()
		and not candidate.return_pending
		and not candidate.is_in_promotion_training()
	)


func _unit_name(unit: UnitState, fallback: String) -> String:
	if unit != null and not unit.display_name.is_empty():
		return unit.display_name
	return fallback


func validate_orders(
	state: GameState,
	orders: Array[SetBuildingStaffOrder],
	result: TurnResolutionResult
) -> Array[SetBuildingStaffOrder]:
	var valid: Array[SetBuildingStaffOrder] = []
	var planned_owner := {}
	for order in orders:
		if order == null:
			result.reject("staffing", "", "Lệnh không còn tồn tại")
			continue
		var building := state.buildings.get(order.building_id) as BuildingState
		if building == null:
			result.reject("staffing", order.building_id, "Công trình không tồn tại")
			continue
		if building.phase != GameEnums.BuildingPhase.ACTIVE:
			result.reject("staffing", order.building_id, "Chỉ được phân công tại công trình đang hoạt động")
			continue
		if building.type not in [GameEnums.BuildingType.FARM, GameEnums.BuildingType.MATERIAL_WORKSHOP]:
			result.reject("staffing", order.building_id, "Công trình này chưa hỗ trợ phân công")
			continue

		var manager_id := order.manager_unit_id
		var normalized_slots := order.job_slots.duplicate(true)
		var has_explicit_slots := not order.job_slots.is_empty()
		if not manager_id.is_empty():
			var manager_validation := _validate_unit(state, building, manager_id, true)
			if not manager_validation.valid:
				result.reject("staffing", order.building_id, manager_validation.reason)
				continue
			var manager := state.units.get(manager_id) as UnitState
			var manager_role := (
				GameEnums.JobRole.WORKSHOP_MANAGER
				if building.type == GameEnums.BuildingType.MATERIAL_WORKSHOP
				else GameEnums.JobRole.MANAGER
			)
			if not has_explicit_slots:
				normalized_slots[manager.board_cell] = manager_role
			elif normalized_slots.get(manager.board_cell, GameEnums.JobRole.NONE) != manager_role:
				result.reject("staffing", order.building_id, "Quản lý chưa đứng đúng vị trí công việc")
				continue

		var workers: Array[String] = []
		var worker_seen := {}
		if building.type == GameEnums.BuildingType.FARM:
			var invalid_worker := false
			for worker_id in order.worker_unit_ids:
				if worker_id == manager_id or worker_seen.has(worker_id):
					continue
				worker_seen[worker_id] = true
				workers.append(worker_id)
				var worker_validation := _validate_unit(state, building, worker_id, false)
				if not worker_validation.valid:
					result.reject("staffing", order.building_id, worker_validation.reason)
					workers.clear()
					invalid_worker = true
					break
				var worker := state.units.get(worker_id) as UnitState
				if not has_explicit_slots:
					normalized_slots[worker.board_cell] = GameEnums.JobRole.FARM_WORKER
				elif normalized_slots.get(worker.board_cell, GameEnums.JobRole.NONE) != GameEnums.JobRole.FARM_WORKER:
					result.reject("staffing", order.building_id, "Lao động chưa đứng đúng vị trí công việc")
					workers.clear()
					invalid_worker = true
					break
			if invalid_worker:
				continue
			if (1 if not manager_id.is_empty() else 0) + workers.size() > MAX_FARM_STAFF:
				result.reject("staffing", order.building_id, "Nông trại tối đa 6 người")
				continue

		var assigned_ids: Array[String] = []
		if not manager_id.is_empty():
			assigned_ids.append(manager_id)
		assigned_ids.append_array(workers)
		var conflicts := false
		for unit_id in assigned_ids:
			if planned_owner.has(unit_id) and planned_owner[unit_id] != order.building_id:
				conflicts = true
				break
		if conflicts:
			result.reject("staffing", order.building_id, "Một quân không thể làm việc tại hai công trình")
			continue
		for unit_id in assigned_ids:
			planned_owner[unit_id] = order.building_id
		valid.append(
			SetBuildingStaffOrder.new(
				order.building_id, manager_id, workers, order.planned_day, normalized_slots
			)
		)
	return valid


func commit(
	state: GameState, orders: Array[SetBuildingStaffOrder], result: TurnResolutionResult
) -> void:
	var planned := {}
	for order in orders:
		planned[order.building_id] = order

	var assignments := {}
	var supported_building_ids: Array[String] = []
	for candidate in state.buildings.values():
		if not (candidate is BuildingState):
			continue
		if candidate.phase != GameEnums.BuildingPhase.ACTIVE:
			continue
		if not _supports_staffing(candidate):
			continue
		supported_building_ids.append(candidate.id)
		supported_building_ids.sort()
		if planned.has(candidate.id):
			var planned_order := planned[candidate.id] as SetBuildingStaffOrder
			assignments[candidate.id] = {
				"manager": planned_order.manager_unit_id,
				"workers": planned_order.worker_unit_ids.duplicate(),
				"slots": planned_order.job_slots.duplicate(true),
			}
		else:
			assignments[candidate.id] = {
				"manager": candidate.manager_unit_id,
				"workers": candidate.worker_unit_ids.duplicate(),
				"slots": candidate.job_slots.duplicate(true),
			}

	var planned_units := {}
	for order in orders:
		if not order.manager_unit_id.is_empty():
			planned_units[order.manager_unit_id] = true
		for worker_id in order.worker_unit_ids:
			planned_units[worker_id] = true
	for building_id in supported_building_ids:
		if planned.has(building_id):
			continue
		var assignment: Dictionary = assignments[building_id]
		if planned_units.has(assignment.manager):
			assignment.manager = ""
		var retained_workers: Array[String] = []
		for worker_id in assignment.workers:
			if not planned_units.has(worker_id):
				retained_workers.append(worker_id)
		assignment.workers = retained_workers
	for candidate in state.buildings.values():
		if not (candidate is BuildingState) or planned.has(candidate.id):
			continue
		if planned_units.has(candidate.manager_unit_id):
			candidate.manager_unit_id = ""
		var retained_candidate_workers: Array[String] = []
		for worker_id in candidate.worker_unit_ids:
			if not planned_units.has(worker_id):
				retained_candidate_workers.append(worker_id)
		candidate.worker_unit_ids = retained_candidate_workers

	var old_staff_ids := {}
	for building_id in supported_building_ids:
		var old_building := state.buildings.get(building_id) as BuildingState
		if not old_building.manager_unit_id.is_empty():
			old_staff_ids[old_building.manager_unit_id] = true
		for worker_id in old_building.worker_unit_ids:
			old_staff_ids[worker_id] = true
	var owners := {}
	for candidate_unit in state.units.values():
		if not (candidate_unit is UnitState):
			continue
		var unit := candidate_unit as UnitState
		var has_work_ref: bool = not unit.work_building_id.is_empty()
		if (
			old_staff_ids.has(unit.id)
			or (
				has_work_ref
				and (
					unit.work_building_id in assignments
					or not state.buildings.has(unit.work_building_id)
				)
			)
		):
			unit.is_manager = false
			unit.work_building_id = ""
	for building_id in supported_building_ids:
		var building := state.buildings.get(building_id) as BuildingState
		building.manager_unit_id = ""
		building.worker_unit_ids.clear()
		building.job_slots.clear()
		var assignment: Dictionary = assignments[building_id]
		for cell in assignment.slots:
			if assignment.slots[cell] != GameEnums.JobRole.NONE:
				building.job_slots[cell] = assignment.slots[cell]

	for building_id in supported_building_ids:
		var target := state.buildings.get(building_id) as BuildingState
		var assignment: Dictionary = assignments[building_id]
		var manager_id: String = assignment.manager
		if not manager_id.is_empty() and _claim_unit(state, owners, manager_id, building_id):
			target.manager_unit_id = manager_id
			var manager := state.units.get(manager_id) as UnitState
			manager.work_building_id = building_id
			manager.is_manager = true
			target.job_slots[manager.board_cell] = (
				GameEnums.JobRole.WORKSHOP_MANAGER
				if target.type == GameEnums.BuildingType.MATERIAL_WORKSHOP
				else GameEnums.JobRole.MANAGER
			)
		for worker_id in assignment.workers:
			if worker_id == manager_id:
				continue
			if not _claim_unit(state, owners, worker_id, building_id):
				continue
			target.worker_unit_ids.append(worker_id)
			var worker := state.units.get(worker_id) as UnitState
			worker.work_building_id = building_id
			worker.is_manager = false
			target.job_slots[worker.board_cell] = GameEnums.JobRole.FARM_WORKER
	if not orders.is_empty():
		for order in orders:
			result.staffing_committed_building_ids.append(order.building_id)


func _validate_unit(
	state: GameState, building: BuildingState, unit_id: String, manager: bool
) -> Dictionary:
	var unit := state.units.get(unit_id) as UnitState
	if unit == null:
		return {"valid": false, "reason": "Quân cờ không tồn tại"}
	if unit.faction != GameEnums.Faction.PLAYER:
		return {"valid": false, "reason": "Chỉ quân phe ta mới được phân công"}
	if manager and unit.rank == GameEnums.Rank.KING:
		return {"valid": false, "reason": "Vua không được làm quản lý"}
	if unit.locked_by_construction:
		return {"valid": false, "reason": "Quân đang bị khóa vì xây dựng"}
	if (
		unit.locked_by_healing
		or unit.away_days_left > 0
		or not unit.away_assignment_id.is_empty()
		or unit.return_pending
		or unit.is_in_promotion_training()
	):
		return {"valid": false, "reason": "Quân hiện không thể nhận công việc"}
	if not is_operational_square(building, unit.board_cell):
		return {"valid": false, "reason": "Quân phải đứng trong vùng vận hành"}
	return {"valid": true, "reason": "Quân hợp lệ"}


func _supports_staffing(building: BuildingState) -> bool:
	return building.type in [GameEnums.BuildingType.FARM, GameEnums.BuildingType.MATERIAL_WORKSHOP]


func _claim_unit(state: GameState, owners: Dictionary, unit_id: String, building_id: String) -> bool:
	var unit := state.units.get(unit_id) as UnitState
	if unit == null or unit.faction != GameEnums.Faction.PLAYER:
		return false
	if owners.has(unit_id):
		return false
	owners[unit_id] = building_id
	return true
