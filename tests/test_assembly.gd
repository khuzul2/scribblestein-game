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
	var kit: Dictionary = CreatureFixture.loadout()
	almost(stats.max_hp, _expected_hp(kit), 0.001, "max_hp = torso.base_hp + Σ hp_bonus")
	almost(stats.total_defense, _stat_sum(kit, "defense"), 0.001, "Σ defense")
	almost(stats.total_weight, _expected_weight(kit), 0.001, "Σ weight")
	almost(stats.speed_mod,
		float((Config.part("legs_scribble_sprint")["stats"] as Dictionary)["speed_mod"]),
		0.001, "the sprinters' speed_mod carries through")
	eq(_creature.weight_class.class_id,
		WeightClass.class_for_weight(_expected_weight(kit)),
		"and the class follows the total")
	almost(_creature.health.maximum, _expected_hp(kit), 0.001,
		"Health takes its ceiling from the assembly")


## Every number here is read out of `parts_db.json` rather than written down.
## The catalogue is tuned regularly; a test that hardcodes a part's HP is
## testing the tuning pass, not the assembly pipeline, and fails for the wrong
## reason every time someone balances the game.
func test_swapping_one_part_changes_sprite_hitboxes_hp_and_weight() -> void:
	_creature = CreatureFixture.spawn(tree)

	var before_texture: Texture2D = CreatureFixture.sprite_on_bone(_creature, "head").texture
	var before_boxes: int = CreatureFixture.boxes_for_slot(_creature, "head").size()
	almost(_creature.stats.max_hp, _expected_hp(CreatureFixture.loadout()), 0.001,
		"starting HP is the sum of the starter kit's")
	eq(_creature.weight_class.class_id,
		WeightClass.class_for_weight(_expected_weight(CreatureFixture.loadout())),
		"starting class")

	# One line of data, no scene edits.
	var swapped: Dictionary = CreatureFixture.loadout({"head": "head_anvil"})
	var problems: PackedStringArray = _creature.assemble(swapped)
	is_true(problems.is_empty(), "the swap is accepted: %s" % str(problems))

	var after_texture: Texture2D = CreatureFixture.sprite_on_bone(_creature, "head").texture
	ne(after_texture.resource_path, before_texture.resource_path, "the head sprite changed")
	almost(_creature.stats.max_hp, _expected_hp(swapped), 0.001,
		"the anvil's hp_bonus replaced the maw's")
	almost(_creature.stats.total_defense, _stat_sum(swapped, "defense"), 0.001,
		"defense is the sum of the equipped parts'")
	almost(_creature.stats.total_weight, _expected_weight(swapped), 0.001,
		"weight is the sum of the equipped parts'")
	eq(_creature.weight_class.class_id,
		WeightClass.class_for_weight(_expected_weight(swapped)),
		"and the class follows the total")

	var after_boxes: Array[Hitbox] = CreatureFixture.boxes_for_slot(_creature, "head")
	eq(after_boxes.size(), (Config.part("head_anvil")["hitboxes"] as Array).size(),
		"the anvil built exactly the boxes its JSON declares")
	var damage_box: Hitbox = after_boxes.filter(
		func(box: Hitbox) -> bool: return box.hitbox_type == Hitbox.TYPE_DAMAGE)[0]
	var declared: Dictionary = _damage_entry("head_anvil")
	eq(str(damage_box.source["shape"]), str(declared["shape"]),
		"with the anvil's own shape")
	almost(damage_box.position.x, float((declared["offset"] as Array)[0]), 0.001,
		"at the anvil's own JSON offset")


func test_attack_power_follows_the_equipped_head() -> void:
	_creature = CreatureFixture.spawn(tree)
	almost(_creature.attack_controller.attack_power("attack_primary"),
		_attack_power("head_monster_maw"), 0.001,
		"the starter head's attack power is wired to the primary button")

	_creature.assemble(CreatureFixture.loadout({"head": "head_pencil_stub"}))
	almost(_creature.attack_controller.attack_power("attack_primary"),
		_attack_power("head_pencil_stub"), 0.001,
		"swapping the head rewires the primary button")


func test_an_empty_attack_slot_leaves_an_inert_button() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({"head": null}))
	is_false(_creature.attack_controller.has_attack("attack_primary"),
		"no head means no primary attack (DESIGN §4.2)")
	is_true(CreatureFixture.boxes_for_slot(_creature, "head").is_empty(),
		"and no head hitboxes at all")
	almost(_creature.stats.max_hp,
		_expected_hp(CreatureFixture.loadout({"head": null})), 0.001,
		"HP drops to what is left equipped")


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
	var sprint: float = float((Config.part("legs_scribble_sprint")["stats"]
		as Dictionary)["speed_mod"])
	almost(_creature.weight_class.max_speed(),
		Config.cfg_float("movement.weight_classes.medium.max_speed") * sprint, 0.01,
		"medium max_speed × the sprinters' own modifier")

	var coiled: Dictionary = CreatureFixture.loadout({
		"legs": "legs_spring_coils", "head": null})
	_creature.assemble(coiled)
	eq(_creature.weight_class.class_id,
		WeightClass.class_for_weight(_expected_weight(coiled)),
		"the class follows the total weight")
	var boost: float = float((Config.part("legs_spring_coils")["stats"]
		as Dictionary)["jump_mod"])
	almost(_creature.weight_class.jump_velocity(),
		Config.cfg_float("movement.weight_classes.medium.jump_velocity") * boost, 0.01,
		"the coils' jump_mod multiplies the class jump velocity")


func test_preview_stats_match_a_real_assembly() -> void:
	var loadout: Dictionary = CreatureFixture.loadout({
		"tail": "tail_eraser_club", "back": "back_sketch_thrusters"})
	_creature = CreatureFixture.spawn(tree, loadout)
	var preview: CreatureStats = PartAssembler.preview_stats(loadout, "biped")
	almost(preview.max_hp, _creature.stats.max_hp, 0.001, "the Lab's HP readout is the real HP")
	almost(preview.total_weight, _creature.stats.total_weight, 0.001, "same for weight")
	almost(preview.total_defense, _creature.stats.total_defense, 0.001, "same for defense")
	eq(preview.effects.size(), _creature.stats.effects.size(), "same effects")



func test_the_body_collider_turns_with_the_creature() -> void:
	# A tail makes the hurtbox union asymmetric, so the body box sits off-centre.
	# It has to follow the creature around: left alone it stays pointing the way
	# the creature was first built, and a Stinger that turns to face you ends up
	# with a slab of collider sticking out of its chest — walling off corridors
	# and holding attackers outside their own reach while its hurtboxes sit
	# somewhere else entirely.
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({
		"tail": "tail_scorpion"}), false)
	_creature.facing = 1
	var right_offset: float = _creature.body_collider.position.x
	is_true(absf(right_offset) > 20.0,
		"a tailed creature's body box really is off-centre (%.0f px)" % right_offset)

	_creature.facing = -1
	var left_offset: float = _creature.body_collider.position.x
	almost(left_offset, -right_offset, 1.0,
		"turning around mirrors the offset")

	# And the box still covers the hurtboxes it is meant to describe.
	var box: RectangleShape2D = _creature.body_collider.shape as RectangleShape2D
	var span: Vector2 = Vector2(
		_creature.body_collider.global_position.x - box.size.x * 0.5,
		_creature.body_collider.global_position.x + box.size.x * 0.5)
	for hurtbox: Hitbox in _creature.hitbox_root.hurtboxes():
		is_true(hurtbox.global_position.x >= span.x - 1.0
				and hurtbox.global_position.x <= span.y + 1.0,
			"the %s hurtbox is inside the body box" % hurtbox.slot)

# --- what the catalogue says, so the test never disagrees with it --------------

func _equipped(loadout: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for slot: Variant in loadout:
		if loadout[slot] != null:
			parts.append(Config.part(str(loadout[slot])))
	return parts


func _stat_sum(loadout: Dictionary, key: String) -> float:
	var total: float = 0.0
	for part: Dictionary in _equipped(loadout):
		total += float((part["stats"] as Dictionary).get(key, 0.0))
	return total


func _expected_hp(loadout: Dictionary) -> float:
	return _stat_sum(loadout, "base_hp") + _stat_sum(loadout, "hp_bonus")


func _expected_weight(loadout: Dictionary) -> float:
	var total: float = 0.0
	for part: Dictionary in _equipped(loadout):
		total += float(part["weight"])
	return total


func _attack_power(part_id: String) -> float:
	return float((Config.part(part_id)["stats"] as Dictionary).get("attack_power", 0.0))


func _damage_entry(part_id: String) -> Dictionary:
	for entry: Variant in Config.part(part_id)["hitboxes"] as Array:
		if str((entry as Dictionary)["type"]) == "damage":
			return entry as Dictionary
	return {}
