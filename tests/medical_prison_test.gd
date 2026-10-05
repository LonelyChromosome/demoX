extends SceneTree


func _init() -> void:
	_test_infirmary_slots_and_healing()
	_test_capacity_and_healing_lock()
	_test_prison_staffing()
	print("MEDICAL_PRISON_TEST_OK")
	quit(0)


func _test_infirmary_slots_and_healing() -> void:
	var state := GameState.new()
	state.food = 20
	var infirmary := _active_building(
		state, "infirmary", GameEnums.BuildingType.INFIRMARY, Vector2i(3, 3)
	)
	var medical := MedicalSystem.new()
	var slots := medical.treatment_slots(infirmary)
	_check(slots == [Vector2i(3, 2), Vector2i(2, 3), Vector2i(4, 3)], "Y xá không có đúng 3 vị trí điều trị cố định")
	var patient := _unit(state, "patient", GameEnums.Rank.KNIGHT, slots[0])
	patient.injured = true
	patient.healing_days_left = 2
	var manager := _manager(state)
	var first := manager.end_day()
	_check(patient.locked_by_healing, "Bệnh nhân không bị khóa sau End Day")
	_check(patient.healing_days_left == 1, "Điều trị không giảm đúng một ngày")
	_check(patient.id in infirmary.patient_unit_ids, "Y xá không giữ phân công bệnh nhân")
	_check(first.food_consumed == 1, "Bệnh nhân phe ta không dùng khẩu phần bình thường")
	manager.end_day()
	_check(not patient.injured and not patient.locked_by_healing, "Hoàn thành điều trị không mở khóa bệnh nhân")
	_check(patient.healing_days_left == 0, "Số ngày điều trị không được chặn ở 0")
	_check(patient.id not in infirmary.patient_unit_ids, "Phân công điều trị không được dọn")
	_check(patient.board_cell == slots[0], "Điều trị đã dịch chuyển quân")


func _test_capacity_and_healing_lock() -> void:
	var state := GameState.new()
	state.food = 30
	var infirmary := _active_building(
		state, "infirmary_capacity", GameEnums.BuildingType.INFIRMARY, Vector2i(3, 3)
	)
	var slots := MedicalSystem.new().treatment_slots(infirmary)
	for index in range(3):
		var patient := _unit(state, "patient_%d" % index, GameEnums.Rank.PAWN, slots[index])
		patient.injured = true
		patient.healing_days_left = 3
	var fourth := _unit(state, "patient_4", GameEnums.Rank.ROOK, Vector2i(0, 0))
	fourth.injured = true
	fourth.healing_days_left = 3
	var manager := _manager(state)
	manager.queue_move(fourth.id, slots[0])
	var result := manager.end_day()
	_check(result.was_rejected("move", fourth.id), "Bệnh nhân thứ tư không bị từ chối khi đủ 3 chỗ")
	_check(fourth.board_cell == Vector2i(0, 0), "Bệnh nhân thứ tư chiếm vị trí đã đầy")
	var first := state.units["patient_0"] as UnitState
	_check(first.locked_by_healing, "Bệnh nhân ở vị trí điều trị không bị khóa")
	_check(not first.can_be_moved() and not first.can_be_builder(), "Khóa điều trị không chặn di chuyển/xây dựng")


func _test_prison_staffing() -> void:
	var state := GameState.new()
	state.food = 30
	var prison := _active_building(
		state, "prison", GameEnums.BuildingType.PRISON, Vector2i(3, 3)
	)
	var system := PrisonSystem.new()
	var enemy := _unit(state, "enemy", GameEnums.Rank.KNIGHT, Vector2i(7, 7), GameEnums.Faction.ENEMY)
	_check(system.admit_prisoner(state, enemy.id, prison.id), "Không thể đưa quân địch vào Nhà giam")
	var manager := _manager(state)
	manager.end_day()
	_check(prison.under_guarded, "Nhà giam có tù và 0 người canh không báo thiếu")
	var chief := _unit(state, "chief", GameEnums.Rank.ROOK, system.manager_cell(prison))
	manager.end_day()
	_check(prison.manager_unit_id == chief.id and prison.under_guarded, "Một Chủ quản phải vẫn là canh giữ thiếu")
	var guard := _unit(state, "guard", GameEnums.Rank.PAWN, system.guard_cells(prison)[0])
	manager.end_day()
	_check(system.guard_count(prison) == 2 and not prison.under_guarded, "Chủ quản + 1 Canh giữ không đủ hai người")
	manager.queue_move(guard.id, Vector2i(0, 1))
	manager.end_day()
	_check(prison.under_guarded and system.guard_count(prison) == 1, "Rời vị trí canh không cập nhật ở End Day")
	_check(prison.job_slots.size() == 3, "Nhà giam không tự duy trì vị trí Chủ quản/Canh giữ")


func _manager(state: GameState) -> TurnManager:
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	return manager


func _active_building(
	state: GameState, id: String, type: GameEnums.BuildingType, cell: Vector2i
) -> BuildingState:
	var building := BuildingState.new(id, type, cell)
	building.phase = GameEnums.BuildingPhase.ACTIVE
	state.buildings[id] = building
	return building


func _unit(
	state: GameState,
	id: String,
	rank: GameEnums.Rank,
	cell: Vector2i,
	faction: GameEnums.Faction = GameEnums.Faction.PLAYER
) -> UnitState:
	var unit := UnitState.new(id)
	unit.display_name = id
	unit.rank = rank
	unit.faction = faction
	unit.board_cell = cell
	state.units[id] = unit
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)