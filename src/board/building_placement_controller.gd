class_name BuildingPlacementController
extends Node

signal placement_mode_changed(active: bool)

var state: GameState
var turn_manager: TurnManager
var view: BoardView
var palette: BuildingPalette
var placement := BuildingPlacementState.new()
var building_system := BuildingSystem.new()
var resolving := false
var selected_builder_ids: Array[String] = []


func setup(
	game_state: GameState,
	manager: TurnManager,
	board_view: BoardView,
	building_palette: BuildingPalette
) -> void:
	state = game_state
	turn_manager = manager
	view = board_view
	palette = building_palette

	view.cell_hovered.connect(_on_cell_hovered)
	view.cell_pressed.connect(_on_cell_pressed)
	palette.building_selected.connect(select_building)
	palette.builder_selection_changed.connect(_on_builder_selection_changed)
	palette.cancel_requested.connect(cancel)
	palette.cancel_construction_requested.connect(cancel_current_construction)
	palette.reassign_builder_requested.connect(reassign_selected_builder)
	palette.demolition_requested.connect(plan_demolition_current)
	palette.demolition_cancel_requested.connect(cancel_planned_demolition)
	palette.staffing_manager_requested.connect(plan_staffing_manager)
	palette.staffing_workers_requested.connect(plan_staffing_workers)
	palette.staffing_cancel_requested.connect(cancel_planned_staffing)
	palette.set_available_builders(state.units)
	palette.set_builder_status(0)
	turn_manager.resolution_started.connect(_on_resolution_started)
	turn_manager.resolution_finished.connect(_on_resolution_finished)
	_refresh_view()


func select_building(type: GameEnums.BuildingType) -> void:
	if not turn_manager.can_edit_orders():
		return
	placement.select(type)
	palette.set_active_type(type)
	palette.set_status("Di chuột lên bàn cờ để xem vùng 3×3")
	placement_mode_changed.emit(true)
	_refresh_view()


func cancel() -> void:
	if not turn_manager.can_edit_orders():
		return
	if placement.planned_building != null:
		turn_manager.cancel_building(placement.planned_building.id)
	placement.cancel()
	palette.clear_active_type()
	palette.set_status("Đã hủy bản thiết kế")
	placement_mode_changed.emit(false)
	_refresh_view()

func cancel_current_construction() -> void:
	if not turn_manager.can_edit_orders():
		return
	for candidate in state.buildings.values():
		if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.BUILDING:
			turn_manager.queue_cancel_construction(candidate.id)
			palette.set_status("Đã lập lệnh hủy xây — Kết thúc ngày để chốt")
			return
	palette.set_status("Không có công trình đang xây")

func reassign_selected_builder() -> void:
	if selected_builder_ids.is_empty():
		palette.set_status("Hãy chọn thợ xây trước")
		return
	for candidate in state.buildings.values():
		if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.BUILDING:
			turn_manager.queue_assign_builder(candidate.id, selected_builder_ids[0])
			palette.set_status("Đã lập lệnh gán thợ xây — Kết thúc ngày để chốt")
			return
	palette.set_status("Không có công trình đang xây")

func plan_demolition_current() -> void:
	if not turn_manager.can_edit_orders():
		return
	for candidate in state.buildings.values():
		if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.ACTIVE:
			turn_manager.queue_demolition(candidate.id)
			palette.set_status("Đã lập lệnh phá %s — Kết thúc ngày để chốt" % _building_name(candidate.type))
			return
	palette.set_status("Không có công trình đang hoạt động")

func cancel_planned_demolition() -> void:
	turn_manager.cancel_demolition()
	palette.set_status("Đã hủy lệnh phá; công trình vẫn hoạt động")

func plan_staffing_manager() -> void:
	var building := _first_active_staffing_building()
	if building == null:
		palette.set_status("Không có Nông trại/Xưởng vật tư đang hoạt động")
		return
	if selected_builder_ids.is_empty():
		palette.set_status("Hãy chọn quân trước")
		return
	var workers := building.worker_unit_ids.duplicate()
	turn_manager.queue_staffing(building.id, selected_builder_ids[0], workers)
	palette.set_status("Đã lập phân công quản lý — Kết thúc ngày để chốt")
	_refresh_staffing_status()

func plan_staffing_workers() -> void:
	var building := _first_active_staffing_building()
	if building == null:
		palette.set_status("Không có Nông trại/Xưởng vật tư đang hoạt động")
		return
	if building.type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
		palette.set_status("Xưởng vật tư chỉ cần quản lý")
		return
	turn_manager.queue_staffing(building.id, building.manager_unit_id, selected_builder_ids)
	palette.set_status("Đã lập phân công lao động — Kết thúc ngày để chốt")
	_refresh_staffing_status()

func cancel_planned_staffing() -> void:
	var building := _first_active_staffing_building()
	if building == null:
		return
	turn_manager.cancel_staffing(building.id)
	palette.set_status("Đã hủy phân công dự kiến")
	_refresh_staffing_status()


func undo_current() -> bool:
	if not placement.is_active() and placement.planned_building == null:
		return false
	cancel()
	return true


func _on_cell_hovered(cell: Vector2i) -> void:
	if resolving or not placement.is_active():
		return
	var result := _validate(cell)
	placement.update_hover(cell, result.valid, result.reason)
	palette.set_status(result.reason)
	_refresh_view()


func _on_cell_pressed(cell: Vector2i) -> void:
	if resolving or not placement.is_active():
		return
	var result := _validate(cell)
	placement.update_hover(cell, result.valid, result.reason)
	if not result.valid:
		palette.set_status(result.reason)
		_refresh_view()
		return

	var builders := selected_builder_ids
	if builders.is_empty():
		builders = turn_manager.get_default_builder_ids()
	var blueprint := turn_manager.queue_building(placement.selected_type, cell, builders)
	if blueprint == null:
		palette.set_status("Không thể lập kế hoạch xây")
		_refresh_view()
		return
	placement.plan(blueprint)
	palette.set_status(
		"Đã đặt bản vẽ tại %s — %d thợ xây — Kết thúc ngày để chốt"
		% [_cell_name(cell), builders.size()]
	)
	_refresh_view()


func _on_resolution_started() -> void:
	resolving = true


func _on_resolution_finished(result: TurnResolutionResult) -> void:
	resolving = false
	placement.cancel()
	palette.clear_active_type()
	palette.set_status(
		_building_result_status(result)
	)
	_refresh_staffing_status()
	placement_mode_changed.emit(false)
	_refresh_view()


func _on_builder_selection_changed(builder_ids: Array[String]) -> void:
	selected_builder_ids = builder_ids.duplicate()
	palette.set_builder_status(selected_builder_ids.size())
	if placement.is_active():
		palette.set_status("Đã chọn %d thợ xây" % selected_builder_ids.size())


func _building_result_status(result: TurnResolutionResult) -> String:
	if not result.demolished_building_ids.is_empty():
		return "Đã phá công trình — vùng chiếm chỗ đã được giải phóng"
	if not result.cancelled_building_ids.is_empty():
		return "Đã hủy xây — hoàn %d vật tư" % result.refunded_materials
	var building: BuildingState
	if not result.new_building_ids.is_empty():
		building = state.buildings.get(result.new_building_ids[0]) as BuildingState
	else:
		for candidate in state.buildings.values():
			if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.BUILDING:
				building = candidate
				break
		if building == null and not result.completed_building_ids.is_empty():
			building = state.buildings.get(result.completed_building_ids[0]) as BuildingState
	if building == null:
		return "Đã kết thúc ngày; lệnh xây bị từ chối"
	var phase_name := "HOẠT ĐỘNG" if building.phase == GameEnums.BuildingPhase.ACTIVE else "ĐANG XÂY"
	return "%s — %s — còn %d ngày — %d builder" % [
		phase_name,
		_building_name(building.type), building.days_left, building.builder_unit_ids.size()
	]


func _building_name(type: GameEnums.BuildingType) -> String:
	return ["Nông trại", "Xưởng vật tư", "Nhà giam", "Y xá", "Doanh trại"][type]


func _refresh_view() -> void:
	if view != null:
		view.present_buildings(
			state.buildings, turn_manager.get_planned_buildings(), placement, building_system
		)
	_refresh_staffing_status()

func _first_active_staffing_building() -> BuildingState:
	var ids := state.buildings.keys()
	ids.sort()
	for building_id in ids:
		var candidate := state.buildings[building_id] as BuildingState
		if (
			candidate != null
			and candidate.phase == GameEnums.BuildingPhase.ACTIVE
			and candidate.type in [GameEnums.BuildingType.FARM, GameEnums.BuildingType.MATERIAL_WORKSHOP]
		):
			return candidate
	return null

func _refresh_staffing_status() -> void:
	if palette == null or state == null:
		return
	var building := _first_active_staffing_building()
	if building == null:
		palette.set_staffing_status("Phân công: chưa có Nông trại/Xưởng vật tư đang hoạt động")
		return
	var manager_id := building.manager_unit_id
	var worker_count := building.worker_unit_ids.size()
	var planned := turn_manager.get_planned_staffing(building.id)
	if planned != null:
		manager_id = planned.manager_unit_id
		worker_count = planned.worker_unit_ids.size()
		palette.set_staffing_status(
			"%s dự kiến — Quản lý: %s — Lao động: %d/6"
			% [_building_name(building.type), manager_id if not manager_id.is_empty() else "không có", worker_count]
		)
		return
	palette.set_staffing_status(
		"%s — Quản lý: %s — Lao động: %d/6"
		% [_building_name(building.type), manager_id if not manager_id.is_empty() else "không có", worker_count]
	)


func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]


func _validate(cell: Vector2i) -> Dictionary:
	var planned_cores: Array[Vector2i] = []
	for building in turn_manager.get_planned_buildings():
		if building.placement_valid:
			planned_cores.append(building.core_cell)
	return building_system.validate_placement(
		state, cell, turn_manager.get_planned_move_targets().values(), planned_cores
	)
