class_name AssignBuilderOrder
extends RefCounted

var building_id := ""
var unit_id := ""

func _init(ordered_building_id := "", assigned_unit_id := "") -> void:
	building_id = ordered_building_id
	unit_id = assigned_unit_id

func copy() -> AssignBuilderOrder:
	return AssignBuilderOrder.new(building_id, unit_id)
