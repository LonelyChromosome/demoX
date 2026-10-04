class_name AssignBuilderOrder
extends RefCounted

var building_id := ""
var unit_id := ""
var slot_cell := Vector2i(-1, -1)

func _init(
	ordered_building_id := "", assigned_unit_id := "", assigned_cell := Vector2i(-1, -1)
) -> void:
	building_id = ordered_building_id
	unit_id = assigned_unit_id
	slot_cell = assigned_cell

func copy() -> AssignBuilderOrder:
	return AssignBuilderOrder.new(building_id, unit_id, slot_cell)
