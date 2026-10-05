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
	event.title = str(definition.get("title", "Sự kiện"))
	event.description = str(definition.get("description", ""))
	event.start_day = state.day
	event.duration = maxi(1, int(definition.get("duration", _definition_duration(definition))))
	event.source = source if not source.is_empty() else str(definition.get("source", "World event"))
	event.target_id = target_id
	event.tags.assign(definition.get("tags", []))
	event.choices.assign(definition.get("choices", []))
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
			_append_report(result, event, "%s đang chờ quyết định của Vua." % event.title)
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
			_append_report(result, event, event.description)


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
	_append_report(result, event, str(definition.get("resolution_text", "%s đã khép lại." % event.title)))
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
		"id": "refugee_waiting", "type": "refugee", "title": "Những quân cờ ngoài cổng",
		"description": "Một nhóm nạn dân vẫn chờ bên ngoài thành.", "duration": 3,
		"condition": "outsider_present", "source": "Refugee camp",
		"attention_level": GameEnums.AttentionLevel.IMPORTANT, "tags": ["refugee", "multi_day"],
		"choices": [
			{"id": "support", "label": "Tiếp tục hỗ trợ", "effects": [
				{"handler": "outsider_pressure", "amount": -1},
				{"handler": "remember", "kind": "refugee_supported"},
			]},
			{"id": "wait", "label": "Để họ tiếp tục chờ", "effects": [
				{"handler": "outsider_pressure", "amount": 1},
				{"handler": "remember", "kind": "refugee_pressure"},
			]},
		],
		"stages": [
			{"effects": [{"handler": "report", "text": "Các quân Tốt ngoài cổng đã dựng chỗ trú tạm."}]},
			{"effects": [{"handler": "report", "text": "Lương thực và sự chờ đợi đang đè lên khu nạn dân."}]},
			{"effects": [{"handler": "report", "text": "Nhóm nạn dân cần một quyết định lâu dài."}]},
		], "follow_up_event_ids": ["refugee_aftercare"],
		"resolution_text": "Khu nạn dân đã bước sang một trạng thái mới."
	})
	register_definition({
		"id": "refugee_aftercare", "type": "refugee", "title": "Tin từ khu nạn dân",
		"description": "Quyết định trước đó đang để lại hệ quả.", "duration": 1,
		"condition": "never", "source": "Refugee camp",
		"attention_level": GameEnums.AttentionLevel.NOTICE, "tags": ["refugee", "follow_up"],
		"stages": [{"effects": [{"handler": "report", "text": "Khu nạn dân đã phản hồi quyết định của thành."}]}],
		"resolution_text": "Tin tiếp nối từ khu nạn dân đã được ghi nhận."
	})
	register_definition({
		"id": "forest_signs", "type": "forest", "title": "Dấu hiệu trong rừng",
		"description": "Người gác cổng báo có dấu vết lạ phía rừng.", "duration": 2,
		"condition": "forest_signal", "source": "Forest",
		"attention_level": GameEnums.AttentionLevel.NOTICE, "tags": ["forest", "encounter"],
		"choices": [
			{"id": "observe", "label": "Tiếp tục quan sát", "effects": [{"handler": "remember", "kind": "forest_observed"}]},
			{"id": "ignore", "label": "Không điều tra", "effects": [{"handler": "remember", "kind": "forest_ignored"}]},
		],
		"stages": [
			{"effects": [{"handler": "report", "text": "Những dấu vết chưa đủ để kết luận."}]},
			{"effects": [{"handler": "report", "text": "Báo cáo từ rừng đã được gửi về thành."}]},
		], "resolution_text": "Tin từ rừng đã được ghi vào sổ theo dõi."
	})
	register_definition({
		"id": "wasteland_work", "type": "wasteland", "title": "Khai phá Đất hoang",
		"description": "Công việc ngoài rìa thành đang tiếp diễn.", "duration": 2,
		"condition": "wasteland_active", "source": "Wasteland",
		"attention_level": GameEnums.AttentionLevel.NORMAL, "tags": ["wasteland", "development"],
		"stages": [
			{"effects": [{"handler": "report", "text": "Những ô đất đầu tiên đã được dọn sạch."}]},
			{"effects": [{"handler": "report", "text": "Đường vào khu khai phá đã thành hình."}]},
		], "follow_up_event_ids": ["wasteland_incident"],
		"resolution_text": "Đợt công việc tại Đất hoang đã được ghi nhận."
	})
	register_definition({
		"id": "wasteland_incident", "type": "wasteland", "title": "Trở ngại ở Đất hoang",
		"description": "Đội khai phá gặp một đoạn nền đất không ổn định.", "duration": 2,
		"condition": "never", "source": "Wasteland",
		"attention_level": GameEnums.AttentionLevel.NOTICE, "tags": ["wasteland", "incident"],
		"choices": [
			{"id": "reinforce", "label": "Gia cố lối đi", "effects": [{"handler": "remember", "kind": "wasteland_reinforced"}]},
			{"id": "reroute", "label": "Đi đường vòng", "effects": [
				{"handler": "wasteland_delay", "days": 1},
				{"handler": "remember", "kind": "wasteland_rerouted"},
			]},
		],
		"stages": [
			{"effects": [{"handler": "report", "text": "Đội khai phá đang đánh giá đoạn đất yếu."}]},
			{"effects": [{"handler": "report", "text": "Lối làm việc mới đã được ổn định."}]},
		], "resolution_text": "Trở ngại tại Đất hoang đã được xử lý."
	})


func _forest_signal_condition(state: GameState, _definition: Dictionary) -> bool:
	if state.day < 2:
		return false
	return absi((state.run_seed * 31 + state.day * 17) % 7) == 0


func _effect_report(_state: GameState, event: EventState, effect: Dictionary, result: TurnResolutionResult) -> void:
	_append_report(result, event, str(effect.get("text", event.description)))


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
