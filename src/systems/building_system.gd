class_name BuildingSystem
extends RefCounted

const BOARD_SIZE := 8


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
