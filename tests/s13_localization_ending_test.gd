extends SceneTree

var failures := 0


func _init() -> void:
	_test_localization_contract()
	_test_onboarding_is_metadata_only()
	_test_day_32_resolves_once()
	_test_recap_is_real_and_deterministic()
	if failures == 0:
		print("S13_LOCALIZATION_ENDING_TEST_OK")
	quit(1 if failures > 0 else 0)


func _test_localization_contract() -> void:
	var vi_keys := Localization.keys_for("vi")
	var en_keys := Localization.keys_for("en")
	_check(vi_keys == en_keys, "VI/EN localization keys differ")
	for key in vi_keys:
		_check(
			Localization.placeholders_for(key, "vi") == Localization.placeholders_for(key, "en"),
			"Placeholder mismatch for %s" % key
		)
	Localization.set_language("vi", false)
	_check(Localization.text("game.end_day") == "Kết thúc ngày", "Vietnamese lookup failed")
	Localization.set_language("en", false)
	_check(Localization.text("game.end_day") == "End Day", "Runtime language switch failed")
	_check(Localization.text("missing.test.key") == "missing.test.key", "Missing-key fallback is unsafe")
	_check(
		Localization.text("common.day", {"day": 12}) == "Day 12",
		"Localized placeholder formatting failed"
	)
	Localization.configure_storage("user://s13_locale_test_%s.cfg" % Time.get_unix_time_from_system())
	Localization.set_language("en", true)
	Localization.set_language("vi", false)
	_check(Localization.load_saved_language() == "en", "Saved locale was not restored")
	Localization.reset_for_tests()
	Localization.set_language("vi", false)


func _test_onboarding_is_metadata_only() -> void:
	OnboardingSystem.configure_storage("user://s13_onboarding_test_%s.cfg" % Time.get_unix_time_from_system())
	var state := GameSession.start_new_game()
	var food := state.food
	var materials := state.materials
	var unit_count := state.units.size()
	var onboarding := OnboardingSystem.new()
	var hint := onboarding.start(state)
	_check(hint.id == "board", "First-run onboarding did not start at the board")
	var same_hint := onboarding.start(state)
	_check(same_hint.id == hint.id, "Repeated onboarding start advanced unexpectedly")
	onboarding.dismiss_current(state)
	_check(state.onboarding_seen_hints.has("board"), "Dismissed hint was not persisted in state")
	onboarding.skip(state)
	_check(onboarding.start(state).is_empty(), "Skipped onboarding started again")
	_check(
		state.food == food and state.materials == materials and state.units.size() == unit_count,
		"Onboarding mutated gameplay state"
	)
	Localization.set_language("en", false)
	var fresh := GameState.new()
	var english_hint := OnboardingSystem.new().current_hint(fresh)
	_check("board" in english_hint.body.to_lower(), "English onboarding content was not localized")
	Localization.set_language("vi", false)
	OnboardingSystem.reset_storage_path()


func _test_day_32_resolves_once() -> void:
	var state := GameState.new()
	state.day = GameState.MAX_DAYS
	state.food = 4
	var king := UnitState.new("king")
	king.display_name = "King"
	king.rank = GameEnums.Rank.KING
	king.board_cell = Vector2i(4, 7)
	state.units[king.id] = king
	var manager := TurnManager.new()
	root.add_child(manager)
	manager.setup(state)
	var result := manager.end_day()
	_check(result != null and result.resolved_day == 32, "Day 32 did not resolve")
	_check(state.day == 32 and state.run_ended, "Run advanced beyond Day 32")
	_check(result.ending_triggered and state.ending_triggered, "Ending did not trigger")
	_check(manager.end_day() == null, "Ending was allowed to resolve a second time")
	var failed := GameState.new()
	failed.day = 12
	failed.game_over = true
	failed.failure_reason = "test"
	_check(not EndingSystem.new().finalize_run(failed), "Failure state was overwritten by ending")
	_check(not failed.run_ended, "Failure incorrectly entered Day 32 ending")


func _test_recap_is_real_and_deterministic() -> void:
	var state := GameState.new()
	state.day = 32
	state.food = 5
	state.materials = 2
	var survivor := UnitState.new("survivor")
	survivor.display_name = "An"
	survivor.rank = GameEnums.Rank.KNIGHT
	survivor.promotion_history.append({
		"day": 10, "from_rank": GameEnums.Rank.PAWN, "to_rank": GameEnums.Rank.KNIGHT,
	})
	state.units[survivor.id] = survivor
	state.deceased_units.append({
		"unit_id": "lost", "name": "Binh", "rank": GameEnums.Rank.PAWN,
		"faction": GameEnums.Faction.PLAYER, "day": 7, "cause": "expedition",
	})
	state.deceased_units.append(state.deceased_units[0].duplicate(true))
	state.resettled_group_count = 2
	var ending := EndingSystem.new()
	var first := ending.build_recap_data(state)
	var second := ending.build_recap_data(state)
	_check(first == second, "Recap is not deterministic")
	_check(first.survivors.size() == 1 and first.survivors[0].name == "An", "Recap invented survivors")
	_check(first.losses.size() == 1 and first.losses[0].name == "Binh", "Recap duplicated or lost death history")
	_check(first.promotions.size() == 1, "Promotion history was not included")
	_check(first.resettled_groups == 2, "Outside history was not included")
	var sparse := EndingSystem.new().localized_recap(GameState.new())
	_check(not sparse.is_empty(), "Recap failed when optional histories were missing")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
