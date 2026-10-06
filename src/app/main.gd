extends Control

const DEV_MODE := false

var game_state: GameState
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
var perimeter_view: PerimeterView
var world_panel: WorldPanel
var onboarding_panel: OnboardingHintPanel
var ending_panel: EndingPanel
var pause_menu: PauseMenu
var day_label: Label
var resource_label: Label
var world_indicator_label: Label
var visual_transition := false
var status_label: Label
var resource_delta_label: Label
var world_system := WorldSystem.new()
var onboarding_system := OnboardingSystem.new()
var undo_button: Button
var report_button: Button
var world_button: Button
var end_button: Button
var phase_label: Label


func _ready() -> void:
	Localization.load_saved_language()
	game_state = GameSession.start_new_game()
	_build_shell()
	turn_manager.setup(game_state)
	add_child(turn_manager)
	board_controller = BoardController.new()
	add_child(board_controller)
	board_controller.setup(game_state, turn_manager, board)
	contextual_controller = ContextualBoardController.new()
	add_child(contextual_controller)
	contextual_controller.setup(game_state, turn_manager, board, context_popup)
	perimeter_view.setup(game_state, turn_manager)
	outside_rail.setup(game_state, turn_manager)
	world_panel.setup(game_state, turn_manager)
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
	onboarding_panel.next_requested.connect(_on_onboarding_next)
	onboarding_panel.skip_requested.connect(_on_onboarding_skip)
	pause_menu.resume_requested.connect(_resume_from_pause)
	pause_menu.main_menu_requested.connect(_return_to_main_menu)
	Localization.watch(_on_language_changed)
	_show_onboarding_hint(onboarding_system.start(game_state))
	_refresh_localized_controls()
	_refresh_header()


func _build_shell() -> void:
	theme = GameplayTheme.create()
	var background := ColorRect.new()
	background.color = Color("697959")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	var header := PanelContainer.new()
	root.add_child(header)

	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 58
	top.add_theme_constant_override("separation", 16)
	header.add_child(top)
	var title_column := VBoxContainer.new()
	top.add_child(title_column)
	var brand := Label.new()
	brand.text = Localization.text("brand.name")
	brand.add_theme_font_size_override("font_size", 23)
	title_column.add_child(brand)

	day_label = Label.new()
	day_label.add_theme_font_size_override("font_size", 17)
	day_label.add_theme_color_override("font_color", Color("dfc889"))
	title_column.add_child(day_label)
	var resources := VBoxContainer.new()
	top.add_child(resources)
	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 16)
	resources.add_child(resource_label)
	phase_label = Label.new()
	phase_label.add_theme_color_override("font_color", Color("bfcdac"))
	resources.add_child(phase_label)
	resource_delta_label = Label.new()
	resource_delta_label.add_theme_color_override("font_color", Color("79d8a5"))
	resources.add_child(resource_delta_label)
	world_indicator_label = Label.new()
	world_indicator_label.add_theme_color_override("font_color", Color("d5cca1"))
	top.add_child(world_indicator_label)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("f3dfb3"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	undo_button = Button.new()
	undo_button.pressed.connect(_undo_current)
	top.add_child(undo_button)

	report_button = Button.new()
	report_button.pressed.connect(_toggle_report)
	top.add_child(report_button)

	world_button = Button.new()
	world_button.pressed.connect(_toggle_world)
	top.add_child(world_button)

	end_button = Button.new()
	end_button.custom_minimum_size = Vector2(142, 54)
	end_button.add_theme_font_size_override("font_size", 17)
	end_button.add_theme_stylebox_override("normal", GameplayTheme.panel(Color("30586b"), Color("d5bc77")))
	end_button.pressed.connect(_end_day)
	top.add_child(end_button)
	root.add_child(status_label)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	perimeter_view = PerimeterView.new()
	perimeter_view.custom_minimum_size = Vector2(720, 560)
	perimeter_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perimeter_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(perimeter_view)
	board = BoardView.new()
	perimeter_view.attach_board(board)

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
	world_panel = WorldPanel.new()
	add_child(world_panel)

	context_popup = ContextPopup.new()
	add_child(context_popup)
	ration_overlay = RationOverlay.new()
	add_child(ration_overlay)
	onboarding_panel = OnboardingHintPanel.new()
	add_child(onboarding_panel)
	ending_panel = EndingPanel.new()
	add_child(ending_panel)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)


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


func _toggle_world() -> void:
	if world_panel.visible:
		world_panel.close()
	else:
		world_panel.open()


func _end_day() -> void:
	if not visual_transition and turn_manager.can_edit_orders():
		visual_transition = true
		var result := turn_manager.end_day()
		if result == null:
			visual_transition = false


func _on_day_started(_day: int) -> void:
	_refresh_header()


func _on_resolution_finished(result: TurnResolutionResult) -> void:
	_refresh_header()
	report_panel.show_result(result)
	_show_resource_delta(result)
	if game_state.game_over:
		var failure_reason := (
			Localization.text(game_state.failure_reason_key, game_state.failure_reason_args)
			if not game_state.failure_reason_key.is_empty()
			else game_state.failure_reason
		)
		status_label.text = Localization.text("game.failure", {"reason": failure_reason})
	elif not result.starved_unit_ids.is_empty():
		var names: Array[String] = []
		for unit_id in result.starved_unit_ids:
			names.append(result.starved_unit_names.get(unit_id, "một quân cờ"))
		status_label.text = Localization.text("game.starved", {"names": ", ".join(names)})
	else:
		status_label.text = Localization.text("game.resolved_day", {"day": "%02d" % result.resolved_day})
	if result.ending_triggered:
		ending_panel.show_ending(game_state)


func _on_ration_requested(result: TurnResolutionResult) -> void:
	ration_overlay.show_request(game_state, result)


func _on_ration_submitted(unit_ids: Array[String]) -> void:
	turn_manager.submit_ration(unit_ids)


func _on_resolution_animation_finished() -> void:
	visual_transition = false


func _show_resource_delta(result: TurnResolutionResult) -> void:
	var food_delta := (
		result.food_produced - result.food_consumed
		- result.outsider_food_consumed - result.expedition_supply_food
		+ result.trade_food_delta
	)
	var material_delta := (
		result.materials_produced - result.materials_spent
		+ result.refunded_materials + result.trade_materials_delta
	)
	var parts: Array[String] = []
	if food_delta != 0:
		parts.append(Localization.text("game.resource_delta", {
			"resource": Localization.text("game.food"),
			"delta": "%s%d" % ["+" if food_delta > 0 else "", food_delta],
		}))
	if material_delta != 0:
		parts.append(Localization.text("game.resource_delta", {
			"resource": Localization.text("game.materials"),
			"delta": "%s%d" % ["+" if material_delta > 0 else "", material_delta],
		}))
	resource_delta_label.text = "   " + " · ".join(parts) if not parts.is_empty() else ""
	resource_delta_label.modulate.a = 1.0
	if not parts.is_empty():
		create_tween().tween_property(resource_delta_label, "modulate:a", 0.0, 1.4).set_delay(0.6)


func _on_placement_mode_changed(active: bool) -> void:
	board_controller.set_input_enabled(not active)


func _refresh_header() -> void:
	day_label.text = Localization.text("game.day_counter", {
		"day": "%02d" % game_state.day, "max_day": "%02d" % GameState.MAX_DAYS,
	})
	# Kho trung tâm là thông tin player quản lý trực tiếp, nên header được phép hiện số chính xác.
	resource_label.text = Localization.text("game.resources", {
		"food": game_state.food, "materials": game_state.materials,
	})
	var world := world_system.ensure_initialized(game_state)
	world_indicator_label.text = Localization.text("s14.season", {
		"season": world_system.season_label(world.season),
	})
	phase_label.text = Localization.text("s14." + RunBalance.stage(game_state.day))
	board.set_day(game_state.day, game_state.day > 1)


func set_language(locale: String) -> bool:
	return GameSession.set_language(locale)


func current_language() -> String:
	return GameSession.current_language()


func start_onboarding() -> Dictionary:
	var hint := onboarding_system.start(game_state)
	_show_onboarding_hint(hint)
	return hint


func skip_onboarding() -> void:
	onboarding_system.skip(game_state)
	_show_onboarding_hint({})


func onboarding_state() -> Dictionary:
	return onboarding_system.snapshot(game_state)


func ending_recap() -> Dictionary:
	return EndingSystem.new().localized_recap(game_state)


func _on_onboarding_next() -> void:
	_show_onboarding_hint(onboarding_system.dismiss_current(game_state))


func _on_onboarding_skip() -> void:
	skip_onboarding()


func _show_onboarding_hint(hint: Dictionary) -> void:
	onboarding_panel.show_hint(hint)
	resource_label.modulate = Color.WHITE
	report_button.modulate = Color.WHITE
	outside_rail.modulate = Color.WHITE
	end_button.modulate = Color.WHITE
	if board != null:
		board.present_context_target()
	if hint.is_empty():
		return
	var emphasis := Color("ffe09a")
	match str(hint.target):
		"king":
			board.present_context_target("king")
		"unit":
			board.present_context_target("pawn_d")
		"resources":
			resource_label.modulate = emphasis
		"report":
			report_button.modulate = emphasis
		"perimeter":
			outside_rail.modulate = emphasis
		"end_day":
			end_button.modulate = emphasis


func _on_language_changed(_locale: String) -> void:
	for unit_id in ["king", "rook", "knight", "pawn_d", "pawn_e"]:
		var unit := game_state.units.get(unit_id) as UnitState
		if unit != null:
			unit.display_name = Localization.text("unit.seed.%s" % unit_id)
	_refresh_localized_controls()
	_refresh_header()
	if contextual_controller != null:
		contextual_controller.refresh()


func _refresh_localized_controls() -> void:
	undo_button.text = Localization.text("game.undo")
	undo_button.tooltip_text = Localization.text("game.undo_hint")
	report_button.text = Localization.text("game.report")
	world_button.text = Localization.text("game.world")
	end_button.text = Localization.text("game.end_day")
	context_popup.refresh_language()
	report_panel.refresh_language()


func _exit_tree() -> void:
	Localization.unwatch(_on_language_changed)
	if get_tree() != null:
		get_tree().paused = false


func _open_pause_menu() -> void:
	if pause_menu == null or ending_panel.visible:
		return
	pause_menu.open()
	get_tree().paused = true


func _resume_from_pause() -> void:
	get_tree().paused = false
	pause_menu.hide()


func _return_to_main_menu() -> void:
	get_tree().paused = false
	AppAudio.begin_menu_opening()
	get_tree().change_scene_to_file("res://src/app/front_door.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_F11 or (key_event.alt_pressed and key_event.keycode == KEY_ENTER):
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN
			else DisplayServer.WINDOW_MODE_FULLSCREEN
		)
		get_viewport().set_input_as_handled()
