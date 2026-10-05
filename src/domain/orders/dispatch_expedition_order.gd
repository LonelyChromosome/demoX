class_name DispatchExpeditionOrder
extends RefCounted

var expedition_id := ""
var unit_ids: Array[String] = []
var planned_day := 1


func _init(id := "", members: Array[String] = [], day := 1) -> void:
	expedition_id = id
	unit_ids = members.duplicate()
	planned_day = day


func copy() -> DispatchExpeditionOrder:
	return DispatchExpeditionOrder.new(expedition_id, unit_ids, planned_day)