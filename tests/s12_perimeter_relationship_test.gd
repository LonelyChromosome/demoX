extends SceneTree


func _init() -> void:
	_test_semantic_perimeter_snapshot()
	_test_relationship_core()
	_test_expedition_relationship_hook()
	print("S12_PERIMETER_RELATIONSHIP_TEST_OK")
	quit(0)


func _test_semantic_perimeter_snapshot() -> void:
	var state := GameState.new()
	state.perimeter_layout.forest_anchor = "tree_line"
	state.perimeter_layout.refugee_anchor = "outer_camp"
	state.perimeter_layout.wasteland_anchor = "open_ground"
	state.perimeter_layout.slot_order = ["wasteland", "forest", "refugee"]

	var group := OutsiderGroupState.new("refugees")
	group.name = "Nhóm tị nạn"
	group.support_active = true
	for index in range(2):
		var refugee := _unit(
			state, "refugee_%d" % index, GameEnums.Rank.QUEEN,
			GameEnums.Faction.OUTSIDER, Vector2i(-1, -1)
		)
		group.member_unit_ids.append(refugee.id)
	state.outsider_groups[group.id] = group

	var scout := _unit(
		state, "scout", GameEnums.Rank.ROOK,
		GameEnums.Faction.PLAYER, Vector2i(-1, -1)
	)
	scout.away_assignment_id = "expedition_a"
	scout.away_reason = "expedition"
	scout.away_days_left = 2
	var king := _unit(
		state, "king", GameEnums.Rank.KING,
		GameEnums.Faction.PLAYER, Vector2i(-1, -1)
	)
	king.away_assignment_id = "expedition_a"
	king.away_reason = "expedition"
	var expedition := ExpeditionState.new("expedition_a")
	expedition.unit_ids = [scout.id, king.id]
	expedition.days_left = 2
	state.expeditions[expedition.id] = expedition

	var developer := _unit(
		state, "developer", GameEnums.Rank.KNIGHT,
		GameEnums.Faction.PLAYER, Vector2i(-1, -1)
	)
	developer.away_assignment_id = "wasteland"
	developer.away_reason = "wasteland"
	state.wasteland.active = true
	state.wasteland.duration_days = 3
	state.wasteland.days_left = 2
	state.wasteland.participant_unit_ids = [developer.id]
	_unit(
		state, "city_pawn", GameEnums.Rank.PAWN,
		GameEnums.Faction.PLAYER, Vector2i(3, 6)
	)

	var view := PerimeterView.new()
	root.add_child(view)
	view.setup(state)
	var zones := view.snapshot
	_check(zones.forest.anchor == "tree_line", "Forest ignored its semantic anchor")
	_check(view.slot_index_for("forest") == 1, "Semantic slot order was ignored")
	_check(zones.refugee.count == 2, "Refugee view did not use group state")
	for piece in zones.refugee.pieces:
		_check(piece.rank == GameEnums.Rank.PAWN, "Refugee was not rendered as a Pawn")
	_check("được hỗ trợ" in zones.refugee.status, "Refugee support state was hidden")
	_check(zones.forest.count == 1, "Forest rendered invalid or missing away units")
	_check(zones.forest.pieces[0].rank == GameEnums.Rank.ROOK, "Forest lost unit rank")
	_check(king.id not in view.rendered_unit_ids(), "King was rendered outside the city")
	_check(zones.wasteland.count == 1, "Wasteland participant was not rendered")
	_check("còn 2 ngày" in zones.wasteland.status, "Wasteland days-left was hidden")
	_check(
		is_equal_approx(float(zones.wasteland.progress), 1.0 / 3.0),
		"Wasteland progress did not come from state"
	)
	var rendered := view.rendered_unit_ids()
	var unique := {}
	for unit_id in rendered:
		_check(not unique.has(unit_id), "A unit was duplicated between perimeter zones")
		unique[unit_id] = true
	for unit in state.units.values():
		if unit is UnitState and view._is_board_cell(unit.board_cell):
			_check(unit.id not in rendered, "A unit appeared on board and perimeter")

	var empty_view := PerimeterView.new()
	root.add_child(empty_view)
	empty_view.setup(GameState.new())
	_check(empty_view.snapshot.refugee.pieces.is_empty(), "Empty zone rendered fake refugees")


func _test_relationship_core() -> void:
	var state := GameState.new()
	_unit(state, "alpha", GameEnums.Rank.PAWN, GameEnums.Faction.PLAYER, Vector2i.ZERO)
	_unit(state, "beta", GameEnums.Rank.KNIGHT, GameEnums.Faction.PLAYER, Vector2i.ONE)
	_unit(state, "outsider", GameEnums.Rank.PAWN, GameEnums.Faction.OUTSIDER, Vector2i(-1, -1))
	var system := RelationshipSystem.new()
	var first := system.relationship_between(state, "alpha", "beta")
	var reverse := system.relationship_between(state, "beta", "alpha")
	_check(first == reverse and state.relationships.size() == 1, "A/B pair was not canonical")
	_check(
		system.relationship_between(state, "alpha", "outsider") == null,
		"Non-player relationship was created"
	)
	_check(
		system.adjust_affinity(
			state, "alpha", "beta", 4, 2, "work", "shared_watch", "work:watch:2"
		),
		"Affinity adjustment failed"
	)
	_check(
		system.adjust_trust(
			state, "beta", "alpha", 3, 2, "work", "shared_watch", "work:trust:2"
		),
		"Trust adjustment failed"
	)
	_check(first.affinity == 4 and first.trust == 3, "Relationship totals are wrong")
	_check(first.status == RelationshipState.CLOSE, "Close status condition was not applied")
	_check(
		not system.adjust_affinity(
			state, "alpha", "beta", 9, 2, "work", "duplicate", "work:watch:2"
		),
		"Duplicate source key was applied"
	)
	_check(first.affinity == 4, "Duplicate source changed affinity")
	_check(
		system.shared_event(
			state, "alpha", "beta", 3, "event", "shared_rescue",
			"event:rescue:3", 3, 2, ["rescue"]
		),
		"Shared event adjustment failed"
	)
	_check(first.status == RelationshipState.ROMANCE_CANDIDATE, "Candidate condition failed")
	_check(first.status != RelationshipState.BONDED, "High values auto-created romance")
	_check(
		"romance_choice" in system.available_relationship_events(state, "beta", "alpha"),
		"Candidate event was unavailable"
	)
	_check(first.shared_history.size() == 3, "Relationship history trace is incomplete")
	_check(first.shared_history[0].day == 2, "History trace lost day")
	_check(first.shared_history[0].source == "work", "History trace lost source")
	_check(first.shared_history[0].affinity_delta == 4, "History trace lost delta")


func _test_expedition_relationship_hook() -> void:
	var state := GameState.new()
	state.food = 30
	var first := _unit(
		state, "explorer_a", GameEnums.Rank.ROOK,
		GameEnums.Faction.PLAYER, Vector2i(0, 7)
	)
	var second := _unit(
		state, "explorer_b", GameEnums.Rank.PAWN,
		GameEnums.Faction.PLAYER, Vector2i(1, 7)
	)
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	manager.queue_expedition([first.id, second.id])
	manager.end_day()
	var expedition := state.expeditions.values()[0] as ExpeditionState
	expedition.outcome_kind = ExpeditionSystem.OUTCOME_EMPTY
	expedition.days_left = 1
	first.away_days_left = 1
	second.away_days_left = 1
	manager.end_day()
	var relationship := manager.relationship_system.relationship_between(
		state, first.id, second.id, false
	)
	_check(relationship != null, "Expedition outcome did not create a relationship")
	_check(
		relationship.affinity == 1 and relationship.trust == 1,
		"Expedition outcome applied wrong deltas"
	)
	_check(relationship.shared_history.size() == 1, "Expedition outcome was duplicated")
	manager.end_day()
	_check(relationship.shared_history.size() == 1, "Completed expedition applied twice")


func _unit(
	state: GameState, unit_id: String, rank: GameEnums.Rank,
	faction: GameEnums.Faction, cell: Vector2i
) -> UnitState:
	var unit := UnitState.new(unit_id)
	unit.display_name = unit_id
	unit.rank = rank
	unit.faction = faction
	unit.board_cell = cell
	state.units[unit.id] = unit
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
