extends TestCase

## `LoadoutSpace` answers "what is the furthest/shortest any legal build can
## leap?" without enumerating builds, because at catalogue scale enumeration is
## not an option — the shipped catalogue is 286,720 biped loadouts and 327,680
## quadruped ones.
##
## The claim it makes is *exactness*, not "close enough", so every answer is
## checked against brute force. Brute force cannot be run over the whole
## catalogue, so the comparison runs over a **slice** of it: three parts per slot,
## chosen to span the extremes the search has to find — lightest, heaviest, and
## whatever carries the effect being queried. That is 972 loadouts, enumerable in
## a moment, and the search is not told it is being restricted; it takes the same
## code path over a smaller catalogue.
##
## Picking the slice by extremes rather than at random is deliberate. A random
## slice would usually still agree, and would occasionally hide exactly the case
## the search exists to get right.

const TOLERANCE: float = 0.001

## Effects worth querying: the two that change a flight, two that do not (so a
## filter that changes nothing still has to give the right answer), and one no
## part has at all.
const QUERIED: Array[String] = [
	"can_glide", "double_jump", "crouch", "thick_hide", "no_such_effect",
]

## How many parts per slot the brute-force slice keeps. Three slots' worth of
## extremes is enough to make every branch of the frontier logic matter, and
## keeps the enumeration in the hundreds rather than the hundreds of thousands.
const SLICE_PER_SLOT: int = 3


func test_the_search_agrees_with_brute_force_on_every_effect() -> void:
	for blueprint_id: String in ["biped", "quadruped"]:
		for effect_id: String in QUERIED:
			var slice: Dictionary = _slice(blueprint_id, effect_id)
			for drop: float in [0.0, 380.0]:
				_compare(blueprint_id, effect_id, drop, slice)


func test_the_height_range_agrees_with_brute_force() -> void:
	for blueprint_id: String in ["biped", "quadruped"]:
		var slice: Dictionary = _slice(blueprint_id, "")
		var fast: Vector2 = LoadoutSpace.standing_height_range(blueprint_id, slice)
		var slow: Vector2 = _brute_height_range(blueprint_id, slice)
		almost(fast.x, slow.x, TOLERANCE, "%s shortest build" % blueprint_id)
		almost(fast.y, slow.y, TOLERANCE, "%s tallest build" % blueprint_id)


func test_the_slice_the_reference_runs_on_is_small_enough_to_enumerate() -> void:
	# If this ever stops holding, the tests above silently become a memory
	# experiment instead of a proof.
	for blueprint_id: String in ["biped", "quadruped"]:
		var count: int = JumpMath.every_loadout(
			blueprint_id, _slice(blueprint_id, "can_glide")).size()
		is_true(count < 5000, "%s slice enumerates %d loadouts" % [blueprint_id, count])


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


func test_a_glide_gate_only_works_below_a_certain_ledge() -> void:
	# Gliding is not simply "further than jumping" — over a short drop the
	# catalogue's best light double-jumper out-reaches a heavy creature wearing
	# wings, and a gate built there would let the wrong builds through. What
	# makes a glide gate a gate is *height*: a glide turns a drop into time at a
	# fixed fall speed, so its reach grows with the drop, while a jump's grows
	# with the square root of it. Past the crossing point every glider beats
	# every non-glider, and that is where a ledge has to hang.
	var crossing: float = -1.0
	for drop: float in [0.0, 200.0, 400.0, 600.0, 800.0, 1000.0]:
		var holds: bool = LoadoutSpace.worst_reach_with("can_glide", drop) \
			> LoadoutSpace.best_reach_without("can_glide", drop)
		if holds and crossing < 0.0:
			crossing = drop
		if crossing >= 0.0:
			is_true(holds, "past the crossing (%.0f px) the gate still holds at %.0f px"
				% [crossing, drop])
	is_true(crossing >= 0.0,
		"there is some drop at which every glider beats every non-glider")


func test_level_01s_glide_ledge_hangs_below_the_crossing() -> void:
	var level: GDScript = load("res://scripts/levels/level_01_margins.gd") as GDScript
	var drop: float = float(level.get("GLIDE_DROP"))
	var gap: float = float(level.get("GLIDE_GAP"))
	var best_without: float = LoadoutSpace.best_reach_without("can_glide", drop)
	var worst_with: float = LoadoutSpace.worst_reach_with("can_glide", drop)
	is_true(worst_with > best_without,
		"at the ledge's own drop the worst glider (%.0f px) beats the best "
		% worst_with + "non-glider (%.0f px)" % best_without)
	is_true(gap > best_without and gap < worst_with,
		"and the %.0f px gap sits between them" % gap)


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

func _compare(blueprint_id: String, effect_id: String, drop: float,
		slice: Dictionary) -> void:
	var label: String = "%s / %s / drop %.0f" % [blueprint_id, effect_id, drop]
	almost(LoadoutSpace.best_reach_without(effect_id, drop, blueprint_id, slice),
		_brute_reach(blueprint_id, effect_id, drop, false, true, slice), TOLERANCE,
		"%s — best without" % label)
	almost(LoadoutSpace.best_reach_with(effect_id, drop, blueprint_id, slice),
		_brute_reach(blueprint_id, effect_id, drop, true, true, slice), TOLERANCE,
		"%s — best with" % label)
	almost(LoadoutSpace.worst_reach_with(effect_id, drop, blueprint_id, slice),
		_brute_reach(blueprint_id, effect_id, drop, true, false, slice), TOLERANCE,
		"%s — worst with" % label)


## Every legal loadout in the slice, built and measured. Slow and obviously
## correct — which is the whole reason it is here.
func _brute_reach(blueprint_id: String, effect_id: String, drop: float,
		want_effect: bool, want_max: bool, slice: Dictionary) -> float:
	var best: float = -INF if want_max else INF
	for loadout: Dictionary in JumpMath.every_loadout(blueprint_id, slice):
		var stats: CreatureStats = PartAssembler.preview_stats(loadout, blueprint_id)
		if stats.has_effect(effect_id) != want_effect:
			continue
		var reach: float = JumpMath.horizontal_reach(stats, drop, blueprint_id)
		best = maxf(best, reach) if want_max else minf(best, reach)
	return 0.0 if best == -INF or best == INF else best


func _brute_height_range(blueprint_id: String, slice: Dictionary) -> Vector2:
	var shortest: float = INF
	var tallest: float = 0.0
	for loadout: Dictionary in JumpMath.every_loadout(blueprint_id, slice):
		var height: float = JumpMath.hurtbox_height(loadout, blueprint_id)
		if height <= 0.0:
			continue
		shortest = minf(shortest, height)
		tallest = maxf(tallest, height)
	return Vector2(shortest if shortest < INF else 0.0, tallest)


## Up to `SLICE_PER_SLOT` parts per slot: the lightest, the heaviest, and one
## carrying `effect_id` if any does. Those are the three that decide every
## extreme the search reports, so agreeing on them is the interesting case.
func _slice(blueprint_id: String, effect_id: String) -> Dictionary:
	var chosen: Dictionary = {}
	for slot_id: Variant in (Config.blueprint(blueprint_id)["slots"] as Dictionary):
		var candidates: PackedStringArray = PackedStringArray()
		for part_id: Variant in Config.parts:
			var part: Dictionary = Config.parts[part_id] as Dictionary
			if str(part["slot"]) == str(slot_id) \
					and (part["fits_blueprints"] as Array).has(blueprint_id):
				candidates.append(str(part_id))
		if candidates.is_empty():
			continue

		var lightest: String = candidates[0]
		var heaviest: String = candidates[0]
		var with_effect: String = ""
		for part_id: String in candidates:
			var weight: float = float(Config.part(part_id)["weight"])
			if weight < float(Config.part(lightest)["weight"]):
				lightest = part_id
			if weight > float(Config.part(heaviest)["weight"]):
				heaviest = part_id
			if effect_id != "" and with_effect == "" \
					and (Config.part(part_id)["effects"] as Array).has(effect_id):
				with_effect = part_id

		for part_id: String in [lightest, heaviest, with_effect]:
			if part_id != "" and chosen.size() < 10_000:
				chosen[part_id] = true
	return chosen
