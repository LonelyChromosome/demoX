extends SceneTree


func _init() -> void:
	_test_prisoner_food_and_starvation()
	_test_prisoner_labor()
	_test_submission_release_and_escape_hooks()
	print("PRISONER_LIFECYCLE_TEST_OK")
	quit(0)


func _test_prisoner_food_and_starvation() -> void:
	var state := GameState.new()
	state.food = 1
	var prison := _active_building(state, "prison_food", GameEnums.BuildingType.PRISON)
	var prisoner := _enemy(state, "hungry_prisoner", GameEnums.Rank.QUEEN)
	_check(PrisonSystem.new().admit_prisoner(state, prisoner.id, prison.id), "Không nhận được tù binh")
	var manager := _manager(state)
	var fed := manager.end_day()
	_check(fed.food_consumed == 1, "Tù binh không lao động phải ăn 1 Lương thực kể cả cấp Hậu")
	state.food = 0
	for expected in [1, 2]:
		var paused := manager.end_day()
		_check(paused.awaiting_ration and prisoner.id in paused.ration_candidate_ids, "Tù binh không lao động thiếu khỏi chia khẩu phần")
		manager.submit_ration([])
		_check(prisoner.hunger_streak == expected and state.units.has(prisoner.id), "Tù binh chết đói sai mốc")
	var third := manager.end_day()
	_check(third.awaiting_ration, "Ngày đói thứ ba không chờ chia khẩu phần")
	var death := manager.submit_ration([])
	_check(prisoner.id in death.starved_unit_ids and not state.units.has(prisoner.id), "Tù binh không chết sau đúng ba ngày đói")
	_check(prisoner.id not in prison.prisoner_unit_ids and prisoner.id not in state.prisoners, "Tù chết để lại tham chiếu Nhà giam")


func _test_prisoner_labor() -> void:
	var state := GameState.new()
	state.food = 20
	var prison := _active_building(state, "prison_labor", GameEnums.BuildingType.PRISON)
	var prisoner := _enemy(state, "laborer", GameEnums.Rank.KNIGHT)
	PrisonSystem.new().admit_prisoner(state, prisoner.id, prison.id)
	var farm := _active_building(state, "farm", GameEnums.BuildingType.FARM, Vector2i(1, 1))
	var construction := BuildingState.new("barracks", GameEnums.BuildingType.BARRACKS, Vector2i(5, 5))
	construction.phase = GameEnums.BuildingPhase.BUILDING
	construction.days_left = 4
	var builder := UnitState.new("builder")
	builder.rank = GameEnums.Rank.ROOK
	builder.board_cell = Vector2i(0, 0)
	builder.assigned_building_id = construction.id
	builder.locked_by_construction = true
	state.units[builder.id] = builder
	construction.builder_unit_ids = [builder.id]
	state.buildings[construction.id] = construction
	var manager := _manager(state)
	manager.queue_prisoner_labor(prisoner.id, construction.id)
	var result := manager.end_day()
	_check(result.food_produced == 2, "Tù lao động đã tăng sản lượng Nông trại")
	_check(result.materials_produced == 0, "Tù lao động trực tiếp tạo Vật tư")
	_check(result.food_consumed == 0 and prisoner.id not in result.ration_candidate_ids, "Tù lao động dùng Lương thực thành phố")
	_check(farm.worker_unit_ids.is_empty(), "Tù lao động chiếm chỗ Nông trại")
	_check(construction.days_left == 2, "Lao động tù binh không giảm tổng thời gian đúng tối đa một ngày")
	_check(not prisoner.prisoner_labor and prisoner.labor_building_id.is_empty(), "Tù lao động không quay về giam sau End Day")
	manager.queue_prisoner_labor(prisoner.id, construction.id)
	manager.end_day()
	_check(construction.days_left == 1, "Lao động tù binh bị cộng dồn bonus nhiều lần")

	var state_two := GameState.new()
	state_two.food = 20
	var prison_two := _active_building(state_two, "prison_two", GameEnums.BuildingType.PRISON)
	var prisoner_two := _enemy(state_two, "laborer_two", GameEnums.Rank.ROOK)
	PrisonSystem.new().admit_prisoner(state_two, prisoner_two.id, prison_two.id)
	var accelerated := BuildingState.new("fast", GameEnums.BuildingType.BARRACKS, Vector2i(4, 4))
	accelerated.phase = GameEnums.BuildingPhase.BUILDING
	accelerated.days_left = 3
	accelerated.accelerated_by_builders = true
	var accelerated_builder := UnitState.new("accelerated_builder")
	accelerated_builder.rank = GameEnums.Rank.ROOK
	accelerated_builder.board_cell = Vector2i(0, 0)
	accelerated_builder.assigned_building_id = accelerated.id
	accelerated_builder.locked_by_construction = true
	state_two.units[accelerated_builder.id] = accelerated_builder
	accelerated.builder_unit_ids = [accelerated_builder.id]
	state_two.buildings[accelerated.id] = accelerated
	var manager_two := _manager(state_two)
	manager_two.queue_prisoner_labor(prisoner_two.id, accelerated.id)
	manager_two.end_day()
	_check(accelerated.days_left == 2, "Tù lao động giảm thêm khi đã có 2+ thợ xây")


func _test_submission_release_and_escape_hooks() -> void:
	var state := GameState.new()
	state.food = 20
	var prison := _active_building(state, "prison_actions", GameEnums.BuildingType.PRISON)
	var prisoner := _enemy(state, "convert", GameEnums.Rank.KNIGHT)
	var system := PrisonSystem.new()
	system.admit_prisoner(state, prisoner.id, prison.id)
	_check(system.request_escape_attempt(state, prisoner.id) and prisoner.escape_attempt_pending, "Hook vượt ngục không tạo trạng thái quyết định")
	_check(system.request_submission(state, prisoner.id), "Hook yêu cầu quy phục không hoạt động")
	var manager := _manager(state)
	manager.queue_prisoner_action(prisoner.id, GameEnums.PrisonerAction.SUBMIT)
	manager.end_day()
	_check(prisoner.faction == GameEnums.Faction.PLAYER and prisoner.rank == GameEnums.Rank.PAWN, "Quy phục không đổi thành Tốt phe ta")
	_check(prisoner.old_rank_tag == GameEnums.Rank.KNIGHT, "Quy phục không giữ cấp cũ")
	_check(not prisoner.is_prisoner and prisoner.id not in prison.prisoner_unit_ids, "Quy phục không dọn trạng thái tù")
	_check("Từng là Mã của quân địch." in prisoner.backstory, "Quy phục không ghi quá khứ cấp cũ")
	_check(state.player_roster_count() == 1 and prisoner.rank != prisoner.old_rank_tag, "Tốt quy phục không chiếm slot bình thường hoặc tự phục hồi cấp")

	var released := _enemy(state, "released", GameEnums.Rank.ROOK)