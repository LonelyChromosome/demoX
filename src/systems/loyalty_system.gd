class_name LoyaltySystem
extends RefCounted

const DISSATISFIED_AT := -1
const LOW_OUTPUT_AT := -2
const OBJECTS_AT := -3
const RESISTS_AT := -4
const REVOLT_AT := -5


func rebellion_level_for(loyalty: int) -> GameEnums.RebellionLevel:
	if loyalty <= REVOLT_AT:
		return GameEnums.RebellionLevel.REVOLT
	if loyalty <= RESISTS_AT:
		return GameEnums.RebellionLevel.RESISTS
	if loyalty <= OBJECTS_AT:
		return GameEnums.RebellionLevel.OBJECTS_BUT_OBEYS
	if loyalty <= LOW_OUTPUT_AT:
		return GameEnums.RebellionLevel.LOW_OUTPUT
	if loyalty <= DISSATISFIED_AT:
		return GameEnums.RebellionLevel.DISSATISFIED
	return GameEnums.RebellionLevel.NONE


func adjust_loyalty(
	state: GameState,
	unit_id: String,
	delta: int,
	day: int,
	source: String,
	reason: String,
	source_key: String,
	result: TurnResolutionResult = null
) -> bool:
	if (
		state == null
		or delta == 0
		or source.is_empty()
		or reason.is_empty()
		or source_key.is_empty()
	):
		return false
	var unit := state.units.get(unit_id) as UnitState
	if (
		unit == null
		or unit.faction != GameEnums.Faction.PLAYER
		or unit.loyalty_source_keys.has(source_key)
	):
		return false
	var old_level := unit.rebellion_level
	unit.loyalty += delta
	unit.rebellion_level = rebellion_level_for(unit.loyalty)
	unit.loyalty_source_keys[source_key] = true
	var trace := {
		"unit_id": unit.id,
		"day": day,
		"source": source,
		"reason": reason,
		"source_key": source_key,
		"delta": delta,
		"loyalty": unit.loyalty,
		"old_level": old_level,
		"new_level": unit.rebellion_level,
	}
	unit.loyalty_history.append(trace.duplicate(true))
	if result != null:
		var event := trace.duplicate(true)
		event["level_changed"] = old_level != unit.rebellion_level
		event["level_label"] = level_label(unit.rebellion_level)
		event["attention"] = attention_for(unit.rebellion_level)
		result.loyalty_events.append(event)
	return true


func is_rebellion_risk(unit: UnitState) -> bool:
	return (
		unit != null
		and unit.faction == GameEnums.Faction.PLAYER
		and unit.rebellion_level >= GameEnums.RebellionLevel.DISSATISFIED
	)


func can_interrogate(unit: UnitState) -> bool:
	return (
		unit != null
		and unit.faction == GameEnums.Faction.PLAYER
		and unit.rank != GameEnums.Rank.KING
		and unit.rebellion_level >= GameEnums.RebellionLevel.OBJECTS_BUT_OBEYS
	)


func attention_for(level: GameEnums.RebellionLevel) -> GameEnums.AttentionLevel:
	if level == GameEnums.RebellionLevel.REVOLT:
		return GameEnums.AttentionLevel.CRITICAL
	if level == GameEnums.RebellionLevel.RESISTS:
		return GameEnums.AttentionLevel.IMPORTANT
	if level == GameEnums.RebellionLevel.OBJECTS_BUT_OBEYS:
		return GameEnums.AttentionLevel.NOTICE
	return GameEnums.AttentionLevel.NORMAL


func level_label(level: GameEnums.RebellionLevel) -> String:
	return [
		"Bất mãn",
		"Giảm hiệu suất",
		"Phản đối nhưng phục tùng",
		"Kháng lệnh",
		"Nổi loạn",
	][level] if level >= GameEnums.RebellionLevel.DISSATISFIED else "Ổn định"
