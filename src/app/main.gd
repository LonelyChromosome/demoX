extends Control

var game_state := GameState.new()
var turn_manager := TurnManager.new()
var board: BoardView
var report_panel: ReportPanel
var day_label: Label

func _ready() -> void:
	_build_shell()
	_seed_day_one()
	turn_manager.setup(game_state)
	add_child(turn_manager)
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
	board.custom_minimum_size = Vector2(760, 760)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(board)

	report_panel = ReportPanel.new()
	report_panel.visible = false
	content.add_child(report_panel)

func _seed_day_one() -> void:
	game_state.food = 10
	game_state.materials = 2
	var king := UnitState.new("king")
	king.display_name = "Vua"
	king.rank = GameEnums.Rank.KING
	king.board_cell = Vector2i(4, 7)
	game_state.units[king.id] = king

func _toggle_report() -> void:
	report_panel.visible = not report_panel.visible

func _end_day() -> void:
	if game_state.day < GameState.MAX_DAYS:
		turn_manager.end_day()

func _on_day_started(_day: int) -> void:
	_refresh_header()

func _refresh_header() -> void:
	day_label.text = "NGÀY %02d / %02d" % [game_state.day, GameState.MAX_DAYS]
