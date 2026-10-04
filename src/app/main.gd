extends Control

var game_state := GameState.new()
var turn_manager := TurnManager.new()
var board: BoardView
var board_controller: BoardController
var building_palette: BuildingPalette
var building_placement_controller: BuildingPlacementController
var report_panel: ReportPanel
var day_label: Label


func _ready() -> void:
	_build_shell()
	_seed_day_one()
	turn_manager.setup(game_state)
	add_child(turn_manager)
	board_controller = BoardController.new()
	add_child(board_controller)
	board_controller.setup(game_state, turn_manager, board)
	building_placement_controller = BuildingPlacementController.new()
	add_child(building_placement_controller)
	building_placement_controller.setup(game_state, turn_manager, board, building_palette)
	building_placement_controller.placement_mode_changed.connect(_on_placement_mode_changed)
	turn_manager.day_started.connect(_on_day_started)
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

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var undo_button := Button.new()
	undo_button.text = "↶ Undo"
	undo_button.tooltip_text = "Hủy lựa chọn hoặc kế hoạch hiện tại"
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
	board.custom_minimum_size = Vector2(560, 0)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(board)

	var palette_scroll := ScrollContainer.new()
	palette_scroll.custom_minimum_size.x = 270
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(palette_scroll)

	building_palette = BuildingPalette.new()
	building_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.add_child(building_palette)

	report_panel = ReportPanel.new()
	report_panel.visible = false
	content.add_child(report_panel)


func _seed_day_one() -> void:
	game_state.food = 10
	game_state.materials = 2
	_spawn_piece("king", "Vua", GameEnums.Rank.KING, Vector2i(4, 7))
	_spawn_piece("queen", "Hậu", GameEnums.Rank.QUEEN, Vector2i(3, 7))
	_spawn_piece("rook", "Xe", GameEnums.Rank.ROOK, Vector2i(0, 7))
	_spawn_piece("knight", "Mã", GameEnums.Rank.KNIGHT, Vector2i(1, 7))
	_spawn_piece("bishop", "Tịnh", GameEnums.Rank.BISHOP, Vector2i(2, 7))
	_spawn_piece("pawn_d", "Tốt D", GameEnums.Rank.PAWN, Vector2i(3, 6))
	_spawn_piece("pawn_e", "Tốt E", GameEnums.Rank.PAWN, Vector2i(4, 6))


func _spawn_piece(unit_id: String, unit_name: String, rank: GameEnums.Rank, cell: Vector2i) -> void:
	var unit := UnitState.new(unit_id)
	unit.display_name = unit_name
	unit.rank = rank
	unit.board_cell = cell
	game_state.units[unit.id] = unit


func _undo_current() -> void:
	if building_placement_controller != null and building_placement_controller.undo_current():
		return
	if board_controller != null:
		board_controller.undo_current()


func _toggle_report() -> void:
	report_panel.visible = not report_panel.visible


func _end_day() -> void:
	if game_state.day < GameState.MAX_DAYS:
		turn_manager.end_day()


func _on_day_started(_day: int) -> void:
	_refresh_header()


func _on_placement_mode_changed(active: bool) -> void:
	board_controller.set_input_enabled(not active)


func _refresh_header() -> void:
	day_label.text = "NGÀY %02d / %02d" % [game_state.day, GameState.MAX_DAYS]
