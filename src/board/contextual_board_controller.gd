class_name ContextualBoardController
extends Node

const BUILD_ACTIONS := {
	"build_farm": "Farm",
	"build_workshop": "Material Workshop",
	"build_prison": "Prison",
	"build_infirmary": "Infirmary / Y",
	"build_barracks": "Barracks",
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
var current_cell := Vector2i(-1, -1)
var current_building_id := ""
var current_unit_id := ""
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
	board.resolution_animation_finished.connect(_on_resolution_animation_finished)
	refresh()


func open_for_cell(cell: Vector2i) -> void:
	if visual_locked or not turn_manager.can_edit_orders():
		return
	current_cell = cell
	current_building_id = ""
	current_unit_id = ""
	var unit := _unit_at(cell)
	if unit != null:
		current_unit_id = unit.id
		board.present_context_target(unit.id)
		popup.open_at(
			board.cell_screen_position(cell),
			unit.display_name if not unit.display_name.is_empty() else unit.id,
			_unit_detail(unit),
			{"cancel_move": "Hủy nước đi"} if turn_manager.has_pending_move(unit.id) else {}
		)
		return
	var building := _building_at(cell)
	if building == null:
		board.present_context_target("", Vector2i(-1, -1), cell)
		popup.open_at(board.cell_screen_position(cell), _cell_name(cell), "Ô trống: chọn công trình 3×3.", BUILD_ACTIONS)
		return
	current_building_id = building.id
	if cell == building.core_cell:
		board.present_context_target("", building.core_cell)
	else:
		board.present_context_target("", Vector2i(-1, -1), cell)
	var actions := {}
	var detail := "%s · %s · còn %d ngày · %d builder\nManager: %s · Workers: %d%s" % [
		_type_name(building.type),
		_phase_name(building.phase),
		building.days_left,
		building.builder_unit_ids.size(),
		building.manager_unit_id if not building.manager_unit_id.is_empty() else "—",
		building.worker_unit_ids.size(),
		_planned_label(building),
	]
	if building.phase == GameEnums.BuildingPhase.BLUEPRINT:
		detail += "\nRight-click ô operational để đặt Builder slot, rồi kéo quân vào slot."
		detail += "\nPlacement: %s" % ("hợp lệ" if building.placement_valid else building.placement_reason)
	var on_core := current_cell == building.core_cell
	if building.phase == GameEnums.BuildingPhase.BLUEPRINT and on_core:
		actions["cancel_blueprint"] = "Hủy blueprint"
	elif building.phase == GameEnums.BuildingPhase.BLUEPRINT:
		actions["builder_slot"] = "Đặt ô Builder"
		actions["clear_slot"] = "Xóa job slot"
	elif building.phase == GameEnums.BuildingPhase.BUILDING and on_core:
		actions["cancel_construction"] = "Hủy xây"
	elif building.phase == GameEnums.BuildingPhase.BUILDING:
		actions["builder_slot"] = "Đặt ô Builder"
		actions["clear_slot"] = "Xóa job slot"
	elif building.phase == GameEnums.BuildingPhase.ACTIVE and on_core:
		var demolition := turn_manager.get_planned_demolition()
		if demolition != null and demolition.building_id == building.id:
			actions["cancel_demolition"] = "Hủy lệnh phá"
		else:
			actions["demolish"] = "Phá công trình"
	elif building.phase == GameEnums.BuildingPhase.ACTIVE:
		if building.type == GameEnums.BuildingType.FARM:
			actions["manager_slot"] = "Đặt ô Manager"
			actions["farm_worker_slot"] = "Đặt ô Farm worker"
		elif building.type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
			actions["workshop_manager_slot"] = "Đặt ô Workshop manager"
		actions["clear_slot"] = "Xóa job slot"
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
	var status: Array[String] = []
	if unit.away_days_left > 0:
		status.append("away")
	if unit.locked_by_construction:
		status.append("construction locked")
	if unit.locked_by_healing:
		status.append("healing locked")
	if unit.is_manager:
		status.append("manager")
	elif not unit.work_building_id.is_empty():
		status.append("worker")
	elif not unit.assigned_building_id.is_empty():
		status.append("builder")
	if status.is_empty():
		status.append("idle")
	var planned := turn_manager.get_planned_move_target(unit.id)
	if planned != Vector2i(-1, -1):
		status.append("planned move → %s" % _cell_name(planned))
	var backstory := "Chưa có dữ kiện."
	if not unit.backstory.is_empty():
		backstory = "\n".join(unit.backstory)
	elif not unit.memories.is_empty():
		backstory = "\n".join(unit.memories)
	return "Rank: %s · Faction: %s\nVị trí: %s\nTrạng thái: %s\nCông việc: %s\nBuilding: %s\n\nBACKSTORY\n%s" % [
		_rank_name(unit.rank),
		_faction_name(unit.faction),
		_cell_name(unit.board_cell),
		", ".join(status),
		"manager" if unit.is_manager else ("worker" if not unit.work_building_id.is_empty() else ("builder" if not unit.assigned_building_id.is_empty() else "—")),
		unit.work_building_id if not unit.work_building_id.is_empty() else (unit.assigned_building_id if not unit.assigned_building_id.is_empty() else "—"),
		backstory,
	]


func _rank_name(rank: int) -> String:
	return ["Pawn", "Knight", "Rook", "Bishop", "Queen", "King"][rank]


func _faction_name(faction: int) -> String:
	return ["PLAYER", "ENEMY", "OUTSIDER"][faction]


func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]


func _type_name(type: int) -> String:
	return ["Farm", "Material Workshop", "Prison", "Infirmary / Y", "Barracks"][type]


func _phase_name(phase: int) -> String:
	return ["BLUEPRINT", "BUILDING", "ACTIVE", "DEMOLISHING"][phase]


func _on_resolution_started() -> void:
	visual_locked = true
	popup.close()


func _on_resolution_animation_finished() -> void:
	visual_locked = false


func _planned_label(building: BuildingState) -> String:
	if building.phase == GameEnums.BuildingPhase.BLUEPRINT:
		return " · PLANNED"
	var demolition := turn_manager.get_planned_demolition()
	if demolition != null and demolition.building_id == building.id:
		return " · PLANNED DEMOLITION"
	if turn_manager.get_planned_staffing(building.id) != null:
		return " · PLANNED STAFFING"
	return ""


func _on_popup_closed() -> void:
	board.present_context_target()
