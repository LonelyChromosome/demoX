class_name OutsiderGroupState
extends RefCounted

var id := ""
var name := ""
var member_unit_ids: Array[String] = []
var discovered_day := 1
var origin_tag := ""
var support_active := false
var support_unmet := false
var trade_offer: Dictionary = {}
var pressure: GameEnums.OutsidePressure = GameEnums.OutsidePressure.CALM
var unresolved_days := 0
var escort_unit_ids: Array[String] = []
var escort_origin_cells: Dictionary = {}
var resettlement_days_left := 0
var resettlement_started_day := 0
var resettlement_complete := false
var history_tags: Array[Dictionary] = []
var region_id := ""
var migration_state := ""
var migration_reason := ""
var supported_days := 0


func _init(group_id := "") -> void:
	id = group_id


func member_count() -> int:
	return member_unit_ids.size()


func is_resettling() -> bool:
	return resettlement_days_left > 0
