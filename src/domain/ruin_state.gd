class_name RuinState
extends RefCounted

enum Status { BLOCKING, CLEANING, CLEARED }

var id := ""
var cells: Array[Vector2i] = []
var cleanup_seconds := 10.0
var cleanup_elapsed := 0.0
var material_reward := 1
var status: Status = Status.BLOCKING


func _init(ruin_id := "", occupied_cells: Array[Vector2i] = []) -> void:
	id = ruin_id
	cells = occupied_cells.duplicate()
	cleanup_seconds = 15.0 if cells.size() == 2 else 10.0


func progress() -> float:
	if cleanup_seconds <= 0.0:
		return 1.0
	return clampf(cleanup_elapsed / cleanup_seconds, 0.0, 1.0)


func occupies(cell: Vector2i) -> bool:
	return status != Status.CLEARED and cell in cells
