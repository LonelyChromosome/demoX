class_name BuildingSystem
extends RefCounted

const BOARD_SIZE := 8

const BUILD_DAYS := {
	GameEnums.BuildingType.FARM: 2,
	GameEnums.BuildingType.MATERIAL_WORKSHOP: 2,
	GameEnums.BuildingType.PRISON: 2,
	GameEnums.BuildingType.INFIRMARY: 3,
	GameEnums.BuildingType.BARRACKS: 4,
}

const MATERIAL_COST := {
	GameEnums.BuildingType.FARM: 1,
	GameEnums.BuildingType.MATERIAL_WORKSHOP: 0,
	GameEnums.BuildingType.PRISON: 1,
	GameEnums.BuildingType.INFIRMARY: 1,
	GameEnums.BuildingType.BARRACKS: 1,
}

func build_days(type: GameEnums.BuildingType, builder_count: int) -> int:
	var base_days: int = BUILD_DAYS.get(type, 1)
	if builder_count >= 2:
		base_days -= 1
	return maxi(base_days, 1)


func material_cost(type: GameEnums.BuildingType) -> int:
	return MATERIAL_COST.get(type, 1)


func validate_builders(state: GameState, builder_ids: Array[String]) -> Dictionary:
	if builder_ids.is_empty():
		return {"valid": false, "reason": "Cần ít nhất 1 builder"}
	var seen := {}
	for builder_id in builder_ids:
		if seen.has(builder_id):
			return {"valid": false, "reason": "Builder bị chọn trùng"}
		seen[builder_id] = true
		var unit := state.units.get(builder_id) as UnitState
		if unit == null:
			return {"valid": false, "reason": "Builder không còn tồn tại"}
		if not unit.can_be_builder():
			return {"valid": false, "reason": "Builder không hợp lệ hoặc đang bị khóa"}
	return {"valid": true, "reason": "Builder hợp lệ"}


func assign_construction(building: BuildingState, builder_ids: Array[String]) -> void:
	building.builder_unit_ids = builder_ids.duplicate()
	building.worker_unit_ids = builder_ids.duplicate()
	building.phase = GameEnums.BuildingPhase.BUILDING
	building.days_left = build_days(building.type, builder_ids.size())


func advance_construction(state: GameState, skip_ids: Dictionary = {}) -> Array[String]:
	var completed: Array[String] = []
	for candidate in state.buildings.values():
		if not (candidate is BuildingState):
			continue
		if candidate.phase != GameEnums.BuildingPhase.BUILDING or skip_ids.has(candidate.id):
			continue
		candidate.days_left -= 1
		if candidate.days_left <= 0:
			candidate.days_left = 0
			candidate.phase = GameEnums.BuildingPhase.ACTIVE
			completed.append(candidate.id)
	return completed


func unlock_builders(state: GameState, building_ids: Array[String]) -> void:
	for building_id in building_ids:
		var building := state.buildings.get(building_id) as BuildingState
		if building == null:
			continue
		for builder_id in building.builder_unit_ids:
			var unit := state.units.get(builder_id) as UnitState
			if unit != null and unit.assigned_building_id == building_id:
				unit.assigned_building_id = ""
				unit.locked_by_construction = false


func footprint(core_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(core_cell.y - 1, core_cell.y + 2):
		for x in range(core_cell.x - 1, core_cell.x + 2):
			cells.append(Vector2i(x, y))
	return cells


func validate_placement(
	state: GameState, core_cell: Vector2i, planned_unit_cells: Array = []
) -> Dictionary:
	var cells := footprint(core_cell)
	for cell in cells:
		if not is_inside_board(cell):
			return {"valid": false, "reason": "Vùng 3x3 vượt khỏi bàn cờ"}

	var occupied_by_buildings := _building_cells(state.buildings)
	for cell in cells:
		if occupied_by_buildings.has(cell):
			return {"valid": false, "reason": "Trùng vùng công trình khác"}

	for candidate in state.units.values():
		if not (candidate is UnitState):
			continue
		if candidate.board_cell in cells:
			return {"valid": false, "reason": "Xung đột vị trí quân cờ"}
	for planned_cell in planned_unit_cells:
		if planned_cell in cells:
			return {"valid": false, "reason": "Xung đột vị trí quân cờ dự kiến"}

	return {"valid": true, "reason": "Vị trí hợp lệ"}


func _building_cells(buildings: Dictionary) -> Dictionary:
	var occupied := {}
	for candidate in buildings.values():
		if not (candidate is BuildingState):
			continue
		for cell in footprint(candidate.core_cell):
			occupied[cell] = true
	return occupied


func is_cell_occupied_by_building(state: GameState, cell: Vector2i) -> bool:
	return _building_cells(state.buildings).has(cell)


func is_inside_board(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < BOARD_SIZE and cell.y < BOARD_SIZE
