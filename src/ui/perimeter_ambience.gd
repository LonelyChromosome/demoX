class_name PerimeterAmbience
extends Control

var perimeter: PerimeterView
var elapsed := 0.0
var frame_accumulator := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	elapsed += delta
	frame_accumulator += delta
	if frame_accumulator >= 0.1:
		frame_accumulator = 0.0
		queue_redraw()


func _draw() -> void:
	if perimeter == null or not is_visible_in_tree():
		return
	var forest := perimeter.zone_rect_for("forest")
	for index in range(4):
		var progress := fmod(elapsed * 0.035 + index * 0.24, 1.0)
		var point := forest.position + Vector2(
			forest.size.x * (0.25 + index * 0.16) + sin(elapsed * 0.6 + index) * 8,
			78 + progress * maxf(10, forest.size.y - 96)
		)
		draw_line(point, point + Vector2(3, -2), Color(0.87, 0.79, 0.42, sin(progress * PI) * 0.55), 2)
	var refugee: Dictionary = perimeter.snapshot.get("refugee", {})
	if int(refugee.get("count", 0)) == 0:
		return
	var camp := perimeter.zone_rect_for("refugee")
	var fire := camp.position + Vector2(camp.size.x * 0.5, maxf(83, camp.size.y * 0.7))
	draw_circle(fire, 9, Color(0.97, 0.66, 0.23, 0.1))
	draw_circle(fire, 3 + sin(elapsed * 3) * 0.5, Color("deaa58"))
	for index in range(3):
		var progress := fmod(elapsed * 0.12 + index * 0.33, 1.0)
		var drift := Vector2(sin(progress * 3 + elapsed * 0.3) * 5, -progress * 25)
		draw_circle(fire + drift, 2 + progress * 3, Color(0.84, 0.82, 0.69, (1 - progress) * 0.15))
