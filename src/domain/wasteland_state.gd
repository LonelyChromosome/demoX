class_name WastelandState
extends RefCounted

var active := false
var completed := false
var started_day := 0
var duration_days := 0
var days_left := 0
var food_cost := 2
var material_cost := 2
var daily_food_yield := 1
var daily_material_yield := 1
var participant_unit_ids: Array[String] = []
var history: Array[Dictionary] = []
var enforce_resettlement_unlock := false


func can_start() -> bool:
	return not active and not completed


func remember(kind: String, day: int, data: Dictionary = {}) -> void:
	var entry := {"kind": kind, "day": day}
	for key in data:
		entry[key] = data[key]
	history.append(entry)
