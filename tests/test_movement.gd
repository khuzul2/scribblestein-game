extends TestCase

## M2 acceptance: the measured motion must match the formulas the config
## implies, per weight class, and every mobility effect must come from a part.

const FLOOR_Y: float = 0.0
## Enough ticks for any jump in the game to rise and fall.
const FLIGHT_TICKS: int = 140

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


# --- setup helpers -------------------------------------------------------------

func _spawn(loadout: Dictionary, at_x: float = 0.0) -> Creature:
	_creature = CreatureFixture.spawn(tree, loadout, true)
	_creature.player_input.set_enabled(false)
	_creature.position = Vector2(at_x, FLOOR_Y - 40.0)
	return _creature


func _settle(ticks: int = 30) -> void:
	for _i: int in range(ticks):
		await tree.physics_frame


func _tick(count: int = 1) -> void:
	for _i: int in range(count):
		await tree.physics_frame


## Step until the creature is off the ground; returns how many ticks that took.
func _wait_until_airborne(limit: int = 30) -> int:
	for i: int in range(limit):
		await tree.physics_frame
		if not _creature.is_on_floor():
			return i + 1
	return 0


## The apex height a jump should reach: v² / 2g, straight out of the config.
func _expected_apex(jump_velocity: float) -> float:
	return (jump_velocity * jump_velocity) / (2.0 * Config.cfg_float("movement.gravity"))


## Jump, then report how far above its starting height the creature got.
func _measure_apex() -> float:
	var start_y: float = _creature.position.y
	var highest: float = start_y
	_creature.locomotion.intent.press_jump()
	for _i: int in range(FLIGHT_TICKS):
		await tree.physics_frame
		highest = minf(highest, _creature.position.y)
		_creature.locomotion.intent.jump_held = false
		if _creature.is_on_floor() and _creature.velocity.y >= 0.0 and _i > 4:
			break
	return start_y - highest


# --- jump apex per class -------------------------------------------------------

func test_medium_jump_apex_matches_the_formula() -> void:
	_spawn(CreatureFixture.loadout())
	await _settle()
	eq(_creature.weight_class.class_id, "medium", "the starter kit is Medium")
	var apex: float = await _measure_apex()
	within_percent(apex, _expected_apex(_creature.weight_class.jump_velocity()), 0.05,
		"Medium apex")


func test_heavy_jump_apex_matches_the_formula() -> void:
	_spawn(CreatureFixture.loadout({
		"torso": "torso_barrel", "legs": "legs_tree_trunks", "head": "head_anvil"}))
	await _settle()
	eq(_creature.weight_class.class_id, "heavy", "a barrel, trunks and an anvil weigh 120")
	var apex: float = await _measure_apex()
	within_percent(apex, _expected_apex(_creature.weight_class.jump_velocity()), 0.05,
		"Heavy apex")


func test_light_jump_apex_matches_the_formula() -> void:
	# No legal biped reaches the Light band with the shipped 14 parts — see
	# DECISIONS_NEEDED.md D4. The preset still has to drive the motion correctly,
	# so force the class and measure.
	_spawn(CreatureFixture.loadout({"head": null}))
	_creature.weight_class.class_id = "light"
	await _settle()
	var apex: float = await _measure_apex()
	within_percent(apex, _expected_apex(_creature.weight_class.jump_velocity()), 0.05,
		"Light apex")


func test_jump_height_scales_with_the_parts_jump_mod() -> void:
	_spawn(CreatureFixture.loadout({"legs": "legs_spring_coils", "head": null}))
	await _settle()
	var boost: float = float((Config.part("legs_spring_coils")["stats"]
		as Dictionary)["jump_mod"])
	almost(_creature.weight_class.jump_velocity(),
		Config.cfg_float("movement.weight_classes.medium.jump_velocity") * boost, 0.01,
		"the coils' jump_mod multiplies the class velocity")
	var apex: float = await _measure_apex()
	within_percent(apex, _expected_apex(_creature.weight_class.jump_velocity()), 0.05,
		"boosted apex")


# --- coyote time and jump buffering (Mandate B6) --------------------------------

func test_a_jump_within_coyote_time_still_fires() -> void:
	_spawn(CreatureFixture.loadout(), 0.0)
	await _settle()

	# Step off the end of the world and fall.
	WorldFixture.clear(_stage)
	_stage = WorldFixture.stage(tree)
	var airborne: int = await _wait_until_airborne()
	is_true(airborne > 0, "the creature has left the ledge")

	# Coyote time is measured from the last grounded tick. Wait until just
	# inside the window, then press.
	var window_ticks: int = int(Config.cfg_float("movement.coyote_time") * 60.0)
	await _tick(maxi(window_ticks - airborne - 2, 0))
	_creature.locomotion.intent.press_jump()
	await _tick(1)
	is_true(_creature.velocity.y < -100.0,
		"a jump inside the %d-tick coyote window still fires" % window_ticks)


func test_a_jump_after_coyote_time_does_not_fire() -> void:
	_spawn(CreatureFixture.loadout(), 0.0)
	await _settle()
	WorldFixture.clear(_stage)
	_stage = WorldFixture.stage(tree)
	await _wait_until_airborne()

	await _tick(int(Config.cfg_float("movement.coyote_time") * 60.0) + 6)
	_creature.locomotion.intent.press_jump()
	await _tick(1)
	is_true(_creature.velocity.y > 0.0, "past the window, the creature keeps falling")


func test_a_jump_buffered_before_landing_fires_on_touchdown() -> void:
	_spawn(CreatureFixture.loadout())
	await _settle()
	_creature.position.y = FLOOR_Y - 400.0
	_creature.velocity = Vector2.ZERO

	# Press while still falling but inside the buffer window, then check the
	# jump fires on touchdown rather than being dropped.
	var pressed: bool = false
	var jumped_again: bool = false
	for _i: int in range(90):
		if not pressed and not _creature.is_on_floor() \
				and _creature.position.y > FLOOR_Y - 90.0:
			_creature.locomotion.intent.press_jump()
			_creature.locomotion.intent.jump_held = false
			pressed = true
		await tree.physics_frame
		if pressed and _creature.is_on_floor():
			await tree.physics_frame
			jumped_again = _creature.velocity.y < -100.0
			break
	is_true(pressed, "the test pressed jump while still in the air")
	is_true(jumped_again, "the buffered press fires the moment the floor arrives")


# --- glide ---------------------------------------------------------------------

func test_glide_caps_fall_speed_only_while_held_and_only_with_wings() -> void:
	var cap: float = Config.cfg_float("movement.glide.glide_fall_cap")
	_spawn(CreatureFixture.loadout({"back": "back_bat_scraps"}))
	await _settle()
	_creature.position.y = FLOOR_Y - 1400.0
	_creature.velocity = Vector2.ZERO

	# Falling with the button held: capped.
	_creature.locomotion.intent.jump_held = true
	await _tick(40)
	is_true(_creature.locomotion.is_gliding(), "the creature is gliding")
	almost(_creature.velocity.y, cap, 2.0, "fall speed sits at glide_fall_cap")

	# Release: normal gravity resumes and it accelerates past the cap.
	_creature.locomotion.intent.jump_held = false
	await _tick(20)
	is_true(_creature.velocity.y > cap * 1.5, "releasing drops the cap")


func test_without_wings_holding_the_button_does_nothing() -> void:
	var cap: float = Config.cfg_float("movement.glide.glide_fall_cap")
	_spawn(CreatureFixture.loadout())
	await _settle()
	_creature.position.y = FLOOR_Y - 1400.0
	_creature.velocity = Vector2.ZERO
	_creature.locomotion.intent.jump_held = true
	await _tick(40)

	is_false(_creature.locomotion.is_gliding(), "no wings, no glide")
	is_true(_creature.velocity.y > cap * 2.0, "the creature falls at full speed")


func test_gliding_never_exceeds_the_cap_over_a_long_fall() -> void:
	var cap: float = Config.cfg_float("movement.glide.glide_fall_cap")
	_spawn(CreatureFixture.loadout({"back": "back_bat_scraps"}))
	await _settle()
	_creature.position.y = FLOOR_Y - 3000.0
	_creature.velocity = Vector2.ZERO
	_creature.locomotion.intent.jump_held = true

	var worst: float = 0.0
	for _i: int in range(120):
		await tree.physics_frame
		worst = maxf(worst, _creature.velocity.y)
	is_true(worst <= cap + 2.0, "peak fall speed %.1f never passes the %.0f cap" % [worst, cap])


# --- double jump ---------------------------------------------------------------

func test_double_jump_gives_exactly_one_extra_jump_per_airtime() -> void:
	_spawn(CreatureFixture.loadout({"back": "back_sketch_thrusters"}))
	await _settle()

	_creature.locomotion.intent.press_jump()
	await _tick(1)
	_creature.locomotion.intent.jump_held = false
	await _tick(20)
	var rising_speed: float = _creature.velocity.y

	_creature.locomotion.intent.press_jump()
	await _tick(1)
	_creature.locomotion.intent.jump_held = false
	is_true(_creature.velocity.y < rising_speed - 100.0, "the second press pushes it up again")
	almost(_creature.velocity.y,
		_creature.weight_class.jump_velocity() * Config.cfg_float("movement.double_jump.velocity_mult"),
		45.0, "at the configured fraction of a full jump")

	await _tick(20)
	var before_third: float = _creature.velocity.y
	_creature.locomotion.intent.press_jump()
	await _tick(1)
	is_true(_creature.velocity.y > before_third, "and a third press does nothing")


func test_without_thrusters_there_is_no_double_jump() -> void:
	_spawn(CreatureFixture.loadout())
	await _settle()
	_creature.locomotion.intent.press_jump()
	await _tick(20)
	_creature.locomotion.intent.jump_held = false
	var before: float = _creature.velocity.y
	_creature.locomotion.intent.press_jump()
	await _tick(1)
	is_true(_creature.velocity.y > before, "the second press is ignored")


# --- climbing ------------------------------------------------------------------

func test_climbing_needs_claws_a_wall_and_the_button() -> void:
	var wall_x: float = 120.0
	WorldFixture.wall_at(_stage, wall_x, FLOOR_Y - 600.0)
	WorldFixture.climbable_region(_stage, Vector2(wall_x + 20.0, FLOOR_Y - 600.0),
		Vector2(120.0, 1200.0))

	_spawn(CreatureFixture.loadout({"arms": "arms_climber_claws"}), wall_x - 45.0)
	await _settle()

	# Walk into the wall so the sensor overlaps it.
	_creature.locomotion.intent.move_axis = 1.0
	await _tick(20)
	is_true(_creature.locomotion.touching_climbable(), "the sensor sees the climbable region")

	var start_y: float = _creature.position.y
	_creature.locomotion.intent.climb_held = true
	await _tick(30)
	is_true(_creature.position.y < start_y - 50.0, "holding climb_up ascends the wall")
	almost(_creature.velocity.y, -Config.cfg_float("movement.climb.climb_speed"), 1.0,
		"at exactly climb_speed")


func test_without_claws_a_wall_is_just_a_wall() -> void:
	var wall_x: float = 120.0
	WorldFixture.wall_at(_stage, wall_x, FLOOR_Y - 600.0)
	WorldFixture.climbable_region(_stage, Vector2(wall_x + 20.0, FLOOR_Y - 600.0),
		Vector2(120.0, 1200.0))

	_spawn(CreatureFixture.loadout(), wall_x - 45.0)
	await _settle()
	var start_y: float = _creature.position.y
	_creature.locomotion.intent.move_axis = 1.0
	_creature.locomotion.intent.climb_held = true
	await _tick(30)
	almost(_creature.position.y, start_y, 4.0, "the creature stays on the ground")


# --- roll & crouch -------------------------------------------------------------

func test_a_roll_covers_the_configured_distance_and_grants_iframes() -> void:
	_spawn(CreatureFixture.loadout())
	await _settle()
	is_true(_creature.has_effect("dodge_roll"), "the sprinters roll")

	var start_x: float = _creature.position.x
	_creature.locomotion.intent.crouch_pressed = true
	await _tick(1)
	is_true(_creature.health.is_invulnerable(), "a roll grants i-frames immediately")

	var ticks: int = int(Config.cfg_float("movement.roll.duration") * 60.0) + 1
	await _tick(ticks)
	within_percent(absf(_creature.position.x - start_x),
		Config.cfg_float("movement.roll.distance"), 0.10, "roll distance")


func test_legs_without_dodge_roll_do_not_roll() -> void:
	_spawn(CreatureFixture.loadout({"legs": "legs_tree_trunks"}))
	await _settle()
	is_false(_creature.has_effect("dodge_roll"), "tree trunks do not roll")
	var start_x: float = _creature.position.x
	_creature.locomotion.intent.crouch_pressed = true
	await _tick(20)
	almost(_creature.position.x, start_x, 4.0, "and the creature stays put")


func test_crouching_halves_the_creature_and_slows_it() -> void:
	_spawn(CreatureFixture.loadout({"legs": "legs_tree_trunks"}))
	await _settle()
	is_true(_creature.has_effect("crouch"), "tree trunks crouch")
	var standing: float = _creature.visual_height()

	_creature.locomotion.intent.crouch_held = true
	await _tick(4)
	is_true(_creature.is_crouched(), "the creature is crouching")
	within_percent(_creature.visual_height(),
		standing * Config.cfg_float("movement.crouch.hurtbox_height_mult"), 0.05,
		"crouched height")

	_creature.locomotion.intent.crouch_held = false
	await _tick(4)
	is_false(_creature.is_crouched(), "releasing stands it back up")
	almost(_creature.visual_height(), standing, 1.0, "at its full height")


# --- cracked floors (a level-design key) ---------------------------------------

func test_a_heavy_creature_stomps_through_a_cracked_floor() -> void:
	var tile: CrackedFloor = WorldFixture.cracked_floor(_stage, 0.0, FLOOR_Y - 900.0)
	_spawn(CreatureFixture.loadout({
		"torso": "torso_barrel", "legs": "legs_tree_trunks", "head": "head_anvil"}), 0.0)
	eq(_creature.weight_class.class_id, "heavy", "the creature is Heavy")
	is_true(_creature.weight_class.breaks_cracked_floors(), "Heavy breaks cracked floors")

	# Drop from high enough to pass crack_break_min_land_speed.
	_creature.position = Vector2(0.0, FLOOR_Y - 1800.0)
	_creature.velocity = Vector2.ZERO
	for _i: int in range(120):
		await tree.physics_frame
		if tile.is_broken:
			break
	is_true(tile.is_broken, "the tile shattered under the landing")


func test_a_medium_creature_never_breaks_a_cracked_floor() -> void:
	var tile: CrackedFloor = WorldFixture.cracked_floor(_stage, 0.0, FLOOR_Y - 900.0)
	_spawn(CreatureFixture.loadout(), 0.0)
	eq(_creature.weight_class.class_id, "medium", "the creature is Medium")

	_creature.position = Vector2(0.0, FLOOR_Y - 2400.0)
	_creature.velocity = Vector2.ZERO
	for _i: int in range(160):
		await tree.physics_frame
	is_false(tile.is_broken, "however far it falls, the tile holds")


func test_a_heavy_creature_landing_gently_does_not_break_the_floor() -> void:
	var tile: CrackedFloor = WorldFixture.cracked_floor(_stage, 0.0, FLOOR_Y - 900.0)
	_spawn(CreatureFixture.loadout({
		"torso": "torso_barrel", "legs": "legs_tree_trunks", "head": "head_anvil"}), 0.0)

	# A short hop cannot reach crack_break_min_land_speed.
	_creature.position = Vector2(0.0, FLOOR_Y - 960.0)
	_creature.velocity = Vector2.ZERO
	for _i: int in range(90):
		await tree.physics_frame
	is_true(_creature.locomotion.last_fall_speed()
		< _creature.weight_class.crack_break_min_land_speed(),
		"the landing was below the threshold")
	is_false(tile.is_broken, "so the tile holds")
