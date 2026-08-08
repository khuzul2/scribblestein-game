extends TestCase

## The `Config` autoload is the only place gameplay numbers come from (Mandate B1).


func test_config_loaded_the_whole_data_set() -> void:
	is_true(Config.is_loaded, "Config finished booting")
	eq(Config.parts.size(), 14, "all 14 v1 parts are loaded")
	eq(Config.blueprints.size(), 2, "biped plus the quadruped stub")
	eq(Config.enemies.size(), 3, "all 3 enemy types are loaded")
	is_true(Config.effects.size() >= 10, "the effect catalogue is loaded")


func test_config_is_read_only() -> void:
	is_true(Config.parts.is_read_only(), "gameplay code cannot mutate the parts table")
	is_true((Config.part("torso_ribby")["stats"] as Dictionary).is_read_only(),
		"nested tuning is frozen too")


func test_starter_kit_matches_the_design() -> void:
	var starters: PackedStringArray = Config.starter_part_ids()
	eq(starters.size(), 3, "three starter parts (DESIGN §8)")
	is_true(starters.has("torso_ribby"), "Ribby Torso is free")
	is_true(starters.has("legs_scribble_sprint"), "Scribble Sprinters are free")
	is_true(starters.has("head_monster_maw"), "Monster Maw is free")


func test_cfg_reads_dotted_paths() -> void:
	almost(Config.cfg_float("movement.gravity"), 2400.0, 0.001, "gravity comes from JSON")
	almost(Config.cfg_float("movement.coyote_time"), 0.10, 0.001, "coyote time comes from JSON")
	almost(Config.cfg_float("movement.weight_classes.light.max_speed"), 340.0, 0.001,
		"nested class presets are reachable")
	eq(Config.cfg_vec2("camera.drag_margin"), Vector2(0.1, 0.1), "vector values convert")


func test_every_part_texture_exists() -> void:
	for part_id: Variant in Config.parts:
		var texture_path: String = str((Config.parts[part_id] as Dictionary)["texture_path"])
		is_true(ResourceLoader.exists(texture_path),
			"part '%s' has an importable texture at %s" % [part_id, texture_path])


func test_every_enemy_assembly_is_buildable_from_the_catalogue() -> void:
	for enemy_id: Variant in Config.enemies:
		var assembly: Dictionary = (Config.enemies[enemy_id] as Dictionary)["assembly"] as Dictionary
		for slot: Variant in assembly:
			if assembly[slot] == null:
				continue
			is_true(Config.parts.has(assembly[slot]),
				"enemy '%s' slot '%s' uses a real part" % [enemy_id, slot])
