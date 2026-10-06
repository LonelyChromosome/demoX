class_name DioramaArt
extends RefCounted

# Small vector scenery, with no simulation state or gameplay coordinates.
static func ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(20):
		var angle := float(index) / 20.0 * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_colored_polygon(points, color)


static func tree(canvas: CanvasItem, base: Vector2, scale_value: float, variant: int) -> void:
	ellipse(canvas, base + Vector2(6, 3) * scale_value, Vector2(15, 6) * scale_value, Color(0.15, 0.24, 0.13, 0.32))
	canvas.draw_line(base, base + Vector2(0, -25) * scale_value, Color("766346"), 4 * scale_value)
	var crown := base + Vector2(0, -26) * scale_value
	var greens := [Color("41654c"), Color("517d50"), Color("618359")]
	canvas.draw_circle(crown + Vector2(4, 2) * scale_value, 16 * scale_value, greens[variant % 3].darkened(0.15))
	canvas.draw_circle(crown + Vector2(-6, -3) * scale_value, 13 * scale_value, greens[variant % 3])
	canvas.draw_circle(crown + Vector2(-5, -9) * scale_value, 9 * scale_value, greens[variant % 3].lightened(0.17))


static func rock(canvas: CanvasItem, base: Vector2, scale_value: float) -> void:
	ellipse(canvas, base + Vector2(3, 2), Vector2(10, 4) * scale_value, Color(0.2, 0.23, 0.16, 0.24))
	canvas.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-9, 0) * scale_value, base + Vector2(-5, -9) * scale_value,
		base + Vector2(4, -11) * scale_value, base + Vector2(9, -3) * scale_value,
		base + Vector2(6, 3) * scale_value,
	]), Color("aba58a"))
	canvas.draw_line(base + Vector2(-5, -9) * scale_value, base + Vector2(4, -11) * scale_value, Color("d0c6a5"), 2)


static func tent(canvas: CanvasItem, base: Vector2, scale_value: float) -> void:
	ellipse(canvas, base + Vector2(4, 4), Vector2(26, 7) * scale_value, Color(0.22, 0.22, 0.14, 0.3))
	canvas.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-24, 0) * scale_value, base + Vector2(-4, -30) * scale_value,
		base + Vector2(25, -8) * scale_value, base + Vector2(12, 5) * scale_value,
	]), Color("c7b18a"))
	canvas.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-24, 0) * scale_value, base + Vector2(-4, -30) * scale_value,
		base + Vector2(12, 5) * scale_value,
	]), Color("ecdcaf"))
	canvas.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-10, 2) * scale_value, base + Vector2(-4, -18) * scale_value,
		base + Vector2(3, 3) * scale_value,
	]), Color("69664b"))
	canvas.draw_line(base + Vector2(-4, -30) * scale_value, base + Vector2(25, -8) * scale_value, Color("f8e9c4"), 1.5)


static func building(canvas: CanvasItem, rect: Rect2, type: int, color: Color) -> void:
	var center := rect.get_center()
	var scale_value := rect.size.x / 48.0
	ellipse(canvas, center + Vector2(4, 14) * scale_value, Vector2(25, 10) * scale_value, Color(0.18, 0.19, 0.12, 0.28 * color.a))
	var wall := Rect2(center + Vector2(-19, -4) * scale_value, Vector2(38, 25) * scale_value)
	canvas.draw_rect(wall, Color(Color("d5bd92"), color.a))
	canvas.draw_rect(Rect2(wall.position, Vector2(7 * scale_value, wall.size.y)), Color(Color("efdbac"), color.a))
	canvas.draw_colored_polygon(PackedVector2Array([
		center + Vector2(-24, -4) * scale_value,
		center + Vector2(-3, -23) * scale_value,
		center + Vector2(25, -4) * scale_value,
	]), color)
	canvas.draw_line(center + Vector2(-24, -4) * scale_value, center + Vector2(-3, -23) * scale_value, color.lightened(0.25), 2)
	canvas.draw_rect(Rect2(center + Vector2(-4, 5) * scale_value, Vector2(8, 16) * scale_value), Color(Color("5d5947"), color.a))
	if type == GameEnums.BuildingType.INFIRMARY:
		canvas.draw_line(center + Vector2(9, 2) * scale_value, center + Vector2(9, 12) * scale_value, Color(Color("f5f0d9"), color.a), 3 * scale_value)
		canvas.draw_line(center + Vector2(4, 7) * scale_value, center + Vector2(14, 7) * scale_value, Color(Color("f5f0d9"), color.a), 3 * scale_value)
	elif type == GameEnums.BuildingType.FARM:
		for index in range(3):
			var start := center + Vector2(-20 + index * 7, 15) * scale_value
			canvas.draw_line(start, start + Vector2(4, -7) * scale_value, Color(Color("8a9a50"), color.a), 2 * scale_value)
	elif type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
		canvas.draw_rect(Rect2(center + Vector2(9, -23) * scale_value, Vector2(6, 17) * scale_value), Color(Color("8b765b"), color.a))
	elif type == GameEnums.BuildingType.PRISON:
		for index in range(3):
			var start := center + Vector2(8 + index * 3, 3) * scale_value
			canvas.draw_line(start, start + Vector2(0, 10) * scale_value, Color(Color("666957"), color.a), scale_value)
	else:
		canvas.draw_line(center + Vector2(12, -16) * scale_value, center + Vector2(12, -31) * scale_value, Color(Color("7c6544"), color.a), scale_value)
		canvas.draw_rect(Rect2(center + Vector2(12, -30) * scale_value, Vector2(10, 6) * scale_value), Color(Color("345e79"), color.a))
