class_name PlaceBuildingOrder
extends RefCounted

var building_id := ""
var building_type: GameEnums.BuildingType = GameEnums.BuildingType.FARM
var core_cell := Vector2i(-1, -1)
var planned_day := 1


func _init(
	ordered_building_id := "",
	type: GameEnums.BuildingType = GameEnums.BuildingType.FARM,
	cell := Vector2i(-1, -1),
	day := 1
) -> void:
	building_id = ordered_building_id
	building_type = type
	core_cell = cell
	planned_day = day


func to_blueprint() -> BuildingState:
	return BuildingState.new(building_id, building_type, core_cell)


func copy() -> PlaceBuildingOrder:
	return PlaceBuildingOrder.new(building_id, building_type, core_cell, planned_day)
