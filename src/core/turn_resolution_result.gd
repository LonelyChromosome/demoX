class_name TurnResolutionResult
extends RefCounted

var resolved_day := 1
var next_day := 1
var phase_trace: Array[int] = []
var committed_move_ids: Array[String] = []
var building_committed := false
var materials_spent := 0
var food_produced := 0
var materials_produced := 0
var food_consumed := 0
var awaiting_ration := false
var ration_food_available := 0
var ration_need := 0
var ration_candidate_ids: Array[String] = []
var fed_unit_ids: Array[String] = []
var unfed_unit_ids: Array[String] = []
var starved_unit_ids: Array[String] = []
var starved_unit_cells: Dictionary = {}
var new_building_ids: Array[String] = []
var completed_building_ids: Array[String] = []
var cancelled_building_ids: Array[String] = []
var refunded_materials := 0
var reassigned_builder_ids: Array[String] = []
var demolishing_building_ids: Array[String] = []
var demolished_building_ids: Array[String] = []
var staffing_committed_building_ids: Array[String] = []
var farm_role_changes: Array[Dictionary] = []
var building_events: Array[Dictionary] = []
var starved_unit_names: Dictionary = {}
var inspection_snapshots: Array[Dictionary] = []
var inspected_building_ids: Array[String] = []
var report_entries: Array[ReportEntry] = []
var rejected_orders: Array[Dictionary] = []


func reject(kind: String, order_id: String, reason: String) -> void:
	rejected_orders.append({"kind": kind, "id": order_id, "reason": reason})


func was_rejected(kind: String, order_id: String) -> bool:
	for rejection in rejected_orders:
		if rejection.kind == kind and rejection.id == order_id:
			return true
	return false
