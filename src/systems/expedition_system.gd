class_name ExpeditionSystem
extends RefCounted

const TEAM_SIZE := 2
const MAX_UNITS_OUT_PER_DAY := 8

func can_dispatch(unit_ids: Array[String]) -> bool:
	return unit_ids.size() == TEAM_SIZE

func context_weights(state: GameState) -> Dictionary:
	var weights := {
		"food": 1.0,
		"materials": 1.0,
		"people": 0.6,
		"injury": 0.35,
		"death": 0.15,
		"late_return": 0.15,
		"empty": 0.35,
	}
	if state.food < 5:
		weights.food = 2.2
	if state.materials < 2:
		weights.materials = 1.8
	if state.player_roster_count() < GameState.MAX_ROSTER:
		weights.people = 1.0
	return weights
