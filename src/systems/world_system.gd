class_name WorldSystem
extends RefCounted

const TURNS_PER_SEASON := 8
const MAX_RECENT_EVENTS := 8
const MAX_DANGER := 5
const MAX_SAFETY := 5
const CITY_REGION_ID := "city"


func ensure_initialized(state: GameState) -> WorldState:
	if state.world_state == null:
		state.world_state = WorldState.new()
	state.world_state.initialize_defaults()
	return state.world_state


func resolve_world(state: GameState, result: TurnResolutionResult) -> void:
	var world := ensure_initialized(state)
	world.world_turn += 1
	_update_routes(world, result)
	_update_regions(world, result)
	_update_factions(world, result)
	_update_migration(state, world, result)
	_update_resource_pressure(state, world, result)
	_update_season_and_weather(state, world, result)
	for event_text in result.world_events:
		world.recent_world_events.append(event_text)
	while world.recent_world_events.size() > MAX_RECENT_EVENTS:
		world.recent_world_events.pop_front()


func record_expedition_result(
	state: GameState, expedition: ExpeditionState, result: TurnResolutionResult
) -> void:
	var world := ensure_initialized(state)
	var region := target_region(world, expedition.target_region_id)
	if region == null:
		return
	var first_discovery := not region.discovered
	region.discovered = true
	region.presence = maxi(region.presence, GameEnums.RegionPresence.VISITED)
	region.last_visited_turn = world.world_turn
	region.current_condition = condition_for_region(region)
	region.remember(
		"expedition_%s" % expedition.outcome_kind,
		world.world_turn,
		{"expedition_id": expedition.id, "departure_day": expedition.departure_day}
	)
	world.add_known_region(region.id)
	expedition.discovered_region_id = region.id if first_discovery else ""
	if first_discovery:
		_add_world_event(
			result,
			"Đoàn thám hiểm đã xác nhận vùng %s. %s" % [region.name, region.current_condition]
		)
	var route := route_to_region(world, region.id)
	if route != null:
		route.last_used_turn = world.world_turn
		route.successful_trips += 1
		if expedition.outcome_kind not in ["injury", "death"]:
			route.safety = mini(MAX_SAFETY, route.safety + 1)
		if not route.discovered:
			route.discovered = true
			_add_world_event(result, "Một tuyến đường tới %s đã được ghi lại." % region.name)
		if route.successful_trips >= 2:
			var shortcut := world.routes.get("route_frontier_link") as RouteState
			if shortcut != null and not shortcut.discovered:
				shortcut.discovered = true
				_add_world_event(result, "Các dấu đường cũ đã làm lộ một lối tắt giữa hai vùng ngoài thành.")
	if expedition.outcome_kind == "food":
		region.food_potential = maxi(0, region.food_potential - 1)
		region.remember("food_found", world.world_turn)
	elif expedition.outcome_kind == "materials":
		region.material_potential = maxi(0, region.material_potential - 1)
		region.remember("materials_found", world.world_turn)
	elif expedition.outcome_kind in ["injury", "death"]:
		region.danger = mini(MAX_DANGER, region.danger + 1)
		region.remember("ambush", world.world_turn)
		if route != null:
			route.safety = maxi(0, route.safety - 1)
			route.memory_tags.append({"kind": "ambush", "turn": world.world_turn})
	elif expedition.outcome_kind == "outsiders":
		region.outsider_presence += 1
	var group := state.outsider_groups.get(expedition.outsider_group_id) as OutsiderGroupState
	if group != null:
		group.region_id = region.id
		group.history_tags.append({"kind": "region_linked", "day": state.day, "region_id": region.id})
	_reveal_faction_presence(world, region, result)


func target_region(world: WorldState, region_id: String) -> RegionState:
	if not region_id.is_empty():
		return world.regions.get(region_id) as RegionState
	for known_id in world.known_regions:
		if known_id == CITY_REGION_ID:
			continue
		var candidate := world.regions.get(known_id) as RegionState
		if candidate != null:
			return candidate
	return world.regions.get(CITY_REGION_ID) as RegionState


func route_to_region(world: WorldState, region_id: String) -> RouteState:
	if region_id == CITY_REGION_ID:
		return null
	return world.route_between(CITY_REGION_ID, region_id)


func discover_route(
	world: WorldState, first_region: String, second_region: String,
	route_id := ""
) -> RouteState:
	var existing := world.route_between(first_region, second_region)
	if existing != null:
		existing.discovered = true
		return existing
	if not world.regions.has(first_region) or not world.regions.has(second_region):
		return null
	var final_id := route_id
	if final_id.is_empty():
		final_id = "route_%s_%s" % [first_region, second_region]
	var route := RouteState.new(final_id, first_region, second_region)
	route.discovered = true
	world.routes[route.id] = route
	(world.regions[first_region] as RegionState).route_links.append(route.id)
	(world.regions[second_region] as RegionState).route_links.append(route.id)
	return route


func expedition_duration_modifier(world: WorldState, region_id: String) -> int:
	var route := route_to_region(world, region_id)
	var modifier := 0
	if route != null:
		modifier += maxi(0, route.travel_cost - 1)
		if route.safety <= 1:
			modifier += 1
	if world.weather in [GameEnums.Weather.STORM, GameEnums.Weather.COLD]:
		modifier += 1
	return modifier


func expedition_weight_modifiers(
	state: GameState, expedition: ExpeditionState
) -> Dictionary:
	var world := ensure_initialized(state)
	var region := target_region(world, expedition.target_region_id)
	var modifiers := {
		"food": 0.0,
		"materials": 0.0,
		"empty": 0.0,
		"outsiders": 0.0,
		"injury": 0.0,
		"death": 0.0,
	}
	if region == null:
		return modifiers
	modifiers.food = float(region.food_potential) * 0.35
	modifiers.materials = float(region.material_potential) * 0.35
	modifiers.outsiders = float(region.outsider_presence + region.population_pressure) * 0.2
	modifiers.injury = float(region.danger) * 0.12
	modifiers.death = float(region.danger) * 0.035
	if not region.discovered:
		modifiers.empty += 0.2
	if region.has_memory("ambush"):
		modifiers.injury += 0.25
		modifiers.death += 0.08
	if expedition.supplies_food > 0:
		modifiers.injury -= 0.15 * float(expedition.supplies_food)
		modifiers.death -= 0.04 * float(expedition.supplies_food)
	for unit_id in expedition.unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		if unit.injured:
			modifiers.injury += 0.2
		if unit.rank in [GameEnums.Rank.KNIGHT, GameEnums.Rank.ROOK]:
			modifiers.empty -= 0.08
	var route := route_to_region(world, region.id)
	if route != null and route.safety <= 1:
		modifiers.injury += 0.25
		modifiers.death += 0.08
	return modifiers


func food_production_multiplier(world: WorldState) -> float:
	if world == null:
		return 1.0
	var multiplier := 1.0
	if world.season == GameEnums.Season.AUTUMN:
		multiplier += 0.15
	elif world.season == GameEnums.Season.WINTER:
		multiplier -= 0.25
	if world.weather == GameEnums.Weather.RAIN:
		multiplier += 0.10
	elif world.weather == GameEnums.Weather.STORM:
		multiplier -= 0.25
	elif world.weather == GameEnums.Weather.COLD:
		multiplier -= 0.20
	elif world.weather == GameEnums.Weather.HEAT:
		multiplier -= 0.15
	return clampf(multiplier, 0.5, 1.25)


func season_label(season: int) -> String:
	return ["Xuân", "Hạ", "Thu", "Đông"][season]


func weather_label(weather: int) -> String:
	return ["Quang", "Mưa", "Bão", "Rét", "Nóng"][weather]


func pressure_label(pressure: int) -> String:
	return ["Dư dả", "Ổn định", "Căng", "Nguy cấp"][pressure]


func presence_label(presence: int) -> String:
	return ["Chưa biết", "Đã quan sát", "Đã ghé", "Được tiếp tế", "Đã kết nối", "Có ảnh hưởng"][presence]


func route_safety_label(safety: int, blocked: bool) -> String:
	if blocked:
		return "Bị chặn"
	if safety >= 4:
		return "An toàn"
	if safety >= 2:
		return "Cần thận trọng"
	return "Nguy hiểm"


func condition_for_region(region: RegionState) -> String:
	if region.danger >= 4:
		return "Dấu hiệu nguy hiểm dày đặc"
	if region.food_potential > region.material_potential:
		return "Có khả năng tìm thấy lương thực"
	if region.material_potential > region.food_potential:
		return "Có dấu vết vật tư"
	return "Chưa thấy lợi thế rõ ràng"


func _update_routes(world: WorldState, result: TurnResolutionResult) -> void:
	var route_ids := world.routes.keys()
	route_ids.sort()
	for route_id in route_ids:
		var route := world.routes.get(route_id) as RouteState
		if route == null:
			continue
		if route.blocked_turns_left > 0:
			route.blocked_turns_left -= 1
			if route.blocked_turns_left == 0:
				route.blocked = false
				_add_world_event(result, "Tuyến %s đã có thể đi lại." % _route_name(world, route))
		if route.last_used_turn == world.world_turn - 1 and not route.blocked:
			route.safety = mini(MAX_SAFETY, route.safety + 1)
		elif route.last_used_turn >= 0 and world.world_turn - route.last_used_turn >= 4:
			route.safety = maxi(0, route.safety - 1)
		if world.weather == GameEnums.Weather.STORM and route.discovered:
			route.safety = maxi(0, route.safety - 1)
			if route.safety == 0 and not route.blocked:
				route.blocked = true
				route.blocked_turns_left = 1
				_add_world_event(result, "Bão đã tạm chặn tuyến %s." % _route_name(world, route))


func _update_regions(world: WorldState, result: TurnResolutionResult) -> void:
	var ids := world.known_regions.duplicate()
	ids.sort()
	var pressure_total := 0
	for region_id in ids:
		var region := world.regions.get(region_id) as RegionState
		if region == null or region.id == CITY_REGION_ID:
			continue
		if region.last_visited_turn >= 0 and world.world_turn - region.last_visited_turn >= 5:
			var old_presence := region.presence
			region.presence = maxi(GameEnums.RegionPresence.OBSERVED, region.presence - 1)
			if region.presence != old_presence:
				_add_world_event(result, "Ảnh hưởng tại %s đang nhạt dần vì lâu không có người tới." % region.name)
		_update_region_threats(world, region)
		region.current_condition = condition_for_region(region)
		pressure_total += region.danger + region.population_pressure
	world.global_pressure = pressure_total


func _update_factions(world: WorldState, result: TurnResolutionResult) -> void:
	var faction_ids := world.factions.keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		var faction := world.factions.get(faction_id) as FactionState
		if faction == null:
			continue
		var region_ids := faction.influence_by_region.keys()
		region_ids.sort()
		for region_id in region_ids:
			var region := world.regions.get(region_id) as RegionState
			if region == null:
				continue
			var influence := int(faction.influence_by_region.get(region_id, 0))
			if region.danger >= 4 and "thù địch" in faction.traits:
				influence = mini(5, influence + 1)
			elif region.presence >= GameEnums.RegionPresence.CONNECTED:
				influence = maxi(0, influence - 1)
			faction.influence_by_region[region_id] = influence
			region.faction_presence[faction.id] = influence
			if faction.known and influence >= 3:
				_add_world_event(result, "%s đang gia tăng ảnh hưởng tại %s." % [faction.name, region.name])


func _update_migration(state: GameState, world: WorldState, result: TurnResolutionResult) -> void:
	var group_ids := state.outsider_groups.keys()
	group_ids.sort()
	for group_id in group_ids:
		var group := state.outsider_groups.get(group_id) as OutsiderGroupState
		if group == null or group.is_resettling() or group.resettlement_complete:
			continue
		if group.region_id.is_empty():
			group.region_id = _default_outside_region(world)
		var current := world.regions.get(group.region_id) as RegionState
		if current == null:
			continue
		if group.support_active and not group.support_unmet:
			group.supported_days += 1
			current.presence = maxi(current.presence, GameEnums.RegionPresence.SUPPLIED)
			current.remember("outsider_supported", world.world_turn, {"group_id": group.id})
		else:
			group.supported_days = 0
		if group.supported_days >= 3 and group.migration_state.is_empty():
			group.migration_state = "request_city"
			group.migration_reason = "Được hỗ trợ ổn định trong nhiều ngày"
			group.history_tags.append({"kind": "requested_entry", "day": state.day, "region_id": current.id})
			_add_world_event(result, "%s xin được tới gần thành sau nhiều ngày nhận hỗ trợ." % group.name)
		elif (
			group.support_unmet
			and group.unresolved_days >= 2
			and group.migration_state != "moved"
		):
			var destination := _migration_destination(world, current.id)
			if destination != null and destination.id != current.id:
				current.outsider_presence = maxi(0, current.outsider_presence - 1)
				destination.outsider_presence += 1
				group.region_id = destination.id
				group.migration_state = "moved"
				group.migration_reason = "Thiếu hỗ trợ và tuyến cũ không còn ổn định"
				group.history_tags.append({"kind": "migrated", "day": state.day, "to_region": destination.id})
				_add_world_event(result, "%s rời %s và chuyển về %s vì thiếu hỗ trợ." % [group.name, current.name, destination.name])


func _update_region_threats(world: WorldState, region: RegionState) -> void:
	var hostile := 0
	for faction_id in region.faction_presence:
		var faction := world.factions.get(faction_id) as FactionState
		if faction != null and "thù địch" in faction.traits:
			hostile = maxi(hostile, int(region.faction_presence[faction_id]))
	region.threats.bandits = maxi(0, hostile - 1)
	region.threats.hostile_faction = hostile
	region.threats.famine = (
		2 if world.food_pressure == GameEnums.ResourcePressure.CRITICAL
		else (1 if world.food_pressure == GameEnums.ResourcePressure.STRAINED else 0)
	)
	region.threats.disease = (
		1 if region.outsider_presence > 0
		and world.weather in [GameEnums.Weather.RAIN, GameEnums.Weather.STORM]
		else 0
	)
	region.threats.weather_hazard = (
		2 if world.weather == GameEnums.Weather.STORM
		else (1 if world.weather in [GameEnums.Weather.COLD, GameEnums.Weather.HEAT] else 0)
	)
	region.threats.refugee_pressure = mini(3, region.population_pressure)
	var total := 0
	for value in region.threats.values():
		total += int(value)
	region.danger = clampi(
		maxi(region.base_danger, int(floor(float(total) / 2.5))), 0, MAX_DANGER
	)


func _update_resource_pressure(
	state: GameState, world: WorldState, result: TurnResolutionResult
) -> void:
	var city_consumers := 0
	for candidate in state.units.values():
		if not (candidate is UnitState):
			continue
		if candidate.away_days_left > 0 or not candidate.away_assignment_id.is_empty():
			continue
		if candidate.faction == GameEnums.Faction.PLAYER and candidate.rank not in [GameEnums.Rank.KING, GameEnums.Rank.QUEEN]:
			city_consumers += 1
		elif candidate.is_prisoner and not candidate.prisoner_labor:
			city_consumers += 1
	var support_cost := 0
	for group in state.outsider_groups.values():
		if group is OutsiderGroupState and group.support_active:
			support_cost += group.member_count()
	var days_of_food := float(state.food) / float(maxi(1, city_consumers + support_cost))
	var previous_food := world.food_pressure
	if days_of_food >= 4.0:
		world.food_pressure = GameEnums.ResourcePressure.SURPLUS
	elif days_of_food >= 2.0:
		world.food_pressure = GameEnums.ResourcePressure.STABLE
	elif days_of_food >= 1.0:
		world.food_pressure = GameEnums.ResourcePressure.STRAINED
	else:
		world.food_pressure = GameEnums.ResourcePressure.CRITICAL
	var previous_material := world.material_pressure
	if state.materials >= 6:
		world.material_pressure = GameEnums.ResourcePressure.SURPLUS
	elif state.materials >= 3:
		world.material_pressure = GameEnums.ResourcePressure.STABLE
	elif state.materials >= 1:
		world.material_pressure = GameEnums.ResourcePressure.STRAINED
	else:
		world.material_pressure = GameEnums.ResourcePressure.CRITICAL
	if previous_food != world.food_pressure and world.food_pressure >= GameEnums.ResourcePressure.STRAINED:
		_add_world_event(result, "Dự trữ Lương thực đang ở mức %s." % pressure_label(world.food_pressure).to_lower())
	if previous_material != world.material_pressure and world.material_pressure >= GameEnums.ResourcePressure.STRAINED:
		_add_world_event(result, "Nguồn Vật tư dài hạn đang ở mức %s." % pressure_label(world.material_pressure).to_lower())


func _update_season_and_weather(
	state: GameState, world: WorldState, result: TurnResolutionResult
) -> void:
	var previous_season := world.season
	world.season = mini(
		GameEnums.Season.WINTER,
		int(floor(float(world.world_turn) / float(TURNS_PER_SEASON)))
	)
	var weather_roll := _stable_seed(state.run_seed, "weather", world.world_turn) % 100
	world.weather = _weather_for_roll(world.season, weather_roll)
	if world.season != previous_season:
		_add_world_event(result, "Mùa %s đã tới; nhịp sản xuất và đường xa sẽ thay đổi." % season_label(world.season))
	if world.weather in [GameEnums.Weather.STORM, GameEnums.Weather.COLD, GameEnums.Weather.HEAT]:
		_add_world_event(result, "Thời tiết chuyển %s, các tuyến ngoài thành chịu thêm áp lực." % weather_label(world.weather).to_lower())


func _weather_for_roll(season: int, roll: int) -> GameEnums.Weather:
	if season == GameEnums.Season.WINTER:
		return GameEnums.Weather.COLD if roll < 55 else (GameEnums.Weather.STORM if roll < 72 else GameEnums.Weather.CLEAR)
	if season == GameEnums.Season.SUMMER:
		return GameEnums.Weather.HEAT if roll < 38 else (GameEnums.Weather.STORM if roll < 52 else GameEnums.Weather.CLEAR)
	if season == GameEnums.Season.SPRING:
		return GameEnums.Weather.RAIN if roll < 40 else (GameEnums.Weather.STORM if roll < 52 else GameEnums.Weather.CLEAR)
	return GameEnums.Weather.RAIN if roll < 25 else (GameEnums.Weather.COLD if roll < 40 else GameEnums.Weather.CLEAR)


func _reveal_faction_presence(
	world: WorldState, region: RegionState, result: TurnResolutionResult
) -> void:
	var ids := region.faction_presence.keys()
	ids.sort()
	for faction_id in ids:
		if int(region.faction_presence.get(faction_id, 0)) <= 0:
			continue
		var faction := world.factions.get(faction_id) as FactionState
		if faction == null or faction.known:
			continue
		faction.known = true
		faction.memory.append({"kind": "discovered", "turn": world.world_turn, "region_id": region.id})
		_add_world_event(result, "Tại %s xuất hiện dấu vết của %s." % [region.name, faction.name])


func _default_outside_region(world: WorldState) -> String:
	for region_id in world.known_regions:
		if region_id != CITY_REGION_ID:
			return region_id
	return CITY_REGION_ID


func _migration_destination(world: WorldState, current_id: String) -> RegionState:
	var current := world.regions.get(current_id) as RegionState
	if current == null:
		return null
	var route_ids := current.route_links.duplicate()
	route_ids.sort()
	for route_id in route_ids:
		var route := world.routes.get(route_id) as RouteState
		if route == null or not route.discovered or route.blocked:
			continue
		var other_id := route.other_end(current_id)
		if other_id == CITY_REGION_ID:
			continue
		var other := world.regions.get(other_id) as RegionState
		if other != null and other.danger < current.danger:
			return other
	return current


func _route_name(world: WorldState, route: RouteState) -> String:
	var first := world.regions.get(route.from_region) as RegionState
	var second := world.regions.get(route.to_region) as RegionState
	return "%s — %s" % [first.name if first != null else "?", second.name if second != null else "?"]


func _add_world_event(result: TurnResolutionResult, text: String) -> void:
	if not text.is_empty() and text not in result.world_events:
		result.world_events.append(text)


func _stable_seed(run_seed: int, salt: String, turn: int) -> int:
	var text := "%d|%s|%d" % [run_seed, salt, turn]
	var value := 216613626
	for index in range(text.length()):
		value = (value * 16777619 + text.unicode_at(index)) % 2147483647
	return absi(value)
