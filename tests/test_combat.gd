extends TestCase

## M4 acceptance: the damage formula, the attack window, and i-frames.

const FLOOR_Y: float = 0.0

var _stage: Node2D = null
var _attacker: Creature = null
var _defender: Creature = null
## Lambdas capture locals by value in GDScript, so a hit counter has to live here.
var _hits: int = 0


func _count_hit(_target: Creature, _damage: int) -> void:
	_hits += 1


func before_each() -> void:
	_stage = WorldFixture.stage(tree)
	WorldFixture.floor_at(_stage, FLOOR_Y)


func after_each() -> void:
	Combat.hitstop_enabled = true
	CreatureFixture.despawn(_attacker)
	CreatureFixture.despawn(_defender)
	WorldFixture.clear(_stage)
	Engine.time_scale = 1.0
	_attacker = null
	_defender = null
	_stage = null


func _tick(count: int = 1) -> void:
	for _i: int in range(count):
		await tree.physics_frame


## Stand a player and an enemy toe to toe: as close as their bodies allow, which
## is exactly the range real melee happens at. Bodies push (Decision 4), so an
## overlapping pair would drift apart before the swing landed — the separation
## has to be derived from the colliders the assemblies actually produced, not
## guessed.
func _face_off(defender_loadout: Dictionary, separation: float = -1.0) -> void:
	_attacker = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	_attacker.player_input.set_enabled(false)
	_attacker.position = Vector2(0.0, FLOOR_Y - 20.0)
	_attacker.facing = 1

	_defender = CreatureFixture.spawn(tree, defender_loadout, false)
	_defender.position = Vector2(2000.0, FLOOR_Y - 20.0)
	await _tick(12)

	_defender.position = Vector2(
		separation if separation > 0.0 else _touching_distance(), FLOOR_Y - 20.0)
	_defender.velocity = Vector2.ZERO
	_attacker.position = Vector2(0.0, _attacker.position.y)
	_attacker.velocity = Vector2.ZERO
	await _tick(4)


## The closest two bodies can stand without pushing each other, plus a hair.
func _touching_distance() -> float:
	var mine: float = (_attacker.body_collider.shape as RectangleShape2D).size.x
	var theirs: float = (_defender.body_collider.shape as RectangleShape2D).size.x
	return (mine + theirs) * 0.5 + 2.0


## Run one full attack and report the damage the defender took.
func _swing(action: String = "attack_primary") -> int:
	var before: float = _defender.health.current
	_attacker.attack_controller.request(action)
	for _i: int in range(120):
		await tree.physics_frame
		if _attacker.attack_controller.phase == AttackController.Phase.IDLE:
			break
	return int(before - _defender.health.current)


# --- the formula ---------------------------------------------------------------

func test_the_damage_formula_is_attack_minus_defense_with_a_floor_of_one() -> void:
	eq(Combat.damage_for(35.0, 0.0), 35, "35 attack against no armour")
	eq(Combat.damage_for(35.0, 5.0), 30, "5 defense subtracts 5")
	eq(Combat.damage_for(20.0, 20.0), 1, "equal attack and defense still deals 1")
	eq(Combat.damage_for(10.0, 99.0), 1, "and overwhelming armour never blocks it entirely")
	eq(CreatureStats.damage_against(35.0, 5.0), 30, "the stats helper agrees")


func test_a_bite_kills_a_grunt_in_exactly_two_hits() -> void:
	# Monster Maw 35 attack vs a Scribble Grunt: 0 defense, 60 hp (hp_override).
	await _face_off(Config.enemy("enemy_scribble_grunt")["assembly"] as Dictionary)
	_defender.health.set_maximum(60.0, true)
	almost(_defender.stats.total_defense, 0.0, 0.001, "the grunt has no defense")

	eq(await _swing(), 35, "first bite deals 35")
	await _tick(int(Config.cfg_float("combat.enemy_iframes_on_hit") * 60.0) + 4)
	is_false(_defender.health.is_dead(), "one bite is not enough")

	eq(await _swing(), 25, "the second bite finishes the remaining 25")
	is_true(_defender.health.is_dead(), "two bites kill a Grunt")


func test_a_bite_kills_a_five_defense_target_in_exactly_two_hits() -> void:
	# torso_barrel brings 3 defense, legs_tree_trunks 2 — five in total. The head
	# stays on: parts_db puts the bite's damage box at head height, so a headless
	# target cannot be bitten at all (DECISIONS_NEEDED.md D5).
	await _face_off(CreatureFixture.loadout({
		"torso": "torso_barrel", "legs": "legs_tree_trunks"}))
	almost(_defender.stats.total_defense, 5.0, 0.001, "the target has 5 defense")
	_defender.health.set_maximum(60.0, true)

	eq(await _swing(), 30, "35 attack minus 5 defense is 30")
	await _tick(int(Config.cfg_float("combat.enemy_iframes_on_hit") * 60.0) + 4)
	eq(await _swing(), 30, "and again")
	is_true(_defender.health.is_dead(), "two hits of 30 kill a 60 hp target")


# --- the attack window (Mandate B5) --------------------------------------------

func test_a_damage_box_is_live_only_during_the_active_phase() -> void:
	await _face_off(CreatureFixture.loadout(), 400.0)
	var controller: AttackController = _attacker.attack_controller
	var root: HitboxRoot = _attacker.hitbox_root

	is_true(root.all_damage_boxes_dormant(), "dormant at rest")
	controller.request("attack_primary")

	var seen_live_outside_active: bool = false
	var seen_live_during_active: bool = false
	for _i: int in range(120):
		await tree.physics_frame
		var live: bool = not root.all_damage_boxes_dormant()
		if controller.phase == AttackController.Phase.ACTIVE:
			seen_live_during_active = seen_live_during_active or live
		elif live:
			seen_live_outside_active = true
		if controller.phase == AttackController.Phase.IDLE and _i > 2:
			break

	is_true(seen_live_during_active, "the box arms during ACTIVE")
	is_false(seen_live_outside_active, "and is dormant in every other phase")
	is_true(root.all_damage_boxes_dormant(), "including once the attack is over")


func test_standing_inside_an_enemy_deals_no_damage_without_an_attack() -> void:
	# Decision 4: bodies push, they never hurt.
	await _face_off(CreatureFixture.loadout())
	var before: float = _defender.health.current
	await _tick(60)
	almost(_defender.health.current, before, 0.001, "overlapping alone does nothing")


func test_a_target_already_inside_the_box_when_it_arms_is_still_hit() -> void:
	# The defender is standing in the bite's footprint before the box exists, so
	# nothing "enters" it — the hit has to land anyway.
	await _face_off(CreatureFixture.loadout())
	is_true(await _swing() > 0, "the swing connects with no fresh entry event")


func test_one_swing_hits_a_given_target_only_once() -> void:
	await _face_off(CreatureFixture.loadout())
	_defender.health.set_maximum(500.0, true)
	eq(await _swing(), 35, "a single swing deals a single hit's worth")


# --- i-frames ------------------------------------------------------------------

func test_player_iframes_last_the_configured_half_second() -> void:
	var iframes: float = Config.cfg_float("combat.player_iframes_on_hit")
	almost(iframes, 0.5, 0.0001, "the player's window is half a second")

	_attacker = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	_attacker.player_input.set_enabled(false)
	_attacker.health.set_maximum(200.0, true)

	eq(_attacker.health.take_damage(10), 10, "the first hit lands")
	eq(_attacker.health.take_damage(10), 0, "an immediate second hit is swallowed")

	await _tick(int(iframes * 60.0) - 4)
	eq(_attacker.health.take_damage(10), 0, "still swallowed just inside the window")

	await _tick(8)
	eq(_attacker.health.take_damage(10), 10, "and lands again once it expires")
	almost(_attacker.health.current, 180.0, 0.001, "exactly two hits got through")


func test_enemies_get_the_shorter_window() -> void:
	almost(Config.cfg_float("combat.enemy_iframes_on_hit"), 0.2, 0.0001,
		"enemies recover in 0.2 s (DESIGN §6)")
	_defender = CreatureFixture.spawn(tree, CreatureFixture.loadout(), false)
	almost(_defender.health.iframe_duration(), 0.2, 0.0001, "and Health knows it")


func test_an_overlapping_enemy_re_hits_only_after_the_window() -> void:
	# Hitstop would freeze the clock this test measures against.
	Combat.hitstop_enabled = false
	# The player stands toe to toe with a Grunt that bites on a loop.
	_defender = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	_defender.player_input.set_enabled(false)
	_defender.position = Vector2(2000.0, FLOOR_Y - 20.0)
	_defender.health.set_maximum(1000.0, true)

	_attacker = CreatureFixture.spawn(tree, CreatureFixture.loadout(), false)
	_attacker.position = Vector2(0.0, FLOOR_Y - 20.0)
	_attacker.facing = 1
	await _tick(10)
	# Re-seat both after settling: a creature dropped into the world drifts while
	# its collider is fitted, and this test needs an exact melee range.
	_attacker.position = Vector2(0.0, _attacker.position.y)
	_attacker.velocity = Vector2.ZERO
	_defender.position = Vector2(_touching_distance(), _defender.position.y)
	_defender.velocity = Vector2.ZERO
	await _tick(4)

	_hits = 0
	_attacker.attack_controller.hit_landed.connect(_count_hit)

	# Two seconds of continuous biting against a 0.5 s window.
	for _i: int in range(120):
		if _attacker.attack_controller.phase == AttackController.Phase.IDLE:
			_attacker.attack_controller.request("attack_primary")
		await tree.physics_frame

	is_true(_hits >= 2, "the player is hit more than once over two seconds (got %d)" % _hits)
	is_true(_hits <= 5, "but no more often than the 0.5 s window allows (got %d)" % _hits)


# --- hitstun and knockback -----------------------------------------------------

func test_a_hit_applies_the_parts_own_hitstun_and_knockback() -> void:
	Combat.hitstop_enabled = false
	await _face_off(CreatureFixture.loadout())
	_defender.health.set_maximum(500.0, true)
	var attack: Dictionary = Config.part("head_monster_maw")["attack"] as Dictionary

	# Both effects are transient — sample them as the hit lands, not after the
	# whole 0.8 s attack has played out.
	var peak_stun: float = 0.0
	var peak_push: float = 0.0
	_attacker.attack_controller.request("attack_primary")
	for _i: int in range(120):
		await tree.physics_frame
		peak_stun = maxf(peak_stun, _defender.locomotion.stun_remaining)
		peak_push = maxf(peak_push, _defender.velocity.x)
		if _attacker.attack_controller.phase == AttackController.Phase.IDLE:
			break

	is_true(peak_stun > 0.0, "the defender is stunned")
	is_true(peak_stun <= float(attack["hitstun"]) + 0.001,
		"for no longer than the part's hitstun (%.3f s)" % float(attack["hitstun"]))
	is_true(peak_push > 0.0, "and is pushed away from the attacker")


func test_a_heavier_defender_is_knocked_back_less() -> void:
	# knockback_taken_mult: Medium 1.0, Heavy 0.5.
	_attacker = _make_dummy(true, CreatureFixture.loadout(), 0.0)

	_defender = _make_dummy(false, CreatureFixture.loadout(), 100.0)
	eq(_defender.weight_class.class_id, "medium", "the first defender is Medium")
	Combat.apply_knockback(_attacker, _defender, 400.0)
	var medium_push: float = absf(_defender.velocity.x)
	CreatureFixture.despawn(_defender)

	_defender = _make_dummy(false, CreatureFixture.loadout({
		"torso": "torso_barrel", "legs": "legs_tree_trunks", "head": "head_anvil"}), 100.0)
	eq(_defender.weight_class.class_id, "heavy", "the second defender is Heavy")
	Combat.apply_knockback(_attacker, _defender, 400.0)

	is_true(absf(_defender.velocity.x) < medium_push,
		"a Heavy creature is shoved less far (%0.f) than a Medium one (%0.f) by the same hit"
		% [absf(_defender.velocity.x), medium_push])


func _make_dummy(is_player: bool, loadout: Dictionary, at_x: float) -> Creature:
	var creature: Creature = CreatureFixture.spawn(tree, loadout, is_player)
	creature.player_input.set_enabled(false)
	creature.position = Vector2(at_x, FLOOR_Y - 20.0)
	return creature
