class_name BuildingState
extends RefCounted

var id := ""
var type: GameEnums.BuildingType = GameEnums.BuildingType.FARM
var core_cell := Vector2i(-1, -1)
var phase: GameEnums.BuildingPhase = GameEnums.BuildingPhase.BLUEPRINT
var days_left := 0
var builder_unit_ids: Array[String] = []
var placement_valid := true
var placement_reason := "Vị trí hợp lệ"

var manager_unit_id := ""
var worker_unit_ids: Array[String] = []
var job_slots: Dictionary = {}
var prisoner_labor := 0
var prisoner_unit_ids: Array[String] = []
var patient_unit_ids: Array[String] = []
var under_guarded := false
var labor_bonus_applied := false
var accelerated_by_builders := false


func _init(
	building_id := "",
	building_type: GameEnums.BuildingType = GameEnums.BuildingType.FARM,
	cell := Vector2i(-1, -1)
) -> void:
	id = building_id
	type = building_type
	core_cell = cell
