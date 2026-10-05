class_name EventState
extends RefCounted

var id := ""
var definition_id := ""
var type := ""
var title := ""
var description := ""
var start_day := 1
var duration := 1
var elapsed_days := 0
var stage := 0
var status: GameEnums.EventStatus = GameEnums.EventStatus.ACTIVE
var source := ""
var target_id := ""
var tags: Array[String] = []
var choices: Array[Dictionary] = []
var chosen_choice := ""
var memory: Array[Dictionary] = []
var follow_up_event_ids: Array[String] = []
var resolved := false
var attention_level: GameEnums.AttentionLevel = GameEnums.AttentionLevel.NORMAL


func _init(event_id := "") -> void:
	id = event_id


func remember(kind: String, day: int, data: Dictionary = {}) -> void:
	var entry := {"kind": kind, "day": day}
	for key in data:
		entry[key] = data[key]
	memory.append(entry)
