class_name SetBuildingStaffOrder
extends RefCounted

var building_id := ""
var manager_unit_id := ""
var worker_unit_ids: Array[String] = []
var planned_day := 1


func _init(
	ordered_building_id := "",
	manager_id := "",
	worker_ids: Array[String] = [],
	day := 1
) -> void:
	building_id = ordered_building_id
	manager_unit_id = manager_id
	worker_unit_ids = worker_ids.duplicate()
	planned_day = day


func copy() -> SetBuildingStaffOrder:
	return SetBuildingStaffOrder.new(building_id, manager_unit_id, worker_unit_ids, planned_day)
