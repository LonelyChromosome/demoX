class_name OnboardingSystem
extends RefCounted

const DEFAULT_STORAGE_PATH := "user://after_checkmate.cfg"
static var storage_path := DEFAULT_STORAGE_PATH

const HINTS: Array[Dictionary] = [
	{"id": "board", "title_key": "onboarding.board.title", "body_key": "onboarding.board.body", "target": "board"},
	{"id": "king", "title_key": "onboarding.king.title", "body_key": "onboarding.king.body", "target": "king"},
	{"id": "resources", "title_key": "onboarding.resources.title", "body_key": "onboarding.resources.body", "target": "resources"},
	{"id": "unit", "title_key": "onboarding.unit.title", "body_key": "onboarding.unit.body", "target": "unit"},
	{"id": "report", "title_key": "onboarding.report.title", "body_key": "onboarding.report.body", "target": "report"},
	{"id": "outside", "title_key": "onboarding.outside.title", "body_key": "onboarding.outside.body", "target": "perimeter"},
	{"id": "end_day", "title_key": "onboarding.end_day.title", "body_key": "onboarding.end_day.body", "target": "end_day"},
]


func start(state: GameState) -> Dictionary:
	if state == null or state.onboarding_skipped or state.onboarding_completed:
		return {}
	var config := ConfigFile.new()
	if config.load(storage_path) == OK:
		for hint_id in config.get_value("onboarding", "seen", []):
			state.onboarding_seen_hints[str(hint_id)] = true
		if bool(config.get_value("onboarding", "completed", false)):
			state.onboarding_completed = true
			state.onboarding_skipped = bool(config.get_value("onboarding", "skipped", false))
			return {}
	state.onboarding_started = true
	return current_hint(state)


func current_hint(state: GameState) -> Dictionary:
	if state == null or state.onboarding_skipped or state.onboarding_completed:
		return {}
	for definition in HINTS:
		if not state.onboarding_seen_hints.has(definition.id):
			return _localized_hint(definition)
	state.onboarding_completed = true
	return {}


func dismiss_current(state: GameState) -> Dictionary:
	var current := current_hint(state)
	if current.is_empty():
		return {}
	state.onboarding_seen_hints[current.id] = true
	_persist_state(state)
	var next := current_hint(state)
	if next.is_empty():
		_persist_completed()
	return next


func skip(state: GameState) -> void:
	if state == null:
		return
	state.onboarding_started = true
	state.onboarding_skipped = true
	state.onboarding_completed = true
	_persist_state(state)


func snapshot(state: GameState) -> Dictionary:
	return {
		"started": state.onboarding_started,
		"skipped": state.onboarding_skipped,
		"completed": state.onboarding_completed,
		"seen": state.onboarding_seen_hints.duplicate(true),
		"current": current_hint(state),
	}


func _localized_hint(definition: Dictionary) -> Dictionary:
	return {
		"id": definition.id,
		"target": definition.target,
		"title": Localization.text(definition.title_key),
		"body": Localization.text(definition.body_key),
		"title_key": definition.title_key,
		"body_key": definition.body_key,
	}


static func configure_storage(path: String) -> void:
	storage_path = path


static func reset_storage_path() -> void:
	storage_path = DEFAULT_STORAGE_PATH


func _persist_completed() -> void:
	var config := ConfigFile.new()
	config.load(storage_path)
	config.set_value("onboarding", "completed", true)
	config.save(storage_path)


func _persist_state(state: GameState) -> void:
	var config := ConfigFile.new()
	config.load(storage_path)
	var seen: Array[String] = []
	seen.assign(state.onboarding_seen_hints.keys())
	seen.sort()
	config.set_value("onboarding", "seen", seen)
	config.set_value("onboarding", "completed", state.onboarding_completed)
	config.set_value("onboarding", "skipped", state.onboarding_skipped)
	config.save(storage_path)
