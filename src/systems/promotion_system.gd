class_name PromotionSystem
extends RefCounted

const EXPEDITION_SUCCESS_MERIT := 2

var definitions: Array[Dictionary] = []
var condition_handlers: Dictionary = {}


func _init() -> void:
	register_condition_handler("always", func(_state, _unit, _definition): return true)
	_register_default_definitions()


func register_definition(definition: Dictionary) -> bool:
	var from_rank := int(definition.get("from_rank", -1))
	var to_rank := int(definition.get("to_rank", -1))
	if (
		not definition.has("from_rank")
		or not definition.has("to_rank")
		or from_rank < GameEnums.Rank.PAWN
		or to_rank < GameEnums.Rank.PAWN
		or from_rank > GameEnums.Rank.KING
		or to_rank > GameEnums.Rank.KING
		or from_rank == GameEnums.Rank.KING
		or to_rank == GameEnums.Rank.KING
		or from_rank == to_rank
		or int(definition.get("merit_required", -1)) < 0
		or int(definition.get("training_days", 0)) < 1
	):
		return false
	if not promotion_requirement(from_rank, to_rank).is_empty():
		return false
	definitions.append(definition.duplicate(true))
	return true


func register_condition_handler(handler_id: String, handler: Callable) -> void:
	if not handler_id.is_empty() and handler.is_valid():
		condition_handlers[handler_id] = handler


func grant_merit(
	unit: UnitState,
	amount: int,
	source: String,
	day: int,
	reason: String,
	grant_key: String,
	result: TurnResolutionResult = null
) -> bool:
	if (
		unit == null
		or amount <= 0
		or source.is_empty()
		or grant_key.is_empty()
		or unit.faction != GameEnums.Faction.PLAYER
		or unit.rank == GameEnums.Rank.KING
		or unit.merit_grant_keys.has(grant_key)
	):
		return false
	unit.merit += amount
	unit.lifetime_merit += amount
	unit.merit_grant_keys[grant_key] = true
	var trace := {
		"unit_id": unit.id,
		"amount": amount,
		"source": source,
		"day": day,
		"reason": reason,
		"grant_key": grant_key,
	}
	unit.merit_history.append(trace.duplicate(true))
	if result != null:
		result.merit_grants.append(trace)
	return true


func merit_for(unit: UnitState) -> int:
	return unit.merit if unit != null else 0


func promotion_requirement(from_rank: int, to_rank: int) -> Dictionary:
	for definition in definitions:
		if int(definition.from_rank) == from_rank and int(definition.to_rank) == to_rank:
			return definition.duplicate(true)
	return {}


func available_promotions(state: GameState, unit: UnitState) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	if unit == null:
		return available
	var barracks_id := _first_active_barracks_id(state)
	for definition in definitions:
		if int(definition.from_rank) == unit.rank and can_promote(state, unit, int(definition.to_rank), barracks_id):
			available.append(definition.duplicate(true))
	return available


func can_promote(state: GameState, unit: UnitState, target_rank: int, barracks_id := "") -> bool:
	var resolved_barracks_id := barracks_id
	if resolved_barracks_id.is_empty():
		resolved_barracks_id = _first_active_barracks_id(state)
	return validate_promotion(state, unit, target_rank, resolved_barracks_id).valid


func validate_promotion(state: GameState, unit: UnitState, target_rank: int, barracks_id := "") -> Dictionary:
	if unit == null:
		return _invalid("Quân cờ không tồn tại")
	if unit.faction != GameEnums.Faction.PLAYER:
		return _invalid("Chỉ quân PLAYER mới được thăng cấp")
	if unit.rank == GameEnums.Rank.KING:
		return _invalid("Vua không tham gia thăng cấp")
	if unit.is_prisoner:
		return _invalid("Tù binh không thể thăng cấp")
	if not unit.away_assignment_id.is_empty() or unit.away_days_left > 0 or unit.return_pending:
		return _invalid("Quân đang ở ngoài thành")
	if unit.is_in_promotion_training():
		return _invalid("Quân đang trong một đợt huấn luyện khác")
	if (
		unit.locked_by_construction
		or unit.locked_by_healing
		or unit.injured
		or not unit.assigned_building_id.is_empty()
		or not unit.work_building_id.is_empty()
	):
		return _invalid("Quân đang có công việc hoặc trạng thái xung đột")
	var definition := promotion_requirement(unit.rank, target_rank)
	if definition.is_empty():
		return _invalid("Hướng thăng cấp không hợp lệ")
	if unit.merit < int(definition.merit_required):
		return _invalid("Chưa đủ chiến công")
	if bool(definition.get("barracks_required", true)):
		var barracks := state.buildings.get(barracks_id) as BuildingState
		if (
			barracks == null
			or barracks.type != GameEnums.BuildingType.BARRACKS
			or barracks.phase != GameEnums.BuildingPhase.ACTIVE
		):
			return _invalid("Doanh trại chưa hoạt động")
	if not _condition_passes(state, unit, definition):
		return _invalid("Chưa đáp ứng điều kiện thăng cấp")
	return {"valid": true, "reason": "Có thể thăng cấp", "definition": definition}


func validate_order(state: GameState, order: PromoteUnitOrder, blocked_unit_ids: Dictionary) -> Dictionary:
	if order == null:
		return _invalid("Lệnh không còn tồn tại")
	if order.barracks_id.is_empty():
		return _invalid("Lệnh chưa chọn Doanh trại")
	if order.planned_day != state.day:
		return _invalid("Lệnh thăng cấp đã quá ngày")
	if blocked_unit_ids.has(order.unit_id):
		return _invalid("Quân đã có lệnh xung đột")
	return validate_promotion(state, state.units.get(order.unit_id) as UnitState, order.target_rank, order.barracks_id)


func commit_training(
	state: GameState, order: PromoteUnitOrder, definition: Dictionary, result: TurnResolutionResult
) -> bool:
	var unit := state.units.get(order.unit_id) as UnitState
	if unit == null or unit.is_in_promotion_training():
		return false
	unit.promotion_target_rank = order.target_rank
	unit.promotion_barracks_id = order.barracks_id
	unit.promotion_started_day = state.day
	unit.promotion_complete_day = state.day + int(definition.training_days)
	unit.promotion_order_key = (
		"promotion:%s:%d:%d"
		% [
			unit.id,
			order.target_rank,
			order.planned_day,
		]
	)
	unit.promotion_last_advanced_day = state.day
	result.promotion_started_unit_ids.append(unit.id)
	result.promotion_events.append({
		"kind": "training_started",
		"unit_id": unit.id,
		"text": "%s bắt đầu huấn luyện tại Doanh trại." % _unit_name(unit),
		"attention": GameEnums.AttentionLevel.NORMAL,
	})
	return true


func advance_training(state: GameState, result: TurnResolutionResult) -> void:
	var unit_ids := state.units.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or not unit.is_in_promotion_training():
			continue
		if unit.promotion_last_advanced_day >= state.day:
			continue
		unit.promotion_last_advanced_day = state.day
		if state.day >= unit.promotion_complete_day:
			_complete_promotion(state, unit, result)


func append_ready_notice(state: GameState, unit: UnitState, result: TurnResolutionResult) -> void:
	for definition in available_promotions(state, unit):
		var key := "%d:%d" % [int(definition.from_rank), int(definition.to_rank)]
		if unit.promotion_ready_notified.has(key):
			continue
		unit.promotion_ready_notified[key] = true
		result.promotion_events.append({
			"kind": "promotion_ready",
			"unit_id": unit.id,
			"text": "%s đã đủ điều kiện huấn luyện lên %s." % [
				_unit_name(unit), rank_name(int(definition.to_rank)),
			],
			"attention": GameEnums.AttentionLevel.NOTICE,
		})


func rank_name(rank: int) -> String:
	var names := ["Tốt", "Mã", "Xe", "Tượng", "Hậu", "Vua"]
	return names[rank] if rank >= 0 and rank < names.size() else "Không rõ"


func _complete_promotion(state: GameState, unit: UnitState, result: TurnResolutionResult) -> void:
	var from_rank := unit.rank
	var target_rank := unit.promotion_target_rank
	var barracks_id := unit.promotion_barracks_id
	var order_key := unit.promotion_order_key
	unit.rank = target_rank
	unit.promotion_history.append({
		"day": state.day,
		"from_rank": from_rank,
		"to_rank": target_rank,
		"barracks_id": barracks_id,
		"order_key": order_key,
	})
	unit.memory_tags.append({
		"kind": "promoted", "day": state.day,
		"from_rank": from_rank, "to_rank": target_rank,
	})
	unit.memories.append(
		"Được thăng từ %s lên %s tại Doanh trại vào Ngày %d." % [
			rank_name(from_rank), rank_name(target_rank), state.day,
		]
	)
	unit.promotion_target_rank = -1
	unit.promotion_barracks_id = ""
	unit.promotion_started_day = 0
	unit.promotion_complete_day = 0
	unit.promotion_order_key = ""
	result.promoted_unit_ids.append(unit.id)
	result.promotion_events.append({
		"kind": "promotion_complete",
		"unit_id": unit.id,
		"text": "%s đã hoàn tất huấn luyện và trở thành %s." % [
			_unit_name(unit), rank_name(target_rank),
		],
		"attention": GameEnums.AttentionLevel.NORMAL,
	})


func _condition_passes(state: GameState, unit: UnitState, definition: Dictionary) -> bool:
	var condition_id := str(definition.get("condition", "always"))
	var handler := condition_handlers.get(condition_id) as Callable
	return handler.is_valid() and bool(handler.call(state, unit, definition))


func _first_active_barracks_id(state: GameState) -> String:
	var building_ids := state.buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		var building := state.buildings.get(building_id) as BuildingState
		if (
			building != null
			and building.type == GameEnums.BuildingType.BARRACKS
			and building.phase == GameEnums.BuildingPhase.ACTIVE
		):
			return building.id
	return ""


func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason, "definition": {}}


func _unit_name(unit: UnitState) -> String:
	return unit.display_name if not unit.display_name.is_empty() else unit.id


func _register_default_definitions() -> void:
	register_definition(
		{
			"from_rank": GameEnums.Rank.PAWN,
			"to_rank": GameEnums.Rank.KNIGHT,
			"merit_required": 4,
			"barracks_required": true,
			"training_days": 1,
			"condition": "always",
		}
	)
	register_definition(
		{
			"from_rank": GameEnums.Rank.PAWN,
			"to_rank": GameEnums.Rank.ROOK,
			"merit_required": 6,
			"barracks_required": true,
			"training_days": 1,
			"condition": "always",
		}
	)
	register_definition(
		{
			"from_rank": GameEnums.Rank.PAWN,
			"to_rank": GameEnums.Rank.BISHOP,
			"merit_required": 6,
			"barracks_required": true,
			"training_days": 1,
			"condition": "always",
		}
	)
