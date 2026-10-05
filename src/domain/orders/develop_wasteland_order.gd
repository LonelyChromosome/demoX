class_name DevelopWastelandOrder
extends RefCounted

var planned_day := 1
var unit_ids: Array[String] = []


func _init(day := 1, participants: Array[String] = []) -> void:
	planned_day = day
	unit_ids = participants.duplicate()


func copy() -> DevelopWastelandOrder:
	return DevelopWastelandOrder.new(planned_day, unit_ids)
