class_name EventSystem
extends RefCounted

var definitions: Dictionary = {}
var condition_handlers: Dictionary = {}
var effect_handlers: Dictionary = {}


func _init() -> void:
	_register_core_handlers()
	_register_default_definitions()


func register_definition(definition: Dictionary) -> bool:
	var definition_id := str(definition.get("id", ""))
	if (
		definition_id.is_empty()
		or not definition.has("stages")
		or not (definition.get("stages") is Array)
	):
		return false
	definitions[definition_id] = definition.duplicate(true)
	return true


func register_condition_handler(handler_id: String, handler: Callable) -> void:
	if not handler_id.is_empty() and handler.is_valid():
		condition_handlers[handler_id] = handler


func register_effect_handler(handler_id: String, handler: Callable) -> void:
	if not handler_id.is_empty() and handler.is_valid():
		effect_handlers[handler_id] = handler


func can_open_large_event(state: GameState) -> bool:
	for candidate in state.events.values():
		if candidate is EventState and not candidate.resolved and candidate.attention_level >= GameEnums.AttentionLevel.IMPORTANT:
			return false
	return true


func create_event(state: GameState, definition_id: String, source := "", target_id := "") -> EventState:
	var definition: Dictionary = definitions.get(definition_id, {})
	if definition.is_empty():
		return null
	state.event_sequence += 1
	var event := EventState.new("event_%d" % state.event_sequence)
	event.definition_id = definition_id
	event.type = str(definition.get("type", "world"))
	event.title = _definition_text(definition, "title", "common.unknown")
	event.description = _definition_text(definition, "description", "")
	event.start_day = state.day
	event.duration = maxi(1, int(definition.get("duration", _definition_duration(definition))))
	event.source = source if not source.is_empty() else str(definition.get("source", "World event"))
	event.target_id = target_id
	event.tags.assign(definition.get("tags", []))
	var localized_choices: Array[Dictionary] = []
	for choice in definition.get("choices", []):
		var localized_choice: Dictionary = choice.duplicate(true)
		if localized_choice.has("label_key"):
			localized_choice.label = Localization.text(str(localized_choice.label_key))
		localized_choices.append(localized_choice)
	event.choices.assign(localized_choices)
	event.follow_up_event_ids.assign(definition.get("follow_up_event_ids", []))
	event.attention_level = int(definition.get("attention_level", GameEnums.AttentionLevel.NORMAL))
	if not event.choices.is_empty():
		event.status = GameEnums.EventStatus.WAITING_CHOICE
	state.events[event.id] = event
	if event.attention_level >= GameEnums.AttentionLevel.IMPORTANT:
		state.active_event_id = event.id
	return event


func choose_event(state: GameState, event_id: String, choice_id: String) -> bool:
	var event := state.events.get(event_id) as EventState
	if event == null or event.resolved or not event.chosen_choice.is_empty():
		return false
	for choice in event.choices:
		if str(choice.get("id", "")) == choice_id:
			event.chosen_choice = choice_id
			event.status = GameEnums.EventStatus.ACTIVE
			event.remember("choice", state.day, {"choice_id": choice_id})
			event.attention_level = mini(event.attention_level, GameEnums.AttentionLevel.NOTICE)
			if state.active_event_id == event.id:
				state.active_event_id = ""
			return true
	return false


func advance(state: GameState, result: TurnResolutionResult) -> void:
	_spawn_triggered_events(state, result)
	var ids := state.events.keys()
	ids.sort()
	for event_id in ids:
		var event := state.events.get(event_id) as EventState
		if event == null or event.resolved:
			continue
		if event.start_day >= state.day or event.last_advanced_day >= state.day:
			continue
		var definition: Dictionary = definitions.get(event.definition_id, {})
		if definition.is_empty():
			continue
		if event.status == GameEnums.EventStatus.WAITING_CHOICE and event.chosen_choice.is_empty():
			_append_report(result, event, Localization.text("event.waiting_choice", {"title": _event_title(event)}))
			event.last_advanced_day = state.day
			continue
		var stages: Array = definition.get("stages", [])
		if event.stage < stages.size():
			var current_stage: Dictionary = stages[event.stage]
			_apply_effect_list(
				state, event, current_stage.get("effects", []), result,
				"stage:%d" % event.stage
			)
			_apply_choice_effects(state, event, result)
			if event.stage_elapsed_days == 0:
				event.remember("stage", state.day, {"stage": event.stage})
			event.stage_elapsed_days += 1
			var stage_duration := maxi(1, int(current_stage.get("duration", 1)))
			if event.stage_elapsed_days >= stage_duration:
				event.stage += 1
				event.stage_elapsed_days = 0
		else:
			_apply_choice_effects(state, event, result)
		event.elapsed_days += 1
		event.last_advanced_day = state.day
		if event.elapsed_days >= event.duration:
			_resolve_event(state, event, definition, result)


func close_event(state: GameState, summary: String, result_text: String) -> void:
	state.remember(summary, result_text)
	state.active_event_id = ""


func _spawn_triggered_events(state: GameState, result: TurnResolutionResult) -> void:
	var definition_ids := definitions.keys()
	definition_ids.sort()
	for definition_id in definition_ids:
		if definition_id in state.resolved_event_definition_ids or _has_definition_active(state, definition_id):
			continue
		var definition: Dictionary = definitions[definition_id]
		var condition_id := str(definition.get("condition", "never"))
		var handler := condition_handlers.get(condition_id) as Callable
		if not handler.is_valid() or not handler.call(state, definition):
			continue
		var target_id := str(definition.get("target_id", ""))
		if condition_id == "outsider_present":
			var group_ids := state.outsider_groups.keys()
			group_ids.sort()
			target_id = str(group_ids[0]) if not group_ids.is_empty() else ""
		var event := create_event(state, definition_id, str(definition.get("source", "")), target_id)
		if event != null:
			_append_report(result, event, _definition_text(definition, "description", "", event.description))


func _apply_effect_list(
	state: GameState,
	event: EventState,
	effects: Array,
	result: TurnResolutionResult,
	prefix: String
) -> void:
	for effect_index in range(effects.size()):
		var effect: Dictionary = effects[effect_index]
		var effect_key := "%s:%d" % [prefix, effect_index]
		if event.has_applied_effect(effect_key):
			continue
		var handler_id := str(effect.get("handler", ""))
		var handler := effect_handlers.get(handler_id) as Callable
		if handler.is_valid():
			handler.call(state, event, effect, result)
			event.mark_effect_applied(effect_key)


func _apply_choice_effects(
	state: GameState, event: EventState, result: TurnResolutionResult
) -> void:
	for choice in event.choices:
		if str(choice.get("id", "")) != event.chosen_choice:
			continue
		_apply_effect_list(
			state, event, choice.get("effects", []), result,
			"choice:%s" % event.chosen_choice
		)


func _resolve_event(state: GameState, event: EventState, definition: Dictionary, result: TurnResolutionResult) -> void:
	event.resolved = true
	event.status = GameEnums.EventStatus.RESOLVED
	event.remember("resolved", state.day)
	if event.definition_id not in state.resolved_event_definition_ids:
		state.resolved_event_definition_ids.append(event.definition_id)
	if state.active_event_id == event.id:
		state.active_event_id = ""
	var fallback := Localization.text("event.closed", {"title": _event_title(event)})
	_append_report(result, event, _definition_text(definition, "resolution_text", "", fallback))
	for follow_up_id in event.follow_up_event_ids:
		if definitions.has(follow_up_id) and not _has_definition_active(state, follow_up_id):
			create_event(state, follow_up_id, event.source, event.target_id)


func _append_report(result: TurnResolutionResult, event: EventState, text: String) -> void:
	if text.is_empty():
		return
	result.event_reports.append({
		"event_id": event.id,
		"text": text,
		"source": event.source,
		"attention": event.attention_level,
	})


func _has_definition_active(state: GameState, definition_id: String) -> bool:
	for candidate in state.events.values():
		if candidate is EventState and candidate.definition_id == definition_id and not candidate.resolved:
			return true
	return false


func _definition_duration(definition: Dictionary) -> int:
	var total := 0
	for stage_definition in definition.get("stages", []):
		total += maxi(1, int(stage_definition.get("duration", 1)))
	return maxi(1, total)


func _register_core_handlers() -> void:
	register_condition_handler("always", func(_state, _definition): return true)
	register_condition_handler("never", func(_state, _definition): return false)
	register_condition_handler("outsider_present", func(state, _definition): return not state.outsider_groups.is_empty())
	register_condition_handler("wasteland_active", func(state, _definition): return state.wasteland.active)
	register_condition_handler("forest_signal", _forest_signal_condition)
	register_effect_handler("report", _effect_report)
	register_effect_handler("outsider_pressure", _effect_outsider_pressure)
	register_effect_handler("wasteland_delay", _effect_wasteland_delay)
	register_effect_handler("remember", _effect_remember)


func _register_default_definitions() -> void:
	register_definition({
		"id": "refugee_waiting", "type": "refugee", "title_key": "event.refugee_waiting.title",
		"description_key": "event.refugee_waiting.description", "duration": 3,
		"condition": "outsider_present", "source": "Refugee camp",
		"attention_level": GameEnums.AttentionLevel.IMPORTANT, "tags": ["refugee", "multi_day"],
		"choices": [
			{"id": "support", "label_key": "event.refugee_waiting.support", "effects": [
				{"handler": "outsider_pressure", "amount": -1},
				{"handler": "remember", "kind": "refugee_supported"},
			]},
			{"id": "wait", "label_key": "event.refugee_waiting.wait", "effects": [
				{"handler": "outsider_pressure", "amount": 1},
				{"handler": "remember", "kind": "refugee_pressure"},
			]},
		],
		"stages": [
			{"effects": [{"handler": "report", "text_key": "event.refugee_waiting.stage1"}]},
			{"effects": [{"handler": "report", "text_key": "event.refugee_waiting.stage2"}]},
			{"effects": [{"handler": "report", "text_key": "event.refugee_waiting.stage3"}]},
		], "follow_up_event_ids": ["refugee_aftercare"],
		"resolution_text_key": "event.refugee_waiting.resolution"
	})
	register_definition({
		"id": "refugee_aftercare", "type": "refugee", "title_key": "event.refugee_aftercare.title",
		"description_key": "event.refugee_aftercare.description", "duration": 1,
		"condition": "never", "source": "Refugee camp",
		"attention_level": GameEnums.AttentionLevel.NOTICE, "tags": ["refugee", "follow_up"],
		"stages": [{"effects": [{"handler": "report", "text_key": "event.refugee_aftercare.stage1"}]}],
		"resolution_text_key": "event.refugee_aftercare.resolution"
	})
	register_definition({
		"id": "forest_signs", "type": "forest", "title_key": "event.forest_signs.title",
		"description_key": "event.forest_signs.description", "duration": 2,
		"condition": "forest_signal", "source": "Forest",
		"attention_level": GameEnums.AttentionLevel.NOTICE, "tags": ["forest", "encounter"],
		"choices": [
			{"id": "observe", "label_key": "event.forest_signs.observe", "effects": [{"handler": "remember", "kind": "forest_observed"}]},
			{"id": "ignore", "label_key": "event.forest_signs.ignore", "effects": [{"handler": "remember", "kind": "forest_ignored"}]},
		],
		"stages": [
			{"effects": [{"handler": "report", "text_key": "event.forest_signs.stage1"}]},
			{"effects": [{"handler": "report", "text_key": "event.forest_signs.stage2"}]},
		], "resolution_text_key": "event.forest_signs.resolution"
	})
	register_definition({
		"id": "wasteland_work", "type": "wasteland", "title_key": "event.wasteland_work.title",
		"description_key": "event.wasteland_work.description", "duration": 2,
		"condition": "wasteland_active", "source": "Wasteland",
		"attention_level": GameEnums.AttentionLevel.NORMAL, "tags": ["wasteland", "development"],
		"stages": [
			{"effects": [{"handler": "report", "text_key": "event.wasteland_work.stage1"}]},
			{"effects": [{"handler": "report", "text_key": "event.wasteland_work.stage2"}]},
		], "follow_up_event_ids": ["wasteland_incident"],
		"resolution_text_key": "event.wasteland_work.resolution"
	})
	register_definition({
		"id": "wasteland_incident", "type": "wasteland", "title_key": "event.wasteland_incident.title",
		"description_key": "event.wasteland_incident.description", "duration": 2,
		"condition": "never", "source": "Wasteland",
		"attention_level": GameEnums.AttentionLevel.NOTICE, "tags": ["wasteland", "incident"],
		"choices": [
			{"id": "reinforce", "label_key": "event.wasteland_incident.reinforce", "effects": [{"handler": "remember", "kind": "wasteland_reinforced"}]},
			{"id": "reroute", "label_key": "event.wasteland_incident.reroute", "effects": [
				{"handler": "wasteland_delay", "days": 1},
				{"handler": "remember", "kind": "wasteland_rerouted"},
			]},
		],
		"stages": [
			{"effects": [{"handler": "report", "text_key": "event.wasteland_incident.stage1"}]},
			{"effects": [{"handler": "report", "text_key": "event.wasteland_incident.stage2"}]},
		], "resolution_text_key": "event.wasteland_incident.resolution"
	})


func _forest_signal_condition(state: GameState, _definition: Dictionary) -> bool:
	if state.day < 2:
		return false
	return absi((state.run_seed * 31 + state.day * 17) % 7) == 0


func _effect_report(_state: GameState, event: EventState, effect: Dictionary, result: TurnResolutionResult) -> void:
	var text := Localization.text(str(effect.text_key)) if effect.has("text_key") else str(effect.get("text", event.description))
	_append_report(result, event, text)


func _effect_outsider_pressure(state: GameState, event: EventState, effect: Dictionary, _result: TurnResolutionResult) -> void:
	var group := state.outsider_groups.get(event.target_id) as OutsiderGroupState
	if group != null:
		group.pressure = clampi(group.pressure + int(effect.get("amount", 0)), GameEnums.OutsidePressure.CALM, GameEnums.OutsidePressure.RIOT)


func _effect_wasteland_delay(state: GameState, _event: EventState, effect: Dictionary, _result: TurnResolutionResult) -> void:
	if state.wasteland.active:
		state.wasteland.days_left += maxi(0, int(effect.get("days", 0)))


func _effect_remember(state: GameState, event: EventState, effect: Dictionary, _result: TurnResolutionResult) -> void:
	var kind := str(effect.get("kind", "event_choice"))
	event.remember(kind, state.day)
	state.remember("%s: %s" % [event.title, kind], kind)


func _definition_text(
	definition: Dictionary, field: String, default_key: String, fallback := ""
) -> String:
	var key_field := "%s_key" % field
	if definition.has(key_field):
		return Localization.text(str(definition[key_field]))
	if definition.has(field):
		return str(definition[field])
	return Localization.text(default_key) if not default_key.is_empty() else fallback


func _event_title(event: EventState) -> String:
	var definition: Dictionary = definitions.get(event.definition_id, {})
	return _definition_text(definition, "title", "", event.title)
