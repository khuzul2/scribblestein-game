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
## `tests/test_loadout_space.gd` checks the whole thing against brute force. The
## shipped catalogue is far too large to enumerate, so the comparison runs over a
## restricted slice of it — the `allowed` filter every query here accepts — which
## keeps the reference implementation runnable without weakening what it proves:
## the search does not know it is being given fewer parts.

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
		blueprint_id: String = "biped", allowed: Dictionary = {}) -> float:
	return _extreme_reach(effect_id, drop, blueprint_id, false, true, allowed)


## The furthest any legal loadout *carrying* `effect_id` can leap.
static func best_reach_with(effect_id: String, drop: float = 0.0,
		blueprint_id: String = "biped", allowed: Dictionary = {}) -> float:
	return _extreme_reach(effect_id, drop, blueprint_id, true, true, allowed)


## The shortest leap of any loadout carrying `effect_id` — what the *worst* build
## holding the key manages, which is what a gate must still let through.
static func worst_reach_with(effect_id: String, drop: float = 0.0,
		blueprint_id: String = "biped", allowed: Dictionary = {}) -> float:
	return _extreme_reach(effect_id, drop, blueprint_id, true, false, allowed)


## Shortest and tallest a legal build stands, as `Vector2(shortest, tallest)`.
##
## No search needed: the body collider is the union of the equipped hurtboxes, so
## its top is the single lowest `top` among them and its bottom the single
## highest `bottom`. The tallest build is therefore the best pairing of any two
## parts anywhere in the catalogue, and the shortest is the best pairing among
## the required slots alone — an optional part can only ever make a creature
## bigger, never smaller.
static func standing_height_range(blueprint_id: String = "biped",
		allowed: Dictionary = {}) -> Vector2:
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
		for part_id: Variant in Config.parts:
			var part: Dictionary = Config.parts[part_id] as Dictionary
			if str(part["slot"]) != slot \
					or not (part["fits_blueprints"] as Array).has(blueprint_id):
				continue
			if not allowed.is_empty() and not allowed.has(part_id):
				continue
			var span: Vector2 = _hurtbox_span(part, bone_y)
			if span.x > span.y:
				continue  # no hurtbox at all
			slot_lowest_top = minf(slot_lowest_top, span.x)
			slot_highest_bottom = maxf(slot_highest_bottom, span.y)

		if slot_lowest_top == INF:
			continue
		lowest_top = minf(lowest_top, slot_lowest_top)
		highest_bottom = maxf(highest_bottom, slot_highest_bottom)
		if required:
			# The shortest build still wears every required slot, so their union
			# is the floor on how small a creature can be.
			required_top = minf(required_top,
				_shortest_top(slot, blueprint_id, bone_y, allowed))
			required_bottom = maxf(required_bottom,
				_shortest_bottom(slot, blueprint_id, bone_y, allowed))

	tallest = 0.0 if lowest_top >= highest_bottom else highest_bottom - lowest_top
	var shortest: float = 0.0 if required_top >= required_bottom \
		else required_bottom - required_top
	return Vector2(shortest, tallest)


# --- the search ----------------------------------------------------------------

## `want_effect` filters to loadouts carrying `effect_id` (or lacking it);
## `want_max` picks the furthest rather than the shortest.
static func _extreme_reach(effect_id: String, drop: float, blueprint_id: String,
		want_effect: bool, want_max: bool, allowed: Dictionary = {}) -> float:
	var flags: PackedStringArray = _flag_effects(effect_id)
	var states: Array[State] = _reachable_states(blueprint_id, flags, want_max, allowed)
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
		flags: PackedStringArray, allowed: Dictionary = {}) -> Array[State]:
	var slots: Dictionary = Config.blueprint(blueprint_id)["slots"] as Dictionary
	var options: Array[State] = []
	if not bool((slots[slot] as Dictionary).get("required", false)):
		options.append(State.new(0, 0, 1.0, 1.0))

	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != slot \
				or not (part["fits_blueprints"] as Array).has(blueprint_id):
			continue
		if not allowed.is_empty() and not allowed.has(part_id):
			continue
		var stats: Dictionary = part.get("stats", {}) as Dictionary
		var mask: int = 0
		for effect_id: Variant in part.get("effects", []) as Array:
			mask |= _bit_of(flags, str(effect_id))
		options.append(State.new(
			int(round(float(part["weight"]))), mask,
			float(stats.get("speed_mod", 1.0)), float(stats.get("jump_mod", 1.0))))
	return options


## Folds already computed this run. The fold depends on the catalogue and the
## queried effects but *not* on the drop height, so asking about the same gate at
## several drops — which is exactly what tuning a gap looks like — costs one
## search instead of one per height.
##
## Safe to keep for the life of the process: `Config` deep-freezes the catalogue
## at boot, so the inputs cannot change underneath it.
static var _fold_cache: Dictionary = {}


## Fold the slots together, keeping only states that could still be an extreme.
static func _reachable_states(blueprint_id: String, flags: PackedStringArray,
		want_max: bool, allowed: Dictionary = {}) -> Array[State]:
	var cache_key: String = "%s|%s|%s|%d" % [blueprint_id, ",".join(flags),
		"max" if want_max else "min", hash(allowed)]
	if _fold_cache.has(cache_key):
		return _fold_cache[cache_key] as Array[State]

	var ceiling: int = _weight_ceiling()
	# bucket key -> Array[State], where the key packs (clamped weight, effect mask).
	var buckets: Dictionary = {}
	buckets[0] = [State.new(0, 0, 1.0, 1.0)] as Array[State]

	for slot_id: Variant in (Config.blueprint(blueprint_id)["slots"] as Dictionary):
		var options: Array[State] = _slot_options(blueprint_id, str(slot_id), flags, allowed)
		# Two passes per slot: gather every combination, deduplicating identical
		# (speed, jump) pairs as we go, then prune each bucket to its frontier
		# once. Pruning on every insert instead would make the slot quadratic in
		# the frontier size, which at catalogue scale is the whole runtime.
		var gathered: Dictionary = {}
		for key: Variant in buckets:
			for carried: State in buckets[key] as Array[State]:
				for option: State in options:
					var weight: int = mini(carried.weight + option.weight, ceiling)
					var bucket_key: int = weight * MASK_SPAN + (carried.mask | option.mask)
					var speed: float = carried.speed_mod * option.speed_mod
					var jump: float = carried.jump_mod * option.jump_mod
					if not gathered.has(bucket_key):
						gathered[bucket_key] = {}
					var seen: Dictionary = gathered[bucket_key] as Dictionary
					var pair_key: int = _quantise(speed) * PAIR_SPAN + _quantise(jump)
					if not seen.has(pair_key):
						seen[pair_key] = State.new(weight,
							carried.mask | option.mask, speed, jump)

		var next: Dictionary = {}
		for bucket_key: Variant in gathered:
			var points: Array[State] = []
			for state: Variant in (gathered[bucket_key] as Dictionary).values():
				points.append(state as State)
			next[bucket_key] = _frontier(points, want_max)
		buckets = next

	var flattened: Array[State] = []
	for key: Variant in buckets:
		flattened.append_array(buckets[key] as Array[State])
	_fold_cache[cache_key] = flattened
	return flattened


## How many distinct effect masks a bucket key must leave room for, and the
## resolution the (speed, jump) dedupe works at. Five decimal places is far finer
## than any authored `speed_mod`, so no two genuinely different builds collide.
const MASK_SPAN: int = 256
const PAIR_SPAN: int = 10_000_000
const QUANTISE_SCALE: float = 100_000.0


static func _quantise(value: float) -> int:
	return int(round(value * QUANTISE_SCALE))


## Reduce a bucket to the points that could still be an extreme: sort by speed,
## then sweep, keeping only the running best jump. One sort beats a quadratic
## all-pairs comparison, and this is the inner loop of the whole search.
static func _frontier(points: Array[State], want_max: bool) -> Array[State]:
	if points.size() <= 1:
		return points
	if want_max:
		points.sort_custom(func(a: State, b: State) -> bool:
			if a.speed_mod == b.speed_mod:
				return a.jump_mod > b.jump_mod
			return a.speed_mod > b.speed_mod)
	else:
		points.sort_custom(func(a: State, b: State) -> bool:
			if a.speed_mod == b.speed_mod:
				return a.jump_mod < b.jump_mod
			return a.speed_mod < b.speed_mod)

	var kept: Array[State] = []
	var best_jump: float = -INF if want_max else INF
	for state: State in points:
		# Speed is already ordered best-first, so a point survives exactly when
		# its jump beats everything better-or-equal on speed seen so far.
		if (state.jump_mod > best_jump) if want_max else (state.jump_mod < best_jump):
			best_jump = state.jump_mod
			kept.append(state)
	return kept


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
static func _shortest_top(slot: String, blueprint_id: String, bone_y: float,
		allowed: Dictionary = {}) -> float:
	var best: float = -INF
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != slot \
				or not (part["fits_blueprints"] as Array).has(blueprint_id):
			continue
		if not allowed.is_empty() and not allowed.has(part_id):
			continue
		var span: Vector2 = _hurtbox_span(part, bone_y)
		if span.x <= span.y:
			best = maxf(best, span.x)
	return INF if best == -INF else best


## The lowest `bottom` any single choice for this slot offers.
static func _shortest_bottom(slot: String, blueprint_id: String, bone_y: float,
		allowed: Dictionary = {}) -> float:
	var best: float = INF
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != slot \
				or not (part["fits_blueprints"] as Array).has(blueprint_id):
			continue
		if not allowed.is_empty() and not allowed.has(part_id):
			continue
		var span: Vector2 = _hurtbox_span(part, bone_y)
		if span.x <= span.y:
			best = minf(best, span.y)
	return -INF if best == INF else best
