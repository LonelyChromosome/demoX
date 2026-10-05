class_name RuinSystem
extends RefCounted

const MIN_CLUSTER_COUNT := 1
const MAX_OCCUPIED_CELLS := 3
const REWARD_BY_SIZE := {1: 1, 2: 2}


func spawn_day_one(state: GameState) -> void:
	if state.day != 1 or not state.ruins.is_empty():
		return
	var occupied := _blocked_cells(state)
	var seed_value := _stable_seed(state.run_seed, "day_one_ruins")
	var target_cells := MIN_CLUSTER_COUNT + seed_value % MAX_OCCUPIED_CELLS
	var remaining := target_cells
	var ruin_index := 1
	while remaining > 0:
		var size := 2 if remaining >= 2 and _stable_seed(seed_value, "size_%d" % ruin_index) % 2 == 0 else 1
		var cells := _find_cells(seed_value, ruin_index, size, occupied)
		if cells.is_empty() and size == 2:
			size = 1
			cells = _find_cells(seed_value, ruin_index, size, occupied)
		if cells.is_empty():
			break
		var ruin := RuinState.new("ruin_%d" % ruin_index, cells)
		ruin.material_reward = REWARD_BY_SIZE.get(size, size)
		state.ruins[ruin.id] = ruin
		for cell in cells:
			occupied[cell] = true
		remaining -= size
		ruin_index += 1


func ruin_at(state: GameState, cell: Vector2i) -> RuinState:
	for candidate in state.ruins.values():
		if candidate is RuinState and candidate.occupies(cell):
			return candidate
	return null


func is_blocked(state: GameState, cell: Vector2i) -> bool:
	return ruin_at(state, cell) != null


func start_cleanup(state: GameState, ruin_id: String) -> bool:
	if not state.active_cleanup_ruin_id.is_empty():
		return false
	var ruin := state.ruins.get(ruin_id) as RuinState
	if ruin == null or ruin.status != RuinState.Status.BLOCKING:
		return false
	ruin.status = RuinState.Status.CLEANING
	ruin.cleanup_elapsed = 0.0
	state.active_cleanup_ruin_id = ruin.id
	return true


func advance_cleanup(state: GameState, delta: float) -> Dictionary:
	if state.active_cleanup_ruin_id.is_empty():
		return {}
	var ruin := state.ruins.get(state.active_cleanup_ruin_id) as RuinState
	if ruin == null or ruin.status != RuinState.Status.CLEANING:
		state.active_cleanup_ruin_id = ""
		return {}
	ruin.cleanup_elapsed = minf(ruin.cleanup_seconds, ruin.cleanup_elapsed + maxf(delta, 0.0))
	if ruin.cleanup_elapsed < ruin.cleanup_seconds:
		return {"completed": false, "ruin_id": ruin.id, "progress": ruin.progress()}
	ruin.status = RuinState.Status.CLEARED
	state.active_cleanup_ruin_id = ""
	state.materials += ruin.material_reward
	state.remember("Tàn cuộc %s đã được dọn." % ruin.id, "ruin_cleared")
	return {
		"completed": true,
		"ruin_id": ruin.id,
		"reward": ruin.material_reward,
		"cells": ruin.cells.duplicate(),
	}


func active_progress(state: GameState) -> float:
	var ruin := state.ruins.get(state.active_cleanup_ruin_id) as RuinState
	return ruin.progress() if ruin != null else 0.0


func _find_cells(seed_value: int, index: int, size: int, occupied: Dictionary) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for y in range(BuildingSystem.BOARD_SIZE):
		for x in range(BuildingSystem.BOARD_SIZE):
			candidates.append(Vector2i(x, y))
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _cell_score(seed_value, index, a) < _cell_score(seed_value, index, b)
	)
	for first in candidates:
		if occupied.has(first):
			continue
		if size == 1:
			return [first]
		var horizontal := _stable_seed(seed_value + index, "orientation") % 2 == 0
		var second := first + (Vector2i.RIGHT if horizontal else Vector2i.DOWN)
		if _inside(second) and not occupied.has(second):
			return [first, second]
	return []


func _blocked_cells(state: GameState) -> Dictionary:
	var blocked := {}
	for candidate in state.units.values():
		if candidate is UnitState and _inside(candidate.board_cell):
			blocked[candidate.board_cell] = true
	var building_system := BuildingSystem.new()
	for candidate in state.buildings.values():
		if candidate is BuildingState:
			for cell in building_system.footprint(candidate.core_cell):
				blocked[cell] = true
	return blocked


func _cell_score(seed_value: int, index: int, cell: Vector2i) -> int:
	return _stable_seed(seed_value, "%d|%d|%d" % [index, cell.x, cell.y])


func _stable_seed(seed_value: int, salt: String) -> int:
	var text := "%d|%s" % [seed_value, salt]
	var value := 216613626
	for character_index in range(text.length()):
		value = (value * 16777619 + text.unicode_at(character_index)) % 2147483647
	return absi(value)


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < BuildingSystem.BOARD_SIZE and cell.y < BuildingSystem.BOARD_SIZE
