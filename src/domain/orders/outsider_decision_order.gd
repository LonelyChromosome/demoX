class_name OutsiderDecisionOrder
extends RefCounted

var group_id := ""
var action: GameEnums.OutsiderAction = GameEnums.OutsiderAction.START_SUPPORT
var escort_unit_ids: Array[String] = []
var king_unit_id := ""
var planned_day := 1


func _init(
	id := "",
	decision: GameEnums.OutsiderAction = GameEnums.OutsiderAction.START_SUPPORT,
	escorts: Array[String] = [],
	king_id := "",
	day := 1
) -> void:
	group_id = id
	action = decision
	escort_unit_ids = escorts.duplicate()
	king_unit_id = king_id
	planned_day = day


func copy() -> OutsiderDecisionOrder:
	return OutsiderDecisionOrder.new(group_id, action, escort_unit_ids, king_unit_id, planned_day)