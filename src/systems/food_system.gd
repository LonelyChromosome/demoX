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


func resolve_consumption(
	state: GameState, result: TurnResolutionResult, building_system: BuildingSystem
) -> bool:
	var candidates := eligible_unit_ids(state)
	result.ration_candidate_ids = candidates.duplicate()
	result.ration_need = candidates.size()
	result.ration_food_available = maxi(0, mini(state.food, candidates.size()))
	if state.food < candidates.size():
		result.awaiting_ration = true
		return false
	state.food -= candidates.size()
	result.food_consumed += candidates.size()
	for unit_id in candidates:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			unit.hunger_streak = 0
			result.fed_unit_ids.append(unit_id)
	_cleanup_deaths(state, result, building_system)
	return true


func apply_ration(
	state: GameState,
	result: TurnResolutionResult,
	selected_unit_ids: Array[String],
	building_system: BuildingSystem
) -> bool:
	var selected: Array[String] = []
	var seen := {}
	for unit_id in selected_unit_ids:
		if seen.has(unit_id) or unit_id not in result.ration_candidate_ids:
			continue
		seen[unit_id] = true
		selected.append(unit_id)
	var feed_count := result.ration_food_available
	if selected.size() != feed_count:
		return false
	state.food -= feed_count
	result.food_consumed += feed_count
	for unit_id in result.ration_candidate_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		if unit_id in selected:
			unit.hunger_streak = 0
			result.fed_unit_ids.append(unit_id)
		else:
			unit.hunger_streak += 1
			result.unfed_unit_ids.append(unit_id)
	result.awaiting_ration = false
	_cleanup_deaths(state, result, building_system)
	return true


func eligible_unit_ids(state: GameState) -> Array[String]:
	var ids: Array[String] = []
	for candidate in state.units.values():
		if (
			candidate is UnitState
			and candidate.faction == GameEnums.Faction.PLAYER
			and candidate.away_days_left <= 0
			and consumes_food(candidate)
		):
			ids.append(candidate.id)
	ids.sort()
	return ids


func _cleanup_deaths(
	state: GameState, result: TurnResolutionResult, building_system: BuildingSystem
) -> void:
	var deaths: Array[String] = []
	for unit_id in result.unfed_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null and unit.hunger_streak >= STARVATION_DAYS:
			deaths.append(unit_id)
	for unit_id in deaths:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		result.starved_unit_cells[unit_id] = unit.board_cell
		if not unit.assigned_building_id.is_empty():
			building_system.remove_builder_from_construction(
				state, unit.assigned_building_id, unit.id
			)
		for candidate in state.buildings.values():
			if not (candidate is BuildingState):
				continue
			if candidate.manager_unit_id == unit.id:
				candidate.manager_unit_id = ""
			candidate.worker_unit_ids.erase(unit.id)
			candidate.builder_unit_ids.erase(unit.id)
			candidate.job_slots.erase(unit.board_cell)
		state.units.erase(unit.id)
		result.starved_unit_ids.append(unit.id)

func consumes_food(unit: UnitState) -> bool:
	return unit.rank != GameEnums.Rank.KING and unit.rank != GameEnums.Rank.QUEEN
