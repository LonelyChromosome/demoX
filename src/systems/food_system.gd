class_name FoodSystem
extends RefCounted

const STARVATION_DAYS := 3
const FARM_BASE_OUTPUT := 2
const FARM_OUTPUT_PER_WORKER := 2
const FARM_MAX_WORKERS := 6

func farm_output(worker_count: int) -> int:
	return FARM_BASE_OUTPUT + mini(worker_count, FARM_MAX_WORKERS) * FARM_OUTPUT_PER_WORKER


func farm_staff_count(state: GameState, building: BuildingState) -> int:
	var assigned := {}
	if not building.manager_unit_id.is_empty():
		var manager := state.units.get(building.manager_unit_id) as UnitState
		if manager != null and manager.faction == GameEnums.Faction.PLAYER:
			assigned[manager.id] = true
	for worker_id in building.worker_unit_ids:
		var worker := state.units.get(worker_id) as UnitState
		if worker != null and worker.faction == GameEnums.Faction.PLAYER:
			assigned[worker.id] = true
	return mini(assigned.size(), FARM_MAX_WORKERS)


func production_for_building(state: GameState, building: BuildingState) -> int:
	if building.phase not in [GameEnums.BuildingPhase.ACTIVE, GameEnums.BuildingPhase.DEMOLISHING]:
		return 0
	if building.type != GameEnums.BuildingType.FARM:
		return 0
	return farm_output(farm_staff_count(state, building))


func produce(state: GameState, result: TurnResolutionResult) -> void:
	for candidate in state.buildings.values():
		if not (candidate is BuildingState):
			continue
		var output := production_for_building(state, candidate)
		if output <= 0:
			continue
		state.food += output
		result.food_produced += output

func consumes_food(unit: UnitState) -> bool:
	return unit.rank != GameEnums.Rank.KING and unit.rank != GameEnums.Rank.QUEEN
