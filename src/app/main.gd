extends Control

const DEV_MODE := false

var game_state := GameState.new()
var turn_manager := TurnManager.new()
var board: BoardView
var board_controller: BoardController
var building_palette: BuildingPalette
var building_placement_controller: BuildingPlacementController
var contextual_controller: ContextualBoardController
var context_popup: ContextPopup
var ration_overlay: RationOverlay
var report_panel: ReportPanel
var outside_rail: OutsideRail
var day_label: Label
var resource_label: Label
var visual_transition := false
var status_label: Label
var resource_delta_label: Label


func _ready() -> void:
	_build_shell()
	_seed_day_one()
	turn_manager.setup(game_state)
	add_child(turn_manager)
	board_controller = BoardController.new()
	add_child(board_controller)
	board_controller.setup(game_state, turn_manager, board)
	contextual_controller = ContextualBoardController.new()
	add_child(contextual_controller)
	contextual_controller.setup(game_state, turn_manager, board, context_popup)
	outside_rail.setup(game_state, turn_manager)
	board_controller.context_requested.connect(contextual_controller.open_for_cell)
	board_controller.view_changed.connect(contextual_controller.refresh)
	board.resolution_animation_finished.connect(_on_resolution_animation_finished)
	if DEV_MODE:
		building_placement_controller = BuildingPlacementController.new()
		add_child(building_placement_controller)
		building_placement_controller.setup(game_state, turn_manager, board, building_palette)
		building_placement_controller.placement_mode_changed.connect(_on_placement_mode_changed)
	turn_manager.day_started.connect(_on_day_started)
	turn_manager.resolution_finished.connect(_on_resolution_finished)
	turn_manager.ration_requested.connect(_on_ration_requested)
	ration_overlay.submitted.connect(_on_ration_submitted)
	_refresh_header()


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("121416")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 58
	root.add_child(top)

	day_label = Label.new()
	day_label.add_theme_font_size_override("font_size", 28)
	top.add_child(day_label)
	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 18)
	top.add_child(resource_label)
	resource_delta_label = Label.new()
	resource_delta_label.add_theme_color_override("font_color", Color("79d8a5"))
	top.add_child(resource_delta_label)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("d9b86c"))
	top.add_child(status_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var undo_button := Button.new()
	undo_button.text = "Đóng / Bỏ chọn"
	undo_button.tooltip_text = "Đóng bảng hoặc bỏ thao tác tạm thời; không hủy lệnh đã định"
	undo_button.pressed.connect(_undo_current)
	top.add_child(undo_button)

	var report_button := Button.new()
	report_button.text = "Báo cáo"
	report_button.pressed.connect(_toggle_report)
	top.add_child(report_button)

	var end_button := Button.new()
	end_button.text = "Kết thúc ngày"
	end_button.pressed.connect(_end_day)
	top.add_child(end_button)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	board = BoardView.new()
	board.custom_minimum_size = Vector2(560, 560)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(board)

	outside_rail = OutsideRail.new()
	content.add_child(outside_rail)

	building_palette = BuildingPalette.new()
	building_palette.visible = DEV_MODE
	if DEV_MODE:
		var palette_scroll := ScrollContainer.new()
		palette_scroll.custom_minimum_size.x = 270
		palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(palette_scroll)
		building_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		palette_scroll.add_child(building_palette)

	report_panel = ReportPanel.new()
	add_child(report_panel)

	context_popup = ContextPopup.new()
	add_child(context_popup)
	ration_overlay = RationOverlay.new()
	add_child(ration_overlay)


func _seed_day_one() -> void:
	game_state.food = 4
	game_state.materials = 3
	_spawn_piece("king", "Vua", GameEnums.Rank.KING, Vector2i(4, 7))
	_spawn_piece("rook", "Xe", GameEnums.Rank.ROOK, Vector2i(0, 7))
	_spawn_piece("knight", "Mã", GameEnums.Rank.KNIGHT, Vector2i(1, 7))
	_spawn_piece("pawn_d", "Tốt D", GameEnums.Rank.PAWN, Vector2i(3, 6))
	_spawn_piece("pawn_e", "Tốt E", GameEnums.Rank.PAWN, Vector2i(4, 6))


func _spawn_piece(unit_id: String, unit_name: String, rank: GameEnums.Rank, cell: Vector2i) -> void:
	var unit := UnitState.new(unit_id)
	unit.display_name = unit_name
	unit.rank = rank
	unit.board_cell = cell
	unit.backstory.append("Sống sót sau những ngày thành trì mất màu.")
	unit.backstory.append("Được Vua tập hợp lại tại %s." % _cell_name(cell))
	game_state.units[unit.id] = unit


func _cell_name(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]


func _undo_current() -> void:
	if contextual_controller != null and contextual_controller.undo_current():
		return
	if building_placement_controller != null and building_placement_controller.undo_current():
		return
	if board_controller != null:
		board_controller.undo_current()


func _toggle_report() -> void:
	if report_panel.visible:
		report_panel.close()
		return
	report_panel.open_latest()


func _end_day() -> void:
	if not visual_transition and not game_state.game_over and game_state.day < GameState.MAX_DAYS:
		visual_transition = true
		turn_manager.end_day()


func _on_day_started(_day: int) -> void:
	_refresh_header()


func _on_resolution_finished(result: TurnResolutionResult) -> void:
	_refresh_header()
	report_panel.show_result(result)
	_show_resource_delta(result)
	if game_state.game_over:
		status_label.text = "THẤT BẠI: %s" % game_state.failure_reason
	elif not result.starved_unit_ids.is_empty():
		var names: Array[String] = []
		for unit_id in result.starved_unit_ids:
			names.append(result.starved_unit_names.get(unit_id, "một quân cờ"))
		status_label.text = "Chết đói: %s" % ", ".join(names)
	else:
		status_label.text = "Đã giải quyết ngày %02d" % result.resolved_day


func _on_ration_requested(result: TurnResolutionResult) -> void:
	ration_overlay.show_request(game_state, result)


func _on_ration_submitted(unit_ids: Array[String]) -> void:
	turn_manager.submit_ration(unit_ids)


func _on_resolution_animation_finished() -> void:
	visual_transition = false


func _show_resource_delta(result: TurnResolutionResult) -> void:
	var food_delta := (
		result.food_produced - result.food_consumed
		- result.outsider_food_consumed + result.trade_food_delta
	)
	var material_delta := (
		result.materials_produced - result.materials_spent
		+ result.refunded_materials + result.trade_materials_delta
	)
	var parts: Array[String] = []
	if food_delta != 0:
		parts.append("Lương thực %s%d" % ["+" if food_delta > 0 else "", food_delta])
	if material_delta != 0:
		parts.append("Vật tư %s%d" % ["+" if material_delta > 0 else "", material_delta])
	resource_delta_label.text = "   " + " · ".join(parts) if not parts.is_empty() else ""
	resource_delta_label.modulate.a = 1.0
	if not parts.is_empty():
		create_tween().tween_property(resource_delta_label, "modulate:a", 0.0, 1.4).set_delay(0.6)


func _on_placement_mode_changed(active: bool) -> void:
	board_controller.set_input_enabled(not active)


func _refresh_header() -> void:
	day_label.text = "NGÀY %02d / %02d" % [game_state.day, GameState.MAX_DAYS]
	# Kho trung tâm là thông tin player quản lý trực tiếp, nên header được phép hiện số chính xác.
	resource_label.text = "   Lương thực %d   ·   Vật tư %d" % [game_state.food, game_state.materials]
	board.set_day(game_state.day, game_state.day > 1)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F11 or (key_event.alt_pressed and key_event.keycode == KEY_ENTER):
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN
			else DisplayServer.WINDOW_MODE_FULLSCREEN
		)
		get_viewport().set_input_as_handled()
