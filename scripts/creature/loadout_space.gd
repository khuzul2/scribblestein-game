class_name LoadoutSpace
extends RefCounted

## Exact extremes over *every* legal loadout of a blueprint, without enumerating
## them.
##
## Level design depends on gaps that are provably uncrossable without a
## particular part (DESIGN §9 — lock and key), and "provably" has to keep meaning
## something as the catalogue grows. Six slots with eight parts each is 286,720
## biped loadouts; building them all costs minutes and hundreds of megabytes, so
## `JumpMath.every_loadout` stops being a tool and becomes a wall.
##
## Nothing here is an approximation or a sample. The search is exact:
##
## A loadout's reach depends on only four things — its weight *class*, the
## product of its `speed_mod`s, the product of its `jump_mod`s, and which
## movement effects it carries. Reach rises with both products, so for a fixed
## class and effect set the extreme loadout always sits on the Pareto frontier of
## (Σspeed, Σjump). So instead of loadouts we carry, slot by slot, a small set of
## reachable (weight, effects) → frontier states, discarding any (speed, jump)
## pair another pair already beats on both axes. What survives to the end is
## every combination that could possibly be an extreme, and the answer is read
## off it directly.
##
## `tests/test_loadout_space.gd` checks the whole thing against brute force on
## the shipped catalogue, where enumeration is still cheap enough to be the
## reference implementation.

## Weights at or above this are all the heaviest class, so the search does not
## need to tell them apart. Computed from `game_config.json`, never assumed.
static func _weight_ceiling() -> int:
	var classes: Dictionary = Config.cfg("movement.weight_classes") as Dictionary
	var highest_named: float = 0.0
	for class_id: Variant in classes:
		var threshold: float = float((classes[class_id] as Dictionary)["max_total_weight"])
		# The last class is open-ended (a huge sentinel); ignore it when finding
		# the point past which every total behaves identically.
		if threshold < 9000.0:
			highest_named = maxf(highest_named, threshold)
	return int(ceil(highest_named)) + 1


## One reachable point in the search: a weight class, a set of movement effects,
## and the speed/jump multipliers that go with them.
class State extends RefCounted:
	var weight: int = 0
	var mask: int = 0
	var speed_mod: float = 1.0
	var jump_mod: float = 1.0

	func _init(w: int = 0, m: int = 0, s: float = 1.0, j: float = 1.0) -> void:
		weight = w
		mask = m
		speed_mod = s
		jump_mod = j


## The furthest any legal loadout *lacking* `effect_id` can leap. A gate keyed to
## that effect has to beat this number.
static func best_reach_without(effect_id: String, drop: float = 0.0,
		blueprint_id: String = "biped") -> float:
	return _extreme_reach(effect_id, drop, blueprint_id, false, true)


## The furthest any legal loadout *carrying* `effect_id` can leap.
static func best_reach_with(effect_id: String, drop: float = 0.0,
		blueprint_id: String = "biped") -> float:
	return _extreme_reach(effect_id, drop, blueprint_id, true, true)


## The shortest leap of any loadout carrying `effect_id` — what the *worst* build
## holding the key manages, which is what a gate must still let through.
static func worst_reach_with(effect_id: String, drop: float = 0.0,
		blueprint_id: String = "biped") -> float:
	return _extreme_reach(effect_id, drop, blueprint_id, true, false)


## Shortest and tallest a legal build stands, as `Vector2(shortest, tallest)`.
##
## No search needed: the body collider is the union of the equipped hurtboxes, so
## its top is the single lowest `top` among them and its bottom the single
## highest `bottom`. The tallest build is therefore the best pairing of any two
## parts anywhere in the catalogue, and the shortest is the best pairing among
## the required slots alone — an optional part can only ever make a creature
## bigger, never smaller.
static func standing_height_range(blueprint_id: String = "biped") -> Vector2:
	var slots: Dictionary = Config.blueprint(blueprint_id)["slots"] as Dictionary
	var bones: Dictionary = Config.blueprint(blueprint_id)["bones"] as Dictionary

	var tallest: float = 0.0
	var required_top: float = INF
	var required_bottom: float = -INF
	var lowest_top: float = INF
	var highest_bottom: float = -INF

	for slot_id: Variant in slots:
		var slot: String = str(slot_id)
		var required: bool = bool((slots[slot] as Dictionary).get("required", false))
		var bone_y: float = _bone_y(_slot_bone(slots[slot] as Dictionary), bones)

		# Per slot: the extreme span any single choice offers.
		var slot_lowest_top: float = INF
		var slot_highest_bottom: float = -INF
		var slot_best_shortest_span: float = INF
		for part_id: Variant in Config.parts:
			var part: Dictionary = Config.parts[part_id] as Dictionary
			if str(part["slot"]) != slot \
					or not (part["fits_blueprints"] as Array).has(blueprint_id):
				continue
			var span: Vector2 = _hurtbox_span(part, bone_y)
			if span.x > span.y:
				continue  # no hurtbox at all
			slot_lowest_top = minf(slot_lowest_top, span.x)
			slot_highest_bottom = maxf(slot_highest_bottom, span.y)
			slot_best_shortest_span = minf(slot_best_shortest_span, span.y - span.x)

		if slot_lowest_top == INF:
			continue
		lowest_top = minf(lowest_top, slot_lowest_top)
		highest_bottom = maxf(highest_bottom, slot_highest_bottom)
		if required:
			# The shortest build still wears every required slot, so their union
			# is the floor on how small a creature can be.
			required_top = minf(required_top, _shortest_top(slot, blueprint_id, bone_y))
			required_bottom = maxf(required_bottom, _shortest_bottom(slot, blueprint_id, bone_y))

	tallest = 0.0 if lowest_top >= highest_bottom else highest_bottom - lowest_top
	var shortest: float = 0.0 if required_top >= required_bottom \
		else required_bottom - required_top
	return Vector2(shortest, tallest)


# --- the search ----------------------------------------------------------------

## `want_effect` filters to loadouts carrying `effect_id` (or lacking it);
## `want_max` picks the furthest rather than the shortest.
static func _extreme_reach(effect_id: String, drop: float, blueprint_id: String,
		want_effect: bool, want_max: bool) -> float:
	var flags: PackedStringArray = _flag_effects(effect_id)
	var states: Array[State] = _reachable_states(blueprint_id, flags, want_max)
	var query_bit: int = _bit_of(flags, effect_id)

	var best: float = -INF if want_max else INF
	for state: State in states:
		if ((state.mask & query_bit) != 0) != want_effect:
			continue
		var reach: float = _reach_of(state, flags, drop, blueprint_id)
		best = maxf(best, reach) if want_max else minf(best, reach)
	if best == -INF or best == INF:
		return 0.0  # no legal loadout matches the filter at all
	return best


## Effects that change how far a leap carries. The queried one rides along so a
## single pass can answer both "with" and "without".
static func _flag_effects(effect_id: String) -> PackedStringArray:
	var flags: PackedStringArray = PackedStringArray(["can_glide", "double_jump"])
	if effect_id != "" and not flags.has(effect_id):
		flags.append(effect_id)
	return flags


static func _bit_of(flags: PackedStringArray, effect_id: String) -> int:
	var index: int = flags.find(effect_id)
	return 0 if index < 0 else 1 << index


## Everything a slot can contribute: one entry per legal part, plus an empty one
## when the slot is optional.
static func _slot_options(blueprint_id: String, slot: String,
		flags: PackedStringArray) -> Array[State]:
	var slots: Dictionary = Config.blueprint(blueprint_id)["slots"] as Dictionary
	var options: Array[State] = []
	if not bool((slots[slot] as Dictionary).get("required", false)):
		options.append(State.new(0, 0, 1.0, 1.0))

	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != slot \
				or not (part["fits_blueprints"] as Array).has(blueprint_id):
			continue
		var stats: Dictionary = part.get("stats", {}) as Dictionary
		var mask: int = 0
		for effect_id: Variant in part.get("effects", []) as Array:
			mask |= _bit_of(flags, str(effect_id))
		options.append(State.new(
			int(round(float(part["weight"]))), mask,
			float(stats.get("speed_mod", 1.0)), float(stats.get("jump_mod", 1.0))))
	return options


## Fold the slots together, keeping only states that could still be an extreme.
static func _reachable_states(blueprint_id: String, flags: PackedStringArray,
		want_max: bool) -> Array[State]:
	var ceiling: int = _weight_ceiling()
	# bucket key -> Array[State], where the key packs (clamped weight, effect mask).
	var buckets: Dictionary = {}
	buckets[0] = [State.new(0, 0, 1.0, 1.0)] as Array[State]

	for slot_id: Variant in (Config.blueprint(blueprint_id)["slots"] as Dictionary):
		var options: Array[State] = _slot_options(blueprint_id, str(slot_id), flags)
		var next: Dictionary = {}
		for key: Variant in buckets:
			for carried: State in buckets[key] as Array[State]:
				for option: State in options:
					var weight: int = mini(carried.weight + option.weight, ceiling)
					var mask: int = carried.mask | option.mask
					var merged: State = State.new(weight, mask,
						carried.speed_mod * option.speed_mod,
						carried.jump_mod * option.jump_mod)
					_insert_pareto(next, weight * 256 + mask, merged, want_max)
		buckets = next

	var flattened: Array[State] = []
	for key: Variant in buckets:
		flattened.append_array(buckets[key] as Array[State])
	return flattened


## Add `candidate` to its bucket unless something already there beats it on both
## axes, and drop anything it beats. This is the whole reason the search stays
## small: within one (weight, effects) bucket only the frontier can ever win.
static func _insert_pareto(buckets: Dictionary, key: int, candidate: State,
		want_max: bool) -> void:
	if not buckets.has(key):
		buckets[key] = [candidate] as Array[State]
		return

	var frontier: Array[State] = buckets[key] as Array[State]
	var survivors: Array[State] = []
	for existing: State in frontier:
		if _dominates(existing, candidate, want_max):
			return  # already covered by a strictly better point
		if not _dominates(candidate, existing, want_max):
			survivors.append(existing)
	survivors.append(candidate)
	buckets[key] = survivors


## True when `a` is at least as good as `b` on both axes. "Good" means larger
## when hunting the furthest leap and smaller when hunting the shortest.
static func _dominates(a: State, b: State, want_max: bool) -> bool:
	if want_max:
		return a.speed_mod >= b.speed_mod and a.jump_mod >= b.jump_mod
	return a.speed_mod <= b.speed_mod and a.jump_mod <= b.jump_mod


## Reach of one state, through exactly the same maths a real creature moves by.
static func _reach_of(state: State, flags: PackedStringArray, drop: float,
		blueprint_id: String) -> float:
	var stats: CreatureStats = CreatureStats.new()
	stats.total_weight = float(state.weight)
	stats.speed_mod = state.speed_mod
	stats.jump_mod = state.jump_mod
	for index: int in range(flags.size()):
		if (state.mask & (1 << index)) != 0:
			stats.effects[flags[index]] = true
	return JumpMath.horizontal_reach(stats, drop, blueprint_id)


# --- hurtbox geometry ----------------------------------------------------------

static func _slot_bone(slot_spec: Dictionary) -> String:
	if slot_spec.has("bone"):
		return str(slot_spec["bone"])
	var pair: Array = slot_spec.get("bone_pair", ["root"]) as Array
	return str(pair[0])


static func _bone_y(bone_id: String, bones: Dictionary) -> float:
	var total: float = 0.0
	var current: Variant = bone_id
	var guard: int = bones.size() + 1
	while current != null and bones.has(current) and guard > 0:
		guard -= 1
		var bone: Dictionary = bones[current] as Dictionary
		total += float((bone["position"] as Array)[1])
		current = bone.get("parent", null)
	return total


## `Vector2(top, bottom)` of one part's hurtboxes in creature space, or an
## inverted pair when it has none.
static func _hurtbox_span(part: Dictionary, bone_y: float) -> Vector2:
	var top: float = INF
	var bottom: float = -INF
	for entry: Variant in part.get("hitboxes", []) as Array:
		var box: Dictionary = entry as Dictionary
		if str(box.get("type", "")) != "hurtbox":
			continue
		var half: float = float(box["radius"]) if str(box.get("shape", "")) == "circle" \
			else float((box["extents"] as Array)[1])
		var centre: float = bone_y + float((box.get("offset", [0, 0]) as Array)[1])
		top = minf(top, centre - half)
		bottom = maxf(bottom, centre + half)
	return Vector2(top, bottom)


## The highest `top` any single choice for this slot offers — i.e. the least this
## slot can push the creature's silhouette upwards.
static func _shortest_top(slot: String, blueprint_id: String, bone_y: float) -> float:
	var best: float = -INF
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != slot \
				or not (part["fits_blueprints"] as Array).has(blueprint_id):
			continue
		var span: Vector2 = _hurtbox_span(part, bone_y)
		if span.x <= span.y:
			best = maxf(best, span.x)
	return INF if best == -INF else best


## The lowest `bottom` any single choice for this slot offers.
static func _shortest_bottom(slot: String, blueprint_id: String, bone_y: float) -> float:
	var best: float = INF
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != slot \
				or not (part["fits_blueprints"] as Array).has(blueprint_id):
			continue
		var span: Vector2 = _hurtbox_span(part, bone_y)
		if span.x <= span.y:
			best = minf(best, span.y)
	return -INF if best == INF else best
