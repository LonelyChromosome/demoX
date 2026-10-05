class_name TurnResolver
extends RefCounted

signal phase_started(phase: Phase)

var food_system := FoodSystem.new()
var material_system := MaterialSystem.new()
var staffing_system := StaffingSystem.new()
var medical_system := MedicalSystem.new()
var prison_system := PrisonSystem.new()
var expedition_system := ExpeditionSystem.new()
var outside_system := OutsideSystem.new()
var world_system := WorldSystem.new()
var event_system := EventSystem.new()
var promotion_system := PromotionSystem.new()
var relationship_system := RelationshipSystem.new()
var loyalty_system := LoyaltySystem.new()
var perimeter_system := PerimeterSystem.new()
var ruin_system := RuinSystem.new()

enum Phase {
	VALIDATE_ORDERS,
	COMMIT_MOVEMENT,
	COMMIT_BUILDING_PLACEMENT,
	COMMIT_CANCEL_CONSTRUCTION,
	COMMIT_DEMOLITION,
	COMMIT_STAFFING,
	COMMIT_OUTSIDE_ORDERS,
	RESOLVE_SYSTEMS,
	FOOD_CONSUMPTION,
	RESOLVE_EVENTS,
	RESOLVE_WORLD,
	RESOLVE_INFORMATION,
	FINALIZE_DEMOLITION,
	FINALIZE_DAY,
	START_NEXT_DAY,
}


func _init() -> void:
	expedition_system.promotion_system = promotion_system
	expedition_system.relationship_system = relationship_system


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
	var blocked_unit_ids := _blocked_unit_ids(snapshot)
	var valid_promotions: Array[Dictionary] = []
	for promotion_order in snapshot.promotion_orders:
		var promotion_validation := promotion_system.validate_order(
			state, promotion_order, blocked_unit_ids
		)
		if not promotion_validation.valid:
			result.reject(
				"promotion", promotion_order.unit_id, promotion_validation.reason
			)
			continue
		valid_promotions.append({
			"order": promotion_order,
			"definition": promotion_validation.definition,
		})
		blocked_unit_ids[promotion_order.unit_id] = true
	var reserved_away_unit_ids := {}
	var valid_expedition := (
		snapshot.expedition_order != null
		and expedition_system.validate_order(
			state, snapshot.expedition_order, blocked_unit_ids,
			reserved_away_unit_ids, result
		)
	)
	var valid_outside_orders: Array[OutsiderDecisionOrder] = []
	for outside_order in snapshot.outsider_orders:
		if outside_system.validate_order(
			state, outside_order, blocked_unit_ids, reserved_away_unit_ids, result
		):
			valid_outside_orders.append(outside_order)
	var valid_wasteland := perimeter_system.validate_development(
		state, snapshot.develop_wasteland_order, blocked_unit_ids, reserved_away_unit_ids, result
	) if snapshot.develop_wasteland_order != null else false

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

	_run_phase(Phase.COMMIT_STAFFING, result)
	var valid_staffing := staffing_system.validate_orders(state, snapshot.staffing_orders, result)
	staffing_system.commit(state, valid_staffing, result)
	prison_system.commit_actions(state, snapshot.prisoner_action_orders, result)
	prison_system.commit_labor(state, snapshot.prisoner_labor_orders, result)
	for promotion in valid_promotions:
		if not promotion_system.commit_training(
			state, promotion.order, promotion.definition, result
		):
			result.reject("promotion", promotion.order.unit_id, "Không thể bắt đầu huấn luyện")

	_run_phase(Phase.COMMIT_OUTSIDE_ORDERS, result)
	if valid_expedition:
		expedition_system.commit(state, snapshot.expedition_order, result)
	for outside_order in valid_outside_orders:
		outside_system.commit_order(state, outside_order, result)
	if valid_wasteland:
		perimeter_system.commit_development(state, snapshot.develop_wasteland_order, result)
		result.wasteland_started = true

	_run_phase(Phase.RESOLVE_SYSTEMS, result)
	_resolve_systems(state, building_system, result)
	_run_phase(Phase.FOOD_CONSUMPTION, result)
	if not food_system.resolve_consumption(state, result, building_system):
		return result
	_finish_resolution(state, snapshot, building_system, result)
	return result


func resume_after_ration(
	state: GameState,
	snapshot: PendingOrderSnapshot,
	building_system: BuildingSystem,
	result: TurnResolutionResult,
	fed_unit_ids: Array[String]
) -> TurnResolutionResult:
	if not result.awaiting_ration:
		return result
	if not food_system.apply_ration(state, result, fed_unit_ids, building_system):
		return result
	_finish_resolution(state, snapshot, building_system, result)
	return result


func _finish_resolution(
	state: GameState,
	snapshot: PendingOrderSnapshot,
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> void:
	var skip_groups := {}
	for group_id in result.new_outsider_group_ids:
		skip_groups[group_id] = true
	for group_id in result.resettlement_started_group_ids:
		skip_groups[group_id] = true
	outside_system.resolve_daily(state, skip_groups, result)
	_run_phase(Phase.RESOLVE_WORLD, result)
	world_system.resolve_world(state, result)
	_run_phase(Phase.RESOLVE_EVENTS, result)
	_resolve_events(state, result)
	_run_phase(Phase.RESOLVE_INFORMATION, result)
	_capture_inspection(state, snapshot, building_system, result)

	_run_phase(Phase.FINALIZE_DEMOLITION, result)
	_finalize_demolition(state, building_system, result)

	_run_phase(Phase.FINALIZE_DAY, result)
	prison_system.finalize_day(state)
	state.day_one_full_knowledge = false
	if not state.game_over and state.day < GameState.MAX_DAYS:
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
		if ruin_system.is_blocked(state, order.target):
			result.reject("move", order.unit_id, "Ô đích vẫn bị Tàn cuộc chiếm")
			continue
		if unit.board_cell != order.origin:
			result.reject("move", order.unit_id, "Vị trí ban đầu của quân đã thay đổi")
			continue
		if not building_system.is_inside_board(order.target):
			result.reject("move", order.unit_id, "Vị trí đích nằm ngoài bàn cờ")
			continue
		var infirmary := medical_system.infirmary_at_slot(state, order.target)
		if infirmary != null and (unit.faction != GameEnums.Faction.PLAYER or not unit.injured):
			result.reject("move", order.unit_id, "Chỉ quân bị thương mới vào vị trí điều trị")
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
	result.building_events.append({
		"kind": "construction_started" if not order.builder_unit_ids.is_empty() else "blueprint_placed",
		"building_id": building.id,
		"type": building.type,
		"core": building.core_cell,
	})
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
	prison_system.apply_construction_bonus(state)
	result.completed_building_ids = building_system.advance_construction(state, skip_ids)
	building_system.unlock_builders(state, result.completed_building_ids)
	for building_id in result.completed_building_ids:
		var completed := state.buildings.get(building_id) as BuildingState
		if completed != null:
			result.building_events.append({
				"kind": "completed",
				"building_id": completed.id,
				"type": completed.type,
				"core": completed.core_cell,
			})
	staffing_system.sync_active_farms_from_positions(state, result)
	prison_system.sync_staffing(state, result)
	medical_system.sync_and_advance(state, result)
	food_system.produce(state, result)
	material_system.produce(state, result)
	var skip_expeditions := {}
	for expedition_id in result.committed_expedition_ids:
		skip_expeditions[expedition_id] = true
	expedition_system.advance(state, skip_expeditions, result)
	perimeter_system.resolve_daily(state, result.wasteland_started, result)
	promotion_system.advance_training(state, result)


func _blocked_unit_ids(snapshot: PendingOrderSnapshot) -> Dictionary:
	var blocked := {}
	for order in snapshot.move_orders:
		blocked[order.unit_id] = true
	for order in snapshot.building_orders:
		for unit_id in order.builder_unit_ids:
			blocked[unit_id] = true
	for order in snapshot.assign_builder_orders:
		blocked[order.unit_id] = true
	for order in snapshot.remove_builder_orders:
		blocked[order.unit_id] = true
	for order in snapshot.staffing_orders:
		if not order.manager_unit_id.is_empty():
			blocked[order.manager_unit_id] = true
		for unit_id in order.worker_unit_ids:
			blocked[unit_id] = true
	if snapshot.inspect_building_order != null:
		blocked[snapshot.inspect_building_order.king_unit_id] = true
	return blocked

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
	var building := state.buildings.get(order.building_id) as BuildingState
	var event := {}
	if building != null:
		event = {
			"kind": "cancelled",
			"building_id": building.id,
			"type": building.type,
			"core": building.core_cell,
		}
	prison_system.cleanup_cancelled_construction(state, order.building_id)
	var refund := building_system.cancel_construction(state, order.building_id)
	if refund < 0:
		result.reject("cancel_construction", order.building_id, "Trạng thái xây dựng đã thay đổi")
		return
	result.cancelled_building_ids.append(order.building_id)
	result.refunded_materials += refund
	if not event.is_empty():
		result.building_events.append(event)

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
		var building := state.buildings.get(order.building_id) as BuildingState
		var was_blueprint := (
			building != null and building.phase == GameEnums.BuildingPhase.BLUEPRINT
		)
		var assignment := building_system.reassign_builder_to_construction(
			state, order.building_id, order.unit_id, order.slot_cell
		)
		if not assignment.valid:
			result.reject("assign_builder", order.unit_id, assignment.reason)
		else:
			result.reassigned_builder_ids.append(order.unit_id)
			if was_blueprint and building != null:
				result.building_events.append({
					"kind": "construction_started",
					"building_id": building.id,
					"type": building.type,
					"core": building.core_cell,
				})

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
		var building := state.buildings.get(building_id) as BuildingState
		if building != null:
			result.building_events.append({
				"kind": "demolished",
				"building_id": building.id,
				"type": building.type,
				"core": building.core_cell,
			})
		if building_system.finalize_demolition(state, building_id):
			result.demolished_building_ids.append(building_id)


func _resolve_events(state: GameState, result: TurnResolutionResult) -> void:
	event_system.advance(state, result)


func _start_next_day(_state: GameState, _result: TurnResolutionResult) -> void:
	pass


func _capture_inspection(
	state: GameState,
	snapshot: PendingOrderSnapshot,
	building_system: BuildingSystem,
	result: TurnResolutionResult
) -> void:
	var order := snapshot.inspect_building_order
	if order == null:
		return
	var king := state.units.get(order.king_unit_id) as UnitState
	var building := state.buildings.get(order.building_id) as BuildingState
	if king == null or not king.can_manage_city():
		result.reject("inspection", order.building_id, "Không còn Vua hợp lệ để kiểm tra")
		return
	if building == null:
		result.reject("inspection", order.building_id, "Công trình không còn tồn tại")
		return
	if state.last_inspection_day == order.planned_day:
		result.reject("inspection", order.building_id, "Vua đã dùng quyền kiểm tra trong ngày")
		return
	var manager := state.units.get(building.manager_unit_id) as UnitState
	var staff := {}
	if manager != null:
		staff[manager.id] = true
	for worker_id in building.worker_unit_ids:
		staff[worker_id] = true
	result.inspection_snapshots.append({
		"building_id": building.id,
		"king_unit_id": king.id,
		"inspected_day": result.resolved_day,
		"delivered_day": result.resolved_day + 1,
		"category": _inspection_category(building),
		"values": {
			"type": building.type,
			"core_cell": building.core_cell,
			"phase": building.phase,
			"days_left": building.days_left,
			"builder_count": building.builder_unit_ids.size(),
			"manager_name": (
				manager.display_name if manager != null and not manager.display_name.is_empty()
				else (manager.id if manager != null else "—")
			),
			"staff_count": staff.size(),
			"daily_output": _inspection_output(state, building),
			"patient_count": building.patient_unit_ids.size(),
			"prisoner_count": building.prisoner_unit_ids.size(),
			"guard_count": prison_system.guard_count(building),
			"under_guarded": building.under_guarded,
			"prisoner_labor_count": _prisoner_labor_count(state, building),
			"prisoners": _prisoner_summaries(state, building),
			"prisoner_ids": building.prisoner_unit_ids.duplicate(),
			"confirmed_food": state.food if building.type == GameEnums.BuildingType.FARM else -1,
			"confirmed_materials": state.materials if building.type == GameEnums.BuildingType.MATERIAL_WORKSHOP else -1,
			"confirmed_troops": state.player_roster_count() if building.type == GameEnums.BuildingType.BARRACKS else -1,
		},
	})
	state.last_inspection_day = order.planned_day
	result.inspected_building_ids.append(building.id)


func _inspection_category(building: BuildingState) -> String:
	if building.type == GameEnums.BuildingType.FARM:
		return "food"
	if building.type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
		return "materials"
	if building.type == GameEnums.BuildingType.BARRACKS:
		return "troops"
	if building.type == GameEnums.BuildingType.INFIRMARY:
		return "medical"
	return "prison"


func _inspection_output(state: GameState, building: BuildingState) -> int:
	if building.type == GameEnums.BuildingType.FARM:
		return food_system.production_for_building(state, building)
	if building.type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
		return material_system.manager_output(state, building)
	return 0


func _prisoner_labor_count(state: GameState, building: BuildingState) -> int:
	var count := 0
	for unit_id in building.prisoner_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null and unit.prisoner_labor:
			count += 1
	return count


func _prisoner_summaries(state: GameState, building: BuildingState) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for unit_id in building.prisoner_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		summaries.append({
			"name": unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank),
			"rank": unit.rank,
			"labor": unit.prisoner_labor,
		})
	return summaries


func _rank_name(rank: int) -> String:
	return ["Tốt", "Mã", "Xe", "Tịnh", "Hậu", "Vua"][rank]


func _run_phase(phase: Phase, result: TurnResolutionResult) -> void:
	result.phase_trace.append(phase)
	phase_started.emit(phase)
