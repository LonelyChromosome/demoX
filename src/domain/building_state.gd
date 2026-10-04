class_name BuildingState
extends RefCounted

var id := ""
var type: GameEnums.BuildingType = GameEnums.BuildingType.FARM
var core_cell := Vector2i(-1, -1)
var phase: GameEnums.BuildingPhase = GameEnums.BuildingPhase.BLUEPRINT
var days_left := 0

var manager_unit_id := ""
var worker_unit_ids: Array[String] = []
var prisoner_labor := 0


func _init(
	building_id := "",
	building_type: GameEnums.BuildingType = GameEnums.BuildingType.FARM,
	cell := Vector2i(-1, -1)
) -> void:
	id = building_id
	type = building_type
	core_cell = cell
