class_name KnownFact
extends RefCounted

var key := ""
var subject_id := ""
var category := ""
var values: Dictionary = {}
var source_unit_id := ""
var source_label := ""
var observed_day := 1
var inspected_day := 1
var delivered_day := 1
var confidence: GameEnums.FactConfidence = GameEnums.FactConfidence.CONFIRMED


func _init(fact_key := "", fact_subject_id := "", fact_category := "") -> void:
	key = fact_key
	subject_id = fact_subject_id
	category = fact_category


func is_stale(current_day: int) -> bool:
	return freshness(current_day) == GameEnums.InformationFreshness.STALE


func freshness(current_day: int) -> GameEnums.InformationFreshness:
	var age := maxi(0, current_day - delivered_day)
	if age <= 1:
		return GameEnums.InformationFreshness.FRESH
	if age <= 3:
		return GameEnums.InformationFreshness.AGING
	return GameEnums.InformationFreshness.STALE


func copy() -> KnownFact:
	var copied_fact := KnownFact.new(key, subject_id, category)
	copied_fact.values = values.duplicate(true)
	copied_fact.source_unit_id = source_unit_id
	copied_fact.source_label = source_label
	copied_fact.observed_day = observed_day
	copied_fact.inspected_day = inspected_day
	copied_fact.delivered_day = delivered_day
	copied_fact.confidence = confidence
	return copied_fact
