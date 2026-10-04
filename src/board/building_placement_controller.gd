class_name BuildingPlacementController
extends Node

signal placement_mode_changed(active: bool)

var state: GameState
var turn_quản lý: TurnManager
var view: BoardView
var palette: BuildingPalette
var placement := BuildingPlacementState.new()
var công trình_system := BuildingSystem.new()
var resolving := false
var selected_thợ xây_ids: Array[String] = []


func setup(
	game_state: GameState,
	quản lý: TurnManager,
	board_view: BoardView,
	công trình_palette: BuildingPalette
) -> void:
	state = game_state
	turn_quản lý = quản lý
	view = board_view
	palette = công trình_palette

	view.cell_hovered.connect(_on_cell_hovered)
	view.cell_pressed.connect(_on_cell_pressed)
	palette.công trình_selected.connect(select_công trình)
	palette.thợ xây_selection_changed.connect(_on_thợ xây_selection_changed)
	palette.cancel_requested.connect(cancel)
	palette.cancel_construction_requested.connect(cancel_current_construction)
	palette.reassign_thợ xây_requested.connect(reassign_selected_thợ xây)
	palette.demolition_requested.connect(plan_demolition_current)
	palette.demolition_cancel_requested.connect(cancel_dự kiến_demolition)
	palette.staffing_quản lý_requested.connect(plan_staffing_quản lý)
	palette.staffing_lao động_requested.connect(plan_staffing_lao động)
	palette.staffing_cancel_requested.connect(cancel_dự kiến_staffing)
	palette.set_available_thợ xâys(state.units)
	palette.set_thợ xây_status(0)
	turn_quản lý.resolution_started.connect(_on_resolution_started)
	turn_quản lý.resolution_finished.connect(_on_resolution_finished)
	_refresh_view()


func select_công trình(type: GameEnums.BuildingType) -> void:
	if not turn_quản lý.can_edit_orders():
		return
	placement.select(type)
	palette.set_active_type(type)
	palette.set_status("Di chuột lên bàn cờ để xem vùng 3×3")
	placement_mode_changed.emit(true)
	_refresh_view()


func cancel() -> void:
	if not turn_quản lý.can_edit_orders():
		return
	if placement.dự kiến_công trình != null:
		turn_quản lý.cancel_công trình(placement.dự kiến_công trình.id)
	placement.cancel()
	palette.clear_active_type()
	palette.set_status("Đã hủy bản thiết kế")
	placement_mode_changed.emit(false)
	_refresh_view()

func cancel_current_construction() -> void:
	if not turn_quản lý.can_edit_orders():
		return
	for candidate in state.công trìnhs.values():
		if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.ĐANG XÂY:
			turn_quản lý.queue_cancel_construction(candidate.id)
			palette.set_status("Đã lập lệnh hủy xây — Kết thúc ngày để chốt")
			return
	palette.set_status("Không có công trình đang xây")

func reassign_selected_thợ xây() -> void:
	if selected_thợ xây_ids.is_empty():
		palette.set_status("Hãy chọn thợ xây trước")
		return
	for candidate in state.công trìnhs.values():
		if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.ĐANG XÂY:
			turn_quản lý.queue_assign_thợ xây(candidate.id, selected_thợ xây_ids[0])
			palette.set_status("Đã lập lệnh gán thợ xây — Kết thúc ngày để chốt")
			return
	palette.set_status("Không có công trình đang xây")

func plan_demolition_current() -> void:
	if not turn_quản lý.can_edit_orders():
		return
	for candidate in state.công trìnhs.values():
		if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.HOẠT ĐỘNG:
			turn_quản lý.queue_demolition(candidate.id)
			palette.set_status("Đã lập lệnh phá %s — Kết thúc ngày để chốt" % _công trình_name(candidate.type))
			return
	palette.set_status("Không có công trình HOẠT ĐỘNG")

func cancel_dự kiến_demolition() -> void:
	turn_quản lý.cancel_demolition()
	palette.set_status("Đã hủy lệnh phá; công trình vẫn HOẠT ĐỘNG")

func plan_staffing_quản lý() -> void:
	var công trình := _first_active_staffing_công trình()
	if công trình == null:
		palette.set_status("Không có Nông trại/Xưởng vật tư HOẠT ĐỘNG")
		return
	if selected_thợ xây_ids.is_empty():
		palette.set_status("Hãy chọn quân trước")
		return
	var lao động := công trình.worker_unit_ids.duplicate()
	turn_quản lý.queue_staffing(công trình.id, selected_thợ xây_ids[0], lao động)
	palette.set_status("Đã lập dự kiến quản lý — Kết thúc ngày để chốt")
	_refresh_staffing_status()

func plan_staffing_lao động() -> void:
	var công trình := _first_active_staffing_công trình()
	if công trình == null:
		palette.set_status("Không có Nông trại/Xưởng vật tư HOẠT ĐỘNG")
		return
	if công trình.type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
		palette.set_status("Xưởng vật tư chỉ cần quản lý")
		return
	turn_quản lý.queue_staffing(công trình.id, công trình.quản lý_unit_id, selected_thợ xây_ids)
	palette.set_status("Đã lập dự kiến lao động — Kết thúc ngày để chốt")
	_refresh_staffing_status()

func cancel_dự kiến_staffing() -> void:
	var công trình := _first_active_staffing_công trình()
	if công trình == null:
		return
	turn_quản lý.cancel_staffing(công trình.id)
	palette.set_status("Đã hủy dự kiến staffing")
	_refresh_staffing_status()


func undo_current() -> bool:
	if not placement.is_active() and placement.dự kiến_công trình == null:
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

	var thợ xâys := selected_thợ xây_ids
	if thợ xâys.is_empty():
		thợ xâys = turn_quản lý.get_default_thợ xây_ids()
	var blueprint := turn_quản lý.queue_công trình(placement.selected_type, cell, thợ xâys)
	if blueprint == null:
		palette.set_status("Không thể lập kế hoạch xây")
		_refresh_view()
		return
	placement.plan(blueprint)
	palette.set_status(
		"Đã đặt ghost tại %s — %d thợ xây — Kết thúc ngày để chốt"
		% [_cell_name(cell), thợ xâys.size()]
	)
	_refresh_view()


func _on_resolution_started() -> void:
	resolving = true


func _on_resolution_finished(result: TurnResolutionResult) -> void:
	resolving = false
	placement.cancel()
	palette.clear_active_type()
	palette.set_status(
		_công trình_result_status(result)
	)
	_refresh_staffing_status()
	placement_mode_changed.emit(false)
	_refresh_view()


func _on_thợ xây_selection_changed(thợ xây_ids: Array[String]) -> void:
	selected_thợ xây_ids = thợ xây_ids.duplicate()
	palette.set_thợ xây_status(selected_thợ xây_ids.size())
	if placement.is_active():
		palette.set_status("Đã chọn %d thợ xây" % selected_thợ xây_ids.size())


func _công trình_result_status(result: TurnResolutionResult) -> String:
	if not result.demolished_công trình_ids.is_empty():
		return "Đã phá công trình — footprint đã được giải phóng"
	if not result.cancelled_công trình_ids.is_empty():
		return "Đã hủy xây — hoàn %d vật tư" % result.refunded_materials
	var công trình: BuildingState
	if not result.new_công trình_ids.is_empty():
		công trình = state.công trìnhs.get(result.new_công trình_ids[0]) as BuildingState
	else:
		for candidate in state.công trìnhs.values():
			if candidate is BuildingState and candidate.phase == GameEnums.BuildingPhase.ĐANG XÂY:
				công trình = candidate
				break
		if công trình == null and not result.completed_công trình_ids.is_empty():
			công trình = state.công trìnhs.get(result.completed_công trình_ids[0]) as BuildingState
	if công trình == null:
		return "Đã kết thúc ngày; build bị từ chối"
	var phase_name := "HOẠT ĐỘNG" if công trình.phase == GameEnums.BuildingPhase.HOẠT ĐỘNG else "ĐANG XÂY"
	return "%s — %s — còn %d ngày — %d thợ xây" % [
		phase_name,
		_công trình_name(công trình.type), công trình.days_left, công trình.thợ xây_unit_ids.size()
	]


func _công trình_name(type: GameEnums.BuildingType) -> String:
	return ["Nông trại", "Material Xưởng vật tư", "Prison", "Infirmary / Y", "Barracks"][type]


func _refresh_view() -> void:
	if view != null:
		view.present_công trìnhs(
			state.công trìnhs, turn_quản lý.get_dự kiến_công trìnhs(), placement, công trình_system
		)
	_refresh_staffing_status()

func _first_active_staffing_công trình() -> BuildingState:
	var ids := state.công trìnhs.keys()
	ids.sort()
	for công trình_id in ids:
		var candidate := state.công trìnhs[công trình_id] as BuildingState
		if (
			candidate != null
			and candidate.phase == GameEnums.BuildingPhase.HOẠT ĐỘNG
			and candidate.type in [GameEnums.BuildingType.FARM, GameEnums.BuildingType.MATERIAL_WORKSHOP]
		):
			return candidate
	return null

func _refresh_staffing_status() -> void:
	if palette == null or state == null:
		return
	var công trình := _first_active_staffing_công trình()
	if công trình == null:
		palette.set_staffing_status("Phân công: chưa có Nông trại/Xưởng vật tư HOẠT ĐỘNG")
		return
	var quản lý_id := công trình.quản lý_unit_id
	var worker_count := công trình.worker_unit_ids.size()
	var dự kiến := turn_quản lý.get_dự kiến_staffing(công trình.id)
	if dự kiến != null:
		quản lý_id = dự kiến.quản lý_unit_id
		worker_count = dự kiến.worker_unit_ids.size()
		palette.set_staffing_status(
			"%s dự kiến — Manager: %s — Workers: %d/6"
			% [_công trình_name(công trình.type), quản lý_id if not quản lý_id.is_empty() else "không có", worker_count]
		)
		return
	palette.set_staffing_status(
		"%s — Manager: %s — Workers: %d/6"
		% [_công trình_name(công trình.type), quản lý_id if not quản lý_id.is_empty() else "không có", worker_count]
	)


func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]


func _validate(cell: Vector2i) -> Dictionary:
	var dự kiến_cores: Array[Vector2i] = []
	for công trình in turn_quản lý.get_dự kiến_công trìnhs():
		if công trình.placement_valid:
			dự kiến_cores.append(công trình.core_cell)
	return công trình_system.validate_placement(
		state, cell, turn_quản lý.get_dự kiến_move_targets().values(), dự kiến_cores
	)
