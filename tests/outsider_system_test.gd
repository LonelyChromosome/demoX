extends SceneTree


func _init() -> void:
	_test_support_food_and_shortage()
	_test_trade_requires_king_and_commits_at_end_day()
	_test_resettlement_exact_cost_and_duration()
	_test_pressure_failure_and_story_language()
	print("OUTSIDER_SYSTEM_TEST_OK")
	quit(0)


func _test_support_food_and_shortage() -> void:
	var state := GameState.new()
	state.food = 5
	var group := _group(state, "north", "Nhóm phía Bắc", 3)
	var manager := _manager(state)
	var order := manager.queue_outsider_action(group.id, GameEnums.OutsiderAction.START_SUPPORT)
	_check(order != null and not group.support_active, "Hỗ trợ không còn là planned order")
	var result := manager.end_day()
	_check(group.support_active and not group.support_unmet, "Hỗ trợ hợp lệ không được commit")
	_check(state.food == 2 and result.outsider_food_consumed == 3, "Ba người ngoài không tốn đúng 3 Food")
	for member_id in group.member_unit_ids:
		var member := state.units.get(member_id) as UnitState
		_check(member.faction == GameEnums.Faction.OUTSIDER, "Hỗ trợ đã biến người ngoài thành phe ta")
		_check(member.hunger_streak == 0, "S8 đã áp starvation của quân thành cho outsider")

	var short_state := GameState.new()
	short_state.food = 0
	var short_group := _group(short_state, "short", "Nhóm lối Nam", 1)
	var short_manager := _manager(short_state)
	short_manager.queue_outsider_action(short_group.id, GameEnums.OutsiderAction.START_SUPPORT)
	short_manager.end_day()
	_check(short_group.support_unmet, "Thiếu Food không lưu trạng thái hỗ trợ thất hứa")
	var outsider := short_state.units.get(short_group.member_unit_ids[0]) as UnitState
	_check(outsider != null and outsider.hunger_streak == 0, "Outsider bị áp luật chết đói 3 ngày")


func _test_trade_requires_king_and_commits_at_end_day() -> void:
	var state := GameState.new()
	state.food = 4
	state.materials = 0
	var group := _group(state, "trade_group", "Nhóm bờ Đông", 1)
	var manager := _manager(state)
	_check(
		manager.queue_outsider_action(group.id, GameEnums.OutsiderAction.ACCEPT_TRADE) == null,
		"Giao dịch không có Vua vẫn được duyệt"
	)
	_unit(state, "king", "Vua", GameEnums.Rank.KING, Vector2i(4, 7))
	var order := manager.queue_outsider_action(group.id, GameEnums.OutsiderAction.ACCEPT_TRADE)
	_check(order != null, "Vua không thể tạo quyết định giao dịch")
	_check(state.food == 4 and state.materials == 0, "Giao dịch sửa tài nguyên trước End Day")
	var result := manager.end_day()
	_check(state.food == 3 and state.materials == 1, "Trao đổi 1:1 commit sai")
	_check(result.trade_food_delta == -1 and result.trade_materials_delta == 1, "Result thiếu delta giao dịch")
	_check(_group_has_history(group, "trade_accepted"), "Group không nhớ giao dịch được chấp thuận")
	var before_food := state.food
	var before_materials := state.materials
	manager.queue_outsider_action(group.id, GameEnums.OutsiderAction.REJECT_TRADE)
	manager.end_day()
	_check(state.food == before_food and state.materials == before_materials, "Từ chối giao dịch vẫn đổi tài nguyên")
	_check(_group_has_history(group, "trade_rejected"), "Group không nhớ giao dịch bị từ chối")


func _test_resettlement_exact_cost_and_duration() -> void:
	var state := GameState.new()
	state.food = 100
	var group := _group(state, "settlers", "Nhóm sườn Tây", 2)
	_unit(state, "king", "Vua", GameEnums.Rank.KING, Vector2i(4, 7))
	var first := _unit(state, "escort_a", "Mã", GameEnums.Rank.KNIGHT, Vector2i(0, 7))
	var second := _unit(state, "escort_b", "Tốt D", GameEnums.Rank.PAWN, Vector2i(1, 7))
	_unit(state, "third", "Xe", GameEnums.Rank.ROOK, Vector2i(2, 7))
	var manager := _manager(state)
	_check(
		manager.queue_outsider_action(group.id, GameEnums.OutsiderAction.RESETTLE, [first.id]) == null,
		"Một hộ tống vẫn tạo được tái định cư"
	)
	_check(
		manager.queue_outsider_action(
			group.id, GameEnums.OutsiderAction.RESETTLE, [first.id, second.id, "third"]
		) == null,
		"Ba hộ tống vẫn tạo được tái định cư"
	)
	var order := manager.queue_outsider_action(
		group.id, GameEnums.OutsiderAction.RESETTLE, [first.id, second.id]
	)+	_check(order != null and first.board_cell == Vector2i(0, 7), "Tái định cư sửa state trước End Day")
	var original_player_count := state.player_roster_count()
	var original_food := state.food
	var original_materials := state.materials
	manager.end_day()
	_check(group.resettlement_days_left == 2, "Ngày khởi hành đã trừ sai thời lượng tái định cư")
	_check(first.away_days_left == 2 and not first.can_be_moved(), "Hộ tống chưa bị khóa ngoài thành")
	manager.end_day()
	_check(group.resettlement_days_left == 1, "Tái định cư không kéo dài đúng hai turn")
	manager.end_day()
	_check(not state.outsider_groups.has(group.id), "Group chưa rời khu vực sau hai turn")
	_check(first.away_assignment_id.is_empty() and second.away_assignment_id.is_empty(), "Hộ tống không trở về")
	_check(first.board_cell == Vector2i(0, 7) and second.board_cell == Vector2i(1, 7), "Hộ tống trở về không deterministic")
	_check(state.materials == original_materials, "Tái định cư tạo phần thưởng Vật tư")
	_check(state.player_roster_count() == original_player_count, "Tái định cư tạo quân mới")
	_check(state.food == original_food - 3, "Tái định cư tạo Food hoặc tính khẩu phần quân away")
	_check(_has_unit_memory(first, "resettlement_escort"), "Hộ tống không lưu memory")


func _test_pressure_failure_and_story_language() -> void:
	var state := GameState.new()
	state.food = 0
	var group := _group(state, "internal_group_id", "Nhóm phía Bắc", 1)
	group.pressure = GameEnums.OutsidePressure.TENSE
	var manager := _manager(state)
	var result := manager.end_day()
	_check(state.game_over and group.pressure == GameEnums.OutsidePressure.RIOT, "LOẠN không kích hoạt failure state")
	_check("Nhóm phía Bắc" in state.failure_reason, "Failure không dùng tên hiển thị của group")
	_check("combat" not in state.failure_reason.to_lower(), "S8 tạo combat mode")
	_check(_report_contains(result, "Nhóm phía Bắc"), "Daily Report không kể hậu quả ngoài thành")
	_check(not _report_contains(result, "internal_group_id"), "Daily Report leak internal id")
	_check(OutsideSystem.new().pressure_label(group) == "Hỗn loạn", "UI không dùng nhãn pressure tiếng Việt")


func _group(
	state: GameState, group_id: String, display_name: String, count: int
) -> OutsiderGroupState:
	var group := OutsiderGroupState.new(group_id)
	group.name = display_name
	group.trade_offer = {"city_gives": "food", "city_receives": "materials", "quantity": 1}
	for index in range(count):
		var member := UnitState.new("%s_member_%d" % [group_id, index])
		member.display_name = "Người ngoài %d" % (index + 1)
		member.faction = GameEnums.Faction.OUTSIDER
		member.rank = GameEnums.Rank.PAWN
		member.board_cell = Vector2i(-1, -1)
		state.units[member.id] = member
		group.member_unit_ids.append(member.id)
	state.outsider_groups[group.id] = group
	state.outsiders_count += count
	return group


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


func _group_has_history(group: OutsiderGroupState, kind: String) -> bool:
	for tag in group.history_tags:
		if tag.get("kind", "") == kind:
			return true
	return false


func _has_unit_memory(unit: UnitState, kind: String) -> bool:
	for tag in unit.memory_tags:
		if tag.get("kind", "") == kind:
			return true
	return false


func _report_contains(result: TurnResolutionResult, text: String) -> bool:
	for entry in result.report_entries:
		if text in entry.text:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)