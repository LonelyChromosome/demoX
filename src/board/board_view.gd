class_name BoardView
extends Control

signal cell_pressed(cell: Vector2i)
signal cell_released(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const BOARD_SIZE := 8
const LIGHT := Color("d7c59d")
const DARK := Color("59665b")
const BORDER := Color("171b19")
const GOLD := Color("d9b86c")
const PLAYER_PIECE := Color("f3ead5")
const ENEMY_PIECE := Color("242826")
const GHOST_TINT := Color(0.55, 0.86, 1.0, 0.48)

const PIECE_GLYPHS := {
	GameEnums.Rank.KING: "♚",
	GameEnums.Rank.QUEEN: "♛",
	GameEnums.Rank.ROOK: "♜",
	GameEnums.Rank.KNIGHT: "♞",
	GameEnums.Rank.BISHOP: "♝",
	GameEnums.Rank.PAWN: "♟",
}

const BUILDING_LABELS := {
	GameEnums.BuildingType.FARM: "F",
	GameEnums.BuildingType.MATERIAL_WORKSHOP: "M",
	GameEnums.BuildingType.PRISON: "P",
	GameEnums.BuildingType.INFIRMARY: "Y",
	GameEnums.BuildingType.BARRACKS: "B",
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
var placement: BuildingPlacementState
var building_system: BuildingSystem
var invalid_cell := Vector2i(-1, -1)
var invalid_flash_left := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func present(
	current_units: Dictionary, current_selected_unit_id: String, current_planned_moves: Dictionary = {}
) -> void:
	units = current_units
	planned_moves = current_planned_moves
	selected_unit_id = current_selected_unit_id
	selected_cell = Vector2i(-1, -1)
	var selected := units.get(selected_unit_id) as UnitState
	if selected != null:
		selected_cell = selected.board_cell
	queue_redraw()


func present_buildings(
	current_buildings: Dictionary,
	current_placement: BuildingPlacementState,
	current_system: BuildingSystem
) -> void:
	buildings = current_buildings
	placement = current_placement
	building_system = current_system
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hover_cell := screen_to_cell(event.position)
		if is_inside(hover_cell):
			cell_hovered.emit(hover_cell)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := screen_to_cell(event.position)
		if not is_inside(cell):
			return
		if event.pressed:
			cell_pressed.emit(cell)
		else:
			cell_released.emit(cell)


func flash_invalid_cell(cell: Vector2i) -> void:
	invalid_cell = cell
	invalid_flash_left = 0.22
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	invalid_flash_left -= delta
	if invalid_flash_left <= 0.0:
		invalid_cell = Vector2i(-1, -1)
		set_process(false)
	queue_redraw()


func screen_to_cell(local_pos: Vector2) -> Vector2i:
	var geometry := _board_geometry()
	var tile: float = geometry.tile
	var origin: Vector2 = geometry.origin
	if tile <= 0.0:
		return Vector2i(-1, -1)
	var p := local_pos - origin
	return Vector2i(floori(p.x / tile), floori(p.y / tile))


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < BOARD_SIZE and cell.y < BOARD_SIZE


func _board_geometry() -> Dictionary:
	var available := Vector2(maxf(size.x - 92.0, 0.0), maxf(size.y - 92.0, 0.0))
	var tile := floorf(minf(available.x, available.y) / float(BOARD_SIZE))
	var board_px := tile * BOARD_SIZE
	var origin := Vector2(
		floorf((size.x - board_px) * 0.5), floorf((size.y - board_px) * 0.5 + 10.0)
	)
	return {"tile": tile, "board_px": board_px, "origin": origin}


func _draw() -> void:
	var geometry := _board_geometry()
	var tile: float = geometry.tile
	var board_px: float = geometry.board_px
	var origin: Vector2 = geometry.origin
	if tile <= 0.0:
		return

	draw_rect(Rect2(origin - Vector2(22, 22), Vector2(board_px + 44, board_px + 44)), BORDER)
	draw_rect(
		Rect2(origin - Vector2(13, 13), Vector2(board_px + 26, board_px + 26)), GOLD, false, 2.0
	)

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var rect := Rect2(origin + Vector2(x, y) * tile, Vector2(tile, tile))
			draw_rect(rect, LIGHT if (x + y) % 2 == 0 else DARK)
			var cell := Vector2i(x, y)
			if cell == selected_cell:
				draw_rect(rect.grow(-4), Color(0.95, 0.78, 0.31, 0.28))
				draw_rect(rect.grow(-5), GOLD, false, 3.0)
			elif cell == invalid_cell:
				draw_rect(rect.grow(-4), Color(0.9, 0.18, 0.16, 0.42))

	_draw_committed_buildings(origin, tile)
	_draw_planned_building(origin, tile)
	_draw_placement_preview(origin, tile)
	_draw_coordinates(origin, tile, board_px)
	_draw_units(origin, tile)


func _draw_committed_buildings(origin: Vector2, tile: float) -> void:
	if building_system == null:
		return
	for candidate in buildings.values():
		if candidate is BuildingState:
			_draw_building(candidate, origin, tile, false)


func _draw_planned_building(origin: Vector2, tile: float) -> void:
	if placement == null or placement.planned_building == null:
		return
	_draw_building(placement.planned_building, origin, tile, true)


func _draw_building(building: BuildingState, origin: Vector2, tile: float, ghost: bool) -> void:
	var color: Color = BUILDING_COLORS.get(building.type, Color.GRAY)
	if ghost:
		color = Color(color.r, color.g, color.b, 0.38)
	for cell in building_system.footprint(building.core_cell):
		var rect := _cell_rect(cell, origin, tile).grow(-3)
		draw_rect(rect, Color(color.r, color.g, color.b, 0.28 if ghost else 0.46))
		draw_rect(rect, color, false, 2.0)
	_draw_core_marker(building.core_cell, building.type, origin, tile, color)


func _draw_placement_preview(origin: Vector2, tile: float) -> void:
	if placement == null or building_system == null or not placement.is_active():
		return
	if not is_inside(placement.hover_core):
		return
	var color := (
		Color(0.24, 0.86, 0.45, 0.58) if placement.hover_valid else Color(0.94, 0.24, 0.2, 0.62)
	)
	for cell in building_system.footprint(placement.hover_core):
		if not is_inside(cell):
			continue
		var rect := _cell_rect(cell, origin, tile).grow(-2)
		draw_rect(rect, Color(color.r, color.g, color.b, 0.22))
		draw_rect(rect, color, false, 3.0)
	var core_rect := _cell_rect(placement.hover_core, origin, tile).grow(-7)
	draw_rect(core_rect, color, false, 5.0)


func _draw_core_marker(
	cell: Vector2i, type: GameEnums.BuildingType, origin: Vector2, tile: float, color: Color
) -> void:
	var rect := _cell_rect(cell, origin, tile).grow(-tile * 0.22)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.88))
	draw_rect(rect, GOLD, false, 2.0)
	var label: String = BUILDING_LABELS.get(type, "?")
	var font := get_theme_default_font()
	var font_size := maxi(16, floori(tile * 0.3))
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := rect.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.34)
	draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _draw_coordinates(origin: Vector2, tile: float, board_px: float) -> void:
	var font := get_theme_default_font()
	var font_size := maxi(13, floori(tile * 0.16))
	for x in range(BOARD_SIZE):
		var file := String.chr(65 + x)
		var width := font.get_string_size(file, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			Vector2(origin.x + x * tile + (tile - width) * 0.5, origin.y + board_px + 18),
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
	for candidate in units.values():
		if not (candidate is UnitState) or not is_inside(candidate.board_cell):
			continue
		_draw_piece(candidate, candidate.board_cell, origin, tile, false)

	for unit_id in planned_moves:
		var candidate := units.get(unit_id) as UnitState
		var planned_cell: Vector2i = planned_moves[unit_id]
		if candidate == null or not is_inside(planned_cell):
			continue
		_draw_piece(candidate, planned_cell, origin, tile, true)


func _draw_piece(
	unit: UnitState, cell: Vector2i, origin: Vector2, tile: float, ghost: bool
) -> void:
	var glyph: String = PIECE_GLYPHS.get(unit.rank, "♟")
	var font := get_theme_default_font()
	var font_size := maxi(34, floori(tile * 0.72))
	var glyph_size := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center := origin + Vector2(cell) * tile + Vector2(tile * 0.5, tile * 0.5)
	var baseline := center + Vector2(-glyph_size.x * 0.5, glyph_size.y * 0.34)
	var color := PLAYER_PIECE if unit.faction == GameEnums.Faction.PLAYER else ENEMY_PIECE
	if ghost:
		color = GHOST_TINT
		draw_circle(center, tile * 0.34, Color(0.27, 0.7, 0.92, 0.12))
		draw_arc(center, tile * 0.35, 0.0, TAU, 48, Color(0.55, 0.86, 1.0, 0.58), 2.0)
	else:
		draw_string(
			font,
			baseline + Vector2(2, 3),
			glyph,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0, 0, 0, 0.35)
		)
	draw_string(font, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _cell_rect(cell: Vector2i, origin: Vector2, tile: float) -> Rect2:
	return Rect2(origin + Vector2(cell) * tile, Vector2(tile, tile))


func _on_mouse_exited() -> void:
	cell_hovered.emit(Vector2i(-1, -1))
