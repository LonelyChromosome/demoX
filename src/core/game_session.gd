class_name GameSession
extends RefCounted


static func start_new_game() -> GameState:
	var state := GameState.new()
	state.food = 4
	state.materials = 3
	_add_unit(state, "king", GameEnums.Rank.KING, Vector2i(4, 7))
	_add_unit(state, "rook", GameEnums.Rank.ROOK, Vector2i(0, 7))
	_add_unit(state, "knight", GameEnums.Rank.KNIGHT, Vector2i(1, 7))
	_add_unit(state, "pawn_d", GameEnums.Rank.PAWN, Vector2i(3, 6))
	_add_unit(state, "pawn_e", GameEnums.Rank.PAWN, Vector2i(4, 6))
	return state


static func set_language(locale: String) -> bool:
	return Localization.set_language(locale)


static func current_language() -> String:
	return Localization.current_language()


static func start_onboarding(state: GameState) -> Dictionary:
	return OnboardingSystem.new().start(state)


static func skip_onboarding(state: GameState) -> void:
	OnboardingSystem.new().skip(state)


static func onboarding_state(state: GameState) -> Dictionary:
	return OnboardingSystem.new().snapshot(state)


static func ending_recap(state: GameState) -> Dictionary:
	return EndingSystem.new().localized_recap(state)


static func _add_unit(
	state: GameState, unit_id: String, rank: GameEnums.Rank, cell: Vector2i
) -> void:
	var unit := UnitState.new(unit_id)
	unit.display_name = Localization.text("unit.seed.%s" % unit_id)
	unit.rank = rank
	unit.board_cell = cell
	unit.backstory.append(Localization.text("unit.seed.backstory"))
	state.units[unit.id] = unit
