extends TestCase

## M9: the Crooked Quadruped is a real second body type, not a variant.
##
## It must rig from its own bone tree through the *same* assembler the biped
## uses (Mandate B2), move on its own pounce profile, be buildable in the Lab
## only once discovered, and keep its own loadout so switching never costs you a
## build.

const FLOOR_Y: float = 0.0

var _stage: Node2D = null
var _creature: Creature = null


func before_each() -> void:
	_stage = WorldFixture.stage(tree)
	WorldFixture.floor_at(_stage, FLOOR_Y)


func after_each() -> void:
	CreatureFixture.despawn(_creature)
	WorldFixture.clear(_stage)
	_creature = null
	_stage = null


# --- the blueprint is real -----------------------------------------------------

func test_the_quadruped_is_no_longer_a_stub() -> void:
	var blueprint: Dictionary = Config.blueprint("quadruped")
	is_false(blueprint.has("status"), "the STUB marker is gone")
	eq(str(blueprint["movement_profile_override"]), "pounce", "it names a movement profile")
	not_null(Config.cfg("movement.profiles.pounce"),
		"and game_config.json defines that profile")


func test_every_required_quadruped_slot_has_a_part_that_fills_it() -> void:
	var slots: Dictionary = Config.blueprint("quadruped")["slots"] as Dictionary
	for slot_id: Variant in slots:
		if not bool((slots[slot_id] as Dictionary).get("required", false)):
			continue
		var count: int = 0
		for part_id: Variant in Config.parts:
			var part: Dictionary = Config.parts[part_id] as Dictionary
			if str(part["slot"]) == str(slot_id) \
					and (part["fits_blueprints"] as Array).has("quadruped"):
				count += 1
		is_true(count > 0, "required slot '%s' has %d part(s)" % [slot_id, count])


func test_a_quadruped_can_be_built_from_free_parts_alone() -> void:
	# Otherwise unlocking the blueprint would hand the player a body they cannot
	# stand up.
	var loadout: Dictionary = {}
	for slot_id: Variant in (Config.blueprint("quadruped")["slots"] as Dictionary):
		loadout[str(slot_id)] = null
	for part_id: String in Config.free_part_ids("quadruped"):
		var slot: String = str(Config.part(part_id)["slot"])
		if loadout.has(slot) and loadout[slot] == null:
			loadout[slot] = part_id
	var problems: PackedStringArray = PartAssembler.validate(loadout, "quadruped")
	is_true(problems.is_empty(), "a free-parts-only quadruped is legal: %s" % [problems])


# --- rigging -------------------------------------------------------------------

func test_it_rigs_from_its_own_bone_tree() -> void:
	_creature = _spawn_quadruped()
	var bones: Dictionary = Config.blueprint("quadruped")["bones"] as Dictionary
	for bone_id: Variant in bones:
		not_null(CreatureFixture.bone(_creature, str(bone_id)),
			"bone '%s' was built" % bone_id)
	is_null(CreatureFixture.bone(_creature, "hip"),
		"and the biped's own bones are not")


func test_front_and_rear_legs_mount_on_different_bones() -> void:
	_creature = _spawn_quadruped()
	var front: Sprite2D = CreatureFixture.sprite_on_bone(_creature, "hip_front")
	var rear: Sprite2D = CreatureFixture.sprite_on_bone(_creature, "hip_rear")
	not_null(front, "a sprite hangs on the front hip")
	not_null(rear, "a sprite hangs on the rear hip")
	ne(front.texture.resource_path, rear.texture.resource_path,
		"they are separate parts, so a build can mix them (DECISIONS_NEEDED D2)")


func test_a_biped_only_part_is_refused() -> void:
	var loadout: Dictionary = _free_loadout("quadruped")
	loadout["legs_front"] = "legs_scribble_sprint"
	var problems: PackedStringArray = PartAssembler.validate(loadout, "quadruped")
	is_false(problems.is_empty(), "biped legs cannot be bolted onto a quadruped")


func test_a_quadruped_stands_lower_than_a_biped_from_the_same_torso() -> void:
	_creature = _spawn_quadruped()
	var quadruped_height: float = _creature.standing_body_box().size.y
	CreatureFixture.despawn(_creature)

	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	_creature.player_input.set_enabled(false)
	var biped_height: float = _creature.standing_body_box().size.y
	is_true(quadruped_height < biped_height,
		"quadruped %.0f px vs biped %.0f px" % [quadruped_height, biped_height])


# --- the pounce ----------------------------------------------------------------

func test_a_pounce_leaves_the_ground_faster_than_it_runs() -> void:
	_creature = _spawn_quadruped()
	await _settle()

	# Run up to speed first, so the launch is measured against a real gait.
	for _i: int in range(60):
		_creature.locomotion.intent.move_axis = 1.0
		await tree.physics_frame
	var running: float = absf(_creature.velocity.x)
	is_true(running > 1.0, "it is running (%.0f px/s)" % running)

	_creature.locomotion.intent.move_axis = 1.0
	_creature.locomotion.intent.press_jump()
	await tree.physics_frame
	var launched: float = absf(_creature.velocity.x)

	var expected: float = running * float(
		(Config.cfg("movement.profiles.pounce") as Dictionary)["launch_speed_mult"])
	within_percent(launched, expected, 2.0,
		"the launch is launch_speed_mult of running speed")


func test_a_pounce_bleeds_back_down_to_running_speed() -> void:
	_creature = _spawn_quadruped()
	await _settle()
	for _i: int in range(60):
		_creature.locomotion.intent.move_axis = 1.0
		await tree.physics_frame
	var running: float = absf(_creature.velocity.x)

	_creature.locomotion.intent.move_axis = 1.0
	_creature.locomotion.intent.press_jump()
	await tree.physics_frame
	var launched: float = absf(_creature.velocity.x)

	for _i: int in range(20):
		_creature.locomotion.intent.move_axis = 1.0
		_creature.locomotion.intent.jump_held = true
		await tree.physics_frame
	var later: float = absf(_creature.velocity.x)
	is_true(later < launched, "the burst decays (%.0f -> %.0f)" % [launched, later])
	is_true(later >= running - 1.0,
		"but never below running speed (%.0f vs %.0f)" % [later, running])


func test_knockback_still_decays_normally_on_a_quadruped() -> void:
	# The launch decay must not take over every overspeed, or being hit would
	# send a quadruped skating.
	_creature = _spawn_quadruped()
	await _settle()
	_creature.velocity.x = 1200.0
	for _i: int in range(30):
		await tree.physics_frame
	is_true(absf(_creature.velocity.x) < 200.0,
		"knockback bled off at the weight class' deceleration (%.0f px/s left)"
			% absf(_creature.velocity.x))


func test_a_biped_is_untouched_by_the_pounce_profile() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	_creature.player_input.set_enabled(false)
	_creature.position = Vector2(0.0, FLOOR_Y - 40.0)
	await _settle()
	for _i: int in range(60):
		_creature.locomotion.intent.move_axis = 1.0
		await tree.physics_frame
	var running: float = absf(_creature.velocity.x)

	_creature.locomotion.intent.move_axis = 1.0
	_creature.locomotion.intent.press_jump()
	await tree.physics_frame
	within_percent(absf(_creature.velocity.x), running, 5.0,
		"a biped jump does not launch")


func test_the_reach_maths_knows_about_the_pounce() -> void:
	# `JumpMath` is what proves a level's gates, so it has to model the profile
	# the creature actually moves on.
	var loadout: Dictionary = _free_loadout("quadruped")
	var stats: CreatureStats = PartAssembler.preview_stats(loadout, "quadruped")
	var with_profile: float = JumpMath.horizontal_reach(stats, 0.0, "quadruped")
	var without_profile: float = JumpMath.horizontal_reach(stats, 0.0, "biped")
	is_true(with_profile > without_profile,
		"a pounce carries further than the same build's plain jump (%.0f vs %.0f)"
			% [with_profile, without_profile])


# --- save & Lab ----------------------------------------------------------------

func test_a_fresh_profile_starts_as_a_locked_biped() -> void:
	var profile: Dictionary = SaveManager.default_save()
	eq(str(profile["active_blueprint"]), "biped", "you start as a biped")
	is_false((profile["blueprint_unlocked"] as Array).has("quadruped"),
		"the quadruped has to be found")


func test_switching_to_a_locked_blueprint_is_refused() -> void:
	SaveManager.data = SaveManager.default_save()
	is_false(SaveManager.set_active_blueprint("quadruped"), "refused while locked")
	eq(SaveManager.active_blueprint(), "biped", "and the body type did not change")


func test_unlocking_the_quadruped_grants_legs_to_stand_on() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager.unlock_blueprint("quadruped")
	is_true(SaveManager.is_blueprint_unlocked("quadruped"), "the blueprint is unlocked")

	is_true(SaveManager.set_active_blueprint("quadruped"), "and can be switched to")
	var loadout: Dictionary = SaveManager.loadout()
	var problems: PackedStringArray = PartAssembler.validate(loadout, "quadruped")
	is_true(problems.is_empty(),
		"the granted loadout assembles straight away: %s" % [problems])


func test_each_body_type_keeps_its_own_build() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager.unlock_blueprint("quadruped")

	var biped_build: Dictionary = SaveManager.loadout("biped").duplicate(true)
	SaveManager.set_active_blueprint("quadruped")
	SaveManager.set_loadout_slot("head", null)
	SaveManager.set_active_blueprint("biped")

	eq(SaveManager.loadout(), biped_build, "the biped build came back untouched")


func test_the_active_blueprint_survives_a_save_round_trip() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager.unlock_blueprint("quadruped")
	SaveManager.set_active_blueprint("quadruped")
	is_true(SaveManager.save_game(), "the profile wrote")

	SaveManager.data = {}
	SaveManager.load_game()
	eq(SaveManager.active_blueprint(), "quadruped", "it reloaded as a quadruped")
	is_true(SaveManager.is_blueprint_unlocked("quadruped"), "still unlocked")


func test_a_version_one_save_keeps_its_biped_build() -> void:
	var legacy: Dictionary = {
		"version": 1,
		"ink": 42,
		"unlocked_parts": ["torso_ribby", "legs_scribble_sprint", "head_monster_maw"],
		"loadout": {
			"torso": "torso_ribby", "legs": "legs_tree_trunks",
			"head": null, "tail": null, "arms": null, "back": null,
		},
		"blueprint_unlocked": ["biped"],
	}
	var path: String = SaveManager.SAVE_PATH
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()

	SaveManager.data = {}
	SaveManager.load_game()
	eq(int(SaveManager.data["version"]), SaveManager.SAVE_VERSION, "migrated to v2")
	eq(SaveManager.ink, 42, "the ink survived")
	eq(SaveManager.loadout("biped")["legs"], "legs_tree_trunks",
		"and so did the build that was in the old `loadout` key")
	is_true((SaveManager.loadouts() as Dictionary).has("quadruped"),
		"a quadruped loadout was added alongside it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- the Lab -------------------------------------------------------------------

func test_the_desk_sells_the_body_and_the_sketchbook_grows_a_tab() -> void:
	var saved_profile: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()

	var editor: SketchbookEditor = SketchbookEditor.new()
	tree.root.add_child(editor)
	await tree.process_frame
	is_null(editor.find_child("BlueprintTabs", true, false),
		"with one body type there is nothing to choose between")

	var desk: UnlockDesk = UnlockDesk.new()
	tree.root.add_child(desk)
	await tree.process_frame

	var cost: int = int(Config.blueprint("quadruped")["unlock_cost"])
	SaveManager.ink = cost + 10
	desk.refresh()
	desk._buy_blueprint("quadruped")

	eq(SaveManager.ink, 10, "the desk charged exactly the blueprint's price")
	is_true(SaveManager.is_blueprint_unlocked("quadruped"), "and unlocked it")

	editor.switch_blueprint("quadruped")
	await tree.process_frame
	eq(editor.blueprint_id, "quadruped", "the sketchbook switched")
	not_null(editor.find_child("BlueprintTabs", true, false),
		"and now offers a tab per body type")
	for slot_id: Variant in (Config.blueprint("quadruped")["slots"] as Dictionary):
		is_true(editor.loadout.has(slot_id), "the page has a '%s' slot" % slot_id)
	is_false(editor.loadout.has("arms"), "and no arms, which a quadruped lacks")

	for node: Node in [editor, desk]:
		node.get_parent().remove_child(node)
		node.queue_free()
	SaveManager.data = saved_profile


func test_the_sketchbook_only_offers_parts_that_fit_the_body() -> void:
	var saved_profile: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	SaveManager.unlock_blueprint("quadruped")
	SaveManager.set_active_blueprint("quadruped")

	var editor: SketchbookEditor = SketchbookEditor.new()
	tree.root.add_child(editor)
	await tree.process_frame

	for part_id: String in editor.owned_parts_for("legs_front"):
		is_true((Config.part(part_id)["fits_blueprints"] as Array).has("quadruped"),
			"'%s' is offered and does fit a quadruped" % part_id)
	eq(editor.owned_parts_for("legs").size(), 0,
		"the biped's `legs` slot offers nothing here — it is not a slot this body has")

	editor.get_parent().remove_child(editor)
	editor.queue_free()
	SaveManager.data = saved_profile


# --- helpers -------------------------------------------------------------------

func _free_loadout(blueprint_id: String) -> Dictionary:
	var loadout: Dictionary = {}
	for slot_id: Variant in (Config.blueprint(blueprint_id)["slots"] as Dictionary):
		loadout[str(slot_id)] = null
	for part_id: String in Config.free_part_ids(blueprint_id):
		var slot: String = str(Config.part(part_id)["slot"])
		if loadout.has(slot) and loadout[slot] == null:
			loadout[slot] = part_id
	return loadout


func _spawn_quadruped() -> Creature:
	var creature: Creature = CreatureFixture.spawn_bare(tree, true)
	creature.blueprint_id = "quadruped"
	creature.assemble(_free_loadout("quadruped"))
	creature.player_input.set_enabled(false)
	creature.position = Vector2(0.0, FLOOR_Y - 40.0)
	return creature


func _settle(ticks: int = 30) -> void:
	for _i: int in range(ticks):
		await tree.physics_frame
