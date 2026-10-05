class_name UnitState
extends RefCounted

var id := ""
var display_name := ""
var rank: GameEnums.Rank = GameEnums.Rank.PAWN
var faction: GameEnums.Faction = GameEnums.Faction.PLAYER
var old_rank_tag := -1

var board_cell := Vector2i(-1, -1)

var loyalty := 0
var rebellion_level: GameEnums.RebellionLevel = GameEnums.RebellionLevel.NONE
var loyalty_history: Array[Dictionary] = []
var loyalty_source_keys: Dictionary = {}
var injured := false
var healing_days_left := 0
var hunger_streak := 0

var assigned_building_id := ""
var work_building_id := ""
var is_manager := false
var locked_by_construction := false
var locked_by_healing := false
var away_days_left := 0
var away_assignment_id := ""
var away_reason := ""
var return_pending := false

var is_prisoner := false
var prison_building_id := ""
var prisoner_labor := false
var labor_building_id := ""
var prison_days := 0
var escape_attempt_pending := false
var submission_requested := false

var guard_days := 0
var food_brought_home := 0
var materials_brought_home := 0
var memories: Array[String] = []
var backstory: Array[String] = []
var memory_tags: Array[Dictionary] = []

var merit := 0
var lifetime_merit := 0
var merit_history: Array[Dictionary] = []
var merit_grant_keys: Dictionary = {}
var promotion_history: Array[Dictionary] = []
var promotion_target_rank := -1
var promotion_barracks_id := ""
var promotion_started_day := 0
var promotion_complete_day := 0
var promotion_order_key := ""
var promotion_last_advanced_day := 0
var promotion_ready_notified: Dictionary = {}

func _init(unit_id := "") -> void:
	id = unit_id

func is_in_city_roster() -> bool:
	return faction == GameEnums.Faction.PLAYER and not is_prisoner


func is_in_promotion_training() -> bool:
	return promotion_target_rank >= 0

func can_be_moved() -> bool:
	return (
		rank != GameEnums.Rank.KING
		and faction == GameEnums.Faction.PLAYER
		and not locked_by_construction
		and not locked_by_healing
		and away_days_left <= 0
		and away_assignment_id.is_empty()
		and not return_pending
		and not is_in_promotion_training()
	)


func can_manage_city() -> bool:
	return (
		faction == GameEnums.Faction.PLAYER
		and rank == GameEnums.Rank.KING
		and not locked_by_healing
		and away_days_left <= 0
		and away_assignment_id.is_empty()
		and not return_pending
		and not is_in_promotion_training()
	)

func can_be_builder() -> bool:
	return (
		faction == GameEnums.Faction.PLAYER
		and rank != GameEnums.Rank.KING
		and assigned_building_id.is_empty()
		and work_building_id.is_empty()
		and not locked_by_construction
		and not locked_by_healing
		and away_days_left <= 0
		and away_assignment_id.is_empty()
		and not return_pending
		and not is_in_promotion_training()
	)
