class_name DemolishBuildingOrder
extends RefCounted

var building_id := ""

func _init(ordered_building_id := "") -> void:
	building_id = ordered_building_id

func copy() -> DemolishBuildingOrder:
	return DemolishBuildingOrder.new(building_id)
