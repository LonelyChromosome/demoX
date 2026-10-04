class_name PendingOrderSnapshot
extends RefCounted

var move_orders: Array[MoveUnitOrder] = []
var building_order: PlaceBuildingOrder
var cancel_construction_order: CancelConstructionOrder
var assign_builder_orders: Array[AssignBuilderOrder] = []
var remove_builder_orders: Array[RemoveBuilderOrder] = []
var demolish_building_order: DemolishBuildingOrder
var staffing_orders: Array[SetBuildingStaffOrder] = []
