class_name FactionState
extends RefCounted

var id := ""
var name := ""
var relation := 0
var influence_by_region: Dictionary = {}
var known := false
var traits: Array[String] = []
var recent_actions: Array[Dictionary] = []
var memory: Array[Dictionary] = []


func _init(faction_id := "", display_name := "") -> void:
	id = faction_id
	name = display_name
