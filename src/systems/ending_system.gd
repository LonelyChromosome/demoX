class_name EndingSystem
extends RefCounted

const REQUIRED := {
	GameEnums.Rank.KING: 1,
	GameEnums.Rank.QUEEN: 1,
	GameEnums.Rank.ROOK: 2,
	GameEnums.Rank.KNIGHT: 2,
	GameEnums.Rank.BISHOP: 2,
	GameEnums.Rank.PAWN: 8,
}

func complete_formation(state: GameState) -> bool:
	var counts := {}
	for rank in REQUIRED.keys():
		counts[rank] = 0
	for unit in state.units.values():
		if unit is UnitState and unit.is_in_city_roster() and counts.has(unit.rank):
			counts[unit.rank] += 1
	for rank in REQUIRED.keys():
		if counts[rank] != REQUIRED[rank]:
			return false
	return true
