class_name BuildingSystem
extends RefCounted

const BASE_BUILD_DAYS := {
	GameEnums.BuildingType.FARM: 2,
	GameEnums.BuildingType.MATERIAL_WORKSHOP: 2,
	GameEnums.BuildingType.PRISON: 2,
	GameEnums.BuildingType.INFIRMARY: 3,
	GameEnums.BuildingType.BARRACKS: 4,
}

func build_days(type: GameEnums.BuildingType, has_extra_labor: bool) -> int:
	var days: int = BASE_BUILD_DAYS[type]
	return maxi(days - (1 if has_extra_labor else 0), 1)

func is_valid_core_cell(cell: Vector2i, occupied: Dictionary) -> bool:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= 7 or cell.y >= 7:
		return false
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			if occupied.has(Vector2i(x, y)):
				return false
	return true
