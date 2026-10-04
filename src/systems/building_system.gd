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

func cancel_refund(type: GameEnums.BuildingType) -> int:
	return floori(float(material_cost(type)) * 0.5)


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
		if (
			candidate.phase != GameEnums.BuildingPhase.BUILDING
			or skip_ids.has(candidate.id)
			or candidate.builder_unit_ids.is_empty()
		):
			continue
		candidate.days_left -= 1
		if candidate.days_left <= 0:
			candidate.days_left = 0
			candidate.phase = GameEnums.BuildingPhase.ACTIVE
			completed.append(candidate.id)
	return completed

func remove_builder_from_construction(
	state: GameState, building_id: String, unit_id: String
) -> bool:
	var building := state.buildings.get(building_id) as BuildingState
	if building == null or building.phase != GameEnums.BuildingPhase.BUILDING:
		return false
	var index := building.builder_unit_ids.find(unit_id)
	if index < 0:
		return false
	var had_one := building.builder_unit_ids.size() == 1
	building.builder_unit_ids.remove_at(index)
	building.worker_unit_ids.erase(unit_id)
	var unit := state.units.get(unit_id) as UnitState
	if unit != null:
		unit.locked_by_construction = false
		unit.assigned_building_id = ""
	if had_one:
		building.days_left = build_days(building.type, 1)
	return true

func reassign_builder_to_construction(
	state: GameState, building_id: String, unit_id: String
) -> Dictionary:
	var building := state.buildings.get(building_id) as BuildingState
	if building == null or building.phase != GameEnums.BuildingPhase.BUILDING:
		return {"valid": false, "reason": "Construction không tồn tại hoặc đã ACTIVE"}
	var unit := state.units.get(unit_id) as UnitState
	if unit == null or not unit.can_be_builder():
		return {"valid": false, "reason": "Builder không hợp lệ hoặc đang bị khóa"}
	if building.builder_unit_ids.has(unit_id):
		return {"valid": false, "reason": "Builder đã được gán"}
	building.builder_unit_ids.append(unit_id)
	building.worker_unit_ids.append(unit_id)
	unit.locked_by_construction = true
	unit.assigned_building_id = building_id
	return {"valid": true, "reason": "Builder đã được gán"}

func cancel_construction(state: GameState, building_id: String) -> int:
	var building := state.buildings.get(building_id) as BuildingState
	if building == null or building.phase != GameEnums.BuildingPhase.BUILDING:
		return -1
	for unit_id in building.builder_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			unit.locked_by_construction = false
			unit.assigned_building_id = ""
	var refund := cancel_refund(building.type)
	state.buildings.erase(building_id)
	state.materials += refund
	return refund

func validate_demolition(state: GameState, building_id: String) -> Dictionary:
	var building := state.buildings.get(building_id) as BuildingState
	if building == null:
		return {"valid": false, "reason": "Building không tồn tại"}
	if building.phase != GameEnums.BuildingPhase.ACTIVE:
		return {"valid": false, "reason": "Chỉ được phá building ACTIVE"}
	return {"valid": true, "reason": "Có thể phá"}

func start_demolition(state: GameState, building_id: String) -> bool:
	var validation := validate_demolition(state, building_id)
	if not validation.valid:
		return false
	var building := state.buildings.get(building_id) as BuildingState
	building.phase = GameEnums.BuildingPhase.DEMOLISHING
	return true

func finalize_demolition(state: GameState, building_id: String) -> bool:
	var building := state.buildings.get(building_id) as BuildingState
	if building == null or building.phase != GameEnums.BuildingPhase.DEMOLISHING:
		return false
	state.buildings.erase(building_id)
	return true


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
