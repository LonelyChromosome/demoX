class_name EventSystem
extends RefCounted

func can_open_large_event(state: GameState) -> bool:
	return state.active_event_id.is_empty()

func close_event(state: GameState, summary: String, result: String) -> void:
	state.remember(summary, result)
	state.active_event_id = ""
