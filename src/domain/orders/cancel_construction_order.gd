class_name CancelConstructionOrder
extends RefCounted

var building_id := ""

func _init(ordered_building_id := "") -> void:
	building_id = ordered_building_id

func copy() -> CancelConstructionOrder:
	return CancelConstructionOrder.new(building_id)
