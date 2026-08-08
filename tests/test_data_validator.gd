extends TestCase

## M0 acceptance: corrupting any value in the data set must produce an error that
## names the file, the JSON path, and the reason — never a silent default.


func test_shipped_data_set_has_no_errors() -> void:
	var issues: Array[Dictionary] = DataValidator.validate(Fixtures.data_set(), Fixtures.waivers())
	var errors: Array[Dictionary] = DataValidator.errors_of(issues)
	var messages: PackedStringArray = PackedStringArray()
	for issue: Dictionary in errors:
		messages.append(str(issue["message"]))
	is_true(errors.is_empty(), "shipped data validates clean: %s" % "\n".join(messages))


func test_corrupt_weight_is_reported_with_file_path_and_reason() -> void:
	var data: Dictionary = Fixtures.data_set()
	Fixtures.part(data, "torso_ribby")["weight"] = "heavy"
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["data/parts_db.json", "/parts/torso_ribby/weight", "expected type number"]),
		"the MILESTONES M0 example corruption is caught")


func test_negative_weight_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	Fixtures.part(data, "torso_ribby")["weight"] = -5
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["/parts/torso_ribby/weight", "below the minimum"]),
		"a negative weight is out of range")


func test_unknown_key_in_a_part_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	Fixtures.part(data, "head_anvil")["atack_power"] = 50
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["/parts/head_anvil", "unknown key 'atack_power'"]),
		"a typo'd key is not silently ignored")


func test_missing_required_part_key_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	Fixtures.part(data, "tail_scorpion").erase("pivot")
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["/parts/tail_scorpion", "missing required key 'pivot'"]),
		"a dropped required key is caught")


func test_damage_hitbox_without_an_attack_block_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	Fixtures.part(data, "head_monster_maw").erase("attack")
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["/parts/head_monster_maw", "missing required key 'attack'"]),
		"a damage hitbox demands attack timings (Mandate B5)")


func test_unknown_effect_id_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	(Fixtures.part(data, "back_bat_scraps")["effects"] as Array).append("can_teleport")
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["back_bat_scraps", "unknown effect 'can_teleport'", "effects.json"]),
		"effects are cross-referenced against effects.json")


func test_effect_on_the_wrong_slot_kind_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	(Fixtures.part(data, "torso_barrel")["effects"] as Array).append("bite_attack")
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["torso_barrel", "bite_attack", "kind 'core'"]),
		"an attack effect cannot live on a core slot")


func test_starter_part_must_be_free() -> void:
	var data: Dictionary = Fixtures.data_set()
	Fixtures.part(data, "torso_ribby")["unlock_cost"] = 50
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["torso_ribby", "starter parts must cost 0"]),
		"a priced starter part is a contradiction")


func test_enemy_referencing_an_unknown_part_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	(Fixtures.enemy(data, "enemy_stinger")["assembly"] as Dictionary)["tail"] = "tail_of_theseus"
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["data/enemies.json", "enemy_stinger", "unknown part 'tail_of_theseus'"]),
		"enemy assemblies are cross-referenced against parts_db.json")


func test_enemy_missing_a_required_slot_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	(Fixtures.enemy(data, "enemy_scribble_grunt")["assembly"] as Dictionary)["legs"] = null
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["enemy_scribble_grunt", "required slot 'legs' is empty"]),
		"a legless enemy is rejected")


func test_enemy_part_in_the_wrong_slot_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	(Fixtures.enemy(data, "enemy_scribble_grunt")["assembly"] as Dictionary)["head"] = "tail_scorpion"
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["enemy_scribble_grunt", "belongs in slot 'tail'"]),
		"a tail cannot be worn as a head")


func test_unknown_ai_profile_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	(Fixtures.enemy(data, "enemy_wall_crawler")["ai"] as Dictionary)["profile"] = "vibes_based"
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["enemy_wall_crawler", "unknown profile 'vibes_based'"]),
		"AI profiles must be implemented ones")


func test_blueprint_slot_pointing_at_a_missing_bone_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	((Fixtures.blueprint(data, "biped")["slots"] as Dictionary)["head"] as Dictionary)["bone"] = "skull"
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["data/blueprints.json", "/blueprints/biped/slots/head", "unknown bone 'skull'"]),
		"blueprint slots are checked against the bone list")


func test_missing_game_config_value_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	((data["game_config"] as Dictionary)["movement"] as Dictionary).erase("coyote_time")
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["data/game_config.json", "/movement/coyote_time", "missing required value"]),
		"tuning values cannot go missing — Mandate B6 needs coyote time")


func test_boil_fps_outside_the_mandated_band_is_reported() -> void:
	var data: Dictionary = Fixtures.data_set()
	((data["game_config"] as Dictionary)["line_boil"] as Dictionary)["boil_fps"] = 24
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["/line_boil/boil_fps", "outside boil_fps_range"]),
		"Mandate A3 pins the boil to 8-12 FPS")


func test_effect_params_from_must_resolve() -> void:
	var data: Dictionary = Fixtures.data_set()
	((data["effects"] as Dictionary)["effects"] as Dictionary)["can_glide"]["params_from"] = "game_config.movement.hover"
	any_contains(Fixtures.error_messages(data),
		PackedStringArray(["can_glide", "does not resolve in data/game_config.json"]),
		"an effect cannot point at tuning that does not exist")


func test_waiver_downgrades_an_error_to_a_warning() -> void:
	var data: Dictionary = Fixtures.data_set()
	Fixtures.part(data, "torso_ribby")["unlock_cost"] = 50
	var table: Dictionary = Fixtures.waivers()
	table["starter_cost:torso_ribby"] = "test waiver"
	var waived: Array[Dictionary] = DataValidator.validate(data, table)
	is_true(DataValidator.errors_of(waived).is_empty(), "the waived issue no longer blocks the build")
	any_contains(_messages(DataValidator.warnings_of(waived)),
		PackedStringArray(["WAIVED", "test waiver", "DECISIONS_NEEDED.md"]),
		"but it still shouts on every boot")


func test_every_waiver_has_a_matching_open_issue() -> void:
	# A waiver for an issue that no longer exists is dead weight hiding nothing.
	var waivers: Dictionary = Fixtures.load_data("res://data/validation_waivers.json")
	var live_ids: Dictionary = {}
	for issue: Dictionary in DataValidator.validate(Fixtures.data_set()):
		live_ids[str(issue["id"])] = true

	var decisions: String = FileAccess.get_file_as_string("res://DECISIONS_NEEDED.md")
	for entry: Variant in waivers["waivers"] as Array:
		var waiver_id: String = str((entry as Dictionary)["id"])
		is_true(live_ids.has(waiver_id), "waiver '%s' still corresponds to a real issue" % waiver_id)
		is_true(decisions.contains(waiver_id),
			"waiver '%s' is documented in DECISIONS_NEEDED.md" % waiver_id)


func _messages(issues: Array[Dictionary]) -> PackedStringArray:
	var messages: PackedStringArray = PackedStringArray()
	for issue: Dictionary in issues:
		messages.append(str(issue["message"]))
	return messages
