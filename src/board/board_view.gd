class_name BoardView
extends Control

signal cell_clicked(cell: Vector2i)

const BOARD_SIZE := 8
const LIGHT := Color("cdbb91")
const DARK := Color("5d584d")
const BORDER := Color("211f1c")

var selected_cell := Vector2i(-1, -1)
var ghost_cells: Array[Vector2i] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := screen_to_cell(event.position)
		if is_inside(cell):
			selected_cell = cell
			cell_clicked.emit(cell)
			queue_redraw()

func screen_to_cell(local_pos: Vector2) -> Vector2i:
	var tile := min(size.x, size.y) / float(BOARD_SIZE)
	var origin := Vector2((size.x - tile * BOARD_SIZE) * 0.5, (size.y - tile * BOARD_SIZE) * 0.5)
	var p := local_pos - origin
	return Vector2i(floori(p.x / tile), floori(p.y / tile))

func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < BOARD_SIZE and cell.y < BOARD_SIZE

func _draw() -> void:
	var tile := min(size.x, size.y) / float(BOARD_SIZE)
	var board_px := tile * BOARD_SIZE
	var origin := Vector2((size.x - board_px) * 0.5, (size.y - board_px) * 0.5)
	draw_rect(Rect2(origin - Vector2(5, 5), Vector2(board_px + 10, board_px + 10)), BORDER)

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var rect := Rect2(origin + Vector2(x, y) * tile, Vector2(tile, tile))
			draw_rect(rect, LIGHT if (x + y) % 2 == 0 else DARK)
			var cell := Vector2i(x, y)
			if cell == selected_cell:
				draw_rect(rect.grow(-4), Color(1, 1, 1, 0.22), false, 3.0)
			elif cell in ghost_cells:
				draw_rect(rect.grow(-5), Color(0.7, 0.85, 1.0, 0.2), true)
