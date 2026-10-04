class_name OrderQueue
extends RefCounted

signal changed

var _move_orders: Dictionary = {}
var _building_order: PlaceBuildingOrder
var _cancel_construction_order: CancelConstructionOrder
var _assign_builder_orders: Dictionary = {}
var _remove_builder_orders: Dictionary = {}
var _demolish_building_order: DemolishBuildingOrder
var _staffing_orders: Dictionary = {}
var _planned_job_slots: Dictionary = {}
var _planned_builder_cells: Dictionary = {}


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
	if _building_order != null and _building_order.building_id != order.building_id:
		_planned_job_slots.erase(_building_order.building_id)
		_planned_builder_cells.clear()
	_building_order = order
	changed.emit()


func cancel_building() -> void:
	if _building_order != null:
		_planned_job_slots.erase(_building_order.building_id)
		_planned_builder_cells.clear()
		_building_order = null
		changed.emit()


func get_building() -> PlaceBuildingOrder:
	return _building_order

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
	if _building_order != null and _building_order.building_id == building_id:
		_building_order.job_slots.clear()
		for slot_cell in slots:
			if slots[slot_cell] != GameEnums.JobRole.NONE:
				_building_order.job_slots[slot_cell] = slots[slot_cell]
	var staffing := _staffing_orders.get(building_id) as SetBuildingStaffOrder
	if staffing != null:
		if role == GameEnums.JobRole.NONE:
			staffing.job_slots.erase(cell)
		else:
			staffing.job_slots[cell] = role
	changed.emit()

func planned_job_slots(building_id: String) -> Dictionary:
	return (_planned_job_slots.get(building_id, {}) as Dictionary).duplicate(true)

func add_planned_builder(unit_id: String, cell: Vector2i) -> bool:
	if _building_order == null:
		return false
	if not _building_order.builder_unit_ids.has(unit_id):
		_building_order.builder_unit_ids.append(unit_id)
	if _planned_builder_cells.has(unit_id):
		var old_cell: Vector2i = _planned_builder_cells[unit_id]
		if old_cell != cell:
			var slots: Dictionary = _planned_job_slots.get(_building_order.building_id, {})
			slots.erase(old_cell)
	_planned_builder_cells[unit_id] = cell
	plan_job_slot(_building_order.building_id, cell, GameEnums.JobRole.BUILDER)
	return true

func remove_planned_builder_at(cell: Vector2i) -> Array[String]:
	var removed: Array[String] = []
	if _building_order == null:
		return removed
	for unit_id in _planned_builder_cells.keys():
		if _planned_builder_cells[unit_id] == cell:
			_building_order.builder_unit_ids.erase(unit_id)
			_planned_builder_cells.erase(unit_id)
			removed.append(unit_id)
	return removed

func remove_planned_builder(unit_id: String) -> void:
	if _building_order == null or not _planned_builder_cells.has(unit_id):
		return
	var old_cell: Vector2i = _planned_builder_cells[unit_id]
	_planned_builder_cells.erase(unit_id)
	_building_order.builder_unit_ids.erase(unit_id)
	var slots: Dictionary = _planned_job_slots.get(_building_order.building_id, {})
	slots.erase(old_cell)
	_building_order.job_slots.erase(old_cell)
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
	if _building_order != null:
		result.building_order = _building_order.copy()
	if _cancel_construction_order != null:
		result.cancel_construction_order = _cancel_construction_order.copy()
	if _demolish_building_order != null:
		result.demolish_building_order = _demolish_building_order.copy()
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
	_building_order = null
	_cancel_construction_order = null
	_demolish_building_order = null
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
		and _building_order == null
		and _cancel_construction_order == null
		and _demolish_building_order == null
		and _staffing_orders.is_empty()
		and _assign_builder_orders.is_empty()
		and _remove_builder_orders.is_empty()
		and _planned_job_slots.is_empty()
	)
