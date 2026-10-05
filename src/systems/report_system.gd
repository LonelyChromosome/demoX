class_name ReportSystem
extends RefCounted

enum Accuracy { EXACT, VAGUE_BUT_TRUE, UNRELIABLE }

func accuracy_for_manager(manager: UnitState) -> Accuracy:
	if manager == null:
		return Accuracy.VAGUE_BUT_TRUE
	if manager.loyalty >= InformationSystem.HIGH_LOYALTY:
		return Accuracy.EXACT
	if manager.loyalty >= InformationSystem.MEDIUM_LOYALTY:
		return Accuracy.VAGUE_BUT_TRUE
	return Accuracy.UNRELIABLE

func can_report(state: GameState, type: GameEnums.BuildingType) -> bool:
	if state.day_one_full_knowledge:
		return true
	for candidate in state.buildings.values():
		if (
			candidate is BuildingState
			and candidate.type == type
			and candidate.phase == GameEnums.BuildingPhase.ACTIVE
			and state.units.has(candidate.manager_unit_id)
		):
			return true
	return false
