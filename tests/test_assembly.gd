extends TestCase

## M1 acceptance: the assembly *is* the character sheet. Changing one entry in a
## loadout must change the sprite, the hitboxes, the HP and the weight, with
## zero scene edits.

var _creature: Creature = null


func after_each() -> void:
	CreatureFixture.despawn(_creature)
	_creature = null


func test_starter_kit_assembles_to_the_expected_sheet() -> void:
	_creature = CreatureFixture.spawn(tree)
	var stats: CreatureStats = _creature.stats
	# torso_ribby 100 base + head_monster_maw 20 bonus; legs add none.
	almost(stats.max_hp, 120.0, 0.001, "max_hp = torso.base_hp + Σ hp_bonus")
	almost(stats.total_defense, 0.0, 0.001, "the starter kit has no defense")
	almost(stats.total_weight, 43.0, 0.001, "20 torso + 8 legs + 15 head")
	almost(stats.speed_mod, 1.15, 0.001, "the sprinters' speed_mod carries through")
	eq(_creature.weight_class.class_id, "medium", "43 falls in the medium band (26-60)")
	almost(_creature.health.maximum, 120.0, 0.001, "Health takes its ceiling from the assembly")


func test_swapping_one_part_changes_sprite_hitboxes_hp_and_weight() -> void:
	_creature = CreatureFixture.spawn(tree)

	var before_texture: Texture2D = CreatureFixture.sprite_on_bone(_creature, "head").texture
	var before_boxes: int = CreatureFixture.boxes_for_slot(_creature, "head").size()
	almost(_creature.stats.max_hp, 120.0, 0.001, "starting HP")
	eq(_creature.weight_class.class_id, "medium", "starting class")

	# One line of data, no scene edits.
	var problems: PackedStringArray = _creature.assemble(
		CreatureFixture.loadout({"head": "head_anvil"}))
	is_true(problems.is_empty(), "the swap is accepted: %s" % str(problems))

	var after_texture: Texture2D = CreatureFixture.sprite_on_bone(_creature, "head").texture
	ne(after_texture.resource_path, before_texture.resource_path, "the head sprite changed")
	almost(_creature.stats.max_hp, 130.0, 0.001, "anvil's +30 replaces the maw's +20")
	almost(_creature.stats.total_defense, 2.0, 0.001, "the anvil brings 2 defense")
	almost(_creature.stats.total_weight, 68.0, 0.001, "20 + 8 + 40")
	eq(_creature.weight_class.class_id, "heavy", "68 tips the creature into Heavy")

	var after_boxes: Array[Hitbox] = CreatureFixture.boxes_for_slot(_creature, "head")
	eq(after_boxes.size(), before_boxes, "the anvil declares the same number of boxes")
	var damage_box: Hitbox = after_boxes.filter(
		func(box: Hitbox) -> bool: return box.hitbox_type == Hitbox.TYPE_DAMAGE)[0]
	eq(str(damage_box.source["shape"]), "rectangle",
		"and a differently shaped one — the maw's damage box is a circle")
	almost(damage_box.position.x, 55.0, 0.001, "at the anvil's own JSON offset")


func test_attack_power_follows_the_equipped_head() -> void:
	_creature = CreatureFixture.spawn(tree)
	almost(_creature.attack_controller.attack_power("attack_primary"), 35.0, 0.001,
		"the maw's 35 attack power is wired to the primary button")

	_creature.assemble(CreatureFixture.loadout({"head": "head_pencil_stub"}))
	almost(_creature.attack_controller.attack_power("attack_primary"), 20.0, 0.001,
		"swapping the head rewires the primary button")


func test_an_empty_attack_slot_leaves_an_inert_button() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({"head": null}))
	is_false(_creature.attack_controller.has_attack("attack_primary"),
		"no head means no primary attack (DESIGN §4.2)")
	is_true(CreatureFixture.boxes_for_slot(_creature, "head").is_empty(),
		"and no head hitboxes at all")
	almost(_creature.stats.max_hp, 100.0, 0.001, "HP drops to the bare torso")


func test_removing_a_required_slot_is_rejected_with_a_clear_error() -> void:
	_creature = CreatureFixture.spawn_bare(tree)
	var problems: PackedStringArray = _creature.assemble(
		CreatureFixture.loadout({"legs": null}))
	is_false(problems.is_empty(), "a legless creature is refused")
	any_contains(problems, PackedStringArray(["Required slot 'legs' is empty"]),
		"and the refusal names the slot")


func test_an_unknown_part_is_rejected() -> void:
	_creature = CreatureFixture.spawn_bare(tree)
	any_contains(_creature.assemble(CreatureFixture.loadout({"head": "head_of_state"})),
		PackedStringArray(["no such part 'head_of_state'"]), "unknown parts are named")


func test_a_part_in_the_wrong_slot_is_rejected() -> void:
	_creature = CreatureFixture.spawn_bare(tree)
	any_contains(_creature.assemble(CreatureFixture.loadout({"head": "tail_scorpion"})),
		PackedStringArray(["belongs in slot 'tail'"]), "slot mismatches are named")


func test_an_unknown_slot_is_rejected() -> void:
	_creature = CreatureFixture.spawn_bare(tree)
	var bad: Dictionary = CreatureFixture.loadout()
	bad["wings"] = "back_bat_scraps"
	any_contains(_creature.assemble(bad),
		PackedStringArray(["has no slot 'wings'"]), "unknown slots are named")


func test_a_rejected_loadout_leaves_the_previous_creature_intact() -> void:
	_creature = CreatureFixture.spawn(tree)
	var before: float = _creature.stats.max_hp
	var sprite_count: int = CreatureFixture.boxes_for_slot(_creature, "torso").size()

	_creature.assemble(CreatureFixture.loadout({"legs": null}))

	almost(_creature.stats.max_hp, before, 0.001, "stats are unchanged after a rejection")
	eq(CreatureFixture.boxes_for_slot(_creature, "torso").size(), sprite_count,
		"and the rig was never torn down")


func test_effects_come_only_from_equipped_parts() -> void:
	_creature = CreatureFixture.spawn(tree)
	is_false(_creature.has_effect("can_glide"), "no wings, no gliding")
	is_false(_creature.has_effect("can_climb"), "no claws, no climbing")

	_creature.assemble(CreatureFixture.loadout({
		"back": "back_bat_scraps", "arms": "arms_climber_claws"}))
	is_true(_creature.has_effect("can_glide"), "the bat scraps grant gliding")
	is_true(_creature.has_effect("can_climb"), "the claws grant climbing")
	eq(str(_creature.stats.effects["can_glide"]), "back_bat_scraps",
		"and the sheet records which part granted it")


func test_weight_class_boundaries_come_from_config() -> void:
	# light ≤ 25, medium ≤ 60, heavy above (game_config.movement.weight_classes)
	eq(WeightClass.class_for_weight(0.0), "light", "an empty frame is Light")
	eq(WeightClass.class_for_weight(25.0), "light", "25 is the top of Light")
	eq(WeightClass.class_for_weight(25.1), "medium", "just over tips to Medium")
	eq(WeightClass.class_for_weight(60.0), "medium", "60 is the top of Medium")
	eq(WeightClass.class_for_weight(60.1), "heavy", "just over tips to Heavy")


func test_weight_class_drives_the_movement_preset() -> void:
	_creature = CreatureFixture.spawn(tree)
	almost(_creature.weight_class.max_speed(), 270.0 * 1.15, 0.01,
		"medium max_speed × the sprinters' 1.15 modifier")

	_creature.assemble(CreatureFixture.loadout({
		"legs": "legs_spring_coils", "head": null}))
	eq(_creature.weight_class.class_id, "medium", "20 torso + 12 coils = 32, still Medium")
	almost(_creature.weight_class.jump_velocity(), -790.0 * 1.3, 0.01,
		"the coils' 1.3 jump_mod multiplies the class jump velocity")


func test_preview_stats_match_a_real_assembly() -> void:
	var loadout: Dictionary = CreatureFixture.loadout({
		"tail": "tail_eraser_club", "back": "back_sketch_thrusters"})
	_creature = CreatureFixture.spawn(tree, loadout)
	var preview: CreatureStats = PartAssembler.preview_stats(loadout, "biped")
	almost(preview.max_hp, _creature.stats.max_hp, 0.001, "the Lab's HP readout is the real HP")
	almost(preview.total_weight, _creature.stats.total_weight, 0.001, "same for weight")
	almost(preview.total_defense, _creature.stats.total_defense, 0.001, "same for defense")
	eq(preview.effects.size(), _creature.stats.effects.size(), "same effects")
