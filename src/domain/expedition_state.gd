class_name ExpeditionState
extends RefCounted

var id := ""
var unit_ids: Array[String] = []
var origin_cells: Dictionary = {}
var departure_day := 1
var duration_days := 1
var days_left := 1
var elapsed_days := 0
var status: GameEnums.ExpeditionStatus = GameEnums.ExpeditionStatus.AWAY
var outcome_kind := "empty"
var reward_amount := 0
var injured_unit_id := ""
var lost_unit_id := ""
var outsider_group_id := ""
var outcome_applied := false
var narrative: Array[String] = []


func _init(expedition_id := "") -> void:
	id = expedition_id