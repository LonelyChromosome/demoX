class_name ReportSystem
extends RefCounted

enum Accuracy { EXACT, VAGUE_BUT_TRUE, UNRELIABLE }

func accuracy_for_manager(manager: UnitState) -> Accuracy:
	if manager == null:
		return Accuracy.VAGUE_BUT_TRUE
	if manager.loyalty > 3:
		return Accuracy.EXACT
	if manager.loyalty >= 0:
		return Accuracy.VAGUE_BUT_TRUE
	return Accuracy.UNRELIABLE

func can_report(state: GameState, type: GameEnums.BuildingType) -> bool:
	return state.day_one_full_knowledge or state.has_active_building(type)
