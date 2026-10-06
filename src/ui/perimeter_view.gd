class_name PerimeterView
extends Control

const ZONE_IDS: Array[String] = ["refugee", "forest", "wasteland"]
const PIECE_GLYPHS := {
	GameEnums.Rank.PAWN: "♟",
	GameEnums.Rank.KNIGHT: "♞",
	GameEnums.Rank.ROOK: "♜",
	GameEnums.Rank.BISHOP: "♝",
	GameEnums.Rank.QUEEN: "♛",
	GameEnums.Rank.KING: "♚",
}
const ZONE_TITLE_KEYS := {
	"refugee": "perimeter.refugee",
	"forest": "perimeter.forest",
	"wasteland": "perimeter.wasteland",
}
const ZONE_COLORS := {
	"refugee": Color("a89b70"),
	"forest": Color("66825b"),
	"wasteland": Color("a09372"),
}

var state: GameState
var turn_manager: TurnManager
var layout := PerimeterLayout.new()
var board: BoardView
var snapshot: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_board)
	Localization.watch(_on_language_changed)
	var ambience := PerimeterAmbience.new()
	ambience.perimeter = self
	ambience.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ambience)
	queue_redraw()


func attach_board(board_view: BoardView) -> void:
	board = board_view
	add_child(board)
	_layout_board()


func setup(game_state: GameState, manager: TurnManager = null) -> void:
	state = game_state
	turn_manager = manager
	layout = state.perimeter_layout if state != null else PerimeterLayout.new()
	if turn_manager != null:
		turn_manager.order_queue.changed.connect(refresh)
		turn_manager.resolution_finished.connect(func(_result): refresh())
		turn_manager.day_started.connect(func(_day): refresh())
	refresh()


func refresh() -> void:
	snapshot = build_snapshot()
	queue_redraw()


func build_snapshot() -> Dictionary:
	var zones := {}
	for zone_id in ZONE_IDS:
		zones[zone_id] = {
			"id": zone_id,
			"anchor": layout.anchor_for(zone_id),
			"title": Localization.text(ZONE_TITLE_KEYS[zone_id]),
			"status": "",
			"pieces": [],
			"count": 0,
			"progress": -1.0,
		}
	if state == null:
		return zones
	var rendered := {}
	_populate_refugees(zones.refugee, rendered)
	_populate_forest(zones.forest, rendered)
	_populate_wasteland(zones.wasteland, rendered)
	return zones


func rendered_unit_ids() -> Array[String]:
	var ids: Array[String] = []
	for zone_id in ZONE_IDS:
		var zone: Dictionary = snapshot.get(zone_id, {})
		for piece in zone.get("pieces", []):
			var unit_id := str(piece.get("unit_id", ""))
			if not unit_id.is_empty() and unit_id not in ids:
				ids.append(unit_id)
	return ids


func slot_index_for(zone_id: String) -> int:
	var semantic_order: Array[String] = layout.slot_order
	var index := semantic_order.find(zone_id)
	if index >= 0:
		return index
	var anchor := layout.anchor_for(zone_id)
	for slot_index in range(semantic_order.size()):
		if layout.anchor_for(semantic_order[slot_index]) == anchor:
			return slot_index
	return ZONE_IDS.find(zone_id)


func zone_rect_for(zone_id: String) -> Rect2:
	var margin := 10.0
	var side_width := clampf(size.x * 0.18, 126.0, 168.0)
	var bottom_height := clampf(size.y * 0.16, 82.0, 112.0)
	var slot_rects := [
		Rect2(margin, 92.0, side_width, maxf(180.0, size.y - bottom_height - 116.0)),
		Rect2(
			size.x - side_width - margin,
			92.0,
			side_width,
			maxf(180.0, size.y - bottom_height - 116.0)
		),
		Rect2(
			side_width + 24.0,
			size.y - bottom_height - margin,
			maxf(220.0, size.x - side_width * 2.0 - 48.0),
			bottom_height
		),
	]
	return slot_rects[clampi(slot_index_for(zone_id), 0, slot_rects.size() - 1)]


func _populate_refugees(zone: Dictionary, rendered: Dictionary) -> void:
	var statuses: Array[String] = []
	var group_ids := state.outsider_groups.keys()
	group_ids.sort()
	for group_id in group_ids:
		var group := state.outsider_groups.get(group_id) as OutsiderGroupState
		if group == null:
			continue
		statuses.append(_refugee_status(group))
		for unit_id in group.member_unit_ids:
			var member := state.units.get(unit_id) as UnitState
			if member == null or member.faction != GameEnums.Faction.OUTSIDER:
				continue
			_add_piece(zone, rendered, member, GameEnums.Rank.PAWN, "refugee")
		for escort_id in group.escort_unit_ids:
			var escort := state.units.get(escort_id) as UnitState
			if escort == null or escort.away_reason != "resettlement":
				continue
			_add_piece(zone, rendered, escort, escort.rank, "escort")
	zone.count = zone.pieces.size()
	zone.status = Localization.text("perimeter.no_refugees") if statuses.is_empty() else " · ".join(statuses)


func _populate_forest(zone: Dictionary, rendered: Dictionary) -> void:
	var statuses: Array[String] = []
	var expedition_ids := state.expeditions.keys()
	expedition_ids.sort()
	for expedition_id in expedition_ids:
		var expedition := state.expeditions.get(expedition_id) as ExpeditionState
		if expedition == null or expedition.status == GameEnums.ExpeditionStatus.COMPLETE:
			continue
		statuses.append(_expedition_status(expedition))
		for unit_id in expedition.unit_ids:
			var unit := state.units.get(unit_id) as UnitState
			if (
				unit == null
				or unit.faction != GameEnums.Faction.PLAYER
				or unit.rank == GameEnums.Rank.KING
				or unit.away_assignment_id != expedition.id
			):
				continue
			_add_piece(zone, rendered, unit, unit.rank, "expedition")
	zone.count = zone.pieces.size()
	zone.status = Localization.text("perimeter.quiet") if statuses.is_empty() else " · ".join(statuses)


func _populate_wasteland(zone: Dictionary, rendered: Dictionary) -> void:
	var project := state.wasteland
	if project.active:
		zone.status = Localization.text("perimeter.developing", {"days": project.days_left})
		zone.progress = 1.0 - float(project.days_left) / maxf(1.0, project.duration_days)
	elif project.completed:
		zone.status = Localization.text("perimeter.complete")
		zone.progress = 1.0
	else:
		zone.status = Localization.text("perimeter.not_started")
	for unit_id in project.participant_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if (
			unit == null
			or unit.faction != GameEnums.Faction.PLAYER
			or unit.rank == GameEnums.Rank.KING
			or unit.away_reason != "wasteland"
		):
			continue
		_add_piece(zone, rendered, unit, unit.rank, "development")
	zone.count = zone.pieces.size()


func _add_piece(
	zone: Dictionary, rendered: Dictionary, unit: UnitState, visual_rank: int, role: String
) -> void:
	if unit.rank == GameEnums.Rank.KING or _is_board_cell(unit.board_cell) or rendered.has(unit.id):
		return
	rendered[unit.id] = true
	zone.pieces.append({
		"unit_id": unit.id,
		"rank": visual_rank,
		"glyph": PIECE_GLYPHS.get(visual_rank, "♟"),
		"role": role,
	})


func _is_board_cell(cell: Vector2i) -> bool:
	return (
		cell.x >= 0 and cell.y >= 0
		and cell.x < BoardView.BOARD_SIZE and cell.y < BoardView.BOARD_SIZE
	)


func _refugee_status(group: OutsiderGroupState) -> String:
	if group.is_resettling():
		return Localization.text("perimeter.resettling", {"days": group.resettlement_days_left})
	if group.support_active and not group.support_unmet:
		return Localization.text("perimeter.supported")
	return Localization.text([
		"perimeter.stable", "perimeter.uneasy", "perimeter.tense", "perimeter.chaos",
	][group.pressure])


func _expedition_status(expedition: ExpeditionState) -> String:
	if expedition.status == GameEnums.ExpeditionStatus.RETURN_PENDING:
		return Localization.text("outside.return_wait")
	if expedition.days_left <= 0:
		return Localization.text("perimeter.returning")
	return Localization.text("perimeter.exploring", {"days": expedition.days_left})


func _layout_board() -> void:
	if board == null:
		return
	var side_margin := clampf(size.x * 0.18, 126.0, 168.0)
	board.position = Vector2(side_margin - 14.0, 44.0)
	board.size = Vector2(
		maxf(360.0, size.x - side_margin * 2.0 + 28.0),
		maxf(360.0, size.y - 116.0)
	)
	queue_redraw()


func _draw() -> void:
	_draw_city_frame()
	_draw_routes()
	for zone_id in ZONE_IDS:
		_draw_zone(zone_id, snapshot.get(zone_id, {}))


func _draw_city_frame() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("7d8963"))
	for index in range(14):
		var strip := Rect2(0, float(index) / 14.0 * size.y, size.x, size.y / 14.0 + 1)
		draw_rect(strip, Color(0.91, 0.86, 0.63, 0.16 * (1.0 - float(index) / 14.0)))
	# Low distant ridges frame the city without crossing the playable plane.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 70), Vector2(size.x * 0.12, 22), Vector2(size.x * 0.3, 59),
		Vector2(size.x * 0.54, 9), Vector2(size.x * 0.78, 53), Vector2(size.x, 16),
		Vector2(size.x, 0), Vector2.ZERO,
	]), Color("a5af88"))
	for index in range(26):
		var x := float(index) / 25.0 * size.x
		var y := 49.0 + sin(index * 1.3) * 14.0
		DioramaArt.tree(self, Vector2(x, y), 0.5 + float(index % 3) * 0.12, index)
	# A soft upper-left haze separates distant scenery from the city.
	DioramaArt.ellipse(self, Vector2(size.x * 0.3, 28), Vector2(size.x * 0.42, 34), Color(0.95, 0.9, 0.72, 0.1))


func _on_language_changed(_locale: String) -> void:
	refresh()


func _exit_tree() -> void:
	Localization.unwatch(_on_language_changed)


func route_segments() -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	if board == null:
		return routes
	var gate := board.position + board.gate_local_position()
	for zone_id in ZONE_IDS:
		var rect := zone_rect_for(zone_id)
		var destination := rect.get_center()
		if absf(destination.x - gate.x) > absf(destination.y - gate.y):
			destination.x = rect.end.x if destination.x < gate.x else rect.position.x
		else:
			destination.y = rect.end.y if destination.y < gate.y else rect.position.y
		routes.append({
			"zone_id": zone_id,
			"from_anchor": layout.anchor_for("gate"),
			"to_anchor": layout.anchor_for(zone_id),
			"from": gate,
			"to": destination,
		})
	return routes


func _draw_routes() -> void:
	for route in route_segments():
		var start: Vector2 = route.from
		var finish: Vector2 = route.to
		var bend := Vector2(start.x, finish.y) if absf(finish.y - start.y) < 80.0 else Vector2(finish.x, start.y)
		var path := PackedVector2Array([start, start.lerp(bend, 0.55), bend, finish])
		draw_polyline(path, Color("73704e"), 19.0, true)
		draw_polyline(path, Color("bea77d"), 13.0, true)
		draw_polyline(path, Color(0.89, 0.79, 0.6, 0.55), 3.0, true)


func _draw_zone(zone_id: String, zone: Dictionary) -> void:
	var rect := zone_rect_for(zone_id)
	var color: Color = ZONE_COLORS[zone_id]
	var terrain := PackedVector2Array()
	for index in range(28):
		var angle := TAU * float(index) / 28.0
		var irregularity := 0.93 + 0.06 * sin(index * 2.7)
		terrain.append(rect.get_center() + Vector2(cos(angle), sin(angle)) * rect.size * 0.53 * irregularity)
	draw_colored_polygon(terrain, color)
	_draw_scenery(zone_id, rect, color)
	# Compact signpost; the zone itself is terrain, not a panel.
	draw_style_box(_zone_sign(), Rect2(rect.position + Vector2(3, 0), Vector2(rect.size.x - 6, 48)))
	var font := get_theme_default_font()
	draw_string(
		font, rect.position + Vector2(10.0, 21.0), str(zone.get("title", "")),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 13, Color("e8dfca")
	)
	var status := str(zone.get("status", ""))
	draw_string(
		font, rect.position + Vector2(10.0, 40.0), status,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 11, Color(0.86, 0.86, 0.82, 0.82)
	)
	_draw_zone_pieces(rect, zone.get("pieces", []))
	var progress := float(zone.get("progress", -1.0))
	if progress >= 0.0:
		var track := Rect2(
			rect.position + Vector2(10.0, rect.size.y - 14.0),
			Vector2(rect.size.x - 20.0, 5.0)
		)
		draw_rect(track, Color(0.08, 0.09, 0.09, 0.72))
		var fill_width := track.size.x * clampf(progress, 0.0, 1.0)
		draw_rect(
			Rect2(track.position, Vector2(fill_width, track.size.y)),
			color.lightened(0.28)
		)


func _zone_sign() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.19, 0.25, 0.19, 0.9)
	style.border_color = Color("b69d67")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


func _draw_scenery(zone_id: String, rect: Rect2, _color: Color) -> void:
	var tall := rect.size.y > 150.0
	var rows := 5 if tall else 1
	for row in range(rows):
		for column in range(3):
			var point := rect.position + Vector2(
				22 + float(column) / 2.0 * (rect.size.x - 44),
				lerpf(110.0 if tall else 80.0, rect.size.y - 20, float(row + 1) / rows)
			)
			point += Vector2(sin(row * 4 + column * 2) * 7, sin(column * 3) * 6)
			if zone_id == "forest":
				DioramaArt.tree(self, point, 0.8 + float((row + column) % 3) * 0.15, row + column)
				DioramaArt.rock(self, point + Vector2(10, 5), 0.45)
			elif zone_id == "refugee":
				if row % 2 == 0 and column != 1:
					DioramaArt.tent(self, point, 0.75 if tall else 0.65)
			else:
				DioramaArt.rock(self, point, 0.9 + column * 0.15)
				if row % 2 == 0:
					draw_line(point + Vector2(-9, -2), point + Vector2(14, -7), Color("7f7256"), 4)
					for stone in range(3):
						draw_rect(Rect2(point + Vector2(stone * 5 - 5, -18), Vector2(6, 10)), Color("c3b291"))
			# Sparse grass clumps share the terrain palette, never the cell palette.
			var grass := point + Vector2(-15, 8)
			draw_line(grass, grass + Vector2(-3, -5), Color("87935d"), 1)
			draw_line(grass, grass + Vector2(2, -7), Color("a4aa70"), 1)
	if zone_id == "wasteland" and float(snapshot.get(zone_id, {}).get("progress", -1.0)) >= 0:
		var point := rect.get_center() + Vector2(0, 15)
		draw_line(point + Vector2(-17, 12), point + Vector2(-17, -8), Color("786d4d"), 3)
		draw_line(point + Vector2(17, 12), point + Vector2(17, -8), Color("786d4d"), 3)
		draw_line(point + Vector2(-20, -6), point + Vector2(20, -6), Color("d4be89"), 3)


func _draw_zone_pieces(rect: Rect2, pieces: Array) -> void:
	var font := get_theme_default_font()
	var shown := mini(5, pieces.size())
	for index in range(shown):
		var glyph := str(pieces[index].get("glyph", "♟"))
		var step := minf(28.0, (rect.size.x - 30.0) / 5.0)
		var x := rect.position.x + 12.0 + index * step
		DioramaArt.ellipse(self, Vector2(x + 11, rect.position.y + 73), Vector2(11, 4), Color(0.15, 0.18, 0.12, 0.4))
		draw_string_outline(font, Vector2(x, rect.position.y + 72), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 2, Color("46523f"))
		draw_string(
			font, Vector2(x, rect.position.y + 72.0), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f2ead8")
		)
	if pieces.size() > shown:
		draw_string(
			font, rect.position + Vector2(rect.size.x - 38.0, 71.0), "×%d" % pieces.size(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e8dfca")
		)
