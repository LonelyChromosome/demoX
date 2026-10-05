class_name RegionState
extends RefCounted

var id := ""
var name := ""
var discovered := false
var danger := 0
var base_danger := 0
var food_potential := 0
var material_potential := 0
var population_pressure := 0
var outsider_presence := 0
var faction_presence: Dictionary = {}
var route_links: Array[String] = []
var memory_tags: Array[Dictionary] = []
var current_condition := "Chưa rõ"
var presence: GameEnums.RegionPresence = GameEnums.RegionPresence.UNKNOWN
var last_visited_turn := -1
var threats: Dictionary = {
	"bandits": 0,
	"famine": 0,
	"disease": 0,
	"hostile_faction": 0,
	"weather_hazard": 0,
	"refugee_pressure": 0,
}


func _init(region_id := "", display_name := "") -> void:
	id = region_id
	name = display_name


func remember(kind: String, turn: int, details: Dictionary = {}) -> void:
	var memory := {"kind": kind, "turn": turn}
	for key in details:
		memory[key] = details[key]
	memory_tags.append(memory)


func has_memory(kind: String) -> bool:
	for memory in memory_tags:
		if memory.get("kind", "") == kind:
			return true
	return false
