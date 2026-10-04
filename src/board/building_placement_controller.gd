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
	palette.set_available_builders(state.units)
	palette.set_builder_status(0)
	turn_manager.resolution_started.connect(_on_resolution_started)
	turn_manager.resolution_finished.connect(_on_resolution_finished)
	_refresh_view()


func select_building(type: GameEnums.BuildingType) -> void:
	if not turn_manager.can_edit_orders():
		return
	turn_manager.cancel_building()
	placement.select(type)
	palette.set_active_type(type)
	palette.set_status("Di chuột lên bàn cờ để xem vùng 3x3")
	placement_mode_changed.emit(true)
	_refresh_view()


func cancel() -> void:
	if not turn_manager.can_edit_orders():
		return
	turn_manager.cancel_building()
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
			palette.set_status("Đã lập lệnh hủy xây — End Day để chốt")
			return
	palette.set_status("Không có building đang xây")

func reassign_selected_builder() -> void:
	if selected_builder_ids.is_empty():
		palette.set_status("Hãy chọn builder trước")
		return
	for candidate in state.buildings.values():
		if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.BUILDING:
			turn_manager.queue_assign_builder(candidate.id, selected_builder_ids[0])
			palette.set_status("Đã lập lệnh gán builder — End Day để chốt")
			return
	palette.set_status("Không có building đang xây")


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
		"Đã đặt ghost tại %s — %d builder — End Day để chốt"
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
	placement_mode_changed.emit(false)
	_refresh_view()


func _on_builder_selection_changed(builder_ids: Array[String]) -> void:
	selected_builder_ids = builder_ids.duplicate()
	palette.set_builder_status(selected_builder_ids.size())
	if placement.is_active():
		palette.set_status("Đã chọn %d builder" % selected_builder_ids.size())


func _building_result_status(result: TurnResolutionResult) -> String:
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
		return "Đã kết thúc ngày; build bị từ chối"
	var phase_name := "ACTIVE" if building.phase == GameEnums.BuildingPhase.ACTIVE else "BUILDING"
	return "%s — %s — còn %d ngày — %d builder" % [
		phase_name,
		_building_name(building.type), building.days_left, building.builder_unit_ids.size()
	]


func _building_name(type: GameEnums.BuildingType) -> String:
	return ["Farm", "Material Workshop", "Prison", "Infirmary / Y", "Barracks"][type]


func _refresh_view() -> void:
	if view != null:
		view.present_buildings(state.buildings, placement, building_system)


func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]


func _validate(cell: Vector2i) -> Dictionary:
	return building_system.validate_placement(
		state, cell, turn_manager.get_planned_move_targets().values()
	)
