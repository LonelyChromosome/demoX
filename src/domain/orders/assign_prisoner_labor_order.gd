class_name AssignPrisonerLaborOrder
extends RefCounted

var prisoner_unit_id := ""
var building_id := ""
var planned_day := 1


func _init(prisoner_id := "", target_building_id := "", day := 1) -> void:
	prisoner_unit_id = prisoner_id
	building_id = target_building_id
	planned_day = day


func copy() -> AssignPrisonerLaborOrder:
	return AssignPrisonerLaborOrder.new(prisoner_unit_id, building_id, planned_day)