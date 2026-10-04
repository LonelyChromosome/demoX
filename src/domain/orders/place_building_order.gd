class_name PlaceBuildingOrder
extends RefCounted

var building_id := ""
var building_type: GameEnums.BuildingType = GameEnums.BuildingType.FARM
var core_cell := Vector2i(-1, -1)
var planned_day := 1
var builder_unit_ids: Array[String] = []
var job_slots: Dictionary = {}
var placement_valid := true
var placement_reason := "Vị trí hợp lệ"


func _init(
	ordered_building_id := "",
	type: GameEnums.BuildingType = GameEnums.BuildingType.FARM,
	cell := Vector2i(-1, -1),
	day := 1,
	builders: Array[String] = [],
	slots: Dictionary = {}
) -> void:
	building_id = ordered_building_id
	building_type = type
	core_cell = cell
	planned_day = day
	builder_unit_ids = builders.duplicate()
	job_slots = slots.duplicate(true)


func to_blueprint() -> BuildingState:
	var building := BuildingState.new(building_id, building_type, core_cell)
	building.builder_unit_ids = builder_unit_ids.duplicate()
	building.job_slots = job_slots.duplicate(true)
	building.placement_valid = placement_valid
	building.placement_reason = placement_reason
	return building


func copy() -> PlaceBuildingOrder:
	var result := PlaceBuildingOrder.new(
		building_id, building_type, core_cell, planned_day, builder_unit_ids, job_slots
	)
	result.placement_valid = placement_valid
	result.placement_reason = placement_reason
	return result
