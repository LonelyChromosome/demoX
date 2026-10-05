class_name ReportEntry
extends RefCounted

var text := ""
var fact_key := ""
var observed_day := 1
var confidence: GameEnums.FactConfidence = GameEnums.FactConfidence.CONFIRMED
var source_label := ""


func _init(
	entry_text := "",
	entry_day := 1,
	entry_confidence: GameEnums.FactConfidence = GameEnums.FactConfidence.CONFIRMED,
	entry_source := "",
	entry_fact_key := ""
) -> void:
	text = entry_text
	observed_day = entry_day
	confidence = entry_confidence
	source_label = entry_source
	fact_key = entry_fact_key