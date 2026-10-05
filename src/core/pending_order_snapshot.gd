class_name PendingOrderSnapshot
extends RefCounted

var move_orders: Array[MoveUnitOrder] = []
var building_orders: Array[PlaceBuildingOrder] = []
var cancel_construction_order: CancelConstructionOrder
var assign_builder_orders: Array[AssignBuilderOrder] = []
var remove_builder_orders: Array[RemoveBuilderOrder] = []
var demolish_building_order: DemolishBuildingOrder
var staffing_orders: Array[SetBuildingStaffOrder] = []
var inspect_building_order: InspectBuildingOrder
var prisoner_labor_orders: Array[AssignPrisonerLaborOrder] = []
var prisoner_action_orders: Array[PrisonerActionOrder] = []
var prisoner_labor_orders: Array[AssignPrisonerLaborOrder] = []
var prisoner_action_orders: Array[PrisonerActionOrder] = []
var inspect_building_order: InspectBuildingOrder
