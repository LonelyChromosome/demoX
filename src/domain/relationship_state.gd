class_name RelationshipState
extends RefCounted

const NEUTRAL := "neutral"
const FAMILIAR := "familiar"
const CLOSE := "close"
const ROMANCE_CANDIDATE := "romance_candidate"
const BONDED := "bonded"

var unit_a_id := ""
var unit_b_id := ""
var affinity := 0
var trust := 0
var status := NEUTRAL
var shared_history: Array[Dictionary] = []
var last_changed_day := 0
var tags: Array[String] = []
var applied_source_keys: Dictionary = {}


func _init(first_unit_id := "", second_unit_id := "") -> void:
	var unit_ids := [first_unit_id, second_unit_id]
	unit_ids.sort()
	unit_a_id = unit_ids[0]
	unit_b_id = unit_ids[1]


func includes(unit_id: String) -> bool:
	return unit_id == unit_a_id or unit_id == unit_b_id


func other_unit_id(unit_id: String) -> String:
	if unit_id == unit_a_id:
		return unit_b_id
	if unit_id == unit_b_id:
		return unit_a_id
	return ""
