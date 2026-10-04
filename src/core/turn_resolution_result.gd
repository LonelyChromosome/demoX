class_name TurnResolutionResult
extends RefCounted

var resolved_day := 1
var next_day := 1
var phase_trace: Array[int] = []
var committed_move_ids: Array[String] = []
var building_committed := false
var materials_spent := 0
var new_building_ids: Array[String] = []
var completed_building_ids: Array[String] = []
var rejected_orders: Array[Dictionary] = []


func reject(kind: String, order_id: String, reason: String) -> void:
	rejected_orders.append({"kind": kind, "id": order_id, "reason": reason})


func was_rejected(kind: String, order_id: String) -> bool:
	for rejection in rejected_orders:
		if rejection.kind == kind and rejection.id == order_id:
			return true
	return false
