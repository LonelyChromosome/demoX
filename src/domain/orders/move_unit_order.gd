class_name MoveUnitOrder
extends RefCounted

var unit_id := ""
var origin := Vector2i(-1, -1)
var target := Vector2i(-1, -1)
var planned_day := 1


func _init(
	ordered_unit_id := "",
	from_cell := Vector2i(-1, -1),
	target_cell := Vector2i(-1, -1),
	day := 1
) -> void:
	unit_id = ordered_unit_id
	origin = from_cell
	target = target_cell
	planned_day = day


func copy() -> MoveUnitOrder:
	return MoveUnitOrder.new(unit_id, origin, target, planned_day)
