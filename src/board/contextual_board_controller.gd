class_name ContextualBoardController
extends Node

const BUILD_ACTIONS := {
	"build_farm": "Nông trại",
	"build_workshop": "Xưởng vật tư",
	"build_prison": "Nhà giam",
	"build_infirmary": "Y xá",
	"build_barracks": "Doanh trại",
}
const BUILD_TYPES := {
	"build_farm": GameEnums.BuildingType.FARM,
	"build_workshop": GameEnums.BuildingType.MATERIAL_WORKSHOP,
	"build_prison": GameEnums.BuildingType.PRISON,
	"build_infirmary": GameEnums.BuildingType.INFIRMARY,
	"build_barracks": GameEnums.BuildingType.BARRACKS,
}

var state: GameState
var turn_manager: TurnManager
var board: BoardView
var popup: ContextPopup
var placement := BuildingPlacementState.new()
var building_system := BuildingSystem.new()
var medical_system := MedicalSystem.new()
var prison_system := PrisonSystem.new()
var current_cell := Vector2i(-1, -1)
var current_building_id := ""
var current_unit_id := ""
var current_prisoner_id := ""
var visual_locked := false


func setup(game_state: GameState, manager: TurnManager, board_view: BoardView, menu: ContextPopup) -> void:
	state = game_state
	turn_manager = manager
	board = board_view
	popup = menu
	popup.action_selected.connect(_on_action_selected)
	popup.action_confirmed.connect(_on_action_confirmed)
	popup.closed.connect(_on_popup_closed)
	board.cell_hovered.connect(_on_cell_hovered)
	turn_manager.order_queue.changed.connect(refresh)
	turn_manager.resolution_finished.connect(func(_result): refresh())
	turn_manager.resolution_started.connect(_on_resolution_started)
	turn_manager.prisoner_decision_requested.connect(_on_prisoner_decision_requested)
	board.resolution_animation_finished.connect(_on_resolution_animation_finished)
	refresh()


func open_for_cell(cell: Vector2i) -> void:
	if visual_locked or not turn_manager.can_edit_orders():
		return
	current_cell = cell
	current_building_id = ""
	current_unit_id = ""
	current_prisoner_id = ""
	var unit := _unit_at(cell)
	if unit != null:
		current_unit_id = unit.id
		board.present_context_target(unit.id)
		var unit_actions := {}
		if turn_manager.has_pending_move(unit.id):
			unit_actions["cancel_move"] = "Hủy nước đi"
		if turn_manager.has_planned_inspection_for_unit(unit.id):
			unit_actions["cancel_inspection"] = "Hủy kiểm tra trực tiếp"
		popup.open_at(
			board.cell_screen_position(cell),
			unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank),
			_unit_detail(unit),
			unit_actions
		)
		return
	var building := _building_at(cell)
	if building == null:
		board.present_context_target("", Vector2i(-1, -1), cell)
		popup.open_at(
			board.cell_screen_position(cell),
			_cell_name(cell),
			"",
			{"open_build_menu": "Xây dựng"},
			false
		)
		return
	current_building_id = building.id
	if cell == building.core_cell:
		board.present_context_target("", building.core_cell)
	else:
		board.present_context_target("", Vector2i(-1, -1), cell)
	var actions := {}
	var on_core := current_cell == building.core_cell
	var detail := turn_manager.information_system.building_detail(state, building)
	detail += _planned_label(building)
	if building.type == GameEnums.BuildingType.BARRACKS:
		detail += "\n\n" + _barracks_progression_detail(building, actions, on_core)
	if cell != building.core_cell:
		var role := int(building.job_slots.get(cell, GameEnums.JobRole.NONE))
		if role == GameEnums.JobRole.TREATMENT:
			detail += "\nVị trí điều trị"
		elif role == GameEnums.JobRole.PRISON_MANAGER:
			detail += "\nVị trí Chủ quản"
		elif role == GameEnums.JobRole.PRISON_GUARD:
			detail += "\nVị trí Canh giữ"
	if building.phase == GameEnums.BuildingPhase.BLUEPRINT:
		detail += "\nKéo trực tiếp quân vào một trong 8 ô vận hành để bắt đầu xây."
		detail += "\nVị trí: %s" % ("hợp lệ" if building.placement_valid else building.placement_reason)
	if building.phase == GameEnums.BuildingPhase.BLUEPRINT and on_core:
		actions["cancel_blueprint"] = "Hủy bản vẽ"
	elif building.phase == GameEnums.BuildingPhase.BLUEPRINT:
		pass
	elif building.phase == GameEnums.BuildingPhase.BUILDING and on_core:
		actions["cancel_construction"] = "Hủy xây"
	elif building.phase == GameEnums.BuildingPhase.BUILDING:
		pass
	elif building.phase == GameEnums.BuildingPhase.ACTIVE and on_core:
		var demolition := turn_manager.get_planned_demolition()
		if demolition != null and demolition.building_id == building.id:
			actions["cancel_demolition"] = "Hủy lệnh phá"
		else:
			actions["demolish"] = "Phá công trình"
		if building.type == GameEnums.BuildingType.PRISON:
			_add_prison_actions(building, actions)
	elif building.phase == GameEnums.BuildingPhase.ACTIVE:
		if building.type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
			actions["workshop_manager_slot"] = "Đặt ô quản lý xưởng"
			actions["clear_slot"] = "Xóa vị trí công việc"
	var inspection := turn_manager.get_planned_inspection()
	if inspection != null and inspection.building_id == building.id:
		actions["cancel_inspection"] = "Hủy kiểm tra trực tiếp"
	elif building.phase != GameEnums.BuildingPhase.BLUEPRINT and turn_manager.can_plan_inspection(building.id):
		actions["inspect_building"] = "Kiểm tra trực tiếp"
	popup.open_at(board.cell_screen_position(cell), _type_name(building.type), detail, actions)


func undo_current() -> bool:
	if popup.visible:
		popup.close()
		return true
	if placement.is_active():
		placement.cancel()
		refresh()
		return true
	return false


func refresh() -> void:
	medical_system.prepare_slots(state)
	prison_system.prepare_staff_positions(state)
	var planned_buildings := turn_manager.get_planned_buildings()
	board.present_buildings(state.buildings, planned_buildings, placement, building_system)
	var slots := {}
	for candidate in state.buildings.values():
		if candidate is BuildingState:
			for cell in candidate.job_slots:
				slots[cell] = candidate.job_slots[cell]
			for cell in turn_manager.get_planned_job_slots(candidate.id):
				var role: int = turn_manager.get_planned_job_slots(candidate.id)[cell]
				if role == GameEnums.JobRole.NONE:
					slots.erase(cell)
				else:
					slots[cell] = role
	for planned in planned_buildings:
		for cell in turn_manager.get_planned_job_slots(planned.id):
			var role: int = turn_manager.get_planned_job_slots(planned.id)[cell]
			if role != GameEnums.JobRole.NONE:
				slots[cell] = role
	board.present_job_slots(slots)


func _on_action_selected(action: String) -> void:
	if action == "open_build_menu":
		popup.open_at(
			board.cell_screen_position(current_cell),
			"Xây dựng tại %s" % _cell_name(current_cell),
			"Chọn công trình",
			BUILD_ACTIONS
		)
		return
	if BUILD_TYPES.has(action):
		placement.select(BUILD_TYPES[action])
		_update_build_preview(current_cell)


func _on_action_confirmed(action: String) -> void:
	if BUILD_TYPES.has(action):
		_update_build_preview(current_cell)
		if placement.hover_valid:
			turn_manager.queue_building_plan(BUILD_TYPES[action], current_cell)
		placement.cancel()
	elif action == "cancel_blueprint":
		if state.buildings.has(current_building_id):
			turn_manager.queue_cancel_construction(current_building_id)
		else:
			turn_manager.cancel_building(current_building_id)
	elif action == "cancel_move":
		turn_manager.cancel_unit_plan(current_unit_id)
	elif action == "cancel_construction":
		var building := state.buildings.get(current_building_id) as BuildingState
		if building != null:
			turn_manager.queue_cancel_construction(building.id)
	elif action == "demolish":
		var building := state.buildings.get(current_building_id) as BuildingState
		if building != null:
			turn_manager.queue_demolition(building.id)
	elif action == "cancel_demolition":
		turn_manager.cancel_demolition()
	elif action == "inspect_building":
		turn_manager.queue_building_inspection(current_building_id)
	elif action == "cancel_inspection":
		turn_manager.cancel_building_inspection()
	elif action.begins_with("prison_release:"):
		turn_manager.queue_prisoner_action(action.get_slice(":", 1), GameEnums.PrisonerAction.RELEASE)
	elif action.begins_with("prison_kill:"):
		turn_manager.queue_prisoner_action(action.get_slice(":", 1), GameEnums.PrisonerAction.KILL)
	elif action.begins_with("prison_continue:"):
		turn_manager.queue_prisoner_action(action.get_slice(":", 1), GameEnums.PrisonerAction.CONTINUE)
	elif action.begins_with("prison_submit:"):
		turn_manager.queue_prisoner_action(action.get_slice(":", 1), GameEnums.PrisonerAction.SUBMIT)
	elif action.begins_with("prison_labor:"):
		turn_manager.queue_prisoner_labor(action.get_slice(":", 1), action.get_slice(":", 2))
	elif action.begins_with("promotion:"):
		var unit_id := action.get_slice(":", 1)
		var target_rank: GameEnums.Rank = int(action.get_slice(":", 2))
		if turn_manager.queue_promotion(unit_id, current_building_id, target_rank) != null:
			call_deferred("_reopen_current")
	elif action.begins_with("cancel_promotion:"):
		turn_manager.cancel_promotion(action.get_slice(":", 1))
		call_deferred("_reopen_current")
	elif action == "clear_slot":
		var building := _building_at(current_cell)
		if building != null:
			turn_manager.plan_clear_job_slot(building.id, current_cell)
	else:
		_plan_slot(action)
	refresh()


func _plan_slot(action: String) -> void:
	var building := _building_at(current_cell)
	if building == null or current_cell == building.core_cell:
		return
	if current_cell not in building_system.footprint(building.core_cell):
		return
	var role := GameEnums.JobRole.NONE
	if action == "builder_slot":
		role = GameEnums.JobRole.BUILDER
	elif action == "manager_slot":
		role = GameEnums.JobRole.MANAGER
	elif action == "farm_worker_slot":
		role = GameEnums.JobRole.FARM_WORKER
	elif action == "workshop_manager_slot":
		role = GameEnums.JobRole.WORKSHOP_MANAGER
	turn_manager.plan_job_slot(building.id, current_cell, role)


func _on_cell_hovered(_cell: Vector2i) -> void:
	pass


func _update_build_preview(cell: Vector2i) -> void:
	var planned_cores: Array[Vector2i] = []
	for building in turn_manager.get_planned_buildings():
		if building.placement_valid:
			planned_cores.append(building.core_cell)
	var validation := building_system.validate_placement(
		state, cell, turn_manager.get_planned_move_targets().values(), planned_cores
	)
	placement.update_hover(cell, validation.valid, validation.reason)
	board.present_buildings(state.buildings, turn_manager.get_planned_buildings(), placement, building_system)


func _building_at(cell: Vector2i) -> BuildingState:
	var planned := turn_manager.get_planned_building_at_cell(cell)
	if planned != null:
		return planned
	return building_system.building_at_cell(state, cell)


func _unit_at(cell: Vector2i) -> UnitState:
	for candidate in state.units.values():
		if candidate is UnitState and candidate.board_cell == cell:
			return candidate
	return null


func _unit_detail(unit: UnitState) -> String:
	var planned := turn_manager.get_planned_move_target(unit.id)
	var planned_text := ""
	if planned != Vector2i(-1, -1):
		planned_text = "\nĐã định nước đi → %s" % _cell_name(planned)
	var inspection := turn_manager.get_planned_inspection()
	if inspection != null and inspection.king_unit_id == unit.id:
		planned_text += "\nDự kiến: kiểm tra trực tiếp công trình vào cuối ngày"
	var progression := _unit_progression_detail(unit)
	var story_lines: Array[String] = unit.backstory.duplicate()
	var first_memory := maxi(0, unit.memories.size() - 4)
	for index in range(first_memory, unit.memories.size()):
		story_lines.append(unit.memories[index])
	var story := "Chưa có dữ kiện." if story_lines.is_empty() else "\n".join(story_lines)
	var template := (
		"Loại quân: %s · Phe: %s\nVị trí nhìn thấy: %s%s\n%s\n%s"
		+ "\n\nQUÁ KHỨ & KÝ ỨC\n%s"
	)
	return template % [
		_rank_name(unit.rank),
		_faction_name(unit.faction),
		_cell_name(unit.board_cell),
		planned_text,
		progression,
		turn_manager.information_system.unit_condition_detail(state, unit),
		story,
	]


func _unit_progression_detail(unit: UnitState) -> String:
	var lines: Array[String] = [
		"TIẾN TRIỂN · %s · %d Chiến công" % [_rank_name(unit.rank), unit.merit]
	]
	if unit.rank == GameEnums.Rank.KING:
		lines.append("Vua không tham gia thăng cấp.")
		return "\n".join(lines)
	if unit.is_in_promotion_training():
		lines.append("ĐANG HUẤN LUYỆN → %s · còn %d ngày" % [
			_rank_name(unit.promotion_target_rank),
			maxi(0, unit.promotion_complete_day - state.day),
		])
		return "\n".join(lines)
	var planned := turn_manager.get_planned_promotion(unit.id)
	if planned != null:
		lines.append(
			"DỰ KIẾN HUẤN LUYỆN → %s vào cuối ngày" % _rank_name(planned.target_rank)
		)
		return "\n".join(lines)
	var ready := turn_manager.available_promotions(unit.id)
	if ready.is_empty():
		lines.append("Chưa có hướng thăng cấp sẵn sàng.")
	else:
		var targets: Array[String] = []
		for definition in ready:
			targets.append(_rank_name(int(definition.to_rank)))
		lines.append("SẴN SÀNG: %s" % ", ".join(targets))
	return "\n".join(lines)


func _barracks_progression_detail(
	barracks: BuildingState, actions: Dictionary, allow_actions: bool
) -> String:
	var lines: Array[String] = ["HUẤN LUYỆN & THĂNG CẤP"]
	if barracks.phase != GameEnums.BuildingPhase.ACTIVE:
		lines.append("Doanh trại phải ACTIVE trước khi huấn luyện.")
		return "\n".join(lines)
	var unit_ids := state.units.keys()
	unit_ids.sort()
	var shown := 0
	for unit_id in unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if (
			unit == null
			or unit.faction != GameEnums.Faction.PLAYER
			or unit.rank == GameEnums.Rank.KING
			or unit.is_prisoner
		):
			continue
		var paths := _promotion_paths_for(unit.rank)
		var planned := turn_manager.get_planned_promotion(unit.id)
		if paths.is_empty() and planned == null and not unit.is_in_promotion_training():
			continue
		shown += 1
		var name := unit.display_name if not unit.display_name.is_empty() else unit.id
		lines.append(
			"%s · %s · %d Chiến công" % [name, _rank_name(unit.rank), unit.merit]
		)
		if unit.is_in_promotion_training():
			lines.append("  ĐANG HUẤN LUYỆN → %s · còn %d ngày" % [
				_rank_name(unit.promotion_target_rank),
				maxi(0, unit.promotion_complete_day - state.day),
			])
			continue
		if planned != null:
			var requirement := turn_manager.promotion_system.promotion_requirement(
				unit.rank, planned.target_rank
			)
			lines.append("  DỰ KIẾN → %s · %d ngày" % [
				_rank_name(planned.target_rank),
				int(requirement.get("training_days", 1)),
			])
			if allow_actions and planned.barracks_id == barracks.id:
				actions["cancel_promotion:%s" % unit.id] = "Hủy huấn luyện %s" % name
			continue
		for definition in paths:
			var target_rank := int(definition.to_rank)
			var merit_required := int(definition.merit_required)
			var training_days := int(definition.training_days)
			var validation := turn_manager.promotion_system.validate_promotion(
				state, unit, target_rank, barracks.id
			)
			lines.append("  → %s · cần %d · %d ngày · %s" % [
				_rank_name(target_rank), merit_required, training_days,
				"SẴN SÀNG" if validation.valid else validation.reason,
			])
			if allow_actions and validation.valid:
				actions["promotion:%s:%d" % [unit.id, target_rank]] = (
					"HUẤN LUYỆN %s → %s" % [name, _rank_name(target_rank)]
				)
	if shown == 0:
		lines.append("Chưa có quân phù hợp để thăng cấp.")
	return "\n".join(lines)


func _promotion_paths_for(rank: int) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	for definition in turn_manager.promotion_system.definitions:
		if int(definition.from_rank) == rank:
			paths.append(definition)
	paths.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.to_rank) < int(b.to_rank)
	)
	return paths


func _reopen_current() -> void:
	if current_cell != Vector2i(-1, -1) and turn_manager.can_edit_orders():
		open_for_cell(current_cell)


func _rank_name(rank: int) -> String:
	return ["Tốt", "Mã", "Xe", "Tịnh", "Hậu", "Vua"][rank]


func _faction_name(faction: int) -> String:
	return ["Phe ta", "Địch", "Bên ngoài"][faction]


func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]


func _type_name(type: int) -> String:
	return ["Nông trại", "Xưởng vật tư", "Nhà giam", "Y xá", "Doanh trại"][type]


func _phase_name(phase: int) -> String:
	return ["Dự kiến", "Đang xây", "Hoạt động", "Đang phá"][phase]


func _on_resolution_started() -> void:
	visual_locked = true
	popup.close()


func _on_resolution_animation_finished() -> void:
	visual_locked = false


func _planned_label(building: BuildingState) -> String:
	var plans: Array[String] = []
	if building.phase == GameEnums.BuildingPhase.BLUEPRINT:
		plans.append("đặt bản thiết kế")
	var demolition := turn_manager.get_planned_demolition()
	if demolition != null and demolition.building_id == building.id:
		plans.append("phá công trình")
	if turn_manager.get_planned_staffing(building.id) != null:
		plans.append("đổi phân công")
	var inspection := turn_manager.get_planned_inspection()
	if inspection != null and inspection.building_id == building.id:
		plans.append("Vua kiểm tra trực tiếp vào cuối ngày")
	return "\nDỰ KIẾN: %s" % ", ".join(plans) if not plans.is_empty() else ""


func _on_popup_closed() -> void:
	board.present_context_target()



func _add_prison_actions(prison: BuildingState, actions: Dictionary) -> void:
	var fact := turn_manager.information_system.get_building_fact(prison.id)
	var prisoner_ids: Array = []
	if state.day_one_full_knowledge:
		prisoner_ids = prison.prisoner_unit_ids.duplicate()
	elif fact != null:
		prisoner_ids = fact.values.get("prisoner_ids", [])
	if prisoner_ids.is_empty():
		return
	prisoner_ids.sort()
	current_prisoner_id = str(prisoner_ids[0])
	var prisoner := state.units.get(current_prisoner_id) as UnitState
	if prisoner == null or not prisoner.is_prisoner:
		return
	if prisoner.escape_attempt_pending:
		actions["prison_continue:%s" % prisoner.id] = "Giam tiếp"
	else:
		actions["prison_release:%s" % prisoner.id] = "Thả tù binh"
		actions["prison_kill:%s" % prisoner.id] = "Xử lý tù binh"
	if prisoner.submission_requested:
		actions["prison_submit:%s" % prisoner.id] = "Chấp nhận quy phục"
	var target := _first_construction()
	if target != null:
		actions["prison_labor:%s:%s" % [prisoner.id, target.id]] = (
			"Lao động xây dựng tại %s" % _cell_name(target.core_cell)
		)


func _first_construction() -> BuildingState:
	var ids := state.buildings.keys()
	ids.sort()
	for building_id in ids:
		var building := state.buildings.get(building_id) as BuildingState
		if building != null and building.phase == GameEnums.BuildingPhase.BUILDING:
			return building
	return null


func _on_prisoner_decision_requested(unit_id: String) -> void:
	var unit := state.units.get(unit_id) as UnitState
	if unit == null:
		return
	var prison := state.buildings.get(unit.prison_building_id) as BuildingState
	if prison != null:
		open_for_cell(prison.core_cell)
