class_name RepairBuildingOrder
extends RefCounted

var building_id := ""
var planned_day := 0


func _init(target_id := "", day := 0) -> void:
	building_id = target_id
	planned_day = day
