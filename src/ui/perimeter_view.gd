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
const ZONE_TITLES := {
	"refugee": "KHU TỊ NẠN",
	"forest": "RỪNG NGOẠI VI",
	"wasteland": "ĐẤT HOANG",
}
const ZONE_COLORS := {
	"refugee": Color("a77d4f"),
	"forest": Color("426958"),
	"wasteland": Color("7e6750"),
}

var state: GameState
var turn_manager: TurnManager
var layout := PerimeterLayout.new()
var board: BoardView
var snapshot: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_board)
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
			"title": ZONE_TITLES[zone_id],
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
	zone.status = "Không có nhóm đang chờ" if statuses.is_empty() else " · ".join(statuses)


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
	zone.status = "Yên tĩnh" if statuses.is_empty() else " · ".join(statuses)


func _populate_wasteland(zone: Dictionary, rendered: Dictionary) -> void:
	var project := state.wasteland
	if project.active:
		zone.status = "Đang khai phá · còn %d ngày" % project.days_left
		zone.progress = 1.0 - float(project.days_left) / maxf(1.0, project.duration_days)
	elif project.completed:
		zone.status = "Hoàn tất · sẵn sàng tái định cư"
		zone.progress = 1.0
	else:
		zone.status = "Chưa khai phá"
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
		return "tái định cư %d ngày" % group.resettlement_days_left
	if group.support_active and not group.support_unmet:
		return "được hỗ trợ"
	return ["ổn định", "bất an", "căng thẳng", "hỗn loạn"][group.pressure]


func _expedition_status(expedition: ExpeditionState) -> String:
	if expedition.status == GameEnums.ExpeditionStatus.RETURN_PENDING:
		return "chờ chỗ trở về"
	if expedition.days_left <= 0:
		return "đang trở về"
	return "thám hiểm · còn %d ngày" % expedition.days_left


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
	var center := Rect2(Vector2(size.x * 0.23, 54.0), Vector2(size.x * 0.54, size.y - 146.0))
	draw_rect(center, Color(0.12, 0.14, 0.14, 0.42))
	draw_rect(center, Color(0.58, 0.49, 0.31, 0.42), false, 1.5)
	var font := get_theme_default_font()
	draw_string(
		font, Vector2(center.get_center().x - 42.0, 73.0), "NỘI THÀNH",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.77, 0.72, 0.58, 0.62)
	)


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
		draw_polyline(path, Color(0.43, 0.37, 0.28, 0.50), 9.0, true)
		draw_polyline(path, Color(0.72, 0.63, 0.45, 0.36), 2.0, true)


func _draw_zone(zone_id: String, zone: Dictionary) -> void:
	var rect := zone_rect_for(zone_id)
	var color: Color = ZONE_COLORS[zone_id]
	draw_rect(rect, Color(color.r, color.g, color.b, 0.20))
	draw_rect(rect, Color(color.r, color.g, color.b, 0.72), false, 1.5)
	_draw_scenery(zone_id, rect, color)
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


func _draw_scenery(zone_id: String, rect: Rect2, color: Color) -> void:
	if zone_id == "forest":
		for index in range(4):
			var x := rect.position.x + 18.0 + index * (rect.size.x - 36.0) / 3.0
			draw_line(
				Vector2(x, rect.end.y - 12.0),
				Vector2(x, rect.end.y - 36.0),
				Color(color, 0.34),
				3.0
			)
			draw_circle(Vector2(x, rect.end.y - 42.0), 11.0, Color(color, 0.24))
	elif zone_id == "refugee":
		draw_polyline(PackedVector2Array([
			rect.position + Vector2(12.0, rect.size.y - 16.0),
			rect.position + Vector2(rect.size.x * 0.5, rect.size.y - 42.0),
			rect.end - Vector2(12.0, 16.0),
		]), Color(color, 0.32), 2.0)
	else:
		for index in range(3):
			var y := rect.end.y - 18.0 - index * 9.0
			draw_line(
				Vector2(rect.position.x + 12.0, y),
				Vector2(rect.end.x - 12.0, y - 3.0),
				Color(color, 0.26),
				1.5
			)


func _draw_zone_pieces(rect: Rect2, pieces: Array) -> void:
	var font := get_theme_default_font()
	var shown := mini(5, pieces.size())
	for index in range(shown):
		var glyph := str(pieces[index].get("glyph", "♟"))
		var step := minf(28.0, (rect.size.x - 30.0) / 5.0)
		var x := rect.position.x + 12.0 + index * step
		draw_string(
			font, Vector2(x, rect.position.y + 72.0), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("f2ead8")
		)
	if pieces.size() > shown:
		draw_string(
			font, rect.position + Vector2(rect.size.x - 38.0, 71.0), "×%d" % pieces.size(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e8dfca")
		)
