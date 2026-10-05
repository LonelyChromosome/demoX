class_name InspectBuildingOrder
extends RefCounted

var building_id := ""
var king_unit_id := ""
var planned_day := 1


func _init(target_building_id := "", king_id := "", day := 1) -> void:
	building_id = target_building_id
	king_unit_id = king_id
	planned_day = day


func copy() -> InspectBuildingOrder:
	return InspectBuildingOrder.new(building_id, king_unit_id, planned_day)