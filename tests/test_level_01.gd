extends TestCase

## M7 acceptance for Level 01 "The Margins".
##
## The gate proofs run `JumpMath` over every legal loadout, so "impassable
## without a glide part" means all 648 of them, not the two a playtester tried.

const LEVEL_ID: String = "level_01_margins"
const LEVEL_SCENE: String = "res://scenes/levels/level_01_margins.tscn"

var _saved_profile: Dictionary = {}
var _level: PlayScene = null


func before_each() -> void:
	_saved_profile = SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	Combat.hitstop_enabled = false


func after_each() -> void:
	Combat.hitstop_enabled = true
	if is_instance_valid(_level):
		_level.get_parent().remove_child(_level)
		_level.queue_free()
	_level = null
	DirAccess.remove_absolute(SaveManager.SAVE_PATH)
	SaveManager.data = _saved_profile


func _enter() -> PlayScene:
	_level = (load(LEVEL_SCENE) as PackedScene).instantiate() as PlayScene
	tree.root.add_child(_level)
	_level.player.player_input.set_enabled(false)
	return _level


func _script() -> GDScript:
	return load("res://scripts/levels/level_01_margins.gd") as GDScript


# --- the gates, proved over every legal loadout --------------------------------

func test_the_glide_gap_is_impassable_without_a_glide_part() -> void:
	var gap: float = float(_script().get("GLIDE_GAP"))
	var drop: float = float(_script().get("GLIDE_DROP"))

	var best_without: float = JumpMath.best_reach_without("can_glide", drop)
	is_true(best_without < gap,
		"the best of all %d legal non-glide builds reaches %.0f px, short of the %.0f px gap"
		% [JumpMath.every_loadout().size(), best_without, gap])

	var worst_with: float = JumpMath.worst_reach_with("can_glide", drop)
	is_true(worst_with > gap,
		"while even the worst glide build reaches %.0f px, clearing it" % worst_with)


func test_the_glide_gap_has_margin_on_both_sides() -> void:
	# A gate that is only just impossible reads as a bug when a good player
	# nearly makes it. Insist on real daylight either way.
	var gap: float = float(_script().get("GLIDE_GAP"))
	var drop: float = float(_script().get("GLIDE_DROP"))
	is_true(gap - JumpMath.best_reach_without("can_glide", drop) > 50.0,
		"no non-glide build comes within 50 px of the ledge")
	is_true(JumpMath.worst_reach_with("can_glide", drop) - gap > 50.0,
		"and no glide build has to be pixel perfect")


func test_the_glide_ledge_hangs_over_the_route_rather_than_across_it() -> void:
	# The ledge is a reward you fly to, not a wall you meet. It floats above the
	# chasm floor, so the head-room underneath has to clear the tallest legal
	# creature — otherwise the critical path is blocked for anyone who cannot
	# glide, which is the exact opposite of what the gate is for.
	var clearance: float = float(_script().get("LEDGE_CLEARANCE")) \
		- float(_script().get("LEDGE_THICKNESS"))
	var tallest: float = JumpMath.standing_height_range().y
	is_true(clearance > tallest,
		"%.0f px of head-room under the ledge clears the tallest build (%.0f px)"
			% [clearance, tallest])


func test_the_climb_shaft_is_taller_than_any_jump_in_the_game() -> void:
	var shaft: float = float(_script().get("SHAFT_HEIGHT"))
	var best_apex: float = 0.0
	for loadout: Dictionary in JumpMath.every_loadout():
		var stats: CreatureStats = PartAssembler.preview_stats(loadout, "biped")
		var weight_class: String = WeightClass.class_for_weight(stats.total_weight)
		var jump: float = Config.cfg_float(
			"movement.weight_classes.%s.jump_velocity" % weight_class) * stats.jump_mod
		var apex: float = JumpMath.apex_height(jump)
		if stats.has_effect("double_jump"):
			apex += JumpMath.apex_height(
				jump * Config.cfg_float("movement.double_jump.velocity_mult"))
		best_apex = maxf(best_apex, apex)
	is_true(shaft > best_apex + 100.0,
		"the %.0f px shaft is out of reach of the best jump in the game (%.0f px)"
		% [shaft, best_apex])


func test_the_crawl_tunnel_admits_a_ducking_creature_and_no_standing_one() -> void:
	var clearance: float = float(_script().get("TUNNEL_CLEARANCE"))
	var heights: Vector2 = JumpMath.standing_height_range()
	var squash: float = Config.cfg_float("movement.crouch.hurtbox_height_mult")

	is_true(clearance < heights.x,
		"the %.0f px tunnel is shorter than the shortest standing build (%.0f px)"
		% [clearance, heights.x])
	is_true(clearance > heights.y * squash,
		"and taller than the tallest crouched one (%.0f px)" % (heights.y * squash))


# --- the level itself ----------------------------------------------------------

func test_the_level_contains_all_three_enemy_types() -> void:
	var level: PlayScene = _enter()
	await tree.physics_frame

	var kinds: Dictionary = {}
	for enemy: Creature in level.enemies():
		kinds[EnemyFactory.id_of(enemy)] = true
	for enemy_id: Variant in Config.enemies:
		is_true(kinds.has(enemy_id), "'%s' appears in the level" % enemy_id)


func test_the_level_telegraphs_its_keys() -> void:
	var level: PlayScene = _enter()
	var signage: PackedStringArray = PackedStringArray()
	for child: Node in level.get_children():
		if child is Label:
			signage.append((child as Label).text.to_lower())
	var all_text: String = " ".join(signage)
	is_true(all_text.contains("claws"), "the climb gate is signposted")
	is_true(all_text.contains("wings"), "the glide gate is signposted")
	is_true(all_text.contains("duck"), "the crawl tunnel is signposted")
	is_true(all_text.contains("heavy"), "the cracked floor is signposted")


func test_the_level_holds_a_cracked_floor_and_a_climbable_wall() -> void:
	var level: PlayScene = _enter()
	var cracked: int = 0
	var climbable: int = 0
	for child: Node in level.get_children():
		if child is CrackedFloor:
			cracked += 1
		elif child is Area2D and child.name == "Climbable":
			climbable += 1
	is_true(cracked >= 1, "there is a cracked floor")
	is_true(climbable >= 1, "and a climbable wall")


func test_reaching_the_exit_marks_the_level_complete_and_persists() -> void:
	var level: PlayScene = _enter()
	is_false(SaveManager.is_level_completed(LEVEL_ID), "not cleared yet")

	var door: ExitDoor = level.get("exit_door") as ExitDoor
	not_null(door, "the level has a way out")
	door.reached.emit(level.player)
	await tree.physics_frame

	is_true(SaveManager.is_level_completed(LEVEL_ID), "clearing it marks the map")

	SaveManager.data = {}
	SaveManager.load_game()
	is_true(SaveManager.is_level_completed(LEVEL_ID), "and the mark survives a relaunch")


func test_the_level_is_reachable_from_the_map_table() -> void:
	is_true(Config.map_level_ids().has(LEVEL_ID), "it is on the world map")
	is_true((Config.level(LEVEL_ID).get("requires", []) as Array).is_empty(),
		"and nothing gates it, so a new player can start")
	is_true(ResourceLoader.exists(str(Config.level(LEVEL_ID)["scene"])),
		"and its scene exists")


func test_the_player_enters_wearing_the_committed_loadout() -> void:
	SaveManager.unlock_part("back_bat_scraps")
	SaveManager.set_loadout(CreatureFixture.loadout({"back": "back_bat_scraps"}))
	var level: PlayScene = _enter()
	eq(str(level.player.stats.loadout["back"]), "back_bat_scraps",
		"the build you committed to in the Lab is the one you are wearing")
	is_true(level.player.has_effect("can_glide"), "with its abilities intact")


# --- completability ------------------------------------------------------------

func test_the_level_is_walkable_end_to_end_with_the_starter_kit() -> void:
	# MILESTONES M7: "completable with the intended loadouts". The bot knows only
	# what a first-time player can see — head right, jump at a wall or a ledge,
	# duck under a ceiling, hit what is in the way — so if it gets out, the route
	# really is walkable with no unlocks at all.
	SaveManager.set_loadout(CreatureFixture.loadout())
	var level: PlayScene = _enter()

	var bot: Autopilot = Autopilot.new()
	level.add_child(bot)
	bot.drive(level)

	# Ninety seconds of game time; the intended clear is 5-10 minutes for a human
	# who explores, and the bot beelines.
	for _i: int in range(5400):
		await tree.physics_frame
		if bot.reached_exit:
			break

	is_true(bot.reached_exit,
		"the bot reached the exit in %.1f s (it got as far as x=%d)"
		% [bot.elapsed, int(level.player.global_position.x)])
	is_true(SaveManager.is_level_completed(LEVEL_ID), "and the level is marked cleared")


func test_a_starter_kit_run_earns_ink_on_the_way() -> void:
	# The loop only works if a clear pays for something (DESIGN §2, §8).
	SaveManager.set_loadout(CreatureFixture.loadout())
	var level: PlayScene = _enter()
	var bot: Autopilot = Autopilot.new()
	level.add_child(bot)
	bot.drive(level)

	for _i: int in range(5400):
		await tree.physics_frame
		if bot.reached_exit:
			break

	is_true(SaveManager.ink > 0,
		"a clean run comes home with ink to spend (got %d)" % SaveManager.ink)
