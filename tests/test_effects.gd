extends TestCase

## M10: the eight effects the catalogue introduces.
##
## Each one is a promise `data/effects.json` makes to the player in prose. These
## tests are that prose, executed — including the negative half, because an
## effect that fires for creatures that do not have it is worse than one that
## does not fire at all.

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


# --- air_dash ------------------------------------------------------------------

func test_an_air_dash_covers_the_configured_distance() -> void:
	_creature = _spawn({"legs": "legs_dash_scratches"})
	is_true(_creature.has_effect("air_dash"), "the legs dash")
	await _settle()

	_creature.locomotion.intent.press_jump()
	await _tick(6)
	var before_x: float = _creature.global_position.x

	_creature.facing = 1
	_creature.locomotion.intent.crouch_pressed = true
	await _tick(int(Config.cfg_float("movement.air_dash.duration") * 60.0) + 1)

	var travelled: float = _creature.global_position.x - before_x
	within_percent(travelled, Config.cfg_float("movement.air_dash.distance"), 12.0,
		"the dash covered air_dash.distance")


func test_a_dash_is_once_per_airtime_and_resets_on_landing() -> void:
	_creature = _spawn({"legs": "legs_dash_scratches"})
	await _settle()

	_creature.locomotion.intent.press_jump()
	await _tick(6)
	_creature.facing = 1
	_creature.locomotion.intent.crouch_pressed = true
	await _tick(1)
	is_true(_creature.locomotion.state == Locomotion.State.DASH, "the first dash fired")
	await _tick(int(Config.cfg_float("movement.air_dash.duration") * 60.0) + 2)

	_creature.locomotion.intent.crouch_pressed = true
	await _tick(1)
	ne(_creature.locomotion.state, Locomotion.State.DASH,
		"a second dash in the same airtime is refused")

	# Land, then dash again.
	await _tick(90)
	is_true(_creature.is_on_floor(), "back on the ground")
	_creature.locomotion.intent.press_jump()
	await _tick(6)
	_creature.locomotion.intent.crouch_pressed = true
	await _tick(1)
	eq(_creature.locomotion.state, Locomotion.State.DASH, "landing restored the dash")


func test_a_creature_without_the_effect_never_dashes() -> void:
	_creature = _spawn({})
	await _settle()
	_creature.locomotion.intent.press_jump()
	await _tick(6)
	_creature.locomotion.intent.crouch_pressed = true
	await _tick(2)
	ne(_creature.locomotion.state, Locomotion.State.DASH, "no part, no dash")


# --- wall_cling ----------------------------------------------------------------

func test_a_cling_holds_a_wall_and_slides_at_the_configured_speed() -> void:
	_creature = _spawn({"back": "back_grapple_spool"})
	is_true(_creature.has_effect("wall_cling"), "the spool clings")
	is_false(_creature.has_effect("can_climb"), "but cannot climb")

	var face_x: float = 300.0
	WorldFixture.wall_at(_stage, face_x, -600.0)
	WorldFixture.climbable_region(_stage, Vector2(face_x + 20.0, -600.0), Vector2(80.0, 1200.0))

	_creature.global_position = Vector2(face_x - 40.0, -700.0)
	_creature.facing = 1
	_creature.velocity = Vector2.ZERO
	await _tick(20)

	eq(_creature.locomotion.state, Locomotion.State.CLING, "it is holding the face")
	almost(_creature.velocity.y, Config.cfg_float("movement.wall_cling.slide_speed"),
		1.0, "and sliding at wall_cling.slide_speed rather than falling")


func test_a_cling_gives_the_air_moves_back() -> void:
	_creature = _spawn({"back": "back_grapple_spool", "legs": "legs_dash_scratches"})
	var face_x: float = 300.0
	WorldFixture.wall_at(_stage, face_x, -600.0)
	WorldFixture.climbable_region(_stage, Vector2(face_x + 20.0, -600.0), Vector2(80.0, 1200.0))

	_creature.global_position = Vector2(face_x - 40.0, -700.0)
	_creature.facing = 1
	await _tick(4)
	_creature.locomotion.intent.crouch_pressed = true  # spend the dash
	await _tick(int(Config.cfg_float("movement.air_dash.duration") * 60.0) + 2)

	_creature.global_position = Vector2(face_x - 40.0, -700.0)
	_creature.velocity = Vector2.ZERO
	_creature.facing = 1
	await _tick(20)
	eq(_creature.locomotion.state, Locomotion.State.CLING, "clinging again")

	_creature.global_position = Vector2(0.0, -700.0)
	await _tick(2)
	_creature.locomotion.intent.crouch_pressed = true
	await _tick(1)
	eq(_creature.locomotion.state, Locomotion.State.DASH, "the cling refreshed the dash")


# --- thick_hide ----------------------------------------------------------------

func test_thick_hide_reduces_knockback_and_stacks() -> void:
	var bare: float = _knockback_with({})
	var one: float = _knockback_with({"back": "back_shell_scrap"})
	var two: float = _knockback_with({"back": "back_shell_scrap", "arms": "arms_shield_flaps"})

	var per_part: float = Config.cfg_float("combat.thick_hide.knockback_mult")
	within_percent(one, bare * per_part, 1.0, "one hide multiplies knockback once")
	within_percent(two, bare * per_part * per_part, 1.0, "two hides multiply it twice")
	is_true(two < one and one < bare, "more armour, less shove")


# --- heavy_landing -------------------------------------------------------------

func test_heavy_landing_breaks_a_cracked_floor_at_any_weight() -> void:
	_creature = _spawn({"torso": "torso_wire_cage", "legs": "legs_stilts",
		"back": "back_lead_weight", "head": null})
	is_true(_creature.has_effect("heavy_landing"), "the weight lands heavy")
	ne(_creature.weight_class.class_id, "heavy",
		"and the creature itself is not Heavy — that is the point")

	var tile: CrackedFloor = WorldFixture.cracked_floor(_stage, 0.0, FLOOR_Y - 900.0)
	_creature.global_position = Vector2(0.0, FLOOR_Y - 2100.0)
	_creature.velocity = Vector2.ZERO
	for _i: int in range(140):
		await tree.physics_frame
		if tile.is_broken:
			break
	is_true(tile.is_broken, "the floor gave way under a Medium creature")


func test_a_medium_creature_without_it_leaves_the_floor_alone() -> void:
	_creature = _spawn({})
	ne(_creature.weight_class.class_id, "heavy", "a Medium creature")
	is_false(_creature.has_effect("heavy_landing"), "with no heavy_landing part")

	var tile: CrackedFloor = WorldFixture.cracked_floor(_stage, 0.0, FLOOR_Y - 900.0)
	_creature.global_position = Vector2(0.0, FLOOR_Y - 2100.0)
	_creature.velocity = Vector2.ZERO
	for _i: int in range(140):
		await tree.physics_frame
	is_false(tile.is_broken, "the floor held")


# --- quick_strike --------------------------------------------------------------

func test_quick_strike_shortens_the_wind_up_but_not_the_window() -> void:
	_creature = _spawn({"head": "head_needle_beak"})
	var timing: Dictionary = Config.part("head_needle_beak")["attack"] as Dictionary
	var mult: float = Config.cfg_float("combat.quick_strike.time_mult")

	almost(_creature.attack_controller.quick_strike_mult(), mult, 0.001,
		"one quick_strike part applies the multiplier once")

	_creature.attack_controller.request("attack_primary")
	var windup: float = await _seconds_in_phase(AttackController.Phase.WINDUP)
	within_percent(windup, float(timing["windup"]) * mult, 20.0,
		"the windup is shortened")

	var active: float = await _seconds_in_phase(AttackController.Phase.ACTIVE)
	within_percent(active, float(timing["active"]), 20.0,
		"but the window damage can land in is untouched")


func test_an_ordinary_head_keeps_its_authored_timings() -> void:
	_creature = _spawn({})
	almost(_creature.attack_controller.quick_strike_mult(), 1.0, 0.001,
		"no quick_strike part, no change")


# --- long_reach ----------------------------------------------------------------

func test_long_reach_grows_the_damage_box_and_leaves_hurtboxes_alone() -> void:
	var plain: Creature = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	var plain_damage: float = _damage_radius(plain)
	var plain_hurt: float = _hurtbox_area(plain)
	CreatureFixture.despawn(plain)

	_creature = _spawn({"arms": "arms_scribble_whips"})
	is_true(_creature.has_effect("long_reach"), "the whips reach")
	var mult: float = Config.cfg_float("combat.long_reach.size_mult")
	within_percent(_damage_radius(_creature), plain_damage * mult, 1.0,
		"the damage box grew by long_reach.size_mult")
	within_percent(_hurtbox_area(_creature), plain_hurt, 1.0,
		"and reaching further did not make the creature a bigger target")


# --- ink_magnet ----------------------------------------------------------------

func test_ink_magnet_widens_the_pull() -> void:
	var mult: float = Config.cfg_float("economy.ink_magnet.radius_mult")
	var base: float = Config.cfg_float("economy.ink_pickup_magnet_radius")

	_creature = _spawn({"arms": "arms_pocket_lint"})
	_creature.add_to_group("player")
	_creature.global_position = Vector2(0.0, FLOOR_Y - 40.0)
	await _settle(4)

	# Just outside the plain radius, comfortably inside the magnified one.
	var pickup: Pickups.Ink = Pickups.Ink.create(10)
	pickup.position = Vector2(base * 1.6, FLOOR_Y - 160.0)
	_stage.add_child(pickup)
	var started_at: float = pickup.global_position.x

	await _tick(20)
	is_true(mult > 1.5, "the magnet is meaningfully wider than default")
	is_true(not is_instance_valid(pickup) or pickup.global_position.x < started_at - 1.0,
		"the ink moved towards a creature it would otherwise have ignored")


# --- spit_attack ---------------------------------------------------------------

func test_a_spit_head_launches_a_projectile_instead_of_arming_a_box() -> void:
	_creature = _spawn({"head": "head_spit_gland"})
	is_true(_creature.attack_controller.is_ranged("attack_primary"),
		"the gland is a ranged attack")

	var fired: Array[Projectile] = []
	_creature.attack_controller.projectile_fired.connect(
		func(shot: Projectile) -> void: fired.append(shot))

	_creature.attack_controller.request("attack_primary")
	await _seconds_in_phase(AttackController.Phase.WINDUP)
	await _tick(2)

	eq(fired.size(), 1, "exactly one projectile left the creature")
	for box: Hitbox in _creature.hitbox_root.all():
		if box.hitbox_type == Hitbox.TYPE_DAMAGE and box.slot == "head":
			is_false(box.is_enabled(),
				"and the head's own damage box stayed dormant (Mandate B5)")


func test_a_projectile_damages_a_target_it_never_touches_in_melee() -> void:
	_creature = _spawn({"head": "head_spit_gland"})
	_creature.global_position = Vector2(0.0, FLOOR_Y - 40.0)
	_creature.facing = 1

	var target: Creature = CreatureFixture.spawn(tree, CreatureFixture.loadout(), false)
	target.player_input.set_enabled(false)
	target.global_position = Vector2(560.0, FLOOR_Y - 40.0)
	await _tick(6)
	target.global_position = Vector2(560.0, FLOOR_Y - 40.0)
	target.velocity = Vector2.ZERO
	var before: float = target.health.current

	_creature.attack_controller.request("attack_primary")
	for _i: int in range(120):
		await tree.physics_frame
		if target.health.current < before:
			break
	is_true(target.health.current < before,
		"the target 560 px away took damage (%.0f -> %.0f)"
			% [before, target.health.current])
	CreatureFixture.despawn(target)


func test_a_projectile_is_stopped_by_the_world() -> void:
	_creature = _spawn({"head": "head_spit_gland"})
	_creature.global_position = Vector2(0.0, FLOOR_Y - 40.0)
	_creature.facing = 1
	WorldFixture.wall_at(_stage, 400.0, -400.0)

	var fired: Array[Projectile] = []
	_creature.attack_controller.projectile_fired.connect(
		func(shot: Projectile) -> void: fired.append(shot))
	_creature.attack_controller.request("attack_primary")
	await _tick(40)

	eq(fired.size(), 1, "one shot")
	is_true(not is_instance_valid(fired[0]) or fired[0].is_queued_for_deletion(),
		"and the wall stopped it rather than letting it fly on forever")


# --- helpers -------------------------------------------------------------------

func _spawn(overrides: Dictionary) -> Creature:
	var creature: Creature = CreatureFixture.spawn(tree,
		CreatureFixture.loadout(overrides), true)
	creature.player_input.set_enabled(false)
	creature.position = Vector2(0.0, FLOOR_Y - 40.0)
	return creature


func _settle(ticks: int = 30) -> void:
	for _i: int in range(ticks):
		await tree.physics_frame


func _tick(count: int) -> void:
	for _i: int in range(count):
		await tree.physics_frame


## How long the controller stays in `which`, in seconds, from now.
func _seconds_in_phase(which: AttackController.Phase) -> float:
	var controller: AttackController = _creature.attack_controller
	var waited: int = 0
	while controller.phase != which and waited < 240:
		await tree.physics_frame
		waited += 1
	var frames: int = 0
	while controller.phase == which and frames < 240:
		await tree.physics_frame
		frames += 1
	return float(frames) / 60.0


## Knockback velocity a build of `overrides` receives from one identical hit.
func _knockback_with(overrides: Dictionary) -> float:
	var defender: Creature = CreatureFixture.spawn(tree,
		CreatureFixture.loadout(overrides), false)
	defender.global_position = Vector2(400.0, FLOOR_Y - 40.0)
	var attacker: Creature = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	attacker.global_position = Vector2(0.0, FLOOR_Y - 40.0)

	Combat.apply_knockback(attacker, defender, 400.0)
	var speed: float = absf(defender.velocity.x)
	CreatureFixture.despawn(defender)
	CreatureFixture.despawn(attacker)
	return speed


func _damage_radius(creature: Creature) -> float:
	for box: Hitbox in creature.hitbox_root.all():
		if box.hitbox_type == Hitbox.TYPE_DAMAGE:
			var circle: CircleShape2D = box.shape() as CircleShape2D
			if circle != null:
				return circle.radius
			var rectangle: RectangleShape2D = box.shape() as RectangleShape2D
			if rectangle != null:
				return rectangle.size.x
	return 0.0


func _hurtbox_area(creature: Creature) -> float:
	var total: float = 0.0
	for box: Hitbox in creature.hitbox_root.all():
		if box.hitbox_type != Hitbox.TYPE_HURTBOX:
			continue
		var circle: CircleShape2D = box.shape() as CircleShape2D
		if circle != null:
			total += PI * circle.radius * circle.radius
			continue
		var rectangle: RectangleShape2D = box.shape() as RectangleShape2D
		if rectangle != null:
			total += rectangle.size.x * rectangle.size.y
	return total
