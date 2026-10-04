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
var injured := false
var healing_days_left := 0
var hunger_streak := 0

var assigned_building_id := ""
var is_manager := false
var locked_by_construction := false
var locked_by_healing := false
var away_days_left := 0

var guard_days := 0
var food_brought_home := 0
var materials_brought_home := 0
var memories: Array[String] = []
var backstory: Array[String] = []

func _init(unit_id := "") -> void:
	id = unit_id

func is_in_city_roster() -> bool:
	return faction == GameEnums.Faction.PLAYER

func can_be_moved() -> bool:
	return not locked_by_construction and not locked_by_healing and away_days_left <= 0
