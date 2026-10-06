class_name BoardView
extends Control

signal cell_pressed(cell: Vector2i)
signal cell_released(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal cell_context_requested(cell: Vector2i)
signal resolution_animation_finished

const BOARD_SIZE := 8
const LIGHT := Color("d1c2a1")
const DARK := Color("92947b")
const BORDER := Color("827455")
const GOLD := Color("d9b86c")
const PLAYER_PIECE := Color("f3ead5")
const ENEMY_PIECE := Color("242826")
const GHOST_TINT := Color(0.55, 0.86, 1.0, 0.48)
const PLAYER_IDENTITY_COLORS := [
	Color("56a7d8"),
	Color("5fbf9f"),
	Color("d4a85b"),
	Color("8f83d8"),
	Color("d77b72"),
	Color("72a9a1"),
]

const PIECE_GLYPHS := {
	GameEnums.Rank.KING: "♚",
	GameEnums.Rank.QUEEN: "♛",
	GameEnums.Rank.ROOK: "♜",
	GameEnums.Rank.KNIGHT: "♞",
	GameEnums.Rank.BISHOP: "♝",
	GameEnums.Rank.PAWN: "♟",
}

const BUILDING_COLORS := {
	GameEnums.BuildingType.FARM: Color("6f9b55"),
	GameEnums.BuildingType.MATERIAL_WORKSHOP: Color("b57b45"),
	GameEnums.BuildingType.PRISON: Color("686b75"),
	GameEnums.BuildingType.INFIRMARY: Color("5b9fa3"),
	GameEnums.BuildingType.BARRACKS: Color("9d5c52"),
}

var selected_cell := Vector2i(-1, -1)
var units: Dictionary = {}
var planned_moves: Dictionary = {}
var selected_unit_id := ""
var buildings: Dictionary = {}
var planned_buildings: Array[BuildingState] = []
var placement: BuildingPlacementState
var building_system: BuildingSystem
var invalid_cell := Vector2i(-1, -1)
var invalid_flash_left := 0.0
var job_slots: Dictionary = {}
var effect_elapsed := 0.0
var effect_duration := 0.32
var movement_effects: Dictionary = {}
var death_effects: Dictionary = {}
var completion_effects: Dictionary = {}
var demolition_effects: Dictionary = {}
var ghost_alpha := 1.0
var planned_building_alpha := 1.0
var last_planned_building_ids := ""
var held_unit_id := ""
var held_mouse_position := Vector2.ZERO
var held_lift_progress := 0.0
var context_unit_id := ""
var context_building_core := Vector2i(-1, -1)
var context_cell := Vector2i(-1, -1)
var board_day_progress := 0.0
var hovered_cell := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func present(
	current_units: Dictionary, current_selected_unit_id: String, current_planned_moves: Dictionary = {}
) -> void:
	var ghost_changed := planned_moves != current_planned_moves
	units = current_units
	planned_moves = current_planned_moves
	selected_unit_id = current_selected_unit_id
	selected_cell = Vector2i(-1, -1)
	var selected := units.get(selected_unit_id) as UnitState
	if selected != null:
		selected_cell = selected.board_cell
	if ghost_changed and not planned_moves.is_empty():
		ghost_alpha = 0.0
		create_tween().tween_method(_set_ghost_alpha, 0.0, 1.0, 0.16)
	if not selected_unit_id.is_empty():
		set_process(true)
	queue_redraw()


func present_buildings(
	current_buildings: Dictionary,
	current_planned_buildings: Array[BuildingState],
	current_placement: BuildingPlacementState,
	current_system: BuildingSystem
) -> void:
	var ids: Array[String] = []
	for building in current_planned_buildings:
		ids.append(building.id)
	var next_ids := ",".join(ids)
	buildings = current_buildings
	planned_buildings = current_planned_buildings
	placement = current_placement
	building_system = current_system
	if not next_ids.is_empty() and next_ids != last_planned_building_ids:
		planned_building_alpha = 0.0
		create_tween().tween_method(_set_planned_building_alpha, 0.0, 1.0, 0.18)
	last_planned_building_ids = next_ids
	queue_redraw()


func set_day(day: int, animate := true) -> void:
	var target := day_color_progress(day)
	if animate and not is_equal_approx(target, board_day_progress):
		create_tween().tween_method(_set_day_progress, board_day_progress, target, 0.5)
	else:
		_set_day_progress(target)


func day_color_progress(day: int) -> float:
	return clampf(float(day - 1) / 31.0, 0.0, 1.0)


func begin_hold(unit_id: String) -> void:
	held_unit_id = unit_id
	held_mouse_position = _board_geometry().projection.screen_to_plane(get_local_mouse_position())
	held_lift_progress = 0.0
	create_tween().tween_method(_set_held_lift, 0.0, 1.0, 0.11)
	queue_redraw()


func cancel_hold() -> void:
	held_unit_id = ""
	held_lift_progress = 0.0
	queue_redraw()


func return_hold_to(cell: Vector2i) -> void:
	if held_unit_id.is_empty() or not is_inside(cell):
		cancel_hold()
		return
	var geometry := _board_geometry()
	var target: Vector2 = geometry.origin + Vector2(cell) * geometry.tile + Vector2.ONE * geometry.tile * 0.5
	var tween := create_tween()
	tween.tween_method(_set_held_mouse_position, held_mouse_position, target, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(cancel_hold)


func present_context_target(unit_id := "", building_core := Vector2i(-1, -1), cell := Vector2i(-1, -1)) -> void:
	context_unit_id = unit_id
	context_building_core = building_core
	context_cell = cell
	queue_redraw()


func present_job_slots(current_slots: Dictionary) -> void:
	job_slots = current_slots.duplicate(true)
	queue_redraw()


func cell_screen_position(cell: Vector2i) -> Vector2:
	var geometry := _board_geometry()
	return global_position + geometry.projection.cell_center(cell)


func gate_local_position() -> Vector2:
	return _board_geometry().projection.gate_position()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		held_mouse_position = _board_geometry().projection.screen_to_plane(event.position)
		if not held_unit_id.is_empty():
			queue_redraw()
		var hover_cell := screen_to_cell(event.position)
		if hover_cell != hovered_cell:
			hovered_cell = hover_cell
			queue_redraw()
		if is_inside(hover_cell):
			cell_hovered.emit(hover_cell)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var context_target := screen_to_cell(event.position)
		if is_inside(context_target):
			cell_context_requested.emit(context_target)
		accept_event()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := screen_to_cell(event.position)
		if event.pressed:
			if is_inside(cell):
				cell_pressed.emit(cell)
		elif is_inside(cell) or not held_unit_id.is_empty():
			cell_released.emit(cell)


func flash_invalid_cell(cell: Vector2i) -> void:
	invalid_cell = cell
	invalid_flash_left = 0.22
	set_process(true)
	queue_redraw()


func play_resolution(
	result: TurnResolutionResult, snapshots: Dictionary, building_snapshots: Dictionary
) -> void:
	movement_effects.clear()
	death_effects.clear()
	completion_effects.clear()
	demolition_effects.clear()
	for unit_id in result.committed_move_ids:
		var unit := units.get(unit_id) as UnitState
		if unit != null and snapshots.has(unit_id):
			movement_effects[unit_id] = {"from": snapshots[unit_id].cell, "to": unit.board_cell}
	for unit_id in result.starved_unit_ids:
		if snapshots.has(unit_id):
			death_effects[unit_id] = snapshots[unit_id]
	for building_id in result.completed_building_ids:
		var building := buildings.get(building_id) as BuildingState
		if building != null:
			completion_effects[building_id] = {"core": building.core_cell, "type": building.type}
	for building_id in result.demolished_building_ids:
		if building_snapshots.has(building_id):
			demolition_effects[building_id] = building_snapshots[building_id]
	if not movement_effects.is_empty() or not death_effects.is_empty() or not completion_effects.is_empty() or not demolition_effects.is_empty():
		effect_elapsed = 0.0
		set_process(true)
		queue_redraw()
	else:
		call_deferred("_emit_resolution_animation_finished")


func _process(delta: float) -> void:
	if invalid_flash_left > 0.0:
		invalid_flash_left -= delta
	if invalid_flash_left <= 0.0:
		invalid_cell = Vector2i(-1, -1)
	if not movement_effects.is_empty() or not death_effects.is_empty() or not completion_effects.is_empty() or not demolition_effects.is_empty():
		effect_elapsed += delta
		if effect_elapsed >= effect_duration:
			movement_effects.clear()
			death_effects.clear()
			completion_effects.clear()
			demolition_effects.clear()
			resolution_animation_finished.emit()
	if invalid_flash_left <= 0.0 and movement_effects.is_empty() and death_effects.is_empty() and completion_effects.is_empty() and demolition_effects.is_empty() and selected_unit_id.is_empty():
		set_process(false)
	queue_redraw()


func screen_to_cell(local_pos: Vector2) -> Vector2i:
	var geometry := _board_geometry()
	var tile: float = geometry.tile
	if tile <= 0.0:
		return Vector2i(-1, -1)
	var grid_position: Vector2 = geometry.projection.screen_to_grid(local_pos)
	return Vector2i(floori(grid_position.x), floori(grid_position.y))


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < BOARD_SIZE and cell.y < BOARD_SIZE


func _board_geometry() -> Dictionary:
	var projection := BoardProjection.fit(size, BOARD_SIZE)
	return {
		"tile": projection.tile,
		"board_px": projection.board_px,
		"origin": Vector2.ZERO,
		"projection": projection,
	}


func _draw() -> void:
	var geometry := _board_geometry()
	var tile: float = geometry.tile
	var board_px: float = geometry.board_px
	var origin: Vector2 = geometry.origin
	var projection: BoardProjection = geometry.projection
	if tile <= 0.0:
		return

	_draw_city_foundation(projection)
	draw_set_transform_matrix(projection.transform)
	var border_color := _progress_color(BORDER, 0.55)
	draw_rect(Rect2(origin - Vector2(22, 22), Vector2(board_px + 44, board_px + 44)), border_color)
	draw_rect(
		Rect2(origin - Vector2(13, 13), Vector2(board_px + 26, board_px + 26)), _progress_color(GOLD, 0.5), false, 2.0
	)

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var rect := Rect2(origin + Vector2(x, y) * tile, Vector2(tile, tile))
			var original := LIGHT if (x + y) % 2 == 0 else DARK
			draw_rect(rect, _progress_color(original, 0.20))
			draw_rect(rect.grow(-1), Color(0.27, 0.26, 0.18, 0.15), false, 1.0)
			var stone_tint := Color(1.0, 0.94, 0.76, 0.06 + float((x * 3 + y * 7) % 4) * 0.018)
			draw_rect(rect.grow(-3), stone_tint)
			draw_line(rect.position + Vector2(3, 3), rect.position + Vector2(tile - 3, 3), Color(1, 0.96, 0.81, 0.2), 1)
			var seam := rect.position + Vector2(tile * 0.5, tile * 0.65)
			draw_line(seam, seam + Vector2(tile * 0.43, 0), Color(0.28, 0.28, 0.2, 0.09), 1)
			var cell := Vector2i(x, y)
			if cell == hovered_cell:
				draw_rect(rect.grow(-3), Color(1, 0.94, 0.76, 0.13))
				draw_rect(rect.grow(-3), Color(1, 0.95, 0.81, 0.45), false, 1.5)
			if cell == selected_cell:
				draw_rect(rect.grow(-4), Color(0.95, 0.78, 0.31, 0.28))
				draw_rect(rect.grow(-5), GOLD, false, 3.0)
			elif cell == invalid_cell:
				draw_rect(rect.grow(-4), Color(0.9, 0.18, 0.16, 0.42))
			if cell == context_cell:
				draw_rect(rect.grow(-6), Color(0.75, 0.9, 1.0, 0.75), false, 2.0)
			if cell == context_building_core:
				draw_rect(rect.grow(-7), Color(1.0, 0.82, 0.38, 0.8), false, 3.0)

	_draw_committed_buildings(origin, tile)
	_draw_planned_buildings(origin, tile)
	_draw_placement_preview(origin, tile)
	_draw_job_slots(origin, tile)
	_draw_building_effects(origin, tile)
	_draw_coordinates(origin, tile, board_px)
	_draw_units(origin, tile)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_city_walls(projection)


func _draw_city_foundation(projection: BoardProjection) -> void:
	var top := projection.board_polygon(24.0)
	var depth := Vector2(0.0, 15.0)
	var shadow := PackedVector2Array()
	for point in top:
		shadow.append(point + Vector2(8, 23))
	draw_colored_polygon(shadow, Color(0.15, 0.19, 0.12, 0.26))
	var front := PackedVector2Array([top[3], top[2], top[2] + depth, top[3] + depth])
	var side := PackedVector2Array([top[1], top[2], top[2] + depth, top[1] + depth])
	draw_colored_polygon(front, Color("766247"))
	draw_colored_polygon(side, Color("625c44"))
	draw_colored_polygon(top, Color("b5a17d"))


func _draw_city_walls(projection: BoardProjection) -> void:
	var wall := projection.board_polygon(19.0)
	for edge in range(4):
		if edge == 2:
			continue
		_draw_wall_segment(wall[edge], wall[(edge + 1) % 4])
	var front_start: Vector2 = wall[3]
	var front_end: Vector2 = wall[2]
	var gate_center := (front_start + front_end) * 0.5
	var direction := (front_end - front_start).normalized()
	_draw_wall_segment(front_start, gate_center - direction * 27.0)
	_draw_wall_segment(gate_center + direction * 27.0, front_end)
	for corner in wall:
		_draw_tower(corner, false)
	for tower in [gate_center - direction * 31.0, gate_center + direction * 31.0]:
		_draw_tower(tower, true)
	# Open gateway: the road remains visible between the two gatehouses.
	draw_line(gate_center + Vector2(-23, 12), gate_center + Vector2(23, 12), Color("e0c49a"), 5.0)
	draw_line(gate_center + Vector2(-22, -8), gate_center + Vector2(22, -8), Color("d4bd8e"), 5.0)
	draw_circle(gate_center + Vector2(0, -8), 4, GOLD)


func _draw_wall_segment(a: Vector2, b: Vector2) -> void:
	var lift := Vector2(0, -7)
	draw_colored_polygon(PackedVector2Array([a + lift, b + lift, b + Vector2(0, 7), a + Vector2(0, 7)]), Color("998263"))
	draw_line(a + lift, b + lift, Color("e0cba4"), 5.0, true)
	draw_line(a + Vector2(0, 6), b + Vector2(0, 6), Color("6e6049"), 2.0, true)
	var count := maxi(1, int(a.distance_to(b) / 19.0))
	for index in range(count + 1):
		var point := a.lerp(b, float(index) / count)
		draw_rect(Rect2(point + Vector2(-3, -11), Vector2(6, 7)), Color("cbb791"))
		draw_line(point + Vector2(0, -3), point + Vector2(0, 5), Color(0.32, 0.28, 0.21, 0.36), 1.0)


func _draw_tower(base: Vector2, gatehouse: bool) -> void:
	var width := 15.0 if gatehouse else 13.0
	draw_rect(Rect2(base + Vector2(-width * 0.5 + 3, 0), Vector2(width, 14)), Color(0.16, 0.16, 0.1, 0.28))
	draw_rect(Rect2(base + Vector2(-width * 0.5, -12), Vector2(width, 23)), Color("b19a74"))
	draw_rect(Rect2(base + Vector2(-width * 0.5, -12), Vector2(4, 23)), Color("dec99f"))
	draw_rect(Rect2(base + Vector2(-width * 0.5 - 2, -15), Vector2(width + 4, 5)), Color("ead6ae"))
	draw_rect(Rect2(base + Vector2(-2, -4), Vector2(4, 8)), Color("565640"))
	for offset in [-6, 0, 6]:
		draw_rect(Rect2(base + Vector2(offset - 2, -18), Vector2(4, 5)), Color("d5bf94"))
	if gatehouse:
		draw_line(base + Vector2(0, -8), base + Vector2(0, 13), Color("7b6549"), 1.5)
		draw_colored_polygon(PackedVector2Array([base + Vector2(0, -7), base + Vector2(11, -4), base + Vector2(0, 2)]), Color("345e79"))


func _draw_job_slots(origin: Vector2, tile: float) -> void:
	var font := get_theme_default_font()
	for cell in job_slots:
		if not is_inside(cell) or job_slots[cell] == GameEnums.JobRole.NONE:
			continue
		var role: int = job_slots[cell]
		var color := Color("61d6a3") if role == GameEnums.JobRole.BUILDER else Color("f0c96a")
		if role == GameEnums.JobRole.TREATMENT:
			color = Color("7ed7db")
		elif role in [GameEnums.JobRole.PRISON_MANAGER, GameEnums.JobRole.PRISON_GUARD]:
			color = Color("aeb1bd")
		var rect := _cell_rect(cell, origin, tile).grow(-tile * 0.15)
		draw_rect(rect, Color(color.r, color.g, color.b, 0.18))
		draw_rect(rect, color, false, 2.0)
		var mark := "◇"
		if role == GameEnums.JobRole.FARM_WORKER:
			mark = "•"
		elif role == GameEnums.JobRole.WORKSHOP_MANAGER:
			mark = "⚙"
		elif role == GameEnums.JobRole.MANAGER:
			mark = "◆"
		elif role == GameEnums.JobRole.TREATMENT:
			mark = "+"
		elif role == GameEnums.JobRole.PRISON_MANAGER:
			mark = "◆"
		elif role == GameEnums.JobRole.PRISON_GUARD:
			mark = "◇"
		draw_string(font, rect.position + Vector2(5, 17), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)


func _draw_building_effects(origin: Vector2, tile: float) -> void:
	var t := clampf(effect_elapsed / effect_duration, 0.0, 1.0)
	var system := building_system
	if system == null:
		system = BuildingSystem.new()
	for effect in completion_effects.values():
		var color: Color = BUILDING_COLORS.get(effect.type, Color.WHITE)
		for cell in system.footprint(effect.core):
			draw_rect(_cell_rect(cell, origin, tile).grow(-2.0 - 5.0 * t), Color(color.r, color.g, color.b, (1.0 - t) * 0.55), false, 4.0)
	for effect in demolition_effects.values():
		var color: Color = BUILDING_COLORS.get(effect.type, Color.WHITE)
		draw_rect(
			_cell_rect(effect.core, origin, tile).grow(-3.0 - 8.0 * t),
			Color(color.r, color.g, color.b, (1.0 - t) * 0.52)
		)
		for cell in system.operational_cells(effect.core):
			draw_rect(
				_cell_rect(cell, origin, tile).grow(-4.0),
				Color(color.r, color.g, color.b, (1.0 - t) * 0.25),
				false,
				1.0
			)


func _draw_committed_buildings(origin: Vector2, tile: float) -> void:
	if building_system == null:
		return
	for candidate in buildings.values():
		if candidate is BuildingState:
			_draw_building(candidate, origin, tile, false)


func _draw_planned_buildings(origin: Vector2, tile: float) -> void:
	for building in planned_buildings:
		_draw_building(building, origin, tile, true)


func _draw_building(building: BuildingState, origin: Vector2, tile: float, ghost: bool) -> void:
	var color: Color = BUILDING_COLORS.get(building.type, Color.GRAY)
	color = _progress_color(color, 0.55)
	if ghost:
		if building.placement_valid:
			color = Color(color.r, color.g, color.b, 0.38 * planned_building_alpha)
		else:
			color = Color(0.94, 0.24, 0.2, 0.48 * planned_building_alpha)
	elif building.phase == GameEnums.BuildingPhase.BLUEPRINT:
		color.a = 0.42
	elif building.phase == GameEnums.BuildingPhase.BUILDING:
		color.a = 0.62
	elif building.phase == GameEnums.BuildingPhase.DEMOLISHING:
		color.a = 0.42
	for cell in building_system.operational_cells(building.core_cell):
		var rect := _cell_rect(cell, origin, tile).grow(-3)
		var area_alpha := (0.06 * planned_building_alpha) if ghost else 0.045
		draw_rect(rect, Color(color.r, color.g, color.b, area_alpha))
		draw_rect(rect, Color(color.r, color.g, color.b, 0.32 if ghost else 0.2), false, 1.0)
	var translucent := ghost or building.phase in [
		GameEnums.BuildingPhase.BLUEPRINT,
		GameEnums.BuildingPhase.BUILDING,
	]
	_draw_core_marker(building, origin, tile, color, translucent)
	if building.type == GameEnums.BuildingType.PRISON and not building.prisoner_unit_ids.is_empty():
		_draw_prisoner_badge(building, origin, tile, color.a)
	var core_rect := _cell_rect(building.core_cell, origin, tile).grow(-tile * 0.25)
	if building.phase == GameEnums.BuildingPhase.BUILDING:
		draw_line(core_rect.position, core_rect.end, Color(1, 1, 1, 0.42), 2.0)
		draw_line(Vector2(core_rect.end.x, core_rect.position.y), Vector2(core_rect.position.x, core_rect.end.y), Color(1, 1, 1, 0.3), 2.0)
	elif building.phase == GameEnums.BuildingPhase.DEMOLISHING:
		var crack := PackedVector2Array([
			Vector2(core_rect.get_center().x, core_rect.position.y),
			core_rect.get_center() + Vector2(-4, -2),
			core_rect.get_center() + Vector2(5, 5),
			Vector2(core_rect.get_center().x - 2, core_rect.end.y),
		])
		draw_polyline(crack, Color(0.15, 0.12, 0.1, 0.72), 2.0)


func _draw_placement_preview(origin: Vector2, tile: float) -> void:
	if placement == null or building_system == null or not placement.is_active():
		return
	if not is_inside(placement.hover_core):
		return
	var color := (
		Color(0.24, 0.86, 0.45, 0.58) if placement.hover_valid else Color(0.94, 0.24, 0.2, 0.62)
	)
	for cell in building_system.operational_cells(placement.hover_core):
		if not is_inside(cell):
			continue
		var rect := _cell_rect(cell, origin, tile).grow(-2)
		draw_rect(rect, Color(color.r, color.g, color.b, 0.055))
		draw_rect(rect, color, false, 1.5)
	var core_rect := _cell_rect(placement.hover_core, origin, tile).grow(-7)
	draw_rect(core_rect, Color(color.r, color.g, color.b, 0.3))
	draw_rect(core_rect, color, false, 5.0)


func _draw_core_marker(
	building: BuildingState,
	origin: Vector2,
	tile: float,
	color: Color,
	ghost: bool
) -> void:
	var rect := _cell_rect(building.core_cell, origin, tile).grow(-tile * 0.14)
	DioramaArt.building(self, rect, building.type, color)
	if building.damaged:
		var crack := PackedVector2Array([
			rect.position + Vector2(rect.size.x * 0.55, 0), rect.get_center() + Vector2(-3, -2),
			rect.get_center() + Vector2(4, 4), rect.end - Vector2(rect.size.x * 0.45, 0),
		])
		draw_polyline(crack, Color("713f2e"), 2.5)
		draw_arc(rect.get_center(), rect.size.x * 0.53, 0, TAU, 32, Color("bc6d40"), 2)
	if building.phase == GameEnums.BuildingPhase.ACTIVE and not ghost:
		var badge_center := rect.end - Vector2(4, 3)
		draw_circle(badge_center, 3.5, Color("c17546") if building.damaged else Color("6d9963"))


func _draw_prisoner_badge(
	building: BuildingState, origin: Vector2, tile: float, alpha: float
) -> void:
	var rect := _cell_rect(building.core_cell, origin, tile)
	var center := rect.position + Vector2(tile * 0.78, tile * 0.22)
	draw_circle(center, tile * 0.13, Color(0.12, 0.13, 0.14, 0.92 * alpha))
	var label := "♟%d" % building.prisoner_unit_ids.size()
	var font := get_theme_default_font()
	var font_size := maxi(11, floori(tile * 0.14))
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		font,
		center + Vector2(-text_size.x * 0.5, text_size.y * 0.32),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.95, 0.95, 0.95, alpha)
	)


func _draw_coordinates(origin: Vector2, tile: float, board_px: float) -> void:
	var font := get_theme_default_font()
	var font_size := maxi(13, floori(tile * 0.16))
	for x in range(BOARD_SIZE):
		var file := String.chr(65 + x)
		var width := font.get_string_size(file, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			Vector2(origin.x + x * tile + (tile - width) * 0.5, origin.y + board_px + 40),
			file,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			GOLD
		)
	for y in range(BOARD_SIZE):
		var rank := str(8 - y)
		var width := font.get_string_size(rank, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			Vector2(origin.x - width - 9, origin.y + y * tile + tile * 0.58),
			rank,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			GOLD
		)


func _draw_units(origin: Vector2, tile: float) -> void:
	if not held_unit_id.is_empty():
		var held_source := units.get(held_unit_id) as UnitState
		if held_source != null:
			var held_origin := origin + Vector2(held_source.board_cell) * tile + Vector2.ONE * tile * 0.5
			draw_dashed_line(
				held_origin,
				held_mouse_position,
				Color(0.75, 0.86, 0.9, 0.48),
				1.5,
				tile * 0.13
			)
	for unit_id in planned_moves:
		var tether_unit := units.get(unit_id) as UnitState
		var target: Vector2i = planned_moves[unit_id]
		if tether_unit == null or not is_inside(target):
			continue
		var from := origin + Vector2(tether_unit.board_cell) * tile + Vector2.ONE * tile * 0.5
		var to := origin + Vector2(target) * tile + Vector2.ONE * tile * 0.5
		var accent := _identity_color(tether_unit.faction, tether_unit.id)
		draw_dashed_line(from, to, Color(accent.r, accent.g, accent.b, 0.66), 2.0, tile * 0.08)
	for candidate in units.values():
		if not (candidate is UnitState) or not is_inside(candidate.board_cell):
			continue
		if movement_effects.has(candidate.id):
			continue
		_draw_piece(candidate, candidate.board_cell, origin, tile, false)

	for unit_id in planned_moves:
		var candidate := units.get(unit_id) as UnitState
		var planned_cell: Vector2i = planned_moves[unit_id]
		if candidate == null or not is_inside(planned_cell):
			continue
		_draw_piece(candidate, planned_cell, origin, tile, true)
		var badge_color := _identity_color(candidate.faction, candidate.id)
		var badge_center := origin + Vector2(planned_cell) * tile + Vector2(tile * 0.77, tile * 0.23)
		draw_circle(badge_center, tile * 0.07, badge_color)

	var t := clampf(effect_elapsed / effect_duration, 0.0, 1.0)
	for unit_id in movement_effects:
		var candidate := units.get(unit_id) as UnitState
		if candidate == null:
			continue
		var effect: Dictionary = movement_effects[unit_id]
		_draw_piece_at_position(candidate.rank, candidate.faction, Vector2(effect.from).lerp(Vector2(effect.to), t), origin, tile, 1.0)
	for unit_id in death_effects:
		var death: Dictionary = death_effects[unit_id]
		_draw_piece_at_position(death.rank, death.faction, Vector2(death.cell), origin, tile, 1.0 - t)
	if not held_unit_id.is_empty():
		var held := units.get(held_unit_id) as UnitState
		if held != null:
			_draw_held_piece(held, held_mouse_position + Vector2(7, -7), tile)


func _draw_piece(
	unit: UnitState, cell: Vector2i, origin: Vector2, tile: float, ghost: bool
) -> void:
	var glyph: String = PIECE_GLYPHS.get(unit.rank, "♟")
	var font := get_theme_default_font()
	var font_size := maxi(34, floori(tile * 0.72))
	var glyph_size := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center := origin + Vector2(cell) * tile + Vector2(tile * 0.5, tile * 0.5)
	var baseline := center + Vector2(-glyph_size.x * 0.5, glyph_size.y * 0.34)
	if not ghost and unit.id == selected_unit_id:
		baseline.y -= tile * 0.045
	var color := PLAYER_PIECE if unit.faction == GameEnums.Faction.PLAYER else ENEMY_PIECE
	color = _progress_color(color, 0.18)
	var identity := _identity_color(unit.faction, unit.id)
	if not ghost and unit.id == context_unit_id:
		draw_arc(center, tile * 0.41, 0.0, TAU, 40, Color(0.75, 0.9, 1.0, 0.8), 2.5)
	if ghost:
		color = Color(GHOST_TINT.r, GHOST_TINT.g, GHOST_TINT.b, GHOST_TINT.a * ghost_alpha)
		draw_circle(center, tile * 0.34, Color(identity.r, identity.g, identity.b, 0.14 * ghost_alpha))
		draw_arc(center, tile * 0.35, 0.0, TAU, 48, Color(identity.r, identity.g, identity.b, 0.72 * ghost_alpha), 2.0)
	else:
		var pulse := 1.0
		if unit.id == selected_unit_id:
			pulse = 1.0 + 0.035 * sin(Time.get_ticks_msec() * 0.003)
		DioramaArt.ellipse(self, center + Vector2(tile * 0.07, tile * 0.3), Vector2(tile * 0.29, tile * 0.1), Color(0.12, 0.14, 0.1, 0.33))
		DioramaArt.ellipse(self, center + Vector2(0, tile * 0.26), Vector2(tile * 0.25, tile * 0.08) * pulse, identity)
		draw_string(
			font,
			baseline + Vector2(2, 3),
			glyph,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0, 0, 0, 0.35)
		)
	if not ghost:
		draw_string_outline(font, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color("514d3d") if unit.faction == GameEnums.Faction.PLAYER else Color("d9c795"))
	draw_string(font, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _identity_color(faction: int, unit_id: String) -> Color:
	var hash_index: int = absi(unit_id.hash())
	var base: Color = PLAYER_IDENTITY_COLORS[hash_index % PLAYER_IDENTITY_COLORS.size()]
	if faction == GameEnums.Faction.ENEMY:
		base = Color("d45b55")
	elif faction == GameEnums.Faction.OUTSIDER:
		base = Color("b887d8")
	var variation := float(hash_index % 9) / 100.0
	return _progress_color(base.lightened(variation), 0.25)


func _set_ghost_alpha(value: float) -> void:
	ghost_alpha = value
	queue_redraw()


func _set_planned_building_alpha(value: float) -> void:
	planned_building_alpha = value
	queue_redraw()


func _set_day_progress(value: float) -> void:
	board_day_progress = value
	queue_redraw()


func _set_held_lift(value: float) -> void:
	held_lift_progress = value
	queue_redraw()


func _set_held_mouse_position(value: Vector2) -> void:
	held_mouse_position = value
	queue_redraw()


func _progress_color(original: Color, minimum_saturation: float) -> Color:
	var gray := original.get_luminance()
	var desaturated := Color(gray, gray, gray, original.a).lerp(original, maxf(0.8, minimum_saturation))
	return desaturated.lerp(original, board_day_progress)


func _emit_resolution_animation_finished() -> void:
	resolution_animation_finished.emit()


func _draw_piece_at_position(rank: int, faction: int, cell_position: Vector2, origin: Vector2, tile: float, alpha: float) -> void:
	var glyph: String = PIECE_GLYPHS.get(rank, "♟")
	var font := get_theme_default_font()
	var font_size := maxi(34, floori(tile * 0.72))
	var glyph_size := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center := origin + cell_position * tile + Vector2(tile * 0.5, tile * 0.5)
	var baseline := center + Vector2(-glyph_size.x * 0.5, glyph_size.y * 0.34)
	var color := PLAYER_PIECE if faction == GameEnums.Faction.PLAYER else ENEMY_PIECE
	color = _progress_color(color, 0.18)
	color.a = alpha
	draw_string(font, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_held_piece(unit: UnitState, center: Vector2, tile: float) -> void:
	var glyph: String = PIECE_GLYPHS.get(unit.rank, "♟")
	var font := get_theme_default_font()
	var scale_factor := lerpf(1.0, 1.1, held_lift_progress)
	var font_size := maxi(34, floori(tile * 0.72 * scale_factor))
	var glyph_size := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var lifted_center := center + Vector2(0, lerpf(0.0, -5.0, held_lift_progress))
	var baseline := lifted_center + Vector2(-glyph_size.x * 0.5, glyph_size.y * 0.34)
	var identity := _identity_color(unit.faction, unit.id)
	draw_circle(lifted_center + Vector2(3, 7), tile * 0.31, Color(0, 0, 0, 0.22))
	draw_circle(lifted_center, tile * 0.35, Color(identity.r, identity.g, identity.b, 0.2))
	draw_arc(lifted_center, tile * 0.36, 0.0, TAU, 40, Color(identity.r, identity.g, identity.b, 0.85), 2.5)
	draw_string(font, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.96, 0.94, 0.88))


func _cell_rect(cell: Vector2i, origin: Vector2, tile: float) -> Rect2:
	return Rect2(origin + Vector2(cell) * tile, Vector2(tile, tile))


func _on_mouse_exited() -> void:
	hovered_cell = Vector2i(-1, -1)
	queue_redraw()
	cell_hovered.emit(Vector2i(-1, -1))
