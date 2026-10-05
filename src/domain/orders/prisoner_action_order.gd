class_name PrisonerActionOrder
extends RefCounted

var prisoner_unit_id := ""
var action: GameEnums.PrisonerAction = GameEnums.PrisonerAction.CONTINUE
var planned_day := 1


func _init(
	prisoner_id := "",
	prisoner_action: GameEnums.PrisonerAction = GameEnums.PrisonerAction.CONTINUE,
	day := 1
) -> void:
	prisoner_unit_id = prisoner_id
	action = prisoner_action
	planned_day = day


func copy() -> PrisonerActionOrder:
	return PrisonerActionOrder.new(prisoner_unit_id, action, planned_day)