class_name KnownFact
extends RefCounted

var key := ""
var subject_id := ""
var category := ""
var values: Dictionary = {}
var source_unit_id := ""
var source_label := ""
var observed_day := 1
var confidence: GameEnums.FactConfidence = GameEnums.FactConfidence.CONFIRMED


func _init(fact_key := "", fact_subject_id := "", fact_category := "") -> void:
	key = fact_key
	subject_id = fact_subject_id
	category = fact_category


func is_stale(current_day: int) -> bool:
	return observed_day < current_day - 1


func copy() -> KnownFact:
	var copied_fact := KnownFact.new(key, subject_id, category)
	copied_fact.values = values.duplicate(true)
	copied_fact.source_unit_id = source_unit_id
	copied_fact.source_label = source_label
	copied_fact.observed_day = observed_day
	copied_fact.confidence = confidence
	return copied_fact