extends TestCase

## `Layers` mirrors project.godot. If the two drift, hitboxes silently stop
## seeing each other — so assert they agree.


func test_layer_constants_match_the_project_settings() -> void:
	for number: Variant in Layers.NAMES:
		var setting: String = "layer_names/2d_physics/layer_%d" % int(number)
		eq(str(ProjectSettings.get_setting(setting, "")), str(Layers.NAMES[number]),
			"physics layer %d is named as TECH_SPEC §4 says" % int(number))


func test_mask_builds_the_expected_bits() -> void:
	eq(Layers.mask([Layers.WORLD]), 1, "layer 1 is bit 0")
	eq(Layers.mask([Layers.WORLD, Layers.WORLD_CRACKED]), 0b11, "layers 1+2")
	eq(Layers.bit(Layers.HAZARD), 1 << 10, "layer 11 is bit 10")


func test_damage_boxes_never_scan_bodies() -> void:
	# Decision 4: bodies push, they never hurt.
	for is_player: bool in [true, false]:
		var mask: int = Layers.damage_mask(is_player)
		eq(mask & Layers.bit(Layers.PLAYER_BODY), 0, "player bodies are not damage targets")
		eq(mask & Layers.bit(Layers.ENEMY_BODY), 0, "enemy bodies are not damage targets")


func test_hurtboxes_also_watch_for_hazards() -> void:
	# Environment hazards are exempt from the attack-window rule (Mandate B5).
	for is_player: bool in [true, false]:
		is_true(Layers.hurtbox_mask(is_player) & Layers.bit(Layers.HAZARD) != 0,
			"hurtboxes see the hazard layer")


func test_a_side_cannot_damage_itself() -> void:
	eq(Layers.damage_mask(true) & Layers.hurtbox_layer(true), 0, "player damage misses player hurtboxes")
	eq(Layers.damage_mask(false) & Layers.hurtbox_layer(false), 0, "enemy damage misses enemy hurtboxes")
	ne(Layers.damage_mask(true) & Layers.hurtbox_layer(false), 0, "but it does reach enemies")
