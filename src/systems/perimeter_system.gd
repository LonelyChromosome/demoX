class_name PerimeterSystem
extends RefCounted

const MIN_WASTELAND_DAYS := 2
const MAX_WASTELAND_DAYS := 3

var expedition_system := ExpeditionSystem.new()


func validate_development(
	state: GameState, order: DevelopWastelandOrder, blocked_unit_ids: Dictionary,
	reserved_unit_ids: Dictionary, result: TurnResolutionResult
) -> bool:
	if order == null or not state.wasteland.can_start():
		return false
	if state.food < state.wasteland.food_cost or state.materials < state.wasteland.material_cost:
		result.reject("wasteland", "wasteland", "Không đủ Lương thực hoặc Vật tư để khai phá")
		return false
	for unit_id in order.unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if blocked_unit_ids.has(unit_id) or reserved_unit_ids.has(unit_id) or unit == null or unit.rank == GameEnums.Rank.KING or not unit.can_be_moved():
			result.reject("wasteland", unit_id, "Quân tham gia khai phá không hợp lệ")
			return false
	for unit_id in order.unit_ids:
		reserved_unit_ids[unit_id] = true
	return true


func commit_development(state: GameState, order: DevelopWastelandOrder, result: TurnResolutionResult) -> void:
	var project := state.wasteland
	project.active = true
	project.started_day = state.day
	project.duration_days = MIN_WASTELAND_DAYS + (_stable_seed(state.run_seed, state.day) % (MAX_WASTELAND_DAYS - MIN_WASTELAND_DAYS + 1))
	project.days_left = project.duration_days
	project.participant_unit_ids = order.unit_ids.duplicate()
	state.food -= project.food_cost
	state.materials -= project.material_cost
	result.wasteland_food_spent += project.food_cost
	result.materials_spent += project.material_cost
	for unit_id in project.participant_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null:
			continue
		expedition_system.release_city_roles(state, unit)
		unit.board_cell = Vector2i(-1, -1)
		unit.away_days_left = project.duration_days
		unit.away_assignment_id = "wasteland"
		unit.away_reason = "wasteland"
	project.remember("started", state.day, {"duration": project.duration_days})
	result.perimeter_events.append({"kind": "wasteland_started", "text": "Công việc khai phá Đất hoang đã bắt đầu."})


func resolve_daily(state: GameState, skip_progress: bool, result: TurnResolutionResult) -> void:
	var project := state.wasteland
	if project.active and not skip_progress:
		project.days_left = maxi(0, project.days_left - 1)
		for unit_id in project.participant_unit_ids:
			var unit := state.units.get(unit_id) as UnitState
			if unit != null:
				unit.away_days_left = project.days_left
		result.perimeter_events.append({
			"kind": "wasteland_progress",
			"text": "Đất hoang đang được khai phá; còn %d ngày." % project.days_left,
		})
		if project.days_left == 0:
			_complete(state, result)
	if project.completed:
		state.food += project.daily_food_yield
		state.materials += project.daily_material_yield
		result.food_produced += project.daily_food_yield
		result.materials_produced += project.daily_material_yield
		result.perimeter_food_produced += project.daily_food_yield
		result.perimeter_materials_produced += project.daily_material_yield


func _complete(state: GameState, result: TurnResolutionResult) -> void:
	var project := state.wasteland
	project.active = false
	project.completed = true
	project.remember("completed", state.day)
	for unit_id in project.participant_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or unit.away_assignment_id != "wasteland":
			continue
		var cell := expedition_system.find_return_cell(state, Vector2i(4, 7))
		if cell == Vector2i(-1, -1):
			unit.return_pending = true
			continue
		unit.board_cell = cell
		unit.away_days_left = 0
		unit.away_assignment_id = ""
		unit.away_reason = ""
		unit.return_pending = false
	result.perimeter_events.append({"kind": "wasteland_complete", "text": "Đất hoang đã khai phá xong; nơi tái định cư an toàn đã sẵn sàng."})


func location_for_unit(unit: UnitState) -> String:
	if unit == null:
		return "city"
	if unit.faction == GameEnums.Faction.OUTSIDER:
		return "refugee"
	if unit.away_reason == "resettlement":
		return "refugee"
	if unit.away_reason == "wasteland":
		return "wasteland"
	if not unit.away_assignment_id.is_empty():
		return "forest"
	return "city"


func _stable_seed(run_seed: int, day: int) -> int:
	return absi((run_seed * 1103515245 + day * 12345) % 2147483647)
