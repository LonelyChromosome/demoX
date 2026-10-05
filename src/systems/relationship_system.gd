class_name RelationshipSystem
extends RefCounted

const FAMILIAR_AFFINITY := 2
const CLOSE_AFFINITY := 4
const CLOSE_TRUST := 3
const ROMANCE_AFFINITY := 7
const ROMANCE_TRUST := 5


func pair_key(first_unit_id: String, second_unit_id: String) -> String:
	var unit_ids := [first_unit_id, second_unit_id]
	unit_ids.sort()
	return "%d:%s|%d:%s" % [
		unit_ids[0].length(), unit_ids[0], unit_ids[1].length(), unit_ids[1],
	]


func relationship_between(
	state: GameState, first_unit_id: String, second_unit_id: String,
	create_if_missing := true
) -> RelationshipState:
	if not _valid_pair(state, first_unit_id, second_unit_id):
		return null
	var key := pair_key(first_unit_id, second_unit_id)
	var relationship := state.relationships.get(key) as RelationshipState
	if relationship == null and create_if_missing:
		relationship = RelationshipState.new(first_unit_id, second_unit_id)
		state.relationships[key] = relationship
	return relationship


func adjust_affinity(
	state: GameState, first_unit_id: String, second_unit_id: String, delta: int,
	day: int, source: String, reason: String, source_key: String,
	tags: Array[String] = []
) -> bool:
	return _adjust(
		state, first_unit_id, second_unit_id, delta, 0,
		day, source, reason, source_key, tags
	)


func adjust_trust(
	state: GameState, first_unit_id: String, second_unit_id: String, delta: int,
	day: int, source: String, reason: String, source_key: String,
	tags: Array[String] = []
) -> bool:
	return _adjust(
		state, first_unit_id, second_unit_id, 0, delta,
		day, source, reason, source_key, tags
	)


func shared_event(
	state: GameState, first_unit_id: String, second_unit_id: String,
	day: int, source: String, reason: String, source_key: String,
	affinity_delta := 0, trust_delta := 0, tags: Array[String] = []
) -> bool:
	return _adjust(
		state, first_unit_id, second_unit_id, affinity_delta, trust_delta,
		day, source, reason, source_key, tags
	)


func available_relationship_events(
	state: GameState, first_unit_id: String, second_unit_id: String
) -> Array[String]:
	var available: Array[String] = []
	var relationship := relationship_between(
		state, first_unit_id, second_unit_id, false
	)
	if relationship == null:
		return available
	if relationship.status in [RelationshipState.FAMILIAR, RelationshipState.CLOSE]:
		available.append("shared_memory")
	if relationship.status == RelationshipState.ROMANCE_CANDIDATE:
		available.append("romance_choice")
	return available


func _adjust(
	state: GameState, first_unit_id: String, second_unit_id: String,
	affinity_delta: int, trust_delta: int, day: int,
	source: String, reason: String, source_key: String,
	tags: Array[String]
) -> bool:
	if (
		(affinity_delta == 0 and trust_delta == 0)
		or source.is_empty()
		or reason.is_empty()
		or source_key.is_empty()
	):
		return false
	var relationship := relationship_between(state, first_unit_id, second_unit_id)
	if relationship == null or relationship.applied_source_keys.has(source_key):
		return false
	relationship.affinity += affinity_delta
	relationship.trust += trust_delta
	relationship.last_changed_day = day
	relationship.applied_source_keys[source_key] = true
	for tag in tags:
		if tag not in relationship.tags:
			relationship.tags.append(tag)
	relationship.shared_history.append({
		"day": day,
		"source": source,
		"reason": reason,
		"source_key": source_key,
		"affinity_delta": affinity_delta,
		"trust_delta": trust_delta,
		"tags": tags.duplicate(),
	})
	_update_status(relationship)
	return true


func _update_status(relationship: RelationshipState) -> void:
	if relationship.status == RelationshipState.BONDED:
		return
	if relationship.affinity >= ROMANCE_AFFINITY and relationship.trust >= ROMANCE_TRUST:
		relationship.status = RelationshipState.ROMANCE_CANDIDATE
	elif relationship.affinity >= CLOSE_AFFINITY and relationship.trust >= CLOSE_TRUST:
		relationship.status = RelationshipState.CLOSE
	elif relationship.affinity >= FAMILIAR_AFFINITY or relationship.trust >= FAMILIAR_AFFINITY:
		relationship.status = RelationshipState.FAMILIAR
	else:
		relationship.status = RelationshipState.NEUTRAL


func _valid_pair(state: GameState, first_unit_id: String, second_unit_id: String) -> bool:
	if state == null or first_unit_id.is_empty() or first_unit_id == second_unit_id:
		return false
	var first := state.units.get(first_unit_id) as UnitState
	var second := state.units.get(second_unit_id) as UnitState
	return (
		first != null
		and second != null
		and first.faction == GameEnums.Faction.PLAYER
		and second.faction == GameEnums.Faction.PLAYER
	)
