class_name OrderQueue
extends RefCounted

signal changed

var _move_orders: Dictionary = {}
var _building_order: PlaceBuildingOrder
var _cancel_construction_order: CancelConstructionOrder
var _assign_builder_orders: Dictionary = {}


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
	_building_order = order
	changed.emit()


func cancel_building() -> void:
	if _building_order != null:
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

func plan_assign_builder(building_id: String, unit_id: String) -> AssignBuilderOrder:
	var order := AssignBuilderOrder.new(building_id, unit_id)
	_assign_builder_orders[building_id] = order
	changed.emit()
	return order

func cancel_assign_builder(building_id: String) -> void:
	if _assign_builder_orders.erase(building_id):
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
	for building_id in _assign_builder_orders:
		result.assign_builder_orders.append((_assign_builder_orders[building_id] as AssignBuilderOrder).copy())
	return result


func clear() -> void:
	var had_orders := not is_empty()
	_move_orders.clear()
	_building_order = null
	_cancel_construction_order = null
	_assign_builder_orders.clear()
	if had_orders:
		changed.emit()


func is_empty() -> bool:
	return (
		_move_orders.is_empty()
		and _building_order == null
		and _cancel_construction_order == null
		and _assign_builder_orders.is_empty()
	)
