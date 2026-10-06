class_name GameState
extends RefCounted

const MAX_DAYS := 32
const MAX_ROSTER := 16

var day := 1
var food := 0
var materials := 0
var city_state: GameEnums.CityState = GameEnums.CityState.MEDIUM
var run_seed := 80232

var units: Dictionary = {}
var buildings: Dictionary = {}
var prisoners: Array[String] = []
var outsiders_count := 0
var outsider_unrest := 0
var expeditions: Dictionary = {}
var outsider_groups: Dictionary = {}
var resettled_group_count := 0
var game_over := false
var failure_reason := ""
var failure_reason_key := ""
var failure_reason_args: Dictionary = {}
var world_state := WorldState.new()
var ruins: Dictionary = {}
var active_cleanup_ruin_id := ""
var events: Dictionary = {}
var resolved_event_definition_ids: Array[String] = []
var event_sequence := 0
var perimeter_layout := PerimeterLayout.new()
var wasteland := WastelandState.new()
var last_inspection_day := 0
var relationships: Dictionary = {}
var pending_social_events: Array[Dictionary] = []
var report_history: Array[Dictionary] = []
var deceased_units: Array[Dictionary] = []

var onboarding_started := false
var onboarding_skipped := false
var onboarding_completed := false
var onboarding_seen_hints: Dictionary = {}

var run_ended := false
var ending_triggered := false
var ending_outcome_id := ""
var ending_recap_data: Dictionary = {}

var day_one_full_knowledge := true
var active_event_id := ""
var history: Array[Dictionary] = []


func _init() -> void:
	world_state.initialize_defaults()

func player_roster_count() -> int:
	var total := 0
	for unit in units.values():
		if unit is UnitState and unit.is_in_city_roster():
			total += 1
	return total

func has_active_building(type: GameEnums.BuildingType) -> bool:
	for building in buildings.values():
		if building is BuildingState and building.type == type and building.phase == GameEnums.BuildingPhase.ACTIVE:
			return true
	return false

func remember(text: String, result := "") -> void:
	history.append({"day": day, "text": text, "result": result})


func record_death(unit: UnitState, cause: String) -> bool:
	if unit == null:
		return false
	for entry in deceased_units:
		if str(entry.get("unit_id", "")) == unit.id:
			return false
	deceased_units.append({
		"unit_id": unit.id,
		"name": unit.display_name if not unit.display_name.is_empty() else unit.id,
		"rank": unit.rank,
		"faction": unit.faction,
		"day": day,
		"cause": cause,
	})
	return true
