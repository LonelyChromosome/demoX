class_name CrisisEvents
extends RefCounted


static func install(engine: EventSystem) -> void:
	engine.register_condition_handler("storm_eligible", _storm_eligible)
	engine.register_effect_handler("storm_prepare", _prepare)
	engine.register_effect_handler("storm_impact", _impact)
	engine.register_condition_handler("bond_eligible", _bond_eligible)
	engine.register_effect_handler("bond_resolve", _bond_resolve)
	engine.register_definition({
		"id": "storm_crisis", "type": "crisis", "source": "World event",
		"title_key": "crisis.title", "description_key": "crisis.warning",
		"condition": "storm_eligible", "min_day": RunBalance.CRISIS_FIRST_DAY,
		"max_day": RunBalance.CRISIS_LAST_DAY,
		"stage_weights": {"early": 0, "mid": 2, "late": 5},
		"duration": 3, "choice_timeout": 1, "default_choice": "wait",
		"attention_level": GameEnums.AttentionLevel.IMPORTANT,
		"choices": [
			{"id": "reinforce", "label_key": "crisis.reinforce",
				"materials_required": RunBalance.REINFORCE_COST,
				"effects": [{"handler": "storm_prepare"}]},
			{"id": "wait", "label_key": "crisis.wait", "effects": []},
		],
		"stages": [
			{"effects": []},
			{"effects": [{"handler": "storm_impact"}]},
			{"effects": [{"handler": "report", "text_key": "crisis.aftermath"}]},
		],
		"resolution_text_key": "crisis.passed",
		"follow_up_event_ids": ["storm_recovery"],
	})
	engine.register_definition({
		"id": "storm_recovery", "type": "crisis", "source": "Building",
		"title_key": "crisis.recovery_title", "description_key": "crisis.aftermath",
		"condition": "never", "duration": 1, "stages": [{"effects": []}],
		"resolution_text_key": "crisis.recovery",
	})
	engine.register_definition({
		"id": "bond_solidarity", "type": "social", "source": "Relationship",
		"title_key": "s14.solidarity_title", "description_key": "s14.solidarity_body",
		"condition": "bond_eligible", "min_day": 9, "max_day": 29, "duration": 2,
		"stage_weights": {"early": 0, "mid": 2, "late": 3},
		"choices": [{"id": "accept", "label_key": "s14.solidarity_accept",
			"effects": [{"handler": "bond_resolve"}]}],
		"stages": [{"effects": []}, {"effects": []}],
		"resolution_text_key": "s14.solidarity_done",
	})


static func _eligible_buildings(state: GameState) -> Array[String]:
	var ids: Array[String] = []
	for building in state.buildings.values():
		if building is BuildingState and building.is_operational() and building.type in [
			GameEnums.BuildingType.FARM, GameEnums.BuildingType.MATERIAL_WORKSHOP,
		]:
			ids.append(building.id)
	ids.sort()
	return ids


static func _storm_eligible(state: GameState, _definition: Dictionary) -> bool:
	if _eligible_buildings(state).size() < 2:
		return false
	var chance := 35 if RunBalance.stage(state.day) == "late" else 20
	return RunBalance.roll(state.run_seed, state.day, "storm_eligibility") % 100 < chance


static func _prepare(state: GameState, event: EventState, _effect: Dictionary, result: TurnResolutionResult) -> void:
	# Recheck at commit: other planned orders may have spent the stockpile.
	if state.materials < RunBalance.REINFORCE_COST:
		_report(result, event, "crisis.unaffordable", GameEnums.AttentionLevel.IMPORTANT)
		return
	state.materials -= RunBalance.REINFORCE_COST
	result.materials_spent += RunBalance.REINFORCE_COST
	event.remember("reinforced", state.day)
	_report(result, event, "crisis.prepared", GameEnums.AttentionLevel.NOTICE)


static func _impact(state: GameState, event: EventState, _effect: Dictionary, result: TurnResolutionResult) -> void:
	for memory in event.memory:
		if memory.get("kind", "") == "reinforced":
			_report(result, event, "crisis.protected", GameEnums.AttentionLevel.NOTICE)
			return
	var ids := _eligible_buildings(state)
	if ids.is_empty():
		_report(result, event, "crisis.no_target", GameEnums.AttentionLevel.NOTICE)
		return
	var id: String = ids[RunBalance.roll(state.run_seed, event.start_day, "storm_target") % ids.size()]
	if BuildingSystem.new().damage(state, id, event.id):
		event.remember("building_damaged", state.day, {"building_id": id})
		var building: BuildingState = state.buildings[id]
		_report(result, event, "crisis.damage", GameEnums.AttentionLevel.IMPORTANT, {
			"building": LocalizationKeys.building_name(building.type),
		})


static func _bonded_pair(state: GameState) -> RelationshipState:
	var keys := state.relationships.keys()
	keys.sort()
	for key in keys:
		var pair := state.relationships[key] as RelationshipState
		if pair == null or pair.status != RelationshipState.BONDED:
			continue
		var a := state.units.get(pair.unit_a_id) as UnitState
		var b := state.units.get(pair.unit_b_id) as UnitState
		if a != null and b != null and a.is_in_city_roster() and b.is_in_city_roster():
			if a.loyalty < 0 or b.loyalty < 0:
				return pair
	return null


static func _bond_eligible(state: GameState, _definition: Dictionary) -> bool:
	return _bonded_pair(state) != null


static func _bond_resolve(state: GameState, event: EventState, _effect: Dictionary, result: TurnResolutionResult) -> void:
	var pair := _bonded_pair(state)
	if pair == null:
		return
	for id in [pair.unit_a_id, pair.unit_b_id]:
		LoyaltySystem.new().adjust_loyalty(state, id, 1, state.day,
			"Relationship", Localization.text("s14.solidarity_done"), "%s:%s" % [event.id, id], result)
	_report(result, event, "s14.solidarity_done", GameEnums.AttentionLevel.NOTICE)


static func _report(result: TurnResolutionResult, event: EventState, key: String, attention: int, args: Dictionary = {}) -> void:
	result.event_reports.append({"event_id": event.id, "text": Localization.text(key, args),
		"source": event.source, "attention": attention})
