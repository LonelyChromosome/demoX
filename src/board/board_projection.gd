class_name BoardProjection
extends RefCounted

const DEFAULT_SHEAR := 0.14
const DEFAULT_VERTICAL_SCALE := 0.82

var board_size := 8
var tile := 0.0
var board_px := 0.0
var transform := Transform2D.IDENTITY


static func fit(view_size: Vector2, grid_size := 8) -> BoardProjection:
	var projection := BoardProjection.new()
	projection.board_size = grid_size
	var available := Vector2(maxf(view_size.x - 112.0, 0.0), maxf(view_size.y - 118.0, 0.0))
	projection.tile = floorf(
		minf(
			available.x / (float(grid_size) * (1.0 + DEFAULT_SHEAR)),
			available.y / (float(grid_size) * DEFAULT_VERTICAL_SCALE)
		)
	)
	projection.board_px = projection.tile * grid_size
	var projected_size := Vector2(
		projection.board_px * (1.0 + DEFAULT_SHEAR), projection.board_px * DEFAULT_VERTICAL_SCALE
	)
	var offset := Vector2(
		floorf((view_size.x - projected_size.x) * 0.5),
		floorf((view_size.y - projected_size.y) * 0.5 - 3.0)
	)
	projection.transform = Transform2D(
		Vector2(1.0, 0.0), Vector2(DEFAULT_SHEAR, DEFAULT_VERTICAL_SCALE), offset
	)
	return projection


func plane_to_screen(point: Vector2) -> Vector2:
	return transform * point


func screen_to_plane(point: Vector2) -> Vector2:
	return transform.affine_inverse() * point


func grid_to_screen(grid_position: Vector2) -> Vector2:
	return plane_to_screen(grid_position * tile)


func screen_to_grid(point: Vector2) -> Vector2:
	if tile <= 0.0:
		return Vector2(-1.0, -1.0)
	return screen_to_plane(point) / tile


func cell_center(cell: Vector2i) -> Vector2:
	return grid_to_screen(Vector2(cell) + Vector2(0.5, 0.5))


func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var top_left := Vector2(cell) * tile
	return PackedVector2Array(
		[
			plane_to_screen(top_left),
			plane_to_screen(top_left + Vector2(tile, 0.0)),
			plane_to_screen(top_left + Vector2(tile, tile)),
			plane_to_screen(top_left + Vector2(0.0, tile)),
		]
	)


func board_polygon(expand := 0.0) -> PackedVector2Array:
	return PackedVector2Array(
		[
			plane_to_screen(Vector2(-expand, -expand)),
			plane_to_screen(Vector2(board_px + expand, -expand)),
			plane_to_screen(Vector2(board_px + expand, board_px + expand)),
			plane_to_screen(Vector2(-expand, board_px + expand)),
		]
	)


func gate_position() -> Vector2:
	return plane_to_screen(Vector2(board_px * 0.5, board_px + 19.0)) + Vector2(0.0, 8.0)