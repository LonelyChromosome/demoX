extends SceneTree


func _init() -> void:
	_test_default_sample_definitions()
	_test_definition_and_multiday_flow()
	_test_choice_effect_once_and_follow_up()
	_test_report_attention_groups()
	print("S10_EVENT_ENGINE_TEST_OK")
	quit(0)


func _test_default_sample_definitions() -> void:
	var engine := EventSystem.new()
	for definition_id in [
		"refugee_waiting", "refugee_aftercare", "forest_signs",
		"wasteland_work", "wasteland_incident",
	]:
		_check(engine.definitions.has(definition_id), "Missing sample event: %s" % definition_id)


func _test_definition_and_multiday_flow() -> void:
	var engine := EventSystem.new()
	var state := GameState.new()
	state.day = 4
	var effect_calls := {"count": 0}
	engine.register_effect_handler("count_once", func(_state, _event, _effect, _result):
		effect_calls["count"] = int(effect_calls["count"]) + 1
	)
	_check(engine.register_definition({
		"id": "extension_test",
		"type": "test",
		"title": "Extensible",
		"description": "Registered without an engine branch.",
		"duration": 3,
		"source": "World event",
		"attention_level": GameEnums.AttentionLevel.CRITICAL,
		"stages": [
			{"duration": 2, "effects": [{"handler": "count_once"}]},
			{"effects": [{"handler": "report", "text": "Final stage"}]},
		],
	}), "Definition registration failed")
	var event := engine.create_event(state, "extension_test")
	_check(event != null and event.attention_level == GameEnums.AttentionLevel.CRITICAL, "Event creation lost definition data")
	engine.advance(state, TurnResolutionResult.new())
	_check(event.elapsed_days == 0 and event.stage == 0, "Event advanced on appearance day")
	state.day = 5
	engine.advance(state, TurnResolutionResult.new())
	engine.advance(state, TurnResolutionResult.new())
	_check(event.elapsed_days == 1 and event.stage == 0, "Same day advanced twice or stage did not persist")
	_check(effect_calls["count"] == 1, "Stage effect was applied more than once")
	state.day = 6
	engine.advance(state, TurnResolutionResult.new())
	_check(event.stage == 1 and not event.resolved, "Multi-day stage did not advance correctly")
	state.day = 7
	engine.advance(state, TurnResolutionResult.new())
	_check(event.resolved and effect_calls["count"] == 1, "Event did not resolve once at duration")
	state.day = 8
	engine.advance(state, TurnResolutionResult.new())
	_check(effect_calls["count"] == 1, "Resolved event ran again")


func _test_choice_effect_once_and_follow_up() -> void:
	var engine := EventSystem.new()
	var state := GameState.new()
	state.day = 10
	var choice_calls := {"count": 0}
	engine.register_effect_handler("choice_once", func(_state, _event, _effect, _result):
		choice_calls["count"] = int(choice_calls["count"]) + 1
	)
	_check(engine.register_definition({
		"id": "choice_parent", "type": "test", "title": "Choice parent",
		"duration": 2, "source": "Forest", "attention_level": GameEnums.AttentionLevel.IMPORTANT,
		"choices": [{"id": "act", "label": "Act", "effects": [{"handler": "choice_once"}]}],
		"stages": [{"effects": []}, {"effects": []}],
		"follow_up_event_ids": ["choice_follow_up"],
	}), "Choice definition registration failed")
	_check(engine.register_definition({
		"id": "choice_follow_up", "type": "test", "title": "Follow up",
		"duration": 1, "source": "Forest", "condition": "never", "stages": [{"effects": []}],
	}), "Follow-up definition registration failed")
	var event := engine.create_event(state, "choice_parent")
	_check(engine.choose_event(state, event.id, "act"), "Choice was rejected")
	_check(event.chosen_choice == "act", "Choice did not persist")
	_check(event.attention_level == GameEnums.AttentionLevel.NOTICE, "Handled event highlight did not reduce")
	state.day = 11
	engine.advance(state, TurnResolutionResult.new())
	state.day = 12
	engine.advance(state, TurnResolutionResult.new())
	_check(choice_calls["count"] == 1, "Choice effect was applied more than once")
	_check(event.resolved, "Choice event did not resolve")
	var follow_up: EventState
	for candidate in state.events.values():
		if candidate is EventState and candidate.definition_id == "choice_follow_up":
			follow_up = candidate
	_check(follow_up != null and not follow_up.resolved, "Follow-up event was not created")
	state.day = 13
	engine.advance(state, TurnResolutionResult.new())
	_check(follow_up.resolved, "Follow-up event did not advance")


func _test_report_attention_groups() -> void:
	var result := TurnResolutionResult.new()
	result.resolved_day = 3
	result.next_day = 4
	result.report_entries.append(ReportEntry.new(
		"Critical warning", 3, GameEnums.FactConfidence.REPORTED,
		"Forest", "", GameEnums.AttentionLevel.CRITICAL, "attention"
	))
	result.report_entries.append(ReportEntry.new(
		"Important warning", 3, GameEnums.FactConfidence.REPORTED,
		"Wasteland", "", GameEnums.AttentionLevel.IMPORTANT, "attention"
	))
	result.report_entries.append(ReportEntry.new(
		"Ordinary update", 3, GameEnums.FactConfidence.CONFIRMED,
		"Building", "", GameEnums.AttentionLevel.NORMAL, "summary"
	))
	var panel := ReportPanel.new()
	root.add_child(panel)
	panel.show_result(result)
	var body := panel.body_label.text
	_check(body.find("CẦN CHÚ Ý") < body.find("TODAY SUMMARY"), "Attention section was not first")
	_check(body.find("TODAY SUMMARY") < body.find("FULL LOG"), "Report groups are out of order")
	_check(body.find("Critical warning") < body.find("Important warning"), "Attention priority was not sorted")
	_check("Nguồn: Forest" in body and "Nguồn: Building" in body, "Report source was lost")
	panel.close()
	panel.open_latest()
	_check("Không có mục chưa đọc." in panel.body_label.text, "Read report highlight did not reduce")
	_check("Critical warning" in panel.body_label.text, "Read report was removed from history")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
