class_name OutsideSystem
extends RefCounted

const RESETTLEMENT_DURATION_DAYS := 2
const ESCORT_COUNT := 2

var expedition_system := ExpeditionSystem.new()


func validate_order(
	state: GameState,
	order: OutsiderDecisionOrder,
	blocked_unit_ids: Dictionary,
	reserved_unit_ids: Dictionary,
	result: TurnResolutionResult
) -> bool:
	if order == null:
		return false
	var group := state.outsider_groups.get(order.group_id) as OutsiderGroupState
	if group == null or group.resettlement_complete:
		result.reject("outsider", order.group_id, "Nhóm ngoài thành không còn tồn tại")
		return false
	if order.action in [GameEnums.OutsiderAction.ACCEPT_TRADE, GameEnums.OutsiderAction.REJECT_TRADE]:
		var king := state.units.get(order.king_unit_id) as UnitState
		if (
			king == null
			or king.faction != GameEnums.Faction.PLAYER
			or king.rank != GameEnums.Rank.KING
			or not king.can_be_moved()
			or blocked_unit_ids.has(king.id)
			or reserved_unit_ids.has(king.id)
		):
			result.reject("trade", order.group_id, "Giao dịch cần Vua trực tiếp chấp thuận")
			return false
		reserved_unit_ids[king.id] = true
	if order.action != GameEnums.OutsiderAction.RESETTLE:
		return true
	if order.escort_unit_ids.size() != ESCORT_COUNT or order.escort_unit_ids[0] == order.escort_unit_ids[1]:
		result.reject("resettlement", order.group_id, "Tái định cư cần đúng 2 quân hộ tống")
		return false
	for unit_id in order.escort_unit_ids:
		if blocked_unit_ids.has(unit_id) or reserved_unit_ids.has(unit_id):
			result.reject("resettlement", order.group_id, "Quân hộ tống đã có lệnh xung đột")
			return false
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or unit.faction != GameEnums.Faction.PLAYER or unit.is_prisoner or not unit.can_be_moved():
			result.reject("resettlement", order.group_id, "Có quân hộ tống không hợp lệ")
			return false
	for unit_id in order.escort_unit_ids:
		reserved_unit_ids[unit_id] = true
	return true


func commit_order(state: GameState, order: OutsiderDecisionOrder, result: TurnResolutionResult) -> void:
	var group := state.outsider_groups.get(order.group_id) as OutsiderGroupState
	if group == null:
		return
	if order.action == GameEnums.OutsiderAction.START_SUPPORT:
		group.support_active = true
		group.history_tags.append({"kind": "support_started", "day": state.day})
		result.outsider_events.append({"kind": "support_started", "text": "%s bắt đầu nhận hỗ trợ lương thực." % group.name})
	elif order.action == GameEnums.OutsiderAction.STOP_SUPPORT:
		group.support_active = false
		group.support_unmet = false
		group.history_tags.append({"kind": "support_stopped", "day": state.day})
		result.outsider_events.append({"kind": "support_stopped", "text": "Vua ngừng hỗ trợ %s." % group.name})
	elif order.action == GameEnums.OutsiderAction.ACCEPT_TRADE:
		_commit_trade(state, group, true, result)
	elif order.action == GameEnums.OutsiderAction.REJECT_TRADE:
		_commit_trade(state, group, false, result)
	else:
		_start_resettlement(state, group, order.escort_unit_ids, result)


func resolve_daily(state: GameState, skip_group_ids: Dictionary, result: TurnResolutionResult) -> void:
	var group_ids := state.outsider_groups.keys()
	group_ids.sort()
	for group_id in group_ids:
		var group := state.outsider_groups.get(group_id) as OutsiderGroupState
		if group == null:
			continue
		if group.is_resettling() or group.resettlement_complete:
			_continue_resettlement(state, group, skip_group_ids.has(group.id), result)
			continue
		_resolve_support(state, group, result)
		if not skip_group_ids.has(group.id):
			_update_pressure(state, group, result)


func pressure_label(group: OutsiderGroupState) -> String:
	if group.pressure == GameEnums.OutsidePressure.CALM:
		return "Yên"
	if group.pressure == GameEnums.OutsidePressure.UNEASY:
		return "Bất an"
	if group.pressure == GameEnums.OutsidePressure.TENSE:
		return "Căng thẳng"
	return "Hỗn loạn"


func _resolve_support(state: GameState, group: OutsiderGroupState, result: TurnResolutionResult) -> void:
	group.support_unmet = false
	if not group.support_active:
		return
	var cost := group.member_count()
	if state.food < cost:
		group.support_unmet = true
		group.history_tags.append({"kind": "support_unmet", "day": state.day})
		result.outsider_events.append({"kind": "support_unmet", "text": "%s vẫn chờ lương thực; kho hôm nay không đủ phần đã hứa." % group.name})
		return
	state.food -= cost
	result.outsider_food_consumed += cost
	group.history_tags.append({"kind": "support_met", "day": state.day, "food": cost})
	result.outsider_events.append({"kind": "support_met", "text": "%s nhận %d Lương thực hỗ trợ." % [group.name, cost]})


func _update_pressure(state: GameState, group: OutsiderGroupState, result: TurnResolutionResult) -> void:
	if group.support_active and not group.support_unmet:
		group.unresolved_days = maxi(0, group.unresolved_days - 1)
		group.pressure = maxi(GameEnums.OutsidePressure.CALM, group.pressure - 1)
	else:
		group.unresolved_days += 1
		group.pressure = mini(GameEnums.OutsidePressure.RIOT, group.pressure + 1)
		group.history_tags.append({"kind": "left_unresolved", "day": state.day})
	if group.pressure == GameEnums.OutsidePressure.RIOT:
		state.game_over = true
		state.failure_reason = "%s đã tràn vào thành trong hỗn loạn." % group.name
		result.outsider_events.append({"kind": "riot", "text": state.failure_reason})


func _commit_trade(state: GameState, group: OutsiderGroupState, accepted: bool, result: TurnResolutionResult) -> void:
	if not accepted:
		group.history_tags.append({"kind": "trade_rejected", "day": state.day})
		result.outsider_events.append({"kind": "trade_rejected", "text": "Vua từ chối đề nghị trao đổi của %s." % group.name})
		return
	if group.trade_offer.is_empty():
		result.reject("trade", group.id, "Nhóm này không có đề nghị trao đổi")
		return
	var quantity := maxi(1, int(group.trade_offer.get("quantity", 1)))
	var gives: String = group.trade_offer.get("city_gives", "food")
	var receives: String = group.trade_offer.get("city_receives", "materials")
	if (gives == "food" and state.food < quantity) or (gives == "materials" and state.materials < quantity):
		result.reject("trade", group.id, "Không đủ tài nguyên để trao đổi")
		return
	if gives == "food":
		state.food -= quantity
		result.trade_food_delta -= quantity
	else:
		state.materials -= quantity
		result.trade_materials_delta -= quantity
	if receives == "food":
		state.food += quantity
		result.trade_food_delta += quantity
	else:
		state.materials += quantity
		result.trade_materials_delta += quantity
	group.history_tags.append({"kind": "trade_accepted", "day": state.day, "quantity": quantity})
	var region := _region_for_group(state, group)
	if region != null:
		region.presence = maxi(region.presence, GameEnums.RegionPresence.CONNECTED)
		region.remember("trade", state.world_state.world_turn, {"group_id": group.id})
	result.outsider_events.append({
		"kind": "trade_accepted",
		"text": "%s đổi %d %s lấy %d %s. Vua đã chấp thuận." % [
			group.name, quantity, "Lương thực" if receives == "food" else "Vật tư",
			quantity, "Lương thực" if gives == "food" else "Vật tư",
		],
	})


func _start_resettlement(state: GameState, group: OutsiderGroupState, escort_ids: Array[String], result: TurnResolutionResult) -> void:
	group.escort_unit_ids = escort_ids.duplicate()
	group.resettlement_days_left = RESETTLEMENT_DURATION_DAYS
	group.resettlement_started_day = state.day
	for unit_id in escort_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		group.escort_origin_cells[unit.id] = unit.board_cell
		expedition_system.release_city_roles(state, unit)
		unit.board_cell = Vector2i(-1, -1)
		unit.away_days_left = RESETTLEMENT_DURATION_DAYS
		unit.away_assignment_id = group.id
		unit.away_reason = "resettlement"
		unit.memory_tags.append({"kind": "resettlement_escort", "day": state.day, "group_id": group.id})
		unit.memories.append("Đã hộ tống %s đi tái định cư vào Ngày %d." % [group.name, state.day])
	group.history_tags.append({"kind": "resettlement_started", "day": state.day})
	var region := _region_for_group(state, group)
	if region != null:
		region.presence = maxi(region.presence, GameEnums.RegionPresence.CONNECTED)
		region.remember("resettlement", state.world_state.world_turn, {"group_id": group.id})
	result.resettlement_started_group_ids.append(group.id)
	result.outsider_events.append({"kind": "resettlement_started", "text": "Hai quân đã hộ tống %s đi tái định cư." % group.name})


func _continue_resettlement(state: GameState, group: OutsiderGroupState, skip: bool, result: TurnResolutionResult) -> void:
	if not group.resettlement_complete:
		if skip:
			return
		group.resettlement_days_left = maxi(0, group.resettlement_days_left - 1)
		for unit_id in group.escort_unit_ids:
			var unit := state.units.get(unit_id) as UnitState
			if unit != null:
				unit.away_days_left = group.resettlement_days_left
		if group.resettlement_days_left > 0:
			return
		group.resettlement_complete = true
		group.history_tags.append({"kind": "resettled", "day": state.day})
		for member_id in group.member_unit_ids:
			state.units.erase(member_id)
		state.outsiders_count = maxi(0, state.outsiders_count - group.member_count())
		group.member_unit_ids.clear()
	var waiting := false
	for unit_id in group.escort_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or unit.away_assignment_id != group.id:
			continue
		var origin: Vector2i = group.escort_origin_cells.get(unit.id, Vector2i(0, 0))
		var cell := expedition_system.find_return_cell(state, origin)
		if cell == Vector2i(-1, -1):
			unit.return_pending = true
			waiting = true
			continue
		unit.board_cell = cell
		unit.away_days_left = 0
		unit.away_assignment_id = ""
		unit.away_reason = ""
		unit.return_pending = false
	if waiting:
		return
	result.resettled_group_ids.append(group.id)
	result.outsider_events.append({"kind": "resettled", "text": "%s đã được tái định cư an toàn. Hai quân hộ tống đã trở về." % group.name})
	state.remember("%s đã được tái định cư an toàn." % group.name, "resettled")
	state.outsider_groups.erase(group.id)


func _region_for_group(state: GameState, group: OutsiderGroupState) -> RegionState:
	var world := WorldSystem.new().ensure_initialized(state)
	if group.region_id.is_empty():
		for region_id in world.known_regions:
			if region_id != WorldSystem.CITY_REGION_ID:
				group.region_id = region_id
				break
	return world.regions.get(group.region_id) as RegionState
