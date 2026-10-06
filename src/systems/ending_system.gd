class_name EndingSystem
extends RefCounted

const REQUIRED := {
	GameEnums.Rank.KING: 1,
	GameEnums.Rank.QUEEN: 1,
	GameEnums.Rank.ROOK: 2,
	GameEnums.Rank.KNIGHT: 2,
	GameEnums.Rank.BISHOP: 2,
	GameEnums.Rank.PAWN: 8,
}

func complete_formation(state: GameState) -> bool:
	var counts := {}
	for rank in REQUIRED.keys():
		counts[rank] = 0
	for unit in state.units.values():
		if unit is UnitState and unit.is_in_city_roster() and counts.has(unit.rank):
			counts[unit.rank] += 1
	for rank in REQUIRED.keys():
		if counts[rank] != REQUIRED[rank]:
			return false
	return true


func finalize_run(state: GameState) -> bool:
	if (
		state == null
		or state.game_over
		or state.run_ended
		or state.day < GameState.MAX_DAYS
	):
		return false
	state.ending_recap_data = build_recap_data(state)
	state.ending_outcome_id = str(state.ending_recap_data.outcome_id)
	state.ending_triggered = true
	state.run_ended = true
	return true


func build_recap_data(state: GameState) -> Dictionary:
	var survivors: Array[Dictionary] = []
	var promotions: Array[Dictionary] = []
	var loyalty_outcomes: Array[Dictionary] = []
	var unit_ids := state.units.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or unit.faction != GameEnums.Faction.PLAYER:
			continue
		survivors.append({"id": unit.id, "name": _unit_name(unit), "rank": unit.rank})
		for promotion in unit.promotion_history:
			promotions.append({
				"unit_id": unit.id,
				"name": _unit_name(unit),
				"day": int(promotion.get("day", 0)),
				"from_rank": int(promotion.get("from_rank", unit.rank)),
				"to_rank": int(promotion.get("to_rank", unit.rank)),
			})
		if unit.rebellion_level >= GameEnums.RebellionLevel.DISSATISFIED:
			loyalty_outcomes.append({
				"unit_id": unit.id,
				"name": _unit_name(unit),
				"loyalty": unit.loyalty,
				"level": unit.rebellion_level,
			})

	var active_buildings := 0
	for building in state.buildings.values():
		if building is BuildingState and building.phase == GameEnums.BuildingPhase.ACTIVE:
			active_buildings += 1

	var losses: Array[Dictionary] = []
	var loss_ids := {}
	for loss in state.deceased_units:
		var loss_id := str(loss.get("unit_id", ""))
		if loss_id.is_empty() or loss_ids.has(loss_id):
			continue
		loss_ids[loss_id] = true
		losses.append(loss.duplicate(true))

	var relationships: Array[Dictionary] = []
	var relationship_keys := state.relationships.keys()
	relationship_keys.sort()
	for relationship_key in relationship_keys:
		var relationship := state.relationships.get(relationship_key) as RelationshipState
		if relationship == null or relationship.status not in [
			RelationshipState.CLOSE,
			RelationshipState.ROMANCE_CANDIDATE,
			RelationshipState.BONDED,
		]:
			continue
		var first := state.units.get(relationship.unit_a_id) as UnitState
		var second := state.units.get(relationship.unit_b_id) as UnitState
		relationships.append({
			"pair_key": str(relationship_key),
			"first": _unit_name_or_id(first, relationship.unit_a_id),
			"second": _unit_name_or_id(second, relationship.unit_b_id),
			"status": relationship.status,
		})

	var completed_expeditions := 0
	for expedition in state.expeditions.values():
		if expedition is ExpeditionState and expedition.status == GameEnums.ExpeditionStatus.COMPLETE:
			completed_expeditions += 1

	var resolved_events := 0
	for event in state.events.values():
		if event is EventState and event.resolved:
			resolved_events += 1
	resolved_events = maxi(resolved_events, state.resolved_event_definition_ids.size())
	var major_reports: Array[Dictionary] = []
	var report_keys := {}
	for report in state.report_history:
		if int(report.get("attention", GameEnums.AttentionLevel.NORMAL)) < GameEnums.AttentionLevel.IMPORTANT:
			continue
		var report_key := "%s:%s:%s" % [
			report.get("day", 0), report.get("fact_key", ""), report.get("text", ""),
		]
		if report_keys.has(report_key):
			continue
		report_keys[report_key] = true
		major_reports.append({
			"day": int(report.get("day", 0)),
			"text": str(report.get("text", "")),
			"source": str(report.get("source", "")),
		})
	while major_reports.size() > 8:
		major_reports.remove_at(0)

	promotions.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.day) != int(b.day):
			return int(a.day) < int(b.day)
		return str(a.unit_id) < str(b.unit_id)
	)
	losses.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.get("day", 0)) != int(b.get("day", 0)):
			return int(a.get("day", 0)) < int(b.get("day", 0))
		return str(a.get("unit_id", "")) < str(b.get("unit_id", ""))
	)
	var outcome_id := _outcome_id(state, survivors.size(), active_buildings)
	return {
		"outcome_id": outcome_id,
		"day": state.day,
		"city": {
			"survivors": survivors.size(),
			"active_buildings": active_buildings,
			"food": state.food,
			"materials": state.materials,
		},
		"survivors": survivors,
		"losses": losses,
		"promotions": promotions,
		"loyalty_outcomes": loyalty_outcomes,
		"relationships": relationships,
		"completed_expeditions": completed_expeditions,
		"resolved_events": resolved_events,
		"major_reports": major_reports,
		"outside_groups": state.outsider_groups.size(),
		"resettled_groups": state.resettled_group_count,
	}


func localized_recap(state: GameState) -> Dictionary:
	if state == null:
		return {}
	var recap := state.ending_recap_data
	if recap.is_empty():
		recap = build_recap_data(state)
	var sections: Array[Dictionary] = []
	var city: Dictionary = recap.city
	sections.append({
		"title": Localization.text("ending.section.city"),
		"lines": [Localization.text("ending.city_line", {
			"survivors": city.survivors,
			"buildings": city.active_buildings,
			"food": city.food,
			"materials": city.materials,
		})],
	})
	var survivor_lines: Array[String] = []
	for survivor in recap.survivors:
		survivor_lines.append(Localization.text("ending.survivor_line", {
			"name": survivor.name,
			"rank": LocalizationKeys.rank_name(int(survivor.rank)),
		}))
	sections.append({"title": Localization.text("ending.section.people"), "lines": survivor_lines})
	var loss_lines: Array[String] = []
	for loss in recap.losses:
		loss_lines.append(Localization.text("ending.loss_line", {
			"name": loss.name,
			"rank": LocalizationKeys.rank_name(int(loss.rank)),
			"day": loss.day,
			"cause": Localization.text("ending.cause.%s" % str(loss.cause)),
		}))
	if loss_lines.is_empty():
		loss_lines.append(Localization.text("ending.no_losses"))
	sections.append({"title": Localization.text("ending.section.lost"), "lines": loss_lines})

	var change_lines: Array[String] = []
	for promotion in recap.promotions:
		change_lines.append(Localization.text("ending.promotion_line", {
			"name": promotion.name,
			"rank": LocalizationKeys.rank_name(int(promotion.to_rank)),
		}))
	for loyalty in recap.loyalty_outcomes:
		change_lines.append(Localization.text("ending.loyalty_line", {
			"name": loyalty.name,
			"level": LocalizationKeys.rebellion_name(int(loyalty.level)),
		}))
	if int(recap.completed_expeditions) > 0:
		change_lines.append(Localization.text("ending.expedition_line", {"count": recap.completed_expeditions}))
	if int(recap.resolved_events) > 0:
		change_lines.append(Localization.text("ending.event_line", {"count": recap.resolved_events}))
	for report in recap.get("major_reports", []):
		if not str(report.text).is_empty():
			change_lines.append(str(report.text))
	if change_lines.is_empty():
		change_lines.append(Localization.text("ending.no_major_changes"))
	sections.append({"title": Localization.text("ending.section.changes"), "lines": change_lines})

	var relationship_lines: Array[String] = []
	for relationship in recap.relationships:
		relationship_lines.append(Localization.text("ending.relationship_line", {
			"first": relationship.first,
			"second": relationship.second,
			"status": LocalizationKeys.relationship_status(str(relationship.status)),
		}))
	if not relationship_lines.is_empty():
		sections.append({
			"title": Localization.text("ending.section.relationships"),
			"lines": relationship_lines,
		})
	sections.append({
		"title": Localization.text("ending.section.outside"),
		"lines": [Localization.text("ending.outside_line", {
			"groups": recap.outside_groups,
			"resettled": recap.resettled_groups,
		})],
	})
	var outcome_id := str(recap.outcome_id)
	return {
		"title": Localization.text("ending.title"),
		"outcome_id": outcome_id,
		"outcome_title": Localization.text("ending.outcome.%s.title" % outcome_id),
		"outcome_body": Localization.text("ending.outcome.%s.body" % outcome_id),
		"sections": sections,
	}


func _outcome_id(state: GameState, survivor_count: int, active_buildings: int) -> String:
	var serious_rebellion := false
	for unit in state.units.values():
		if unit is UnitState and unit.rebellion_level >= GameEnums.RebellionLevel.RESISTS:
			serious_rebellion = true
			break
	if serious_rebellion or state.food <= 0 or survivor_count <= 2:
		return "fractured"
	if survivor_count >= 5 and state.food >= survivor_count and active_buildings >= 3:
		return "renewal"
	return "survived"


func _unit_name(unit: UnitState) -> String:
	return _unit_name_or_id(unit, unit.id if unit != null else "")


func _unit_name_or_id(unit: UnitState, fallback_id: String) -> String:
	return unit.display_name if unit != null and not unit.display_name.is_empty() else fallback_id
