class_name PromotionSystem
extends RefCounted

const REQUIRED_GUARD_DAYS := 3
const REQUIRED_FOOD := 5
const REQUIRED_MATERIALS := 5

func has_merit(unit: UnitState) -> bool:
	return unit.guard_days >= REQUIRED_GUARD_DAYS or unit.food_brought_home >= REQUIRED_FOOD or unit.materials_brought_home >= REQUIRED_MATERIALS or unit.memories.has("proved_value")

func can_promote(state: GameState, unit: UnitState) -> bool:
	return state.has_active_building(GameEnums.BuildingType.BARRACKS) and unit.rank == GameEnums.Rank.PAWN and has_merit(unit)

func promote(unit: UnitState, new_rank: GameEnums.Rank) -> bool:
	if new_rank in [GameEnums.Rank.QUEEN, GameEnums.Rank.KING]:
		return false
	unit.rank = new_rank
	return true
