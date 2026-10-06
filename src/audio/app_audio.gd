extends Node

const SETTINGS_PATH := "user://after_checkmate_settings.cfg"
const OPENING_STREAM := preload("res://assets/intro/after_checkmate_opening.ogg")
const INTRO_MENU_OFFSET := 11.0

var intro_played := false
var _bgm: AudioStreamPlayer
var _config := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("BGM")
	_ensure_bus("SFX")
	_ensure_bus("Ambience")
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "OpeningBGM"
	_bgm.bus = "BGM"
	_bgm.stream = OPENING_STREAM
	add_child(_bgm)
	_load_settings()
	_apply_saved_resolution()


func begin_intro_opening() -> void:
	intro_played = true
	_play_opening_from(0.0)


func begin_menu_opening() -> void:
	intro_played = true
	_play_opening_from(INTRO_MENU_OFFSET)


func ensure_menu_music() -> void:
	if not _bgm.playing:
		begin_menu_opening()


func opening_position() -> float:
	if _bgm == null or not _bgm.playing:
		return 0.0
	return _bgm.get_playback_position() + AudioServer.get_time_since_last_mix()


func stop_bgm() -> void:
	if _bgm != null:
		_bgm.stop()


func set_bus_level(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var normalized := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, -80.0 if normalized <= 0.0001 else linear_to_db(normalized))
	_config.set_value("audio", bus_name.to_lower(), normalized)
	_config.save(SETTINGS_PATH)


func bus_level(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return 1.0
	if AudioServer.is_bus_mute(index):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.0, 1.0)


func set_master_muted(muted: bool) -> void:
	var index := AudioServer.get_bus_index("Master")
	if index >= 0:
		AudioServer.set_bus_mute(index, muted)
	_config.set_value("audio", "muted", muted)
	_config.save(SETTINGS_PATH)


func master_muted() -> bool:
	var index := AudioServer.get_bus_index("Master")
	return index >= 0 and AudioServer.is_bus_mute(index)


func set_resolution(size: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i(
		maxi(0, (screen.x - size.x) / 2), maxi(0, (screen.y - size.y) / 2)
	))
	_config.set_value("display", "width", size.x)
	_config.set_value("display", "height", size.y)
	_config.save(SETTINGS_PATH)


func saved_resolution() -> Vector2i:
	return Vector2i(
		int(_config.get_value("display", "width", 1280)),
		int(_config.get_value("display", "height", 720))
	)


func _play_opening_from(position: float) -> void:
	if _bgm == null:
		return
	_bgm.stream = OPENING_STREAM
	_bgm.play(position)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _apply_saved_resolution() -> void:
	var saved := saved_resolution()
	if saved.x <= 0 or saved.y <= 0:
		return
	DisplayServer.window_set_size(saved)
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i(
		maxi(0, (screen.x - saved.x) / 2), maxi(0, (screen.y - saved.y) / 2)
	))


func _load_settings() -> void:
	_config.load(SETTINGS_PATH)
	for bus_name in ["Master", "BGM", "SFX", "Ambience"]:
		var value := float(_config.get_value("audio", bus_name.to_lower(), 1.0))
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, -80.0 if value <= 0.0001 else linear_to_db(value))
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, bool(_config.get_value("audio", "muted", false)))
