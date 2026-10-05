class_name WorldPanel
extends PanelContainer

var state: GameState
var turn_manager: TurnManager
var content: VBoxContainer
var world_system := WorldSystem.new()


func _ready() -> void:
	visible = false
	z_index = 28
	custom_minimum_size = Vector2(390, 500)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-410, 72)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "THẾ GIỚI NGOÀI THÀNH"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)


func setup(game_state: GameState, manager: TurnManager) -> void:
	state = game_state
	turn_manager = manager
	turn_manager.resolution_finished.connect(func(_result): refresh())
	refresh()


func open() -> void:
	refresh()
	visible = true


func close() -> void:
	visible = false


func refresh() -> void:
	if content == null or state == null:
		return
	for child in content.get_children():
		child.queue_free()
	var world := world_system.ensure_initialized(state)
	_add_text("Mùa %s · %s\nLương thực dài hạn: %s · Vật tư: %s" % [
		world_system.season_label(world.season),
		world_system.weather_label(world.weather),
		world_system.pressure_label(world.food_pressure),
		world_system.pressure_label(world.material_pressure),
	], Color("d9b86c"))
	_add_heading("KHU VỰC")
	var region_ids := world.known_regions.duplicate()
	region_ids.sort()
	for region_id in region_ids:
		if region_id == WorldSystem.CITY_REGION_ID:
			continue
		var region := world.regions.get(region_id) as RegionState
		if region == null:
			continue
		if not region.discovered:
			_add_text("%s\nĐã quan sát · Chưa khảo sát trực tiếp" % region.name)
			continue
		_add_text("%s\n%s · %s · Nguy cơ: %s" % [
			region.name,
			world_system.presence_label(region.presence),
			region.current_condition,
			_danger_label(region.danger),
		])
	_add_heading("TUYẾN ĐƯỜNG")
	var route_ids := world.routes.keys()
	route_ids.sort()
	for route_id in route_ids:
		var route := world.routes.get(route_id) as RouteState
		if route == null or not route.discovered:
			continue
		var destination := world.regions.get(route.to_region) as RegionState
		_add_text("Tới %s · %s" % [
			destination.name if destination != null else "vùng chưa rõ",
			world_system.route_safety_label(route.safety, route.blocked),
		])
	var known_factions: Array[FactionState] = []
	for candidate in world.factions.values():
		if candidate is FactionState and candidate.known:
			known_factions.append(candidate)
	if not known_factions.is_empty():
		_add_heading("DẤU VẾT PHE KHÁC")
		for faction in known_factions:
			_add_text("♟ %s · %s" % [faction.name, _relation_label(faction.relation)])
	if not world.recent_world_events.is_empty():
		_add_heading("TIN GẦN ĐÂY")
		var start := maxi(0, world.recent_world_events.size() - 4)
		for index in range(start, world.recent_world_events.size()):
			_add_text("• %s" % world.recent_world_events[index])


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("79d8a5"))
	content.add_child(label)


func _add_text(text: String, color := Color("d6d8da")) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	content.add_child(label)


func _danger_label(danger: int) -> String:
	if danger >= 4:
		return "Cao"
	if danger >= 2:
		return "Đáng lưu ý"
	return "Thấp"


func _relation_label(relation: int) -> String:
	if relation >= 2:
		return "Có thiện chí"
	if relation <= -2:
		return "Thù địch"
	return "Chưa rõ thái độ"


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
