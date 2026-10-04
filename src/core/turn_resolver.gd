class_name TurnResolver
extends RefCounted

signal phase_started(phase: Phase)

var food_system := FoodSystem.new()
var material_system := MaterialSystem.new()
var staffing_system := StaffingSystem.new()

enum Phase {
	VALIDATE_ORDERS,
	COMMIT_MOVEMENT,
	COMMIT_BUILDING_PLACEMENT,
	COMMIT_CANCEL_CONSTRUCTION,
	COMMIT_DEMOLITION,
	COMMIT_STAFFING,
	RESOLVE_SYSTEMS,
	FOOD_CONSUMPTION,
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
	var valid_moves := _validate_moves(
		state, snapshot.move_orders, building_system, snapshot.demolish_building_order, result
	)
	var valid_buildings := _validate_buildings(
		state, snapshot.building_orders, valid_moves, building_system, result
	)
	var valid_cancel := _validate_cancel(state, snapshot.cancel_construction_order, result)
	var valid_demolition := _validate_demolition(
		state, snapshot.demolish_building_order, building_system, result
	)

	_run_phase(Phase.COMMIT_MOVEMENT, result)
	_commit_moves(state, valid_moves, result)

	_run_phase(Phase.COMMIT_BUILDING_PLACEMENT, result)
	for building_order in valid_buildings:
		_commit_building(state, building_order, building_system, result)

	_run_phase(Phase.COMMIT_CANCEL_CONSTRUCTION, result)
	_commit_cancel(state, valid_cancel, building_system, result)
	_commit_reassignments(state, snapshot.assign_builder_orders, building_system, result)
	_commit_builder_removals(state, snapshot.remove_builder_orders, building_system, result)

	_run_phase(Phase.COMMIT_DEMOLITION, result)
	_commit_demolition(state, valid_demolition, building_system, result)

	_run_phase(Phase.RESOLVE_SYSTEMS, result)
	_resolve_systems(state, building_system, result)
	_run_phase(Phase.FOOD_CONSUMPTION, result)
	if not food_system.resolve_consumption(state, result, building_system):
		return result
	_finish_resolution(state, building_system, result)
	return result


func resume_after_ration(
	state: GameState,
	_snapshot: PendingOrderSnapshot,
	building_system: BuildingSystem,
	result: TurnResolutionResult,
	fed_unit_ids: Array[String]
) -> TurnResolutionResult:
	if not result.awaiting_ration:
		return result
	if not food_system.apply_ration(state, result, fed_unit_ids, building_system):
		return result
	_finish_resolution(state, building_system, result)
	return result


func _finish_resolution(
	state: GameState,
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> void:
	_run_phase(Phase.RESOLVE_EVENTS, result)
	_resolve_events(state, result)

	_run_phase(Phase.FINALIZE_DEMOLITION, result)
	_finalize_demolition(state, building_system, result)

	_run_phase(Phase.COMMIT_STAFFING, result)
	var valid_staffing := staffing_system.validate_orders(state, snapshot.staffing_orders, result)
	staffing_system.commit(state, valid_staffing, result)

	_run_phase(Phase.FINALIZE_DAY, result)
	state.day_one_full_knowledge = false
	if state.day < GameState.MAX_DAYS:
		state.day += 1
	result.next_day = state.day

	_run_phase(Phase.START_NEXT_DAY, result)
	_start_next_day(state, result)


func _validate_moves(
	state: GameState,
	orders: Array[MoveUnitOrder],
	building_system: BuildingSystem,
	demolition_order: DemolishBuildingOrder,
	result: TurnResolutionResult
) -> Array[MoveUnitOrder]:
	var preliminary: Array[MoveUnitOrder] = []
	for order in orders:
		if order == null:
			result.reject("move", "", "Lệnh không còn tồn tại")
			continue
		var unit := state.units.get(order.unit_id) as UnitState
		if unit == null:
			result.reject("move", order.unit_id, "Quân cờ không còn tồn tại")
			continue
		if not unit.can_be_moved():
			result.reject("move", order.unit_id, "Quân cờ đang bị khóa thao tác")
			continue
		if unit.board_cell != order.origin:
			result.reject("move", order.unit_id, "Vị trí ban đầu của quân đã thay đổi")
			continue
		if not building_system.is_inside_board(order.target):
			result.reject("move", order.unit_id, "Vị trí đích nằm ngoài bàn cờ")
			continue
		if building_system.is_cell_occupied_by_building(state, order.target):
			var core_building := building_system.building_at_cell(state, order.target)
			var is_active_farm_core := (
				core_building != null
				and core_building.type == GameEnums.BuildingType.FARM
				and core_building.phase == GameEnums.BuildingPhase.ACTIVE
				and core_building.core_cell == order.target
				and (demolition_order == null or demolition_order.building_id != core_building.id)
			)
			if not is_active_farm_core:
				result.reject("move", order.unit_id, "Ô lõi công trình không thể đi vào")
				continue
		preliminary.append(order)

	var destination_counts := {}
	for order in preliminary:
		destination_counts[order.target] = int(destination_counts.get(order.target, 0)) + 1

	var valid: Array[MoveUnitOrder] = []
	for order in preliminary:
		if destination_counts[order.target] > 1:
			result.reject("move", order.unit_id, "Nhiều quân đang cùng nhắm tới một ô")
		else:
			valid.append(order)

	var changed := true
	while changed:
		changed = false
		var moving_ids := {}
		for order in valid:
			moving_ids[order.unit_id] = true
		for index in range(valid.size() - 1, -1, -1):
			var order := valid[index]
			var occupant_id := _unit_id_at(state, order.target, order.unit_id)
			if not occupant_id.is_empty() and not moving_ids.has(occupant_id):
				result.reject("move", order.unit_id, "Ô đích vẫn còn quân")
				valid.remove_at(index)
				changed = true
	return _filter_farm_capacity(state, valid, result)


func _filter_farm_capacity(
	state: GameState,
	orders: Array[MoveUnitOrder],
	result: TurnResolutionResult
) -> Array[MoveUnitOrder]:
	var counts := {}
	for unit in state.units.values():
		if not (unit is UnitState) or unit.faction != GameEnums.Faction.PLAYER:
			continue
		var farm := staffing_system.active_farm_at(state, unit.board_cell)
		if farm != null:
			counts[farm.id] = int(counts.get(farm.id, 0)) + 1

	for order in orders:
		var unit := state.units.get(order.unit_id) as UnitState
		if unit == null or unit.faction != GameEnums.Faction.PLAYER:
			continue
		var origin_farm := staffing_system.active_farm_at(state, order.origin)
		var target_farm := staffing_system.active_farm_at(state, order.target)
		if origin_farm != null and (target_farm == null or target_farm.id != origin_farm.id):
			counts[origin_farm.id] = maxi(0, int(counts.get(origin_farm.id, 0)) - 1)

	var accepted: Array[MoveUnitOrder] = []
	for order in orders:
		var unit := state.units.get(order.unit_id) as UnitState
		var origin_farm := staffing_system.active_farm_at(state, order.origin)
		var target_farm := staffing_system.active_farm_at(state, order.target)
		var enters_new_farm := (
			unit != null
			and unit.faction == GameEnums.Faction.PLAYER
			and target_farm != null
			and (origin_farm == null or origin_farm.id != target_farm.id)
		)
		if enters_new_farm and int(counts.get(target_farm.id, 0)) >= StaffingSystem.MAX_FARM_STAFF:
			result.reject("move", order.unit_id, "Nông trại đã đủ 6 người")
			if origin_farm != null:
				counts[origin_farm.id] = int(counts.get(origin_farm.id, 0)) + 1
			continue
		if enters_new_farm:
			counts[target_farm.id] = int(counts.get(target_farm.id, 0)) + 1
		accepted.append(order)
	return accepted

func _validate_buildings(
	state: GameState,
	orders: Array[PlaceBuildingOrder],
	valid_moves: Array[MoveUnitOrder],
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> Array[PlaceBuildingOrder]:
	var valid: Array[PlaceBuildingOrder] = []
	var targets: Array = []
	for move in valid_moves:
		targets.append(move.target)
	var reserved_cores: Array[Vector2i] = []
	var materials_left := state.materials
	var planned_builder_owner := {}
	for order in orders:
		if order == null:
			result.reject("building", "", "Lệnh không còn tồn tại")
			continue
		var validation := building_system.validate_placement(
			state, order.core_cell, targets, reserved_cores
		)
		if not validation.valid:
			result.reject("building", order.building_id, validation.reason)
			continue
		if state.buildings.has(order.building_id):
			result.reject("building", order.building_id, "Mã công trình đã tồn tại")
			continue
		if not order.builder_unit_ids.is_empty():
			var builders := building_system.validate_builders(state, order.builder_unit_ids)
			if not builders.valid:
				result.reject("building", order.building_id, builders.reason)
				continue
		var builder_conflict := false
		for builder_id in order.builder_unit_ids:
			if planned_builder_owner.has(builder_id):
				builder_conflict = true
				break
		if builder_conflict:
			result.reject("building", order.building_id, "Thợ xây đã được phân cho công trình dự kiến khác")
			continue
		var cost := building_system.material_cost(order.building_type)
		if materials_left < cost:
			result.reject("building", order.building_id, "Không đủ vật tư")
			continue
		materials_left -= cost
		for builder_id in order.builder_unit_ids:
			planned_builder_owner[builder_id] = order.building_id
		reserved_cores.append(order.core_cell)
		valid.append(order)
	return valid


func _unit_id_at(state: GameState, cell: Vector2i, moving_unit_id: String) -> String:
	for candidate in state.units.values():
		if candidate is UnitState and candidate.id != moving_unit_id and candidate.board_cell == cell:
			return candidate.id
	return ""


func _commit_moves(
	state: GameState, orders: Array[MoveUnitOrder], result: TurnResolutionResult
) -> void:
	for order in orders:
		var unit := state.units.get(order.unit_id) as UnitState
		if unit == null:
			result.reject("move", order.unit_id, "Quân cờ không còn tồn tại khi chốt ngày")
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
	if order.builder_unit_ids.is_empty():
		building.phase = GameEnums.BuildingPhase.BLUEPRINT
		building.days_left = building_system.build_days(building.type, 1)
	else:
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
		result.reject("cancel_construction", order.building_id, "Công trình không tồn tại")
		return null
	if building.phase not in [GameEnums.BuildingPhase.BLUEPRINT, GameEnums.BuildingPhase.BUILDING]:
		result.reject("cancel_construction", order.building_id, "Chỉ được hủy bản vẽ hoặc công trình đang xây")
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
		result.reject("cancel_construction", order.building_id, "Trạng thái xây dựng đã thay đổi")
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
			result.reject("assign_builder", order.unit_id, "Công trình đã bị hủy trong ngày này")
			continue
		var assignment := building_system.reassign_builder_to_construction(
			state, order.building_id, order.unit_id, order.slot_cell
		)
		if not assignment.valid:
			result.reject("assign_builder", order.unit_id, assignment.reason)
		else:
			result.reassigned_builder_ids.append(order.unit_id)

func _commit_builder_removals(
	state: GameState,
	orders: Array[RemoveBuilderOrder],
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> void:
	for order in orders:
		var unit := state.units.get(order.unit_id) as UnitState
		var old_cell := unit.board_cell if unit != null else Vector2i(-1, -1)
		if not building_system.remove_builder_from_construction(
			state, order.building_id, order.unit_id
		):
			result.reject("remove_builder", order.unit_id, "Phân công thợ xây không tồn tại")
			continue
		var building := state.buildings.get(order.building_id) as BuildingState
		if building != null:
			building.job_slots.erase(old_cell)

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
		result.reject("demolition", order.building_id, "Trạng thái phá dỡ đã thay đổi")

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
