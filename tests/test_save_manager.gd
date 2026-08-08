extends TestCase

## Save file shape and durability (TECH_SPEC §8).


func before_each() -> void:
	SaveManager.data = SaveManager.default_save()


func after_each() -> void:
	DirAccess.remove_absolute(SaveManager.SAVE_PATH)
	DirAccess.remove_absolute(SaveManager.TEMP_PATH)
	SaveManager.data = SaveManager.default_save()


func test_default_profile_matches_the_spec_shape() -> void:
	var profile: Dictionary = SaveManager.default_save()
	for key: String in ["version", "ink", "unlocked_parts", "blueprints_found", "kill_counters",
			"loadout", "blueprint_unlocked", "levels", "settings"]:
		is_true(profile.has(key), "the save carries '%s'" % key)
	eq(int(profile["version"]), SaveManager.SAVE_VERSION, "version stamp")
	eq(int(profile["ink"]), 0, "a new creature has no ink")
	eq((profile["unlocked_parts"] as Array).size(), 3, "only the starter kit is unlocked")


func test_default_loadout_wears_the_starter_kit() -> void:
	var loadout: Dictionary = SaveManager.default_save()["loadout"] as Dictionary
	eq(loadout["torso"], "torso_ribby", "starter torso equipped")
	eq(loadout["legs"], "legs_scribble_sprint", "starter legs equipped")
	eq(loadout["head"], "head_monster_maw", "starter head equipped")
	is_null(loadout["tail"], "no tail to start")
	is_null(loadout["arms"], "no arms to start")
	is_null(loadout["back"], "no back to start")


func test_kill_counters_cover_every_enemy() -> void:
	var counters: Dictionary = SaveManager.default_save()["kill_counters"] as Dictionary
	for enemy_id: Variant in Config.enemies:
		is_true(counters.has(enemy_id), "counter exists for '%s'" % enemy_id)


func test_save_and_reload_round_trips() -> void:
	SaveManager.add_ink(47)
	SaveManager.unlock_part("tail_scorpion")
	SaveManager.set_death_blob("level_01_margins", Vector2(1234, -56), 47)
	is_true(SaveManager.save_game(), "the profile writes")

	SaveManager.data = {}
	SaveManager.load_game()

	eq(SaveManager.ink, 47, "ink survives the round trip")
	is_true(SaveManager.is_unlocked("tail_scorpion"), "unlocks survive")
	var blob: Dictionary = SaveManager.death_blob("level_01_margins") as Dictionary
	almost(float(blob["x"]), 1234.0, 0.5, "blob x survives")
	almost(float(blob["y"]), -56.0, 0.5, "blob y survives")
	eq(int(blob["amount"]), 47, "blob amount survives")


func test_writes_are_atomic() -> void:
	SaveManager.add_ink(9)
	SaveManager.save_game()
	is_true(FileAccess.file_exists(SaveManager.SAVE_PATH), "the save exists")
	is_false(FileAccess.file_exists(SaveManager.TEMP_PATH),
		"the temp file is renamed away, never left behind")


func test_spending_more_ink_than_you_have_changes_nothing() -> void:
	SaveManager.add_ink(30)
	is_false(SaveManager.spend_ink(31), "an unaffordable purchase is refused")
	eq(SaveManager.ink, 30, "and costs nothing")
	is_true(SaveManager.spend_ink(30), "an affordable one goes through")
	eq(SaveManager.ink, 0, "leaving the wallet empty")


func test_ink_never_goes_negative() -> void:
	SaveManager.ink = -5
	eq(SaveManager.ink, 0, "the wallet floors at zero")


func test_an_unreadable_save_starts_a_fresh_profile_rather_than_crashing() -> void:
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()

	SaveManager.load_game()
	eq(SaveManager.ink, 0, "a corrupt save falls back to a new profile")
	eq((SaveManager.unlocked_parts()).size(), 3, "with the starter kit intact")


func test_migration_fills_in_keys_an_old_save_lacks() -> void:
	var old_profile: Dictionary = {"version": 1, "ink": 12}
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_profile))
	file.close()

	SaveManager.load_game()
	eq(SaveManager.ink, 12, "the old value is kept")
	is_true(SaveManager.data.has("kill_counters"), "and the missing ones are filled in")
	eq((SaveManager.loadout() as Dictionary).size(), 6, "loadout gains every biped slot")
