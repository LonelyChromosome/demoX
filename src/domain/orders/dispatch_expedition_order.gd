class_name DispatchExpeditionOrder
extends RefCounted

var expedition_id := ""
var unit_ids: Array[String] = []
var planned_day := 1
var target_region_id := ""
var supplies_food := 0


func _init(
	id := "", members: Array[String] = [], day := 1,
	region_id := "", supply_food := 0
) -> void:
	expedition_id = id
	unit_ids = members.duplicate()
	planned_day = day
	target_region_id = region_id
	supplies_food = maxi(0, supply_food)


func copy() -> DispatchExpeditionOrder:
	return DispatchExpeditionOrder.new(
		expedition_id, unit_ids, planned_day, target_region_id, supplies_food
	)
