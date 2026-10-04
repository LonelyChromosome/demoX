class_name BuildingPlacementState
extends RefCounted

var selected_type := -1
var hover_core := Vector2i(-1, -1)
var hover_valid := false
var hover_reason := ""
var planned_building: BuildingState


func is_active() -> bool:
	return selected_type >= 0


func select(type: GameEnums.BuildingType) -> void:
	selected_type = type
	hover_core = Vector2i(-1, -1)
	hover_valid = false
	hover_reason = ""
	planned_building = null


func update_hover(cell: Vector2i, valid: bool, reason := "") -> void:
	hover_core = cell
	hover_valid = valid
	hover_reason = reason


func plan(building: BuildingState) -> void:
	planned_building = building


func cancel() -> void:
	selected_type = -1
	hover_core = Vector2i(-1, -1)
	hover_valid = false
	hover_reason = ""
	planned_building = null
