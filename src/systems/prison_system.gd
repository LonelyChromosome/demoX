class_name PrisonSystem
extends RefCounted

const MANAGER_OFFSET := Vector2i(0, -1)
const GUARD_OFFSETS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0)]
const REQUIRED_GUARD_COUNT := 2


func manager_cell(prison: BuildingState) -> Vector2i:
	return prison.core_cell + MANAGER_OFFSET


func guard_cells(prison: BuildingState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in GUARD_OFFSETS:
		cells.append(prison.core_cell + offset)
	return cells


func prepare_staff_positions(state: GameState) -> void:
	for candidate in state.buildings.values():
		if _is_active_prison(candidate):
			candidate.job_slots[manager_cell(candidate)] = GameEnums.JobRole.PRISON_MANAGER
			for cell in guard_cells(candidate):
				candidate.job_slots[cell] = GameEnums.JobRole.PRISON_GUARD


func sync_staffing(state: GameState, result: TurnResolutionResult) -> void:
	prepare_staff_positions(state)
	for candidate in state.buildings.values():
		if not _is_active_prison(candidate):
			continue
		var old_staff: Array[String] = candidate.worker_unit_ids.duplicate()
		if not candidate.manager_unit_id.is_empty():
			old_staff.append(candidate.manager_unit_id)
		for unit_id in old_staff:
			var old_unit := state.units.get(unit_id) as UnitState
			if old_unit != null and old_unit.work_building_id == candidate.id:
				old_unit.work_building_id = ""
				old_unit.is_manager = false
		candidate.manager_unit_id = ""
		candidate.worker_unit_ids.clear()
		var manager := _available_player_at(state, manager_cell(candidate))
		if manager != null:
			candidate.manager_unit_id = manager.id
			manager.work_building_id = candidate.id
			manager.is_manager = true
		for cell in guard_cells(candidate):
			var guard := _available_player_at(state, cell)
			if guard == null or guard.id == candidate.manager_unit_id:
				continue
			candidate.worker_unit_ids.append(guard.id)
			guard.work_building_id = candidate.id
			guard.is_manager = false
		candidate.under_guarded = (
			not candidate.prisoner_unit_ids.is_empty()
			and guard_count(candidate) < REQUIRED_GUARD_COUNT
		)
		if candidate.under_guarded:
			result.prison_events.append({
				"kind": "under_guarded",
				"building_id": candidate.id,
				"core": candidate.core_cell,
			})


func guard_count(prison: BuildingState) -> int:
	return (1 if not prison.manager_unit_id.is_empty() else 0) + prison.worker_unit_ids.size()


func admit_prisoner(
	state: GameState, unit_id: String, prison_id: String, result: TurnResolutionResult = null
) -> bool:
	var unit := state.units.get(unit_id) as UnitState
	var prison := state.buildings.get(prison_id) as BuildingState
	if unit == null or not _is_active_prison(prison):
		return false
	if unit.faction != GameEnums.Faction.ENEMY:
		return false
	_cleanup_prison_membership(state, unit)
	unit.is_prisoner = true
	unit.prison_building_id = prison.id
	unit.prisoner_labor = false
	unit.labor_building_id = ""
	unit.board_cell = Vector2i(-1, -1)
	if unit.id not in prison.prisoner_unit_ids:
		prison.prisoner_unit_ids.append(unit.id)
	if unit.id not in state.prisoners:
		state.prisoners.append(unit.id)
	if result != null:
		result.prison_events.append({"kind": "admitted", "unit_name": _unit_name(unit)})
	return true


func commit_actions(
	state: GameState, orders: Array[PrisonerActionOrder], result: TurnResolutionResult
) -> void:
	for order in orders:
		var unit := state.units.get(order.prisoner_unit_id) as UnitState
		if unit == null or not unit.is_prisoner:
			result.reject("prisoner", order.prisoner_unit_id, "Tù binh không còn tồn tại")
			continue
		if order.action == GameEnums.PrisonerAction.RELEASE:
			_release(state, unit)
			result.prison_events.append({"kind": "released", "unit_name": _unit_name(unit)})
		elif order.action == GameEnums.PrisonerAction.KILL:
			var name := _unit_name(unit)
			_cleanup_prison_membership(state, unit)
			state.units.erase(unit.id)
			result.prison_events.append({"kind": "killed", "unit_name": name})
		elif order.action == GameEnums.PrisonerAction.SUBMIT:
			if not unit.submission_requested:
				result.reject("prisoner", unit.id, "Tù binh chưa yêu cầu quy phục")
				continue
			if state.player_roster_count() >= GameState.MAX_ROSTER:
				result.reject("prisoner", unit.id, "Đội hình đã đủ 16 quân")
				continue
			_accept_submission(state, unit)
			result.prison_events.append({"kind": "submitted", "unit_name": _unit_name(unit)})
		else:
			unit.escape_attempt_pending = false
			result.prison_events.append({"kind": "continued", "unit_name": _unit_name(unit)})


func commit_labor(
	state: GameState, orders: Array[AssignPrisonerLaborOrder], result: TurnResolutionResult
) -> void:
	for order in orders:
		var prisoner := state.units.get(order.prisoner_unit_id) as UnitState
		var building := state.buildings.get(order.building_id) as BuildingState
		if prisoner == null or not prisoner.is_prisoner:
			result.reject("prisoner_labor", order.prisoner_unit_id, "Tù binh không còn hợp lệ")
			continue
		if building == null or building.phase != GameEnums.BuildingPhase.BUILDING:
			result.reject("prisoner_labor", order.prisoner_unit_id, "Công trường không còn hợp lệ")
			continue
		var prison := state.buildings.get(prisoner.prison_building_id) as BuildingState
		if not _is_active_prison(prison):
			result.reject("prisoner_labor", order.prisoner_unit_id, "Nhà giam không còn hoạt động")
			continue
		prisoner.prisoner_labor = true
		prisoner.labor_building_id = building.id
		building.prisoner_labor += 1
		result.prison_labor_unit_ids.append(prisoner.id)
		result.prison_events.append({
			"kind": "labor", "unit_name": _unit_name(prisoner), "core": building.core_cell,
		})


func apply_construction_bonus(state: GameState) -> void:
	for candidate in state.buildings.values():
		if not (candidate is BuildingState) or candidate.phase != GameEnums.BuildingPhase.BUILDING:
			continue
		if (
			candidate.prisoner_labor > 0
			and not candidate.accelerated_by_builders
			and not candidate.labor_bonus_applied
			and candidate.days_left > 1
		):
			candidate.days_left -= 1
			candidate.labor_bonus_applied = true


func cleanup_cancelled_construction(state: GameState, building_id: String) -> void:
	for candidate in state.units.values():
		if candidate is UnitState and candidate.labor_building_id == building_id:
			candidate.prisoner_labor = false
			candidate.labor_building_id = ""
	var building := state.buildings.get(building_id) as BuildingState
	if building != null:
		building.prisoner_labor = 0


func finalize_day(state: GameState) -> void:
	for candidate in state.units.values():
		if not (candidate is UnitState) or not candidate.is_prisoner:
			continue
		candidate.prison_days += 1
		if candidate.prisoner_labor:
			var building := state.buildings.get(candidate.labor_building_id) as BuildingState
			if building != null:
				building.prisoner_labor = maxi(0, building.prisoner_labor - 1)
			candidate.prisoner_labor = false
			candidate.labor_building_id = ""


func request_escape_attempt(state: GameState, unit_id: String) -> bool:
	var unit := state.units.get(unit_id) as UnitState
	if unit == null or not unit.is_prisoner:
		return false
	unit.escape_attempt_pending = true
	return true


func request_submission(state: GameState, unit_id: String) -> bool:
	var unit := state.units.get(unit_id) as UnitState
	if unit == null or not unit.is_prisoner:
		return false
	unit.submission_requested = true
	return true


func _release(state: GameState, unit: UnitState) -> void:
	_cleanup_prison_membership(state, unit)
	unit.is_prisoner = false
	unit.prison_building_id = ""
	unit.prisoner_labor = false
	unit.labor_building_id = ""
	unit.escape_attempt_pending = false
	unit.submission_requested = false
	unit.board_cell = Vector2i(-1, -1)
	unit.memories.append("Được Vua tha khỏi Nhà giam.")


func _accept_submission(state: GameState, unit: UnitState) -> void:
	var former_rank := unit.rank
	var prison := state.buildings.get(unit.prison_building_id) as BuildingState
	_cleanup_prison_membership(state, unit)
	unit.old_rank_tag = former_rank
	unit.faction = GameEnums.Faction.PLAYER
	unit.rank = GameEnums.Rank.PAWN
	unit.is_prisoner = false
	unit.prison_building_id = ""
	unit.prisoner_labor = false
	unit.labor_building_id = ""
	unit.escape_attempt_pending = false
	unit.submission_requested = false
	unit.hunger_streak = 0
	unit.backstory.append("Từng là %s của quân địch." % _rank_name(former_rank))
	unit.board_cell = _first_free_cell(state, prison)


func _cleanup_prison_membership(state: GameState, unit: UnitState) -> void:
	for candidate in state.buildings.values():
		if candidate is BuildingState:
			candidate.prisoner_unit_ids.erase(unit.id)
			if unit.labor_building_id == candidate.id:
				candidate.prisoner_labor = maxi(0, candidate.prisoner_labor - 1)
	state.prisoners.erase(unit.id)


func _first_free_cell(state: GameState, prison: BuildingState) -> Vector2i:
	var building_system := BuildingSystem.new()
	var occupied := {}
	for candidate in state.units.values():
		if candidate is UnitState and candidate.board_cell.x >= 0:
			occupied[candidate.board_cell] = true
	if prison != null:
		for cell in building_system.operational_cells(prison.core_cell):
			if not occupied.has(cell):
				return cell
	for y in range(BuildingSystem.BOARD_SIZE):
		for x in range(BuildingSystem.BOARD_SIZE):
			var cell := Vector2i(x, y)
			if not occupied.has(cell) and not building_system.is_cell_reserved_by_building(state, cell):
				return cell
	return Vector2i(-1, -1)


func _available_player_at(state: GameState, cell: Vector2i) -> UnitState:
	for candidate in state.units.values():
		if (
			candidate is UnitState
			and candidate.faction == GameEnums.Faction.PLAYER
			and candidate.board_cell == cell
			and not candidate.locked_by_construction
			and not candidate.locked_by_healing
			and candidate.away_days_left <= 0
		):
			return candidate
	return null


func _is_active_prison(candidate: Variant) -> bool:
	return (
		candidate is BuildingState
		and candidate.type == GameEnums.BuildingType.PRISON
		and candidate.phase == GameEnums.BuildingPhase.ACTIVE
	)


func _unit_name(unit: UnitState) -> String:
	if not unit.display_name.is_empty():
		return unit.display_name
	return "Tù binh %s" % _rank_name(unit.rank) if unit.is_prisoner else _rank_name(unit.rank)


func _rank_name(rank: int) -> String:
	return ["Tốt", "Mã", "Xe", "Tịnh", "Hậu", "Vua"][rank]
