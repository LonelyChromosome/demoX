class_name InformationSystem
extends RefCounted

enum ReportQuality { VERY_LOW, LOW, MEDIUM, HIGH }

const HIGH_LOYALTY := 4
const MEDIUM_LOYALTY := 0
const LOW_LOYALTY := -3

var observed := ObservedState.new()
var food_system := FoodSystem.new()
var material_system := MaterialSystem.new()
var prison_system := PrisonSystem.new()


func initialize_day_one(state: GameState) -> void:
	if not state.day_one_full_knowledge:
		return
	for candidate in state.buildings.values():
		if candidate is BuildingState:
			observed.upsert(_exact_building_fact(
				state, candidate, 1, Localization.text("report.initial_observation"), ""
			))
	for candidate in state.units.values():
		if candidate is UnitState:
			observed.upsert(_exact_unit_fact(candidate, 1))


func resolve_daily_information(state: GameState, result: TurnResolutionResult) -> void:
	var entries: Array[ReportEntry] = []
	var updated_keys := {}
	_append_resource_entries(result, entries)
	_append_visible_events(result, entries)
	_append_role_changes(result, entries)
	_append_medical_prison_events(result, entries)
	_append_outside_events(result, entries)
	_append_progression_events(state, result, entries)
	_append_loyalty_events(state, result, entries)
	_append_social_events(result, entries)
	_append_world_events(result, entries)
	_append_perimeter_events(result, entries)
	_append_event_reports(result, entries)
	_update_visible_building_facts(state, result, updated_keys)
	for candidate in state.buildings.values():
		if not (candidate is BuildingState) or candidate.phase != GameEnums.BuildingPhase.ACTIVE:
			continue
		var source := state.units.get(candidate.manager_unit_id) as UnitState
		if source == null or source.faction != GameEnums.Faction.PLAYER:
			continue
		var fact := _reported_building_fact(state, candidate, source, result.resolved_day)
		if fact == null:
			continue
		observed.upsert(fact)
		updated_keys[fact.key] = true
		entries.append(_entry_for_building_fact(fact))
	for snapshot in result.inspection_snapshots:
		var inspected := _fact_from_inspection(snapshot, result.resolved_day)
		if inspected == null:
			continue
		if inspected.subject_id not in result.demolished_building_ids:
			observed.upsert(inspected)
			updated_keys[inspected.key] = true
			entries.append(ReportEntry.new(
				"Báo cáo kiểm tra %s đã được chuyển tới Vua." % _building_label(inspected),
				inspected.delivered_day,
				GameEnums.FactConfidence.CONFIRMED,
				inspected.source_label,
				inspected.key,
				GameEnums.AttentionLevel.IMPORTANT,
				"attention"
			))
	_append_stale_notices(state.day, updated_keys, entries)
	_append_rejections(result, entries)
	if entries.is_empty():
		entries.append(ReportEntry.new("Không có thông tin mới đáng chú ý.", result.resolved_day))
	result.report_entries = entries
	observed.set_daily_report(result.resolved_day, entries)
	_archive_report_entries(state, result.resolved_day, entries)


func _archive_report_entries(
	state: GameState, day: int, entries: Array[ReportEntry]
) -> void:
	var known := {}
	for archived in state.report_history:
		known["%s:%s:%s" % [archived.get("day", 0), archived.get("fact_key", ""), archived.get("text", "")]] = true
	for entry in entries:
		var key := "%s:%s:%s" % [day, entry.fact_key, entry.text]
		if known.has(key):
			continue
		known[key] = true
		state.report_history.append({
			"day": day,
			"text": entry.text,
			"source": entry.source_label,
			"fact_key": entry.fact_key,
			"attention": entry.attention_level,
			"confidence": entry.confidence,
		})


func building_detail(state: GameState, building: BuildingState) -> String:
	if building == null:
		return Localization.text("report.no_data")
	if state.day_one_full_knowledge:
		return _format_building_fact(
			_exact_building_fact(
				state, building, state.day, Localization.text("report.initial_observation"), ""
			), state.day
		)
	var fact := observed.get_fact(building_fact_key(building.id))
	if fact == null:
		return "%s · %s\n%s" % [
			_building_name(building.type), _phase_name(building.phase),
			Localization.text("report.no_internal"),
		]
	var visible_fact := fact.copy()
	visible_fact.values["type"] = building.type
	visible_fact.values["core_cell"] = building.core_cell
	visible_fact.values["phase"] = building.phase
	return _format_building_fact(visible_fact, state.day)


func unit_condition_detail(state: GameState, unit: UnitState) -> String:
	if unit == null:
		return Localization.text("report.no_data")
	if state.day_one_full_knowledge:
		return _format_unit_fact(_exact_unit_fact(unit, state.day), state.day)
	var fact := observed.get_fact(unit_fact_key(unit.id))
	if fact == null:
		return Localization.text("report.unit_no_internal")
	return _format_unit_fact(fact, state.day)


func get_building_fact(building_id: String) -> KnownFact:
	return observed.get_fact(building_fact_key(building_id))


func quality_for_loyalty(loyalty: int) -> ReportQuality:
	if loyalty >= HIGH_LOYALTY:
		return ReportQuality.HIGH
	if loyalty >= MEDIUM_LOYALTY:
		return ReportQuality.MEDIUM
	if loyalty >= LOW_LOYALTY:
		return ReportQuality.LOW
	return ReportQuality.VERY_LOW


func building_fact_key(building_id: String) -> String:
	return "building:%s" % building_id


func unit_fact_key(unit_id: String) -> String:
	return "unit:%s" % unit_id


func confidence_label(confidence: GameEnums.FactConfidence, stale: bool) -> String:
	if stale:
		return Localization.text("report.stale")
	if confidence == GameEnums.FactConfidence.CONFIRMED:
		return Localization.text("report.confirmed")
	if confidence == GameEnums.FactConfidence.REPORTED:
		return Localization.text("report.reported")
	return Localization.text("report.uncertain")


func _reported_building_fact(
	state: GameState, building: BuildingState, source: UnitState, day: int
) -> KnownFact:
	var quality := quality_for_loyalty(source.loyalty)
	if quality == ReportQuality.VERY_LOW and _stable_code(source.id, building.id, day) % 3 != 0:
		return null
	var fact := KnownFact.new(building_fact_key(building.id), building.id, "building")
	fact.observed_day = day
	fact.inspected_day = day
	fact.delivered_day = day
	fact.source_unit_id = source.id
	fact.source_label = _unit_name(source)
	fact.confidence = (
		GameEnums.FactConfidence.REPORTED
		if quality in [ReportQuality.HIGH, ReportQuality.MEDIUM]
		else GameEnums.FactConfidence.UNCERTAIN
	)
	fact.values = {
		"type": building.type,
		"core_cell": building.core_cell,
		"phase": building.phase,
	}
	var staff_count := _unique_staff_count(building)
	if quality == ReportQuality.HIGH:
		fact.values["days_left"] = building.days_left
		fact.values["builder_count"] = building.builder_unit_ids.size()
		fact.values["manager_name"] = _unit_name(source)
		fact.values["staff_count"] = staff_count
		fact.values["daily_output"] = _building_output(state, building)
		_add_special_building_values(state, building, fact.values, true)
	elif quality == ReportQuality.MEDIUM:
		fact.values["manager_name"] = _unit_name(source)
		fact.values["staff_count"] = staff_count
		_add_special_building_values(state, building, fact.values, false)
	else:
		var offset := -1 if _stable_code(building.id, source.id, day) % 2 == 0 else 1
		fact.values["staff_count"] = maxi(0, staff_count + offset)
	return fact


func _exact_building_fact(
	state: GameState, building: BuildingState, day: int, source_label: String, source_id: String
) -> KnownFact:
	var fact := KnownFact.new(building_fact_key(building.id), building.id, "building")
	fact.observed_day = day
	fact.inspected_day = day
	fact.delivered_day = day
	fact.source_label = source_label
	fact.source_unit_id = source_id
	fact.confidence = GameEnums.FactConfidence.CONFIRMED
	fact.values = {
		"type": building.type,
		"core_cell": building.core_cell,
		"phase": building.phase,
		"days_left": building.days_left,
		"builder_count": building.builder_unit_ids.size(),
		"manager_name": _unit_name(state.units.get(building.manager_unit_id) as UnitState),
		"staff_count": _unique_staff_count(building),
		"daily_output": _building_output(state, building),
	}
	_add_special_building_values(state, building, fact.values, true)
	return fact


func _exact_unit_fact(unit: UnitState, day: int) -> KnownFact:
	var fact := KnownFact.new(unit_fact_key(unit.id), unit.id, "unit")
	fact.observed_day = day
	fact.inspected_day = day
	fact.delivered_day = day
	fact.source_label = Localization.text("report.initial_observation")
	fact.confidence = GameEnums.FactConfidence.CONFIRMED
	fact.values = {
		"condition": _true_unit_condition(unit),
		"job": _true_unit_job(unit),
	}
	return fact


func _fact_from_inspection(snapshot: Dictionary, day: int) -> KnownFact:
	if snapshot.is_empty() or not snapshot.has("building_id"):
		return null
	var fact := KnownFact.new(
		building_fact_key(snapshot.building_id), snapshot.building_id, "building"
	)
	fact.observed_day = int(snapshot.get("inspected_day", day))
	fact.inspected_day = fact.observed_day
	fact.delivered_day = int(snapshot.get("delivered_day", day + 1))
	fact.category = str(snapshot.get("category", "building"))
	fact.source_unit_id = snapshot.king_unit_id
	fact.source_label = Localization.text("report.king_inspection")
	fact.confidence = GameEnums.FactConfidence.CONFIRMED
	fact.values = snapshot.values.duplicate(true)
	return fact


func _entry_for_building_fact(fact: KnownFact) -> ReportEntry:
	var detail := "%s: đã nhận báo cáo mới" % _building_label(fact)
	if fact.values.has("daily_output"):
		detail += ", sản lượng %s" % _output_text(fact.values.type, fact.values.daily_output)
	return ReportEntry.new(detail + ".", fact.observed_day, fact.confidence, fact.source_label, fact.key)


func _append_resource_entries(result: TurnResolutionResult, entries: Array[ReportEntry]) -> void:
	if (
		result.food_produced != 0
		or result.food_consumed != 0
		or result.outsider_food_consumed != 0
		or result.expedition_supply_food != 0
		or result.trade_food_delta != 0
	):
		var food_delta := (
			result.food_produced - result.food_consumed
			- result.outsider_food_consumed - result.expedition_supply_food
			+ result.trade_food_delta
		)
		entries.append(ReportEntry.new(
			"Lương thực: Nông trại +%d, thám hiểm +%d, trong thành -%d, tù binh -%d, ngoài thành -%d, chuẩn bị đường xa -%d, trao đổi %s%d; thay đổi %s%d." % [
				result.farm_food_produced,
				result.expedition_food_found,
				result.city_food_consumed,
				result.prisoner_food_consumed,
				result.outsider_food_consumed,
				result.expedition_supply_food,
				"+" if result.trade_food_delta > 0 else "",
				result.trade_food_delta,
				"+" if food_delta > 0 else "",
				food_delta,
			],
			result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED,
			"Sổ kho trung tâm"
		))
	if result.materials_produced != 0 or result.materials_spent != 0 or result.refunded_materials != 0 or result.trade_materials_delta != 0:
		var delta := result.materials_produced - result.materials_spent + result.refunded_materials + result.trade_materials_delta
		entries.append(ReportEntry.new(
			"Vật tư: Xưởng +%d, thám hiểm +%d, chi -%d, hoàn +%d, trao đổi %s%d; thay đổi %s%d." % [
				result.workshop_materials_produced,
				result.expedition_materials_found,
				result.materials_spent,
				result.refunded_materials,
				"+" if result.trade_materials_delta > 0 else "",
				result.trade_materials_delta,
				"+" if delta > 0 else "",
				delta,
			],
			result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED,
			"Sổ kho trung tâm"
		))


func _append_visible_events(result: TurnResolutionResult, entries: Array[ReportEntry]) -> void:
	for event in result.building_events:
		var label := "%s tại %s" % [_building_name(event.type), _cell_name(event.core)]
		var action := "đã bị phá"
		if event.kind == "construction_started":
			action = "bắt đầu xây dựng"
		elif event.kind == "completed":
			action = "đã hoàn thành"
		elif event.kind == "cancelled":
			action = "đã hủy xây"
		entries.append(ReportEntry.new(
			"%s %s." % [label, action], result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED, "Building"
		))
	for unit_id in result.starved_unit_ids:
		observed.facts.erase(unit_fact_key(unit_id))
		entries.append(ReportEntry.new(
			"%s đã chết đói." % result.starved_unit_names.get(unit_id, "Một quân cờ"),
			result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED,
			"Phân phối khẩu phần"
		))
	for event in result.expedition_events:
		if event.kind == "death" and event.has("unit_id"):
			observed.facts.erase(unit_fact_key(event.unit_id))


func _append_role_changes(result: TurnResolutionResult, entries: Array[ReportEntry]) -> void:
	for change in result.farm_role_changes:
		var role := "người phụ trách" if change.role == "manager" else "lao động"
		entries.append(ReportEntry.new(
			"%s %s vai trò %s tại Nông trại." % [
				change.unit_name,
				"nhận" if change.started else "rời",
				role,
			],
			result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED,
			"Quan sát trực tiếp"
		))


func _append_medical_prison_events(
	result: TurnResolutionResult, entries: Array[ReportEntry]
) -> void:
	for event in result.medical_events:
		var text := "%s đã vào Y xá điều trị." % event.unit_name
		if event.kind == "recovered":
			text = "%s đã hồi phục." % event.unit_name
		entries.append(ReportEntry.new(
			text, result.resolved_day, GameEnums.FactConfidence.CONFIRMED, "Y xá"
		))
	for event in result.prison_events:
		var text := "Nhà giam thiếu người canh giữ."
		if event.kind == "admitted":
			text = "%s đã được đưa vào Nhà giam." % event.unit_name
		elif event.kind == "labor":
			text = "%s đã lao động hỗ trợ xây dựng." % event.unit_name
		elif event.kind == "released":
			text = "%s đã được thả." % event.unit_name
		elif event.kind == "killed":
			text = "%s đã bị xử lý." % event.unit_name
		elif event.kind == "submitted":
			text = "%s đã quy phục và trở thành Tốt." % event.unit_name
		elif event.kind == "continued":
			text = "%s tiếp tục bị giam." % event.unit_name
		entries.append(ReportEntry.new(
			text, result.resolved_day, GameEnums.FactConfidence.CONFIRMED, "Nhà giam"
		))


func _append_outside_events(result: TurnResolutionResult, entries: Array[ReportEntry]) -> void:
	for event in result.expedition_events:
		entries.append(ReportEntry.new(
			event.text, result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED, "Expedition"
		))
	for event in result.outsider_events:
		entries.append(ReportEntry.new(
			event.text, result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED, "Refugee camp"
		))


func _append_progression_events(
	state: GameState, result: TurnResolutionResult, entries: Array[ReportEntry]
) -> void:
	if not result.merit_grants.is_empty():
		var total := 0
		for grant_entry in result.merit_grants:
			total += int(grant_entry.amount)
		var text := "%d quân nhận tổng cộng %d Chiến công từ chuyến thám hiểm." % [
			result.merit_grants.size(), total,
		]
		if result.merit_grants.size() == 1:
			var single_grant: Dictionary = result.merit_grants[0]
			var unit := state.units.get(single_grant.unit_id) as UnitState
			var unit_name: String = (
				unit.display_name
				if unit != null and not unit.display_name.is_empty()
				else str(single_grant.unit_id)
			)
			text = "%s nhận %d Chiến công từ chuyến thám hiểm." % [
				unit_name, int(single_grant.amount),
			]
		entries.append(ReportEntry.new(
			text, result.resolved_day, GameEnums.FactConfidence.CONFIRMED,
			"Expedition", "", GameEnums.AttentionLevel.NORMAL, "summary"
		))
	for event in result.promotion_events:
		var attention := int(event.get("attention", GameEnums.AttentionLevel.NORMAL))
		entries.append(ReportEntry.new(
			event.text, result.resolved_day, GameEnums.FactConfidence.CONFIRMED,
			"Barracks", "promotion:%s" % event.unit_id, attention, "summary"
		))


func _append_loyalty_events(
	state: GameState, result: TurnResolutionResult, entries: Array[ReportEntry]
) -> void:
	for event in result.loyalty_events:
		var unit := state.units.get(str(event.get("unit_id", ""))) as UnitState
		var unit_name := (
			unit.display_name
			if unit != null and not unit.display_name.is_empty()
			else str(event.get("unit_id", "Một quân cờ"))
		)
		var delta := int(event.get("delta", 0))
		var text := "%s: Trung thành %s%d." % [
			unit_name, "+" if delta > 0 else "", delta,
		]
		if bool(event.get("level_changed", false)):
			text += " Mức bất mãn: %s." % str(event.get("level_label", "không rõ"))
		entries.append(ReportEntry.new(
			text, result.resolved_day, GameEnums.FactConfidence.CONFIRMED,
			str(event.get("source", "Nội bộ")),
			"loyalty:%s" % str(event.get("unit_id", "")),
			int(event.get("attention", GameEnums.AttentionLevel.NORMAL)),
			"summary"
		))


func _append_social_events(
	result: TurnResolutionResult, entries: Array[ReportEntry]
) -> void:
	for event in result.social_events:
		entries.append(ReportEntry.new(
			str(event.get("text", "Sự kiện xã hội đã được ghi nhận.")),
			result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED,
			str(event.get("source", "Nội bộ")),
			str(event.get("fact_key", "")),
			int(event.get("attention", GameEnums.AttentionLevel.NORMAL)),
			str(event.get("category", "summary"))
		))


func _append_world_events(result: TurnResolutionResult, entries: Array[ReportEntry]) -> void:
	for event_text in result.world_events:
		entries.append(ReportEntry.new(
			event_text, result.resolved_day,
			GameEnums.FactConfidence.REPORTED, "World event"
		))


func _append_perimeter_events(result: TurnResolutionResult, entries: Array[ReportEntry]) -> void:
	for event in result.perimeter_events:
		var attention := GameEnums.AttentionLevel.NOTICE
		if event.kind == "wasteland_complete":
			attention = GameEnums.AttentionLevel.IMPORTANT
		entries.append(ReportEntry.new(
			event.text, result.resolved_day, GameEnums.FactConfidence.CONFIRMED,
			"Wasteland", "", attention, "summary"
		))


func _append_event_reports(result: TurnResolutionResult, entries: Array[ReportEntry]) -> void:
	for event in result.event_reports:
		entries.append(ReportEntry.new(
			event.text, result.resolved_day, GameEnums.FactConfidence.REPORTED,
			event.source, "event:%s" % event.event_id, int(event.attention),
			"attention" if int(event.attention) >= GameEnums.AttentionLevel.IMPORTANT else "summary"
		))


func _update_visible_building_facts(
	state: GameState, result: TurnResolutionResult, updated_keys: Dictionary
) -> void:
	for event in result.building_events:
		var key := building_fact_key(event.building_id)
		if event.kind in ["cancelled", "demolished"]:
			observed.facts.erase(key)
			continue
		var building := state.buildings.get(event.building_id) as BuildingState
		if building == null:
			continue
		var fact := KnownFact.new(key, building.id, "building")
		fact.observed_day = result.resolved_day
		fact.inspected_day = result.resolved_day
		fact.delivered_day = result.resolved_day
		fact.source_label = "Quan sát trực tiếp"
		fact.confidence = GameEnums.FactConfidence.CONFIRMED
		fact.values = {
			"type": building.type,
			"core_cell": building.core_cell,
			"phase": building.phase,
		}
		observed.upsert(fact)
		updated_keys[key] = true


func _append_stale_notices(
	current_day: int, updated_keys: Dictionary, entries: Array[ReportEntry]
) -> void:
	var keys := observed.facts.keys()
	keys.sort()
	var shown := 0
	for key in keys:
		if updated_keys.has(key):
			continue
		var fact := observed.get_fact(key)
		if fact == null or fact.category != "building" or not fact.is_stale(current_day):
			continue
		entries.append(ReportEntry.new(
			"%s: chưa có tin mới; lần biết gần nhất Ngày %d." % [
				_building_label(fact), fact.observed_day
			],
			fact.observed_day,
			fact.confidence,
			fact.source_label,
			fact.key
		))
		shown += 1
		if shown >= 3:
			break


func _append_rejections(result: TurnResolutionResult, entries: Array[ReportEntry]) -> void:
	for rejection in result.rejected_orders:
		entries.append(ReportEntry.new(
			"Một lệnh không thể thực hiện: %s." % rejection.reason,
			result.resolved_day,
			GameEnums.FactConfidence.CONFIRMED,
			"Bộ điều phối"
		))


func _format_building_fact(fact: KnownFact, current_day: int) -> String:
	var values := fact.values
	var lines: Array[String] = ["%s · %s" % [
		_building_name(values.get("type", GameEnums.BuildingType.FARM)),
		_phase_name(values.get("phase", GameEnums.BuildingPhase.ACTIVE)),
	]]
	if values.has("days_left") and int(values.days_left) > 0:
		lines.append("Còn %d ngày xây dựng" % values.days_left)
	if values.has("builder_count"):
		lines.append("Thợ xây: %d" % values.builder_count)
	if values.has("manager_name"):
		lines.append("Người phụ trách: %s" % values.manager_name)
	if values.has("staff_count"):
		lines.append("Nhân lực: %d" % values.staff_count)
	if values.has("daily_output"):
		lines.append("Sản lượng hôm qua: %s" % _output_text(values.type, values.daily_output))
	if int(values.get("confirmed_food", -1)) >= 0:
		lines.append("Lương thực xác nhận: %d" % values.confirmed_food)
	if int(values.get("confirmed_materials", -1)) >= 0:
		lines.append("Vật tư xác nhận: %d" % values.confirmed_materials)
	if int(values.get("confirmed_troops", -1)) >= 0:
		lines.append("Quân số xác nhận: %d" % values.confirmed_troops)
	if values.has("patient_count") and values.get("type") == GameEnums.BuildingType.INFIRMARY:
		lines.append("Bệnh nhân: %d/3" % values.patient_count)
	if values.has("prisoner_count") and values.get("type") == GameEnums.BuildingType.PRISON:
		lines.append("Tù binh: %d" % values.prisoner_count)
		lines.append("Canh giữ: %d/2" % values.get("guard_count", 0))
		lines.append("Trạng thái: %s" % (
			"CANH GIỮ THIẾU" if values.get("under_guarded", false) else "Canh giữ đầy đủ"
		))
		lines.append("Đang lao động: %d" % values.get("prisoner_labor_count", 0))
		for prisoner in values.get("prisoners", []):
			lines.append("%s %s · %s" % [
				_rank_glyph(prisoner.rank),
				prisoner.name,
				"đang lao động" if prisoner.labor else "đang bị giam",
			])
	lines.append("Nguồn: %s" % (fact.source_label if not fact.source_label.is_empty() else "Chưa rõ"))
	lines.append("Độ tin cậy: %s" % confidence_label(fact.confidence, fact.is_stale(current_day)))
	lines.append("Kiểm tra: Ngày %d · Nhận: Ngày %d" % [fact.inspected_day, fact.delivered_day])
	lines.append("Độ mới: %s" % freshness_label(fact.freshness(current_day)))
	return "\n".join(lines)


func freshness_label(value: GameEnums.InformationFreshness) -> String:
	if value == GameEnums.InformationFreshness.FRESH:
		return Localization.text("report.fresh")
	if value == GameEnums.InformationFreshness.AGING:
		return Localization.text("report.aging")
	return Localization.text("report.stale").to_upper()


func _format_unit_fact(fact: KnownFact, current_day: int) -> String:
	return "Tình trạng: %s\nCông việc: %s\nNguồn: %s\nĐộ tin cậy: %s · Cập nhật: Ngày %d" % [
		fact.values.get("condition", "chưa rõ"),
		fact.values.get("job", "chưa rõ"),
		fact.source_label if not fact.source_label.is_empty() else "Chưa rõ",
		confidence_label(fact.confidence, fact.is_stale(current_day)),
		fact.observed_day,
	]


func _building_output(state: GameState, building: BuildingState) -> int:
	if building.type == GameEnums.BuildingType.FARM:
		return food_system.production_for_building(state, building)
	if building.type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
		return material_system.manager_output(state, building)
	return 0


func _unique_staff_count(building: BuildingState) -> int:
	var staff := {}
	if not building.manager_unit_id.is_empty():
		staff[building.manager_unit_id] = true
	for unit_id in building.worker_unit_ids:
		staff[unit_id] = true
	return staff.size()


func _add_special_building_values(
	state: GameState, building: BuildingState, values: Dictionary, include_people: bool
) -> void:
	if building.type == GameEnums.BuildingType.INFIRMARY:
		values["patient_count"] = building.patient_unit_ids.size()
	elif building.type == GameEnums.BuildingType.PRISON:
		values["prisoner_count"] = building.prisoner_unit_ids.size()
		values["guard_count"] = prison_system.guard_count(building)
		values["under_guarded"] = building.under_guarded
		var labor_count := 0
		var prisoners: Array[Dictionary] = []
		for unit_id in building.prisoner_unit_ids:
			var unit := state.units.get(unit_id) as UnitState
			if unit == null:
				continue
			if unit.prisoner_labor:
				labor_count += 1
			if include_people:
				prisoners.append({
					"name": unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank),
					"rank": unit.rank,
					"labor": unit.prisoner_labor,
				})
		values["prisoner_labor_count"] = labor_count
		if include_people:
			values["prisoners"] = prisoners
			values["prisoner_ids"] = building.prisoner_unit_ids.duplicate()


func _true_unit_condition(unit: UnitState) -> String:
	if unit.locked_by_healing:
		return Localization.text("condition.healing")
	if unit.away_days_left > 0 or not unit.away_assignment_id.is_empty():
		return Localization.text("condition.away")
	if unit.locked_by_construction:
		return Localization.text("condition.building")
	return Localization.text("condition.stable")


func _true_unit_job(unit: UnitState) -> String:
	if unit.is_manager:
		return Localization.text("job.manager")
	if not unit.work_building_id.is_empty():
		return Localization.text("job.worker")
	if not unit.assigned_building_id.is_empty():
		return Localization.text("job.builder")
	return Localization.text("job.idle")


func _stable_code(first: String, second: String, day: int) -> int:
	var text := "%s|%s|%d" % [first, second, day]
	var value := 17
	for index in range(text.length()):
		value = (value * 31 + text.unicode_at(index)) % 2147483647
	return value


func _unit_name(unit: UnitState) -> String:
	if unit == null:
		return "—"
	return unit.display_name if not unit.display_name.is_empty() else _rank_name(unit.rank)


func _rank_name(rank: int) -> String:
	return LocalizationKeys.rank_name(rank)


func _rank_glyph(rank: int) -> String:
	return ["♟", "♞", "♜", "♝", "♛", "♚"][rank]


func _building_label(fact: KnownFact) -> String:
	return "%s tại %s" % [
		_building_name(fact.values.get("type", GameEnums.BuildingType.FARM)),
		_cell_name(fact.values.get("core_cell", Vector2i(-1, -1))),
	]


func _output_text(type: int, output: int) -> String:
	if type == GameEnums.BuildingType.FARM:
		return "+%d lương thực" % output
	if type == GameEnums.BuildingType.MATERIAL_WORKSHOP:
		return "+%d vật tư" % output
	return "không có"


func _building_name(type: int) -> String:
	return LocalizationKeys.building_name(type)


func _phase_name(phase: int) -> String:
	return Localization.text([
		"building.phase.blueprint", "building.phase.building",
		"building.phase.active", "building.phase.demolishing",
	][phase])


func _cell_name(cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0:
		return "vị trí chưa rõ"
	return "%s%d" % [String.chr(65 + cell.x), 8 - cell.y]
