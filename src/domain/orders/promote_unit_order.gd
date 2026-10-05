class_name PromoteUnitOrder
extends RefCounted

var unit_id := ""
var barracks_id := ""
var target_rank: GameEnums.Rank = GameEnums.Rank.PAWN
var planned_day := 1


func _init(
	p_unit_id := "", p_barracks_id := "", p_target_rank: GameEnums.Rank = GameEnums.Rank.PAWN, p_planned_day := 1
) -> void:
	unit_id = p_unit_id
	barracks_id = p_barracks_id
	target_rank = p_target_rank
	planned_day = p_planned_day


func copy() -> PromoteUnitOrder:
	return PromoteUnitOrder.new(unit_id, barracks_id, target_rank, planned_day)
