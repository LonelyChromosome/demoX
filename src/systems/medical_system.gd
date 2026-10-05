class_name MedicalSystem
extends RefCounted

const SLOT_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0),
]


func treatment_slots(building: BuildingState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if building == null or building.type != GameEnums.BuildingType.INFIRMARY:
		return result
	for offset in SLOT_OFFSETS:
		result.append(building.core_cell + offset)
	return result


func infirmary_at_slot(state: GameState, cell: Vector2i) -> BuildingState:
	for candidate in state.buildings.values():
		if (
			candidate is BuildingState
			and candidate.type == GameEnums.BuildingType.INFIRMARY
			and candidate.phase == GameEnums.BuildingPhase.ACTIVE
			and cell in treatment_slots(candidate)
		):
			return candidate
	return null


func prepare_slots(state: GameState) -> void:
	for candidate in state.buildings.values():
		if (
			candidate is BuildingState
			and candidate.type == GameEnums.BuildingType.INFIRMARY
			and candidate.phase == GameEnums.BuildingPhase.ACTIVE
		):
			for cell in treatment_slots(candidate):
				candidate.job_slots[cell] = GameEnums.JobRole.TREATMENT


func sync_and_advance(state: GameState, result: TurnResolutionResult) -> void:
	prepare_slots(state)
	for candidate in state.buildings.values():
		if not (
			candidate is BuildingState
			and candidate.type == GameEnums.BuildingType.INFIRMARY
			and candidate.phase == GameEnums.BuildingPhase.ACTIVE
		):
			continue
		var previous: Array[String] = candidate.patient_unit_ids.duplicate()
		candidate.patient_unit_ids.clear()
		for cell in treatment_slots(candidate):
			var unit := _player_unit_at(state, cell)
			if unit == null or not unit.injured:
				continue
			candidate.patient_unit_ids.append(unit.id)
			if not unit.locked_by_healing:
				result.medical_events.append({"kind": "admitted", "unit_name": _unit_name(unit)})
			_clear_other_jobs(state, unit)
			unit.locked_by_healing = true
			unit.work_building_id = ""
			unit.is_manager = false
			unit.healing_days_left = maxi(0, unit.healing_days_left - 1)
			if unit.healing_days_left <= 0:
				unit.healing_days_left = 0
				unit.injured = false
				unit.locked_by_healing = false
				candidate.patient_unit_ids.erase(unit.id)
				result.medical_events.append({"kind": "recovered", "unit_name": _unit_name(unit)})
		for unit_id in previous:
			if unit_id in candidate.patient_unit_ids:
				continue
			var old_patient := state.units.get(unit_id) as UnitState
			if old_patient != null and old_patient.board_cell not in treatment_slots(candidate):
				old_patient.locked_by_healing = false


func _player_unit_at(state: GameState, cell: Vector2i) -> UnitState:
	for candidate in state.units.values():
		if (
			candidate is UnitState
			and candidate.faction == GameEnums.Faction.PLAYER
			and candidate.board_cell == cell
		):
			return candidate
	return null


func _unit_name(unit: UnitState) -> String:
	return unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank)


func _rank_name(rank: int) -> String:
	return ["Tốt", "Mã", "Xe", "Tịnh", "Hậu", "Vua"][rank]


func _clear_other_jobs(state: GameState, unit: UnitState) -> void:
	for candidate in state.buildings.values():
		if not (candidate is BuildingState):
			continue
		if candidate.manager_unit_id == unit.id:
			candidate.manager_unit_id = ""
		candidate.worker_unit_ids.erase(unit.id)
	unit.work_building_id = ""
	unit.is_manager = false