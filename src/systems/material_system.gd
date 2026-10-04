class_name MaterialSystem
extends RefCounted

const WORKSHOP_OUTPUT := {
	GameEnums.Rank.PAWN: 1,
	GameEnums.Rank.KNIGHT: 2,
	GameEnums.Rank.ROOK: 2,
	GameEnums.Rank.BISHOP: 2,
	GameEnums.Rank.QUEEN: 3,
	GameEnums.Rank.KING: 0,
}


func manager_output(state: GameState, building: BuildingState) -> int:
	if building.phase not in [GameEnums.BuildingPhase.ACTIVE, GameEnums.BuildingPhase.DEMOLISHING]:
		return 0
	if building.type != GameEnums.BuildingType.MATERIAL_WORKSHOP:
		return 0
	var manager := state.units.get(building.manager_unit_id) as UnitState
	if manager == null or manager.faction != GameEnums.Faction.PLAYER:
		return 0
	return WORKSHOP_OUTPUT.get(manager.rank, 0)


func produce(state: GameState, result: TurnResolutionResult) -> void:
	for candidate in state.buildings.values():
		if not (candidate is BuildingState):
			continue
		var output := manager_output(state, candidate)
		if output <= 0:
			continue
		state.materials += output
		result.materials_produced += output
