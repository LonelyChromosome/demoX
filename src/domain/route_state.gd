class_name RouteState
extends RefCounted

var id := ""
var from_region := ""
var to_region := ""
var discovered := false
var safety := 2
var travel_cost := 1
var food_cost := 0
var blocked := false
var blocked_turns_left := 0
var last_used_turn := -1
var successful_trips := 0
var memory_tags: Array[Dictionary] = []


func _init(route_id := "", from_id := "", to_id := "") -> void:
	id = route_id
	from_region = from_id
	to_region = to_id


func connects(region_id: String) -> bool:
	return from_region == region_id or to_region == region_id


func other_end(region_id: String) -> String:
	if from_region == region_id:
		return to_region
	if to_region == region_id:
		return from_region
	return ""
