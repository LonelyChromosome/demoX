extends SceneTree


func _init() -> void:
	_test_exact_team_and_planned_state()
	_test_away_lifecycle_and_role_cleanup()
	_test_deterministic_weighted_outcomes()
	_test_injury_death_and_outsider_memory()
	print("EXPEDITION_SYSTEM_TEST_OK")
	quit(0)


func _test_exact_team_and_planned_state() -> void:
	var state := GameState.new()
	state.food = 30
	var first := _unit(state, "rook", "Xe", GameEnums.Rank.ROOK, Vector2i(0, 7))
	var second := _unit(state, "knight", "Mã", GameEnums.Rank.KNIGHT, Vector2i(1, 7))
	_unit(state, "pawn", "Tốt", GameEnums.Rank.PAWN, Vector2i(2, 7))
	var manager := _manager(state)
	_check(manager.queue_expedition([first.id]) == null, "Một quân vẫn tạo được đoàn thám hiểm")
	_check(
		manager.queue_expedition([first.id, second.id, "pawn"]) == null,
		"Ba quân vẫn tạo được đoàn thám hiểm"
	)
	var order := manager.queue_expedition([first.id, second.id])
	_check(order != null, "Đúng hai quân không tạo được lệnh dự kiến")
	_check(first.board_cell == Vector2i(0, 7), "Lệnh dự kiến đã đưa quân rời thành sớm")
	_check(first.away_assignment_id.is_empty(), "Lệnh dự kiến đã sửa trạng thái thật")
	manager.cancel_expedition()
	_check(manager.get_planned_expedition() == null, "Không hủy được chuyến đi dự kiến")


func _test_away_lifecycle_and_role_cleanup() -> void:
	var state := GameState.new()
	state.food = 30
	var farm := BuildingState.new("farm", GameEnums.BuildingType.FARM, Vector2i(3, 3))
	farm.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[farm.id] = farm
	var first := _unit(state, "manager", "Xe", GameEnums.Rank.ROOK, farm.core_cell)
	var second := _unit(state, "worker", "Tốt D", GameEnums.Rank.PAWN, Vector2i(2, 2))
	farm.manager_unit_id = first.id
	farm.worker_unit_ids = [second.id]
	farm.job_slots[first.board_cell] = GameEnums.JobRole.MANAGER
	farm.job_slots[second.board_cell] = GameEnums.JobRole.FARM_WORKER
	first.work_building_id = farm.id
	first.is_manager = true
	second.work_building_id = farm.id
	var first_origin := first.board_cell
	var second_origin := second.board_cell
	var manager := _manager(state)
	manager.queue_expedition([first.id, second.id])
	var departure := manager.end_day()
	var expedition := state.expeditions.values()[0] as ExpeditionState
	_check(first.board_cell == Vector2i(-1, -1), "Quân thám hiểm còn trên bàn")
	_check(first.away_assignment_id == expedition.id, "Quân không có trạng thái ngoài thành")
	_check(not first.can_be_moved(), "Quân ngoài thành vẫn nhận được lệnh")
	_check(departure.food_consumed == 0, "Quân ngoài thành vẫn ăn khẩu phần thành phố")
	_check(farm.manager_unit_id.is_empty(), "Người phụ trách rời thành nhưng role còn treo")
	_check(second.id not in farm.worker_unit_ids, "Lao động rời thành nhưng role còn treo")
	_check(first.work_building_id.is_empty() and second.work_building_id.is_empty(), "Unit còn work reference")
	_check(not expedition.outcome_applied, "Kết quả chuyến đi bị lộ/áp dụng lúc vừa khởi hành")
	_check(
		departure.expedition_events.size() == 1
		and departure.expedition_events[0].kind == "departed",
		"Ngày khởi hành đã công bố kết quả ẩn"
	)
	expedition.outcome_kind = ExpeditionSystem.OUTCOME_DEATH
	expedition.reward_amount = 99
	var rail := OutsideRail.new()
	root.add_child(rail)
	rail.setup(state, manager)
	var rail_text := _control_text(rail)
	_check("Chưa có tin" in rail_text, "Khu Ngoài thành không giữ kết quả ở trạng thái ẩn")
	_check("99" not in rail_text and "death" not in rail_text, "Khu Ngoài thành làm lộ kết quả")
	expedition.outcome_kind = ExpeditionSystem.OUTCOME_EMPTY
	expedition.days_left = 1
	first.away_days_left = 1
	second.away_days_left = 1
	manager.end_day()
	_check(expedition.status == GameEnums.ExpeditionStatus.COMPLETE, "Đoàn không hoàn tất đúng hạn")
	_check(first.board_cell == first_origin and second.board_cell == second_origin, "Vị trí trở về không deterministic")
	_check(first.away_assignment_id.is_empty(), "Trở về không dọn trạng thái ngoài thành")


func _test_deterministic_weighted_outcomes() -> void:
	var system := ExpeditionSystem.new()
	var low := GameState.new()
	low.food = 0
	low.materials = 0
	var stocked := GameState.new()
	stocked.food = 100
	stocked.materials = 100
	var low_weights := system.context_weights(low)
	var stocked_weights := system.context_weights(stocked)
	_check(
		float(low_weights[ExpeditionSystem.OUTCOME_FOOD])
		> float(stocked_weights[ExpeditionSystem.OUTCOME_FOOD]),
		"Food thấp không tăng trọng số tìm lương thực"
	)
	var first := system.choose_outcome(low_weights, 713421)
	var second := system.choose_outcome(low_weights, 713421)
	_check(first == second, "Cùng seed không cho cùng kết quả")
	_check(
		system.choose_outcome(low_weights, 999999) != ExpeditionSystem.OUTCOME_FOOD,
		"Food thấp đã biến tìm lương thực thành bảo đảm"
	)
	var found_empty := false
	for seed_value in range(0, 1000000, 997):
		if system.choose_outcome(stocked_weights, seed_value) == ExpeditionSystem.OUTCOME_EMPTY:
			found_empty = true
			break
	_check(found_empty, "Kết quả tay trắng không còn khả năng xảy ra")


func _test_injury_death_and_outsider_memory() -> void:
	var injury := _departure_context("injury")
	var injury_state: GameState = injury.state
	var injury_manager: TurnManager = injury.manager
	var injury_expedition: ExpeditionState = injury_state.expeditions.values()[0]
	injury_expedition.outcome_kind = ExpeditionSystem.OUTCOME_INJURY
	_force_return_next_day(injury_state, injury_expedition)
	injury_manager.end_day()
	var injured := injury_state.units.get("injury_a") as UnitState
	_check(injured != null and injured.injured, "Thám hiểm không chuyển chấn thương sang Y xá")
	_check(injured.healing_days_left == 2, "Thời gian điều trị từ thám hiểm không hợp lệ")

	var death := _departure_context("death")
	var death_state: GameState = death.state
	var death_manager: TurnManager = death.manager
	var death_expedition: ExpeditionState = death_state.expeditions.values()[0]
	death_expedition.outcome_kind = ExpeditionSystem.OUTCOME_DEATH
	_force_return_next_day(death_state, death_expedition)
	death_manager.end_day()
	_check(not death_state.units.has(death_expedition.lost_unit_id), "Quân đã mất vẫn còn trong state")
	var survivor_id := "death_b" if death_expedition.lost_unit_id == "death_a" else "death_a"
	var survivor := death_state.units.get(survivor_id) as UnitState
	_check(survivor != null and _has_memory(survivor, "partner_lost"), "Người sống sót không nhớ đồng đội đã mất")

	var outsiders := _departure_context("outsiders")
	var outsider_state: GameState = outsiders.state
	var outsider_manager: TurnManager = outsiders.manager
	var outsider_expedition: ExpeditionState = outsider_state.expeditions.values()[0]
	outsider_expedition.outcome_kind = ExpeditionSystem.OUTCOME_OUTSIDERS
	_force_return_next_day(outsider_state, outsider_expedition)
	outsider_manager.end_day()
	var group := outsider_state.outsider_groups.values()[0] as OutsiderGroupState
	_check(group != null and group.member_count() > 0, "Gặp người ngoài không tạo group persistent")
	for member_id in group.member_unit_ids:
		var member := outsider_state.units.get(member_id) as UnitState
		_check(member.faction == GameEnums.Faction.OUTSIDER, "Người ngoài bị đổi faction")
		_check(member.board_cell == Vector2i(-1, -1), "Người ngoài chiếm ô bàn cờ")
	var explorer := outsider_state.units.get("outsiders_a") as UnitState
	_check(_has_memory(explorer, "met_outsiders"), "Chuyến đi không lưu ký ức gặp group")
	_check(group.history_tags[0].expedition_id == outsider_expedition.id, "Group không liên kết lịch sử chuyến đi")


func _departure_context(prefix: String) -> Dictionary:
	var state := GameState.new()
	state.food = 50
	state.run_seed = 1945
	_unit(state, "%s_a" % prefix, "Mã", GameEnums.Rank.KNIGHT, Vector2i(0, 7))
	_unit(state, "%s_b" % prefix, "Tốt E", GameEnums.Rank.PAWN, Vector2i(1, 7))
	var manager := _manager(state)
	manager.queue_expedition(["%s_a" % prefix, "%s_b" % prefix])
	manager.end_day()
	return {"state": state, "manager": manager}


func _force_return_next_day(state: GameState, expedition: ExpeditionState) -> void:
	expedition.days_left = 1
	for unit_id in expedition.unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			unit.away_days_left = 1


func _has_memory(unit: UnitState, kind: String) -> bool:
	for tag in unit.memory_tags:
		if tag.get("kind", "") == kind:
			return true
	return false


func _control_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		parts.append(_control_text(child))
	return "\n".join(parts)


func _manager(state: GameState) -> TurnManager:
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return manager


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


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)