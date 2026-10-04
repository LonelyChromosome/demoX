class_name BuildingPlacementController
extends Node

signal placement_mode_changed(active: bool)

var state: GameState
var turn_manager: TurnManager
var view: BoardView
var palette: BuildingPalette
var placement := BuildingPlacementState.new()
var building_system := BuildingSystem.new()


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
	palette.cancel_requested.connect(cancel)
	turn_manager.day_resolved.connect(_on_day_resolved)
	_refresh_view()


func select_building(type: GameEnums.BuildingType) -> void:
	turn_manager.cancel_building()
	placement.select(type)
	palette.set_active_type(type)
	palette.set_status("Di chuột lên bàn cờ để xem vùng 3x3")
	placement_mode_changed.emit(true)
	_refresh_view()


func cancel() -> void:
	turn_manager.cancel_building()
	placement.cancel()
	palette.clear_active_type()
	palette.set_status("Đã hủy bản thiết kế")
	placement_mode_changed.emit(false)
	_refresh_view()


func undo_current() -> bool:
	if not placement.is_active() and placement.planned_building == null:
		return false
	cancel()
	return true


func _on_cell_hovered(cell: Vector2i) -> void:
	if not placement.is_active():
		return
	var result := building_system.validate_placement(state, cell)
	placement.update_hover(cell, result.valid, result.reason)
	palette.set_status(result.reason)
	_refresh_view()


func _on_cell_pressed(cell: Vector2i) -> void:
	if not placement.is_active():
		return
	var result := building_system.validate_placement(state, cell)
	placement.update_hover(cell, result.valid, result.reason)
	if not result.valid:
		palette.set_status(result.reason)
		_refresh_view()
		return

	var blueprint := turn_manager.queue_building(placement.selected_type, cell)
	placement.plan(blueprint)
	palette.set_status("Đã đặt ghost tại %s — End Day để chốt" % _cell_name(cell))
	_refresh_view()


func _on_day_resolved(_day: int) -> void:
	placement.cancel()
	palette.clear_active_type()
	palette.set_status("Blueprint đã được chốt vào bàn cờ")
	placement_mode_changed.emit(false)
	_refresh_view()


func _refresh_view() -> void:
	if view != null:
		view.present_buildings(state.buildings, placement, building_system)


func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]
