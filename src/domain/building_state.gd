class_name BuildingState
extends RefCounted

var id := ""
var type: GameEnums.BuildingType = GameEnums.BuildingType.FARM
var core_cell := Vector2i(-1, -1)
var phase: GameEnums.BuildingPhase = GameEnums.BuildingPhase.BUILDING
var days_left := 1

var manager_unit_id := ""
var worker_unit_ids: Array[String] = []
var prisoner_labor := 0
