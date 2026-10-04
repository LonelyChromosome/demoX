class_name FoodSystem
extends RefCounted

const STARVATION_DAYS := 3
const FARM_BASE_OUTPUT := 2
const FARM_OUTPUT_PER_WORKER := 2
const FARM_MAX_WORKERS := 6

func farm_output(worker_count: int) -> int:
	return FARM_BASE_OUTPUT + mini(worker_count, FARM_MAX_WORKERS) * FARM_OUTPUT_PER_WORKER

func consumes_food(unit: UnitState) -> bool:
	return unit.rank != GameEnums.Rank.KING and unit.rank != GameEnums.Rank.QUEEN
