extends TestCase

## `LoadoutSpace` answers "what is the furthest/shortest any legal build can
## leap?" without enumerating builds, because at catalogue scale enumeration is
## not an option — six slots with eight parts each is 286,720 biped loadouts.
##
## The claim it makes is *exactness*, not "close enough", so every answer here is
## checked against brute force over the real catalogue. That reference is only
## affordable while the catalogue is small, which is exactly why these tests are
## written now: they pin the fast path to the obvious one before the obvious one
## becomes impossible to run.

const TOLERANCE: float = 0.001

## Effects worth querying: the two that change a flight, one that does not (so a
## filter that does nothing still has to give the right answer), and one no part
## has at all.
const QUERIED: Array[String] = ["can_glide", "double_jump", "crouch", "no_such_effect"]


func test_the_search_agrees_with_brute_force_on_every_effect() -> void:
	for blueprint_id: String in ["biped", "quadruped"]:
		for effect_id: String in QUERIED:
			for drop: float in [0.0, 380.0]:
				_compare(blueprint_id, effect_id, drop)


func test_the_height_range_agrees_with_brute_force() -> void:
	for blueprint_id: String in ["biped", "quadruped"]:
		var fast: Vector2 = LoadoutSpace.standing_height_range(blueprint_id)
		var slow: Vector2 = _brute_height_range(blueprint_id)
		almost(fast.x, slow.x, TOLERANCE, "%s shortest build" % blueprint_id)
		almost(fast.y, slow.y, TOLERANCE, "%s tallest build" % blueprint_id)


func test_jump_math_delegates_to_the_search() -> void:
	# The rest of the game asks `JumpMath`; it must be the same answer.
	for effect_id: String in ["can_glide", "double_jump"]:
		almost(JumpMath.best_reach_without(effect_id, 380.0),
			LoadoutSpace.best_reach_without(effect_id, 380.0), TOLERANCE,
			"best_reach_without(%s)" % effect_id)
		almost(JumpMath.worst_reach_with(effect_id, 380.0),
			LoadoutSpace.worst_reach_with(effect_id, 380.0), TOLERANCE,
			"worst_reach_with(%s)" % effect_id)


func test_an_effect_no_part_carries_has_no_reach() -> void:
	eq(LoadoutSpace.best_reach_with("no_such_effect"), 0.0,
		"nothing carries it, so nothing reaches anywhere with it")
	eq(LoadoutSpace.worst_reach_with("no_such_effect"), 0.0,
		"and the shortest such leap is likewise nothing")
	is_true(LoadoutSpace.best_reach_without("no_such_effect") > 0.0,
		"but every build lacks it, so the without-case is the whole catalogue")


func test_a_glide_build_always_out_reaches_every_build_without_one() -> void:
	# This is the property Level 01's glide gate is built on, stated directly.
	var drop: float = 380.0
	is_true(LoadoutSpace.worst_reach_with("can_glide", drop)
			> LoadoutSpace.best_reach_without("can_glide", drop),
		"the worst glider (%.0f px) beats the best non-glider (%.0f px)"
			% [LoadoutSpace.worst_reach_with("can_glide", drop),
				LoadoutSpace.best_reach_without("can_glide", drop)])


func test_the_search_is_fast_enough_to_stay_honest() -> void:
	# A proof nobody runs is not a proof. If this ever creeps into minutes the
	# gates stop being checked, so the budget is asserted rather than assumed.
	var started: int = Time.get_ticks_msec()
	for effect_id: String in ["can_glide", "double_jump"]:
		LoadoutSpace.best_reach_without(effect_id, 380.0)
		LoadoutSpace.worst_reach_with(effect_id, 380.0)
	var elapsed: int = Time.get_ticks_msec() - started
	is_true(elapsed < 4000, "four searches took %d ms" % elapsed)


# --- the reference implementation ----------------------------------------------

func _compare(blueprint_id: String, effect_id: String, drop: float) -> void:
	var label: String = "%s / %s / drop %.0f" % [blueprint_id, effect_id, drop]
	almost(LoadoutSpace.best_reach_without(effect_id, drop, blueprint_id),
		_brute_reach(blueprint_id, effect_id, drop, false, true), TOLERANCE,
		"%s — best without" % label)
	almost(LoadoutSpace.best_reach_with(effect_id, drop, blueprint_id),
		_brute_reach(blueprint_id, effect_id, drop, true, true), TOLERANCE,
		"%s — best with" % label)
	almost(LoadoutSpace.worst_reach_with(effect_id, drop, blueprint_id),
		_brute_reach(blueprint_id, effect_id, drop, true, false), TOLERANCE,
		"%s — worst with" % label)


## Every legal loadout, built and measured. Slow and obviously correct.
func _brute_reach(blueprint_id: String, effect_id: String, drop: float,
		want_effect: bool, want_max: bool) -> float:
	var best: float = -INF if want_max else INF
	for loadout: Dictionary in JumpMath.every_loadout(blueprint_id):
		var stats: CreatureStats = PartAssembler.preview_stats(loadout, blueprint_id)
		if stats.has_effect(effect_id) != want_effect:
			continue
		var reach: float = JumpMath.horizontal_reach(stats, drop, blueprint_id)
		best = maxf(best, reach) if want_max else minf(best, reach)
	return 0.0 if best == -INF or best == INF else best


func _brute_height_range(blueprint_id: String) -> Vector2:
	var shortest: float = INF
	var tallest: float = 0.0
	for loadout: Dictionary in JumpMath.every_loadout(blueprint_id):
		var height: float = JumpMath.hurtbox_height(loadout, blueprint_id)
		if height <= 0.0:
			continue
		shortest = minf(shortest, height)
		tallest = maxf(tallest, height)
	return Vector2(shortest if shortest < INF else 0.0, tallest)
