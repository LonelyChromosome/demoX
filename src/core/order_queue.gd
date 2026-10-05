class_name OrderQueue
extends RefCounted

signal changed

var _move_orders: Dictionary = {}
var _building_orders: Dictionary = {}
var _building_sequence: Array[String] = []
var _cancel_construction_order: CancelConstructionOrder
var _assign_builder_orders: Dictionary = {}
var _remove_builder_orders: Dictionary = {}
var _demolish_building_order: DemolishBuildingOrder
var _staffing_orders: Dictionary = {}
var _planned_job_slots: Dictionary = {}
var _planned_builder_cells: Dictionary = {}
var _inspect_building_order: InspectBuildingOrder
var _prisoner_labor_orders: Dictionary = {}
var _prisoner_action_orders: Dictionary = {}
var _expedition_order: DispatchExpeditionOrder
var _outsider_orders: Dictionary = {}


func plan_move(
	unit_id: String, origin: Vector2i, target: Vector2i, day: int
) -> MoveUnitOrder:
	var order := MoveUnitOrder.new(unit_id, origin, target, day)
	_move_orders[unit_id] = order
	changed.emit()
	return order


func cancel_move(unit_id: String) -> void:
	if _move_orders.erase(unit_id):
		changed.emit()


func get_move(unit_id: String) -> MoveUnitOrder:
	return _move_orders.get(unit_id) as MoveUnitOrder


func plan_inspection(building_id: String, king_unit_id: String, day: int) -> InspectBuildingOrder:
	_inspect_building_order = InspectBuildingOrder.new(building_id, king_unit_id, day)
	changed.emit()
	return _inspect_building_order


func cancel_inspection() -> void:
	if _inspect_building_order != null:
		_inspect_building_order = null
		changed.emit()


func get_inspection() -> InspectBuildingOrder:
	return _inspect_building_order


func has_inspection_for_unit(unit_id: String) -> bool:
	return _inspect_building_order != null and _inspect_building_order.king_unit_id == unit_id


func plan_prisoner_labor(
	prisoner_id: String, building_id: String, day: int
) -> AssignPrisonerLaborOrder:
	var order := AssignPrisonerLaborOrder.new(prisoner_id, building_id, day)
	_prisoner_labor_orders[prisoner_id] = order
	changed.emit()
	return order


func cancel_prisoner_labor(prisoner_id: String) -> void:
	if _prisoner_labor_orders.erase(prisoner_id):
		changed.emit()


func plan_prisoner_action(
	prisoner_id: String, action: GameEnums.PrisonerAction, day: int
) -> PrisonerActionOrder:
	var order := PrisonerActionOrder.new(prisoner_id, action, day)
	_prisoner_action_orders[prisoner_id] = order
	changed.emit()
	return order


func cancel_prisoner_action(prisoner_id: String) -> void:
	if _prisoner_action_orders.erase(prisoner_id):
		changed.emit()


func plan_expedition(
	expedition_id: String, unit_ids: Array[String], day: int,
	target_region_id := "", supplies_food := 0
) -> DispatchExpeditionOrder:
	_expedition_order = DispatchExpeditionOrder.new(
		expedition_id, unit_ids, day, target_region_id, supplies_food
	)
	changed.emit()
	return _expedition_order


func cancel_expedition() -> void:
	if _expedition_order != null:
		_expedition_order = null
		changed.emit()


func get_expedition() -> DispatchExpeditionOrder:
	return _expedition_order


func plan_outsider_decision(
	group_id: String,
	action: GameEnums.OutsiderAction,
	escort_unit_ids: Array[String],
	king_unit_id: String,
	day: int
) -> OutsiderDecisionOrder:
	var order := OutsiderDecisionOrder.new(group_id, action, escort_unit_ids, king_unit_id, day)
	_outsider_orders[group_id] = order
	changed.emit()
	return order


func cancel_outsider_decision(group_id: String) -> void:
	if _outsider_orders.erase(group_id):
		changed.emit()


func get_outsider_decision(group_id: String) -> OutsiderDecisionOrder:
	return _outsider_orders.get(group_id) as OutsiderDecisionOrder


func move_targets() -> Dictionary:
	var targets := {}
	for unit_id in _move_orders:
		var order := _move_orders[unit_id] as MoveUnitOrder
		if order != null:
			targets[unit_id] = order.target
	return targets


func move_count() -> int:
	return _move_orders.size()


func plan_building(order: PlaceBuildingOrder) -> void:
	if not _building_orders.has(order.building_id):
		_building_sequence.append(order.building_id)
	_building_orders[order.building_id] = order
	changed.emit()


func cancel_building(building_id: String) -> void:
	if _building_orders.erase(building_id):
		_building_sequence.erase(building_id)
		_planned_job_slots.erase(building_id)
		for unit_id in _planned_builder_cells.keys():
			var assignment: Dictionary = _planned_builder_cells[unit_id]
			if assignment.building_id == building_id:
				_planned_builder_cells.erase(unit_id)
				_move_orders.erase(unit_id)
		changed.emit()


func get_building(building_id: String) -> PlaceBuildingOrder:
	return _building_orders.get(building_id) as PlaceBuildingOrder


func get_buildings() -> Array[PlaceBuildingOrder]:
	var result: Array[PlaceBuildingOrder] = []
	for building_id in _building_sequence:
		var order := get_building(building_id)
		if order != null:
			result.append(order)
	return result

func plan_cancel_construction(building_id: String) -> CancelConstructionOrder:
	_cancel_construction_order = CancelConstructionOrder.new(building_id)
	changed.emit()
	return _cancel_construction_order

func cancel_cancel_construction() -> void:
	if _cancel_construction_order != null:
		_cancel_construction_order = null
		changed.emit()

func get_cancel_construction() -> CancelConstructionOrder:
	return _cancel_construction_order

func plan_demolition(building_id: String) -> DemolishBuildingOrder:
	_demolish_building_order = DemolishBuildingOrder.new(building_id)
	changed.emit()
	return _demolish_building_order

func cancel_demolition() -> void:
	if _demolish_building_order != null:
		_demolish_building_order = null
		changed.emit()

func get_demolition() -> DemolishBuildingOrder:
	return _demolish_building_order

func plan_job_slot(building_id: String, cell: Vector2i, role: GameEnums.JobRole) -> void:
	var slots: Dictionary = _planned_job_slots.get(building_id, {})
	# NONE is an explicit tombstone so a planned clear can override authoritative slots.
	slots[cell] = role
	_planned_job_slots[building_id] = slots
	var building_order := get_building(building_id)
	if building_order != null:
		building_order.job_slots.clear()
		for slot_cell in slots:
			if slots[slot_cell] != GameEnums.JobRole.NONE:
				building_order.job_slots[slot_cell] = slots[slot_cell]
	var staffing := _staffing_orders.get(building_id) as SetBuildingStaffOrder
	if staffing != null:
		if role == GameEnums.JobRole.NONE:
			staffing.job_slots.erase(cell)
		else:
			staffing.job_slots[cell] = role
	changed.emit()

func planned_job_slots(building_id: String) -> Dictionary:
	return (_planned_job_slots.get(building_id, {}) as Dictionary).duplicate(true)

func add_planned_builder(building_id: String, unit_id: String, cell: Vector2i) -> bool:
	var building_order := get_building(building_id)
	if building_order == null:
		return false
	if not building_order.builder_unit_ids.has(unit_id):
		building_order.builder_unit_ids.append(unit_id)
	if _planned_builder_cells.has(unit_id):
		var old_assignment: Dictionary = _planned_builder_cells[unit_id]
		var old_cell: Vector2i = old_assignment.cell
		if old_cell != cell or old_assignment.building_id != building_id:
			var old_order := get_building(old_assignment.building_id)
			if old_order != null:
				old_order.builder_unit_ids.erase(unit_id)
				old_order.job_slots.erase(old_cell)
			var slots: Dictionary = _planned_job_slots.get(old_assignment.building_id, {})
			slots.erase(old_cell)
	_planned_builder_cells[unit_id] = {"building_id": building_id, "cell": cell}
	plan_job_slot(building_id, cell, GameEnums.JobRole.BUILDER)
	return true

func remove_planned_builder_at(building_id: String, cell: Vector2i) -> Array[String]:
	var removed: Array[String] = []
	var building_order := get_building(building_id)
	if building_order == null:
		return removed
	for unit_id in _planned_builder_cells.keys():
		var assignment: Dictionary = _planned_builder_cells[unit_id]
		if assignment.building_id == building_id and assignment.cell == cell:
			building_order.builder_unit_ids.erase(unit_id)
			_planned_builder_cells.erase(unit_id)
			removed.append(unit_id)
	return removed

func remove_planned_builder(unit_id: String) -> void:
	if not _planned_builder_cells.has(unit_id):
		return
	var assignment: Dictionary = _planned_builder_cells[unit_id]
	var old_cell: Vector2i = assignment.cell
	var building_order := get_building(assignment.building_id)
	_planned_builder_cells.erase(unit_id)
	if building_order == null:
		return
	building_order.builder_unit_ids.erase(unit_id)
	var slots: Dictionary = _planned_job_slots.get(building_order.building_id, {})
	slots.erase(old_cell)
	building_order.job_slots.erase(old_cell)
	changed.emit()

func plan_staffing(order: SetBuildingStaffOrder) -> void:
	_staffing_orders[order.building_id] = order
	var preview_slots := order.job_slots.duplicate(true)
	var existing: Dictionary = _planned_job_slots.get(order.building_id, {})
	for cell in existing:
		if existing[cell] == GameEnums.JobRole.NONE:
			preview_slots[cell] = GameEnums.JobRole.NONE
	_planned_job_slots[order.building_id] = preview_slots
	changed.emit()

func cancel_staffing(building_id: String) -> void:
	if _staffing_orders.erase(building_id):
		_planned_job_slots.erase(building_id)
		changed.emit()

func get_staffing(building_id: String) -> SetBuildingStaffOrder:
	return _staffing_orders.get(building_id) as SetBuildingStaffOrder

func plan_assign_builder(
	building_id: String, unit_id: String, cell := Vector2i(-1, -1)
) -> AssignBuilderOrder:
	var order := AssignBuilderOrder.new(building_id, unit_id, cell)
	_assign_builder_orders["%s:%s" % [building_id, unit_id]] = order
	changed.emit()
	return order

func plan_remove_builder(building_id: String, unit_id: String) -> RemoveBuilderOrder:
	var order := RemoveBuilderOrder.new(building_id, unit_id)
	_remove_builder_orders["%s:%s" % [building_id, unit_id]] = order
	changed.emit()
	return order

func cancel_assign_builder(building_id: String, unit_id: String) -> void:
	if _assign_builder_orders.erase("%s:%s" % [building_id, unit_id]):
		changed.emit()


func snapshot() -> PendingOrderSnapshot:
	var result := PendingOrderSnapshot.new()
	var unit_ids := _move_orders.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var order := _move_orders[unit_id] as MoveUnitOrder
		if order != null:
			result.move_orders.append(order.copy())
	for order in get_buildings():
		result.building_orders.append(order.copy())
	if _cancel_construction_order != null:
		result.cancel_construction_order = _cancel_construction_order.copy()
	if _demolish_building_order != null:
		result.demolish_building_order = _demolish_building_order.copy()
	if _inspect_building_order != null:
		result.inspect_building_order = _inspect_building_order.copy()
	if _expedition_order != null:
		result.expedition_order = _expedition_order.copy()
	var outsider_group_ids := _outsider_orders.keys()
	outsider_group_ids.sort()
	for group_id in outsider_group_ids:
		result.outsider_orders.append(
			(_outsider_orders[group_id] as OutsiderDecisionOrder).copy()
		)
	var prisoner_ids := _prisoner_labor_orders.keys()
	prisoner_ids.sort()
	for prisoner_id in prisoner_ids:
		result.prisoner_labor_orders.append(
			(_prisoner_labor_orders[prisoner_id] as AssignPrisonerLaborOrder).copy()
		)
	var action_ids := _prisoner_action_orders.keys()
	action_ids.sort()
	for prisoner_id in action_ids:
		result.prisoner_action_orders.append(
			(_prisoner_action_orders[prisoner_id] as PrisonerActionOrder).copy()
		)
	var staffing_ids := _staffing_orders.keys()
	staffing_ids.sort()
	for building_id in staffing_ids:
		var order := _staffing_orders[building_id] as SetBuildingStaffOrder
		if order != null:
			result.staffing_orders.append(order.copy())
	for building_id in _assign_builder_orders:
		result.assign_builder_orders.append((_assign_builder_orders[building_id] as AssignBuilderOrder).copy())
	for key in _remove_builder_orders:
		result.remove_builder_orders.append((_remove_builder_orders[key] as RemoveBuilderOrder).copy())
	return result


func clear() -> void:
	var had_orders := not is_empty()
	_move_orders.clear()
	_building_orders.clear()
	_building_sequence.clear()
	_cancel_construction_order = null
	_demolish_building_order = null
	_inspect_building_order = null
	_expedition_order = null
	_outsider_orders.clear()
	_prisoner_labor_orders.clear()
	_prisoner_action_orders.clear()
	_staffing_orders.clear()
	_planned_job_slots.clear()
	_planned_builder_cells.clear()
	_assign_builder_orders.clear()
	_remove_builder_orders.clear()
	if had_orders:
		changed.emit()


func is_empty() -> bool:
	return (
		_move_orders.is_empty()
		and _building_orders.is_empty()
		and _cancel_construction_order == null
		and _demolish_building_order == null
		and _inspect_building_order == null
		and _expedition_order == null
		and _outsider_orders.is_empty()
		and _prisoner_labor_orders.is_empty()
		and _prisoner_action_orders.is_empty()
		and _staffing_orders.is_empty()
		and _assign_builder_orders.is_empty()
		and _remove_builder_orders.is_empty()
		and _planned_job_slots.is_empty()
	)
