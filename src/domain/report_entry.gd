class_name ReportEntry
extends RefCounted

var text := ""
var fact_key := ""
var observed_day := 1
var confidence: GameEnums.FactConfidence = GameEnums.FactConfidence.CONFIRMED
var source_label := ""
var attention_level: GameEnums.AttentionLevel = GameEnums.AttentionLevel.NORMAL
var category := "log"
var read := false


func _init(
	entry_text := "",
	entry_day := 1,
	entry_confidence: GameEnums.FactConfidence = GameEnums.FactConfidence.CONFIRMED,
	entry_source := "",
	entry_fact_key := "",
	entry_attention: GameEnums.AttentionLevel = GameEnums.AttentionLevel.NORMAL,
	entry_category := "log"
) -> void:
	text = entry_text
	observed_day = entry_day
	confidence = entry_confidence
	source_label = entry_source
	fact_key = entry_fact_key
	attention_level = entry_attention
	category = entry_category
