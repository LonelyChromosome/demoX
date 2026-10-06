class_name OutsideRail
extends PanelContainer

var state: GameState
var turn_manager: TurnManager
var content: VBoxContainer
var selected_units: Array[String] = []
var outside_system := OutsideSystem.new()
var world_system := WorldSystem.new()
var selected_target_region_id := ""
var selected_supply_food := 0


func _ready() -> void:
	custom_minimum_size = Vector2(240, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	Localization.watch(_on_language_changed)


func setup(game_state: GameState, manager: TurnManager) -> void:
	state = game_state
	turn_manager = manager
	turn_manager.order_queue.changed.connect(refresh)
	turn_manager.resolution_finished.connect(func(_result): refresh())
	refresh()


func refresh() -> void:
	if content == null or state == null:
		return
	for child in content.get_children():
		child.queue_free()
	var retained_units: Array[String] = []
	for unit_id in selected_units:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null and unit.can_be_moved() and unit.faction == GameEnums.Faction.PLAYER:
			retained_units.append(unit_id)
	selected_units = retained_units
	_add_title(Localization.text("outside.title"))
	_add_team_picker()
	_add_expeditions()
	_add_outsider_groups()


func _add_team_picker() -> void:
	var planned := turn_manager.get_planned_expedition()
	if planned != null:
		var planned_region := state.world_state.regions.get(planned.target_region_id) as RegionState
		_add_text(Localization.text("outside.planned_expedition", {
			"units": _unit_list(planned.unit_ids),
			"target": planned_region.name if planned_region != null else Localization.text("outside.near_city"),
			"food": planned.supplies_food,
		}))
		_add_button(Localization.text("outside.cancel_expedition"), func(): turn_manager.cancel_expedition())
		return
	_add_text(Localization.text("outside.choose_two"))
	var ids := state.units.keys()
	ids.sort()
	for unit_id in ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit == null or unit.faction != GameEnums.Faction.PLAYER or not unit.can_be_moved():
			continue
		var check := CheckButton.new()
		check.text = "%s %s" % [_glyph(unit.rank), _unit_name(unit)]
		check.button_pressed = unit.id in selected_units
		check.toggled.connect(_toggle_unit.bind(unit.id, check))
		content.add_child(check)
	_add_expedition_target_picker()
	var expedition_button := Button.new()
	expedition_button.text = Localization.text("outside.explore")
	expedition_button.disabled = selected_units.size() != ExpeditionSystem.TEAM_SIZE
	expedition_button.pressed.connect(_queue_expedition)
	content.add_child(expedition_button)


func _add_expeditions() -> void:
	var ids := state.expeditions.keys()
	ids.sort()
	for expedition_id in ids:
		var expedition := state.expeditions.get(expedition_id) as ExpeditionState
		if expedition == null or expedition.status == GameEnums.ExpeditionStatus.COMPLETE:
			continue
		_add_separator()
		_add_title(Localization.text("outside.expedition"))
		_add_text(_unit_list(expedition.unit_ids))
		var region := state.world_state.regions.get(expedition.target_region_id) as RegionState
		var status := Localization.text("outside.return_wait") if expedition.status == GameEnums.ExpeditionStatus.RETURN_PENDING else Localization.text("outside.day_status", {"day": expedition.elapsed_days + 1})
		_add_text(Localization.text("outside.expedition_detail", {
			"status": status,
			"target": region.name if region != null else Localization.text("outside.unknown_region"),
			"news": Localization.text("outside.no_news"),
		}))


func _add_outsider_groups() -> void:
	var ids := state.outsider_groups.keys()
	ids.sort()
	for group_id in ids:
		var group := state.outsider_groups.get(group_id) as OutsiderGroupState
		if group == null:
			continue
		_add_separator()
		_add_title(group.name.to_upper())
		_add_text(Localization.text("outside.group_detail", {
			"pieces": _group_glyphs(group),
			"people": Localization.text("outside.people", {"count": group.member_count()}),
			"status": Localization.text("outside.status", {"status": outside_system.pressure_label(group)}),
		}))
		var region := state.world_state.regions.get(group.region_id) as RegionState
		if region != null:
			_add_text(Localization.text("outside.location", {"region": region.name}))
		if group.is_resettling() or group.resettlement_complete:
			_add_text(Localization.text("outside.resettling", {"days": group.resettlement_days_left}))
			continue
		_add_text(
			Localization.text("outside.supported", {"food": group.member_count()})
			if group.support_active else Localization.text("outside.unsupported")
		)
		var planned := turn_manager.get_planned_outsider_action(group.id)
		if planned != null:
			_add_text(Localization.text("outside.planned", {"action": _outside_action_name(planned.action)}))
			_add_button(Localization.text("outside.cancel_decision"), _cancel_group_action.bind(group.id))
			continue
		if group.support_active:
			_add_button(
				Localization.text("outside.stop_support"),
				_queue_group_action.bind(group.id, GameEnums.OutsiderAction.STOP_SUPPORT)
			)
		else:
			_add_button(
				Localization.text("outside.support"),
				_queue_group_action.bind(group.id, GameEnums.OutsiderAction.START_SUPPORT)
			)
		if not group.trade_offer.is_empty():
			_add_text(Localization.text("outside.trade_offer"))
			_add_button(
				Localization.text("outside.accept_trade"),
				_queue_group_action.bind(group.id, GameEnums.OutsiderAction.ACCEPT_TRADE)
			)
			_add_button(
				Localization.text("outside.reject_trade"),
				_queue_group_action.bind(group.id, GameEnums.OutsiderAction.REJECT_TRADE)
			)
		var resettle := Button.new()
		resettle.text = Localization.text("outside.resettle")
		resettle.disabled = selected_units.size() != OutsideSystem.ESCORT_COUNT
		resettle.pressed.connect(_queue_resettlement.bind(group.id))
		content.add_child(resettle)


func _queue_group_action(group_id: String, action: GameEnums.OutsiderAction) -> void:
	turn_manager.queue_outsider_action(group_id, action)


func _cancel_group_action(group_id: String) -> void:
	turn_manager.cancel_outsider_action(group_id)


func _queue_resettlement(group_id: String) -> void:
	turn_manager.queue_outsider_action(
		group_id, GameEnums.OutsiderAction.RESETTLE, selected_units.duplicate()
	)
	selected_units.clear()


func _toggle_unit(enabled: bool, unit_id: String, check: CheckButton) -> void:
	if enabled and selected_units.size() >= ExpeditionSystem.TEAM_SIZE:
		check.set_pressed_no_signal(false)
		return
	if enabled:
		selected_units.append(unit_id)
	else:
		selected_units.erase(unit_id)
	refresh()


func _queue_expedition() -> void:
	var team := selected_units.duplicate()
	selected_units.clear()
	turn_manager.queue_expedition(team, selected_target_region_id, selected_supply_food)


func _add_expedition_target_picker() -> void:
	var world := world_system.ensure_initialized(state)
	var selector := OptionButton.new()
	selector.tooltip_text = Localization.text("outside.select_region")
	var target_ids: Array[String] = []
	for region_id in world.known_regions:
		if region_id != WorldSystem.CITY_REGION_ID:
			target_ids.append(region_id)
	target_ids.sort()
	for region_id in target_ids:
		var region := world.regions.get(region_id) as RegionState
		if region == null:
			continue
		selector.add_item(region.name + ("" if region.discovered else " · " + Localization.text("outside.not_explored")))
		selector.set_item_metadata(selector.item_count - 1, region.id)
	if selector.item_count > 0:
		if selected_target_region_id.is_empty():
			selected_target_region_id = selector.get_item_metadata(0)
		for index in range(selector.item_count):
			if selector.get_item_metadata(index) == selected_target_region_id:
				selector.select(index)
		selector.item_selected.connect(func(index: int):
			selected_target_region_id = selector.get_item_metadata(index)
		)
	content.add_child(selector)
	var supply := SpinBox.new()
	supply.min_value = 0
	supply.max_value = mini(2, state.food)
	supply.step = 1
	supply.value = mini(selected_supply_food, int(supply.max_value))
	supply.prefix = Localization.text("outside.supply_prefix")
	supply.value_changed.connect(func(value: float): selected_supply_food = int(value))
	content.add_child(supply)


func _add_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	content.add_child(label)


func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)


func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	content.add_child(button)


func _add_separator() -> void:
	content.add_child(HSeparator.new())


func _unit_list(unit_ids: Array[String]) -> String:
	var lines: Array[String] = []
	for unit_id in unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			lines.append("%s %s" % [_glyph(unit.rank), _unit_name(unit)])
	return "\n".join(lines)


func _group_glyphs(group: OutsiderGroupState) -> String:
	var counts := {}
	for unit_id in group.member_unit_ids:
		var unit := state.units.get(unit_id) as UnitState
		if unit != null:
			counts[unit.rank] = int(counts.get(unit.rank, 0)) + 1
	var labels: Array[String] = []
	var ranks := counts.keys()
	ranks.sort()
	for rank in ranks:
		labels.append("%s ×%d" % [_glyph(rank), counts[rank]])
	return " · ".join(labels)


func _outside_action_name(action: GameEnums.OutsiderAction) -> String:
	return Localization.text([
		"outside.action.support", "outside.action.stop_support", "outside.action.accept_trade",
		"outside.action.reject_trade", "outside.action.resettle",
	][action])


func _unit_name(unit: UnitState) -> String:
	return unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank)


func _rank_name(rank: int) -> String:
	return LocalizationKeys.rank_name(rank)


func _glyph(rank: int) -> String:
	return ["♟", "♞", "♜", "♝", "♛", "♚"][rank]


func _on_language_changed(_locale: String) -> void:
	refresh()


func _exit_tree() -> void:
	Localization.unwatch(_on_language_changed)
