class_name WorldState
extends RefCounted

var regions: Dictionary = {}
var routes: Dictionary = {}
var known_regions: Array[String] = []
var factions: Dictionary = {}
var global_pressure := 0
var season: GameEnums.Season = GameEnums.Season.SPRING
var weather: GameEnums.Weather = GameEnums.Weather.CLEAR
var world_turn := 0
var recent_world_events: Array[String] = []
var food_pressure: GameEnums.ResourcePressure = GameEnums.ResourcePressure.STABLE
var material_pressure: GameEnums.ResourcePressure = GameEnums.ResourcePressure.STABLE


func initialize_defaults() -> void:
	if not regions.is_empty():
		return
	var city := RegionState.new("city", "Thành trì")
	city.discovered = true
	city.current_condition = "Có kiểm soát"
	city.presence = GameEnums.RegionPresence.INFLUENCED
	regions[city.id] = city

	var north := RegionState.new("north_fields", "Đồng cỏ phía Bắc")
	north.food_potential = 3
	north.material_potential = 1
	north.danger = 2
	north.base_danger = 2
	north.population_pressure = 1
	north.current_condition = "Chỉ mới thấy từ xa"
	north.presence = GameEnums.RegionPresence.OBSERVED
	regions[north.id] = north

	var east := RegionState.new("east_ruins", "Phế tích bờ Đông")
	east.food_potential = 1
	east.material_potential = 3
	east.danger = 3
	east.base_danger = 3
	east.current_condition = "Dấu vết cũ chưa rõ"
	east.presence = GameEnums.RegionPresence.OBSERVED
	regions[east.id] = east
	known_regions = [city.id, north.id, east.id]

	_add_route("route_north", city.id, north.id, true, 3, 1)
	_add_route("route_east", city.id, east.id, true, 2, 2)
	_add_route("route_frontier_link", north.id, east.id, false, 1, 1)

	var raiders := FactionState.new("ash_raiders", "Những quân cờ Tro Xám")
	raiders.traits = ["thù địch", "chặn đường"]
	raiders.influence_by_region[north.id] = 1
	factions[raiders.id] = raiders

	var traders := FactionState.new("river_traders", "Đoàn buôn Bờ Đông")
	traders.traits = ["trao đổi", "thận trọng"]
	traders.influence_by_region[east.id] = 1
	factions[traders.id] = traders


func add_known_region(region_id: String) -> void:
	if not known_regions.has(region_id):
		known_regions.append(region_id)


func route_between(first_region: String, second_region: String) -> RouteState:
	for candidate in routes.values():
		if not (candidate is RouteState):
			continue
		if (
			(candidate.from_region == first_region and candidate.to_region == second_region)
			or (candidate.from_region == second_region and candidate.to_region == first_region)
		):
			return candidate
	return null


func _add_route(
	route_id: String, from_id: String, to_id: String,
	discovered_value: bool, safety_value: int, travel_value: int
) -> void:
	var route := RouteState.new(route_id, from_id, to_id)
	route.discovered = discovered_value
	route.safety = safety_value
	route.travel_cost = travel_value
	routes[route.id] = route
	(regions[from_id] as RegionState).route_links.append(route.id)
	(regions[to_id] as RegionState).route_links.append(route.id)
