class_name ExpeditionSystem
extends RefCounted

const TEAM_SIZE := 2
const MIN_DURATION_DAYS := 1
const MAX_DURATION_DAYS := 3
const LOW_FOOD_THRESHOLD := 5
const LOW_MATERIAL_THRESHOLD := 2
const MIN_RESOURCE_REWARD := 2
const MAX_RESOURCE_REWARD := 5

const OUTCOME_FOOD := "food"
const OUTCOME_MATERIALS := "materials"
const OUTCOME_EMPTY := "empty"
const OUTCOME_OUTSIDERS := "outsiders"
const OUTCOME_INJURY := "injury"
const OUTCOME_DEATH := "death"

var world_system := WorldSystem.new()


func can_dispatch(unit_ids: Array[String]) -> bool:
	return unit_ids.size() == TEAM_SIZE and unit_ids[0] != unit_ids[1]


func context_weights(state: GameState, expedition: ExpeditionState = null) -> Dictionary:
	var weights := {
		OUTCOME_FOOD: 1.0,
		OUTCOME_MATERIALS: 1.0,
		OUTCOME_EMPTY: 0.8,
		OUTCOME_OUTSIDERS: 0.55,
		OUTCOME_INJURY: 0.4,
		OUTCOME_DEATH: 0.16,
	}
	if state.food < LOW_FOOD_THRESHOLD:
		weights[OUTCOME_FOOD] = 2.2
	if state.materials < LOW_MATERIAL_THRESHOLD:
		weights[OUTCOME_MATERIALS] = 1.8
	var world := world_system.ensure_initialized(state)
	if world.food_pressure >= GameEnums.ResourcePressure.STRAINED:
		weights[OUTCOME_FOOD] = float(weights[OUTCOME_FOOD]) + 0.45
	if world.material_pressure >= GameEnums.ResourcePressure.STRAINED:
		weights[OUTCOME_MATERIALS] = float(weights[OUTCOME_MATERIALS]) + 0.35
	if expedition != null:
		var modifiers := world_system.expedition_weight_modifiers(state, expedition)
		for kind in weights:
			weights[kind] = maxf(0.02, float(weights[kind]) + float(modifiers.get(kind, 0.0)))
	return weights


func validate_order(
	state: GameState,
	order: DispatchExpeditionOrder,
	blocked_unit_ids: Dictionary,
	reserved_unit_ids: Dictionary,
	result: TurnResolutionResult
) -> bool:
	if order == null or not can_dispatch(order.unit_ids):
		result.reject("expedition", order.expedition_id if order != null else "", "Đoàn thám hiểm cần đúng 2 quân")
		return false
	var world := world_system.ensure_initialized(state)
	var region := world_system.target_region(world, order.target_region_id)
	if region == null or region.id not in world.known_regions:
		result.reject("expedition", order.expedition_id, "Vùng đích chưa được biết tới")
		return false
	var route := world_system.route_to_region(world, region.id)
	if route != null and route.blocked:
		result.reject("expedition", order.expedition_id, "Tuyến đường tới vùng này đang bị chặn")
		return false
	if order.supplies_food > state.food:
		result.reject("expedition", order.expedition_id, "Không đủ Lương thực chuẩn bị cho chuyến đi")
		return false
	for unit_id in order.unit_ids:
		if blocked_unit_ids.has(unit_id) or reserved_unit_ids.has(unit_id):
			result.reject("expedition", order.expedition_id, "Quân đã có lệnh xung đột")
			return false
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or unit.faction != GameEnums.Faction.PLAYER or unit.is_prisoner or not unit.can_be_moved():
			result.reject("expedition", order.expedition_id, "Có quân không đủ điều kiện rời thành")
			return false
	for unit_id in order.unit_ids:
		reserved_unit_ids[unit_id] = true
	return true


func commit(state: GameState, order: DispatchExpeditionOrder, result: TurnResolutionResult) -> ExpeditionState:
	var expedition := ExpeditionState.new(order.expedition_id)
	expedition.unit_ids = order.unit_ids.duplicate()
	expedition.departure_day = state.day
	var world := world_system.ensure_initialized(state)
	var region := world_system.target_region(world, order.target_region_id)
	expedition.target_region_id = region.id if region != null else WorldSystem.CITY_REGION_ID
	var route := world_system.route_to_region(world, expedition.target_region_id)
	expedition.route_id = route.id if route != null else ""
	expedition.supplies_food = mini(order.supplies_food, state.food)
	state.food -= expedition.supplies_food
	result.expedition_supply_food += expedition.supplies_food
	var base_duration := _duration_for(state.run_seed, expedition.id, state.day)
	expedition.duration_days = clampi(
		base_duration + world_system.expedition_duration_modifier(
			world, expedition.target_region_id
		) - mini(1, expedition.supplies_food),
		MIN_DURATION_DAYS,
		MAX_DURATION_DAYS
	)
	expedition.days_left = expedition.duration_days
	expedition.outcome_kind = choose_outcome(
		context_weights(state, expedition),
		_stable_seed(state.run_seed, expedition.id, state.day, "outcome")
	)
	expedition.reward_amount = MIN_RESOURCE_REWARD + (
		_stable_seed(state.run_seed, expedition.id, state.day, "reward")
		% (MAX_RESOURCE_REWARD - MIN_RESOURCE_REWARD + 1)
	)
	for unit_id in expedition.unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		expedition.origin_cells[unit.id] = unit.board_cell
		release_city_roles(state, unit)
		unit.away_days_left = expedition.duration_days
		unit.away_assignment_id = expedition.id
		unit.away_reason = "expedition"
		unit.return_pending = false
		unit.board_cell = Vector2i(-1, -1)
		unit.memory_tags.append({
			"kind": "expedition_departed", "day": state.day,
			"expedition_id": expedition.id, "partner_id": _partner_id(expedition.unit_ids, unit.id),
		})
		unit.memories.append("Đã rời thành trong một chuyến thám hiểm vào Ngày %d." % state.day)
	state.expeditions[expedition.id] = expedition
	result.committed_expedition_ids.append(expedition.id)
	result.expedition_events.append({
		"kind": "departed",
		"text": "%s đã rời thành hướng tới %s. Những vị trí họ để lại nay bỏ trống." % [
			_team_names(state, expedition.unit_ids), region.name if region != null else "vùng chưa rõ",
		],
	})
	return expedition


func advance(state: GameState, skip_ids: Dictionary, result: TurnResolutionResult) -> void:
	var ids := state.expeditions.keys()
	ids.sort()
	for expedition_id in ids:
		var expedition := state.expeditions.get(expedition_id) as ExpeditionState
		if expedition == null or expedition.status == GameEnums.ExpeditionStatus.COMPLETE:
			continue
		if expedition.status == GameEnums.ExpeditionStatus.RETURN_PENDING:
			_attempt_return(state, expedition, result)
			continue
		if skip_ids.has(expedition.id):
			continue
		expedition.elapsed_days += 1
		expedition.days_left = maxi(0, expedition.days_left - 1)
		for unit_id in expedition.unit_ids:
			var unit := state.units.get(unit_id) as UnitState
			if unit != null:
				unit.away_days_left = expedition.days_left
		if expedition.days_left > 0:
			result.expedition_events.append({
				"kind": "silent", "text": "Chưa có tin từ đoàn thám hiểm %s." % _team_names(state, expedition.unit_ids),
			})
			continue
		_apply_outcome(state, expedition, result)
		_attempt_return(state, expedition, result)


func choose_outcome(weights: Dictionary, seed_value: int) -> String:
	var order := [OUTCOME_FOOD, OUTCOME_MATERIALS, OUTCOME_EMPTY, OUTCOME_OUTSIDERS, OUTCOME_INJURY, OUTCOME_DEATH]
	var total := 0.0
	for kind in order:
		total += maxf(0.0, float(weights.get(kind, 0.0)))
	if total <= 0.0:
		return OUTCOME_EMPTY
	var roll := (float(seed_value % 1000000) / 1000000.0) * total
	for kind in order:
		roll -= maxf(0.0, float(weights.get(kind, 0.0)))
		if roll <= 0.0:
			return kind
	return OUTCOME_EMPTY


func _apply_outcome(state: GameState, expedition: ExpeditionState, result: TurnResolutionResult) -> void:
	if expedition.outcome_applied:
		return
	expedition.outcome_applied = true
	if expedition.outcome_kind == OUTCOME_FOOD:
		state.food += expedition.reward_amount
		result.food_produced += expedition.reward_amount
		result.expedition_food_found += expedition.reward_amount
		result.expedition_events.append({"kind": "food", "text": "%s mang về %d Lương thực." % [_team_names(state, expedition.unit_ids), expedition.reward_amount]})
		_add_memory(state, expedition, "found_food")
		_add_memory_text(state, expedition, "Đã mang Lương thực về sau chuyến đi Ngày %d." % expedition.departure_day)
	elif expedition.outcome_kind == OUTCOME_MATERIALS:
		state.materials += expedition.reward_amount
		result.materials_produced += expedition.reward_amount
		result.expedition_materials_found += expedition.reward_amount
		result.expedition_events.append({"kind": "materials", "text": "%s mang về %d Vật tư." % [_team_names(state, expedition.unit_ids), expedition.reward_amount]})
		_add_memory(state, expedition, "found_materials")
		_add_memory_text(state, expedition, "Đã tìm thấy Vật tư trong chuyến đi Ngày %d." % expedition.departure_day)
	elif expedition.outcome_kind == OUTCOME_OUTSIDERS:
		var group := _create_outsider_group(state, expedition)
		expedition.outsider_group_id = group.id
		result.new_outsider_group_ids.append(group.id)
		result.expedition_events.append({"kind": "outsiders", "text": "%s trở về cùng tin về %s." % [_team_names(state, expedition.unit_ids), group.name]})
		_add_memory(state, expedition, "met_outsiders", {"group_id": group.id})
		_add_memory_text(state, expedition, "Đã tìm thấy %s ngoài thành." % group.name)
	elif expedition.outcome_kind == OUTCOME_INJURY:
		var injured := state.units.get(expedition.unit_ids[0]) as UnitState
		if injured != null:
			injured.injured = true
			injured.healing_days_left = maxi(injured.healing_days_left, 2)
			expedition.injured_unit_id = injured.id
			injured.memory_tags.append({"kind": "returned_injured", "day": state.day})
			injured.memories.append("Trở về bị thương sau chuyến đi Ngày %d." % expedition.departure_day)
		result.expedition_events.append({"kind": "injury", "text": "%s trở về với một người bị thương." % _team_names(state, expedition.unit_ids)})
	elif expedition.outcome_kind == OUTCOME_DEATH:
		var lost_id: String = expedition.unit_ids[_stable_seed(state.run_seed, expedition.id, expedition.departure_day, "lost") % TEAM_SIZE]
		expedition.lost_unit_id = lost_id
		var lost_name := _unit_name(state.units.get(lost_id) as UnitState)
		_remove_unit(state, lost_id)
		expedition.unit_ids.erase(lost_id)
		expedition.origin_cells.erase(lost_id)
		for survivor_id in expedition.unit_ids:
			var survivor := state.units.get(survivor_id) as UnitState
			if survivor == null:
				continue
			survivor.memory_tags.append({"kind": "partner_lost", "day": state.day, "partner_id": lost_id})
			survivor.memories.append("Trở về một mình; %s đã không trở lại." % lost_name)
		result.expedition_events.append({
			"kind": "death",
			"unit_id": lost_id,
			"text": "%s trở về một mình. %s không trở lại." % [
				_team_names(state, expedition.unit_ids), lost_name,
			],
		})
	else:
		result.expedition_events.append({"kind": "empty", "text": "%s trở về tay trắng." % _team_names(state, expedition.unit_ids)})
		_add_memory(state, expedition, "expedition_survived")
	world_system.record_expedition_result(state, expedition, result)


func _attempt_return(state: GameState, expedition: ExpeditionState, result: TurnResolutionResult) -> void:
	var waiting := false
	for unit_id in expedition.unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or unit.away_assignment_id != expedition.id:
			continue
		var origin: Vector2i = expedition.origin_cells.get(unit.id, Vector2i(0, 0))
		var cell := find_return_cell(state, origin)
		if cell == Vector2i(-1, -1):
			unit.return_pending = true
			unit.away_days_left = 0
			waiting = true
			continue
		unit.board_cell = cell
		unit.away_days_left = 0
		unit.away_assignment_id = ""
		unit.away_reason = ""
		unit.return_pending = false
		unit.memory_tags.append({"kind": "expedition_survived", "day": state.day})
	if waiting:
		expedition.status = GameEnums.ExpeditionStatus.RETURN_PENDING
		return
	expedition.status = GameEnums.ExpeditionStatus.COMPLETE
	result.returned_expedition_ids.append(expedition.id)


func find_return_cell(state: GameState, origin: Vector2i) -> Vector2i:
	var occupied := {}
	for candidate in state.units.values():
		if candidate is UnitState and _inside(candidate.board_cell):
			occupied[candidate.board_cell] = true
	var cells: Array[Vector2i] = []
	for y in range(BuildingSystem.BOARD_SIZE):
		for x in range(BuildingSystem.BOARD_SIZE):
			cells.append(Vector2i(x, y))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := a.distance_squared_to(origin)
		var db := b.distance_squared_to(origin)
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	var building_system := BuildingSystem.new()
	for cell in cells:
		if (
			not occupied.has(cell)
			and not building_system.is_cell_occupied_by_building(state, cell)
			and not RuinSystem.new().is_blocked(state, cell)
		):
			return cell
	return Vector2i(-1, -1)


func _create_outsider_group(state: GameState, expedition: ExpeditionState) -> OutsiderGroupState:
	var index := 1
	var group_id := "outsider_%s" % expedition.id
	while state.outsider_groups.has(group_id):
		index += 1
		group_id = "outsider_%s_%d" % [expedition.id, index]
	var group := OutsiderGroupState.new(group_id)
	group.discovered_day = state.day
	var directions := ["phía Bắc", "bờ Đông", "lối Nam", "sườn Tây"]
	var direction_index := _stable_seed(state.run_seed, expedition.id, state.day, "origin") % directions.size()
	group.origin_tag = directions[direction_index]
	group.name = "Nhóm %s" % group.origin_tag
	var count := 1 + _stable_seed(state.run_seed, expedition.id, state.day, "members") % 3
	for member_index in range(count):
		var unit_id := "%s_member_%d" % [group.id, member_index + 1]
		var unit := UnitState.new(unit_id)
		unit.display_name = "Người ngoài %d" % (member_index + 1)
		unit.faction = GameEnums.Faction.OUTSIDER
		unit.rank = GameEnums.Rank.KNIGHT if member_index == count - 1 and count > 2 else GameEnums.Rank.PAWN
		unit.board_cell = Vector2i(-1, -1)
		state.units[unit.id] = unit
		group.member_unit_ids.append(unit.id)
	group.trade_offer = {"city_gives": "food", "city_receives": "materials", "quantity": 1}
	group.history_tags.append({"kind": "discovered", "day": state.day, "expedition_id": expedition.id})
	state.outsider_groups[group.id] = group
	state.outsiders_count += group.member_count()
	return group


func release_city_roles(state: GameState, unit: UnitState) -> void:
	for candidate in state.buildings.values():
		if not (candidate is BuildingState):
			continue
		if candidate.manager_unit_id == unit.id:
			candidate.manager_unit_id = ""
		candidate.worker_unit_ids.erase(unit.id)
		candidate.builder_unit_ids.erase(unit.id)
		candidate.patient_unit_ids.erase(unit.id)
		candidate.job_slots.erase(unit.board_cell)
	unit.work_building_id = ""
	unit.assigned_building_id = ""
	unit.is_manager = false
	unit.locked_by_construction = false
	unit.locked_by_healing = false


func _remove_unit(state: GameState, unit_id: String) -> void:
	var unit := state.units.get(unit_id) as UnitState
	if unit == null:
		return
	release_city_roles(state, unit)
	state.prisoners.erase(unit.id)
	for group in state.outsider_groups.values():
		if group is OutsiderGroupState:
			group.member_unit_ids.erase(unit.id)
	state.units.erase(unit.id)


func _add_memory(state: GameState, expedition: ExpeditionState, kind: String, extra: Dictionary = {}) -> void:
	for unit_id in expedition.unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		var tag := {"kind": kind, "day": state.day, "expedition_id": expedition.id}
		for key in extra:
			tag[key] = extra[key]
		unit.memory_tags.append(tag)


func _add_memory_text(state: GameState, expedition: ExpeditionState, text: String) -> void:
	for unit_id in expedition.unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			unit.memories.append(text)


func _duration_for(run_seed: int, expedition_id: String, day: int) -> int:
	return MIN_DURATION_DAYS + (_stable_seed(run_seed, expedition_id, day, "duration") % (MAX_DURATION_DAYS - MIN_DURATION_DAYS + 1))


func _stable_seed(run_seed: int, id: String, day: int, salt: String) -> int:
	var text := "%d|%s|%d|%s" % [run_seed, id, day, salt]
	var value := 216613626
	for index in range(text.length()):
		value = (value * 16777619 + text.unicode_at(index)) % 2147483647
	return absi(value)


func _partner_id(unit_ids: Array[String], unit_id: String) -> String:
	for candidate in unit_ids:
		if candidate != unit_id:
			return candidate
	return ""


func _team_names(state: GameState, unit_ids: Array[String]) -> String:
	var names: Array[String] = []
	for unit_id in unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			names.append(_unit_name(unit))
	return "Đoàn thám hiểm" if names.is_empty() else " và ".join(names)


func _unit_name(unit: UnitState) -> String:
	if unit == null:
		return "Một quân cờ"
	return unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank)


func _rank_name(rank: int) -> String:
	return ["Tốt", "Mã", "Xe", "Tịnh", "Hậu", "Vua"][rank]


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < BuildingSystem.BOARD_SIZE and cell.y < BuildingSystem.BOARD_SIZE
