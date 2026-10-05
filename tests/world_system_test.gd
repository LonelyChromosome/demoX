extends SceneTree


func _init() -> void:
	_test_independent_world_and_route_lifecycle()
	_test_expedition_discovers_region_and_uses_memory()
	_test_season_weather_and_resource_pressure()
	_test_migration_and_faction_influence()
	print("WORLD_SYSTEM_TEST_OK")
	quit(0)


func _test_independent_world_and_route_lifecycle() -> void:
	var state := GameState.new()
	var world := state.world_state
	_check(world != null and world.regions.has("city"), "WorldState không tồn tại độc lập")
	_check(state.buildings.is_empty() and state.units.is_empty(), "WorldState phụ thuộc board state")
	var system := WorldSystem.new()
	var custom := RegionState.new("south_woods", "Rừng phía Nam")
	world.regions[custom.id] = custom
	world.add_known_region(custom.id)
	var route := system.discover_route(world, "city", custom.id)
	_check(route != null and route.discovered, "Không tạo được tuyến đường mới")
	var result := TurnResolutionResult.new()
	route.last_used_turn = world.world_turn
	var old_safety := route.safety
	system.resolve_world(state, result)
	_check(route.safety >= old_safety, "Tuyến được sử dụng không thể ổn định hơn")


func _test_expedition_discovers_region_and_uses_memory() -> void:
	var state := GameState.new()
	state.food = 100
	state.run_seed = 7221
	_unit(state, "scout_a", "Mã", GameEnums.Rank.KNIGHT, Vector2i(0, 7))
	_unit(state, "scout_b", "Tốt D", GameEnums.Rank.PAWN, Vector2i(1, 7))
	var manager := _manager(state)
	var order := manager.queue_expedition(["scout_a", "scout_b"], "north_fields", 1)
	_check(order != null, "Không tạo được expedition theo region")
	_check(not (state.world_state.regions.north_fields as RegionState).discovered, "Planned expedition đã leak discovery")
	manager.end_day()
	var expedition := state.expeditions.values()[0] as ExpeditionState
	expedition.days_left = 1
	expedition.outcome_kind = ExpeditionSystem.OUTCOME_FOOD
	for unit_id in expedition.unit_ids:
		(state.units[unit_id] as UnitState).away_days_left = 1
	var result := manager.end_day()
	var region := state.world_state.regions.north_fields as RegionState
	_check(region.discovered, "Expedition hoàn tất không khám phá region")
	_check(region.presence >= GameEnums.RegionPresence.VISITED, "Expedition không tăng presence mềm")
	_check(expedition.discovered_region_id == region.id, "Expedition không ghi region mới")
	_check(not result.world_events.is_empty(), "Region discovery không tạo storytelling từ state")
	var route := state.world_state.routes.route_north as RouteState
	_check(route.last_used_turn >= 0, "Expedition không cập nhật route")

	var probe := ExpeditionState.new("probe")
	probe.unit_ids = ["scout_a", "scout_b"]
	probe.target_region_id = region.id
	var system := ExpeditionSystem.new()
	var before := system.context_weights(state, probe)
	region.remember("ambush", state.world_state.world_turn)
	var after := system.context_weights(state, probe)
	_check(float(after.injury) > float(before.injury), "Memory phục kích không ảnh hưởng outcome")
	_check(
		system.choose_outcome(after, 433221) == system.choose_outcome(after, 433221),
		"Fixed seed không deterministic"
	)


func _test_season_weather_and_resource_pressure() -> void:
	var state := GameState.new()
	state.food = 0
	state.materials = 0
	_unit(state, "pawn", "Tốt", GameEnums.Rank.PAWN, Vector2i(0, 7))
	var world := state.world_state
	world.world_turn = WorldSystem.TURNS_PER_SEASON - 1
	var system := WorldSystem.new()
	var result := TurnResolutionResult.new()
	system.resolve_world(state, result)
	_check(world.season == GameEnums.Season.SUMMER, "Season không chuyển đúng chu kỳ")
	_check(world.food_pressure == GameEnums.ResourcePressure.CRITICAL, "Food pressure thấp không thành nguy cấp")
	_check(world.material_pressure == GameEnums.ResourcePressure.CRITICAL, "Material pressure thấp không thành nguy cấp")

	var farm := BuildingState.new("farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	var food_system := FoodSystem.new()
	world.season = GameEnums.Season.SPRING
	world.weather = GameEnums.Weather.CLEAR
	var normal := food_system.production_for_building(state, farm)
	world.season = GameEnums.Season.WINTER
	world.weather = GameEnums.Weather.COLD
	var harsh := food_system.production_for_building(state, farm)
	_check(harsh < normal, "Mùa và thời tiết không tác động production")


func _test_migration_and_faction_influence() -> void:
	var state := GameState.new()
	state.food = 20
	state.materials = 4
	var world := state.world_state
	var north := world.regions.north_fields as RegionState
	var east := world.regions.east_ruins as RegionState
	north.discovered = true
	east.discovered = true
	north.base_danger = 1
	north.danger = 1
	east.base_danger = 5
	east.danger = 5
	(world.routes.route_frontier_link as RouteState).discovered = true
	var group := OutsiderGroupState.new("migrants")
	group.name = "Nhóm Đồng Cỏ"
	group.region_id = east.id
	group.support_unmet = true
	group.unresolved_days = 2
	state.outsider_groups[group.id] = group
	var faction := world.factions.ash_raiders as FactionState
	faction.known = true
	faction.influence_by_region[north.id] = 3
	north.faction_presence[faction.id] = 3
	north.presence = GameEnums.RegionPresence.CONNECTED
	var old_influence := int(faction.influence_by_region[north.id])
	var result := TurnResolutionResult.new()
	WorldSystem.new().resolve_world(state, result)
	_check(group.region_id == north.id, "Migration không theo nguyên nhân food/safety/route")
	_check(group.migration_reason != "", "Migration không lưu nguyên nhân")
	_check(
		int(faction.influence_by_region[north.id]) < old_influence,
		"Presence của thành không tác động influence phe ngoài"
	)


func _unit(
	state: GameState, unit_id: String, unit_name: String,
	rank: GameEnums.Rank, cell: Vector2i
) -> UnitState:
	var unit := UnitState.new(unit_id)
	unit.display_name = unit_name
	unit.rank = rank
	unit.board_cell = cell
	state.units[unit.id] = unit
	return unit


func _manager(state: GameState) -> TurnManager:
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return manager


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
