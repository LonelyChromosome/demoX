extends SceneTree


func _init() -> void:
	_test_loyalty_trace_and_levels()
	_test_romance_requires_explicit_confirmation()
	print("S12B_SOCIAL_CORE_TEST_OK")
	quit(0)


func _test_loyalty_trace_and_levels() -> void:
	var state := GameState.new()
	var unit := UnitState.new("guard")
	unit.display_name = "Tốt gác"
	unit.faction = GameEnums.Faction.PLAYER
	state.units[unit.id] = unit
	var outsider := UnitState.new("outsider")
	outsider.faction = GameEnums.Faction.OUTSIDER
	state.units[outsider.id] = outsider
	var system := LoyaltySystem.new()
	var result := TurnResolutionResult.new()
	result.resolved_day = 2

	_check(
		system.rebellion_level_for(0) == GameEnums.RebellionLevel.NONE,
		"Neutral loyalty was not stable"
	)
	for index in range(5):
		_check(
			system.adjust_loyalty(
				state, unit.id, -1, 2 + index, "test", "pressure",
				"loyalty:test:%d" % index, result
			),
			"Valid loyalty change was rejected"
		)
	_check(unit.loyalty == -5, "Loyalty total is wrong")
	_check(
		unit.rebellion_level == GameEnums.RebellionLevel.REVOLT,
		"Rebellion level did not reach REVOLT"
	)
	_check(
		not system.adjust_loyalty(
			state, unit.id, -1, 9, "test", "duplicate",
			"loyalty:test:4", result
		),
		"Duplicate loyalty source was applied"
	)
	_check(unit.loyalty_history.size() == 5, "Loyalty history is not traceable")
	_check(system.can_interrogate(unit), "High rebellion did not enable interrogation")
	_check(
		not system.adjust_loyalty(
			state, outsider.id, -1, 2, "test", "invalid",
			"loyalty:outsider", result
		),
		"Non-player loyalty was mutated"
	)
	var information := InformationSystem.new()
	information.resolve_daily_information(state, result)
	var found := false
	for entry in result.report_entries:
		if entry.source_label == "test" and "Trung thành" in entry.text:
			found = true
	_check(found, "Loyalty change did not reach the existing report system")


func _test_romance_requires_explicit_confirmation() -> void:
	var state := GameState.new()
	for unit_id in ["alpha", "beta"]:
		var unit := UnitState.new(unit_id)
		unit.faction = GameEnums.Faction.PLAYER
		state.units[unit.id] = unit
	var system := RelationshipSystem.new()
	_check(
		system.shared_event(
			state, "alpha", "beta", 2, "event", "shared_trial",
			"relationship:trial", 7, 5, ["trial"]
		),
		"Relationship setup failed"
	)
	var relationship := system.relationship_between(
		state, "alpha", "beta", false
	)
	_check(
		relationship.status == RelationshipState.ROMANCE_CANDIDATE,
		"Threshold did not create a romance candidate"
	)
	_check(
		relationship.status != RelationshipState.BONDED,
		"Romance auto-bonded without a player choice"
	)
	_check(
		system.confirm_romance(
			state, "beta", "alpha", 3, "relationship:romance:choice"
		),
		"Explicit romance confirmation failed"
	)
	_check(
		relationship.status == RelationshipState.BONDED,
		"Explicit romance choice did not bond the pair"
	)
	_check(
		not system.confirm_romance(
			state, "alpha", "beta", 3, "relationship:romance:choice"
		),
		"Romance confirmation was applied twice"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
