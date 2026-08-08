class_name JumpMath
extends RefCounted

## Closed-form answers to "can this build get across that?", derived from
## `game_config.json` alone.
##
## Level design depends on gaps that are provably uncrossable without a
## particular part (DESIGN §9 — lock and key). Measuring that by playing is not
## proof; this is. `tests/test_level_01.gd` enumerates every legal loadout and
## checks the level's gates against these numbers.


## Apex height of a jump, in pixels: v² / 2g.
static func apex_height(jump_velocity: float) -> float:
	return (jump_velocity * jump_velocity) / (2.0 * Config.cfg_float("movement.gravity"))


## Seconds from leaving the ground to landing back at the same height.
static func airtime(jump_velocity: float) -> float:
	return 2.0 * absf(jump_velocity) / Config.cfg_float("movement.gravity")


## Seconds to fall `distance` pixels from rest, respecting terminal velocity.
static func fall_time(distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	var gravity: float = Config.cfg_float("movement.gravity")
	var terminal: float = Config.cfg_float("movement.terminal_fall_speed")
	var accelerating: float = (terminal * terminal) / (2.0 * gravity)
	if distance <= accelerating:
		return sqrt(2.0 * distance / gravity)
	return terminal / gravity + (distance - accelerating) / terminal


## The furthest a build can travel horizontally in one leap, landing `drop`
## pixels below where it started, using every jump it has. Glide is handled
## separately because it converts height into an arbitrary amount of time.
static func horizontal_reach(stats: CreatureStats, drop: float = 0.0,
		blueprint_id: String = "biped") -> float:
	var weight_class: String = WeightClass.class_for_weight(stats.total_weight)
	var profile: Dictionary = profile_for(blueprint_id)
	var speed: float = Config.cfg_float("movement.weight_classes.%s.max_speed" % weight_class) \
		* stats.speed_mod * float(profile.get("max_speed_mult", 1.0))
	var jump_velocity: float = Config.cfg_float(
		"movement.weight_classes.%s.jump_velocity" % weight_class) * stats.jump_mod \
		* float(profile.get("jump_velocity_mult", 1.0))
	var gravity: float = Config.cfg_float("movement.gravity")

	var rise: float = absf(jump_velocity) / gravity
	var height: float = apex_height(jump_velocity)
	var airtime: float = 0.0

	if stats.has_effect("can_glide"):
		# Rise, then descend at the glide cap for as long as the height lasts.
		airtime = rise + (height + drop) / Config.cfg_float("movement.glide.glide_fall_cap")
	else:
		if stats.has_effect("double_jump"):
			# Spend the second jump at the apex: it buys another rise, and the
			# fall is from the combined height.
			var second: float = absf(jump_velocity) \
				* Config.cfg_float("movement.double_jump.velocity_mult")
			rise += second / gravity
			height += apex_height(second)
		airtime = rise + fall_time(height + drop)

	return _flight_distance(speed, airtime, profile)


## How far a flight of `airtime` seconds carries a creature whose running speed
## is `speed`. Without a launch profile that is simply speed × time; a pounce
## leaves the ground faster and bleeds back down, so its distance is the area
## under the decaying speed curve.
static func _flight_distance(speed: float, airtime: float, profile: Dictionary) -> float:
	if not profile.has("launch_speed_mult") or airtime <= 0.0 or speed <= 0.0:
		return speed * airtime

	var launch: float = speed * float(profile["launch_speed_mult"])
	var decay: float = float(profile.get("launch_decay", 0.0)) * speed
	if decay <= 0.0:
		return launch * airtime  # no bleed-off: the burst lasts the whole flight

	var decay_time: float = (launch - speed) / decay
	if airtime <= decay_time:
		# Still decaying at touchdown: a trapezoid from `launch` down to whatever
		# it has reached.
		return airtime * (launch - decay * airtime * 0.5)
	# The burst's trapezoid, then running speed for the rest of the flight.
	return decay_time * (launch + speed) * 0.5 + speed * (airtime - decay_time)


## `movement.profiles.<override>` for a blueprint, or empty for the default feel.
static func profile_for(blueprint_id: String) -> Dictionary:
	if not Config.blueprints.has(blueprint_id):
		return {}
	var override_id: String = str(Config.blueprint(blueprint_id)
		.get("movement_profile_override", ""))
	if override_id == "":
		return {}
	var profiles: Variant = Config.cfg("movement.profiles")
	if profiles == null:
		return {}
	return (profiles as Dictionary).get(override_id, {}) as Dictionary


## The furthest reach of any legal loadout that lacks `effect_id`. This is the
## number a gate keyed to that effect has to beat.
##
## Delegated to `LoadoutSpace`, which finds the extreme without building every
## loadout — six slots with eight parts each is 286,720 of them. `every_loadout`
## below is kept as the reference implementation the search is tested against.
static func best_reach_without(effect_id: String, drop: float = 0.0,
		blueprint_id: String = "biped") -> float:
	return LoadoutSpace.best_reach_without(effect_id, drop, blueprint_id)


## The furthest reach of any legal loadout that *has* `effect_id`.
static func best_reach_with(effect_id: String, drop: float = 0.0,
		blueprint_id: String = "biped") -> float:
	return LoadoutSpace.best_reach_with(effect_id, drop, blueprint_id)


## The shortest reach of any legal loadout carrying `effect_id` — what the
## *worst* build with the key can manage, which is what a gate must let through.
static func worst_reach_with(effect_id: String, drop: float = 0.0,
		blueprint_id: String = "biped") -> float:
	return LoadoutSpace.worst_reach_with(effect_id, drop, blueprint_id)


## Tallest and shortest a legal build stands — the numbers a crawl tunnel's
## clearance has to sit between.
static func standing_height_range(blueprint_id: String = "biped") -> Vector2:
	return LoadoutSpace.standing_height_range(blueprint_id)


## The vertical span of a loadout's hurtboxes, which is what the body collider
## is fitted to.
static func hurtbox_height(loadout: Dictionary, blueprint_id: String) -> float:
	var slots: Dictionary = Config.blueprint(blueprint_id)["slots"] as Dictionary
	var bones: Dictionary = Config.blueprint(blueprint_id)["bones"] as Dictionary
	var top: float = INF
	var bottom: float = -INF
	for slot_id: Variant in loadout:
		var part_id: Variant = loadout[slot_id]
		if part_id == null or not slots.has(slot_id):
			continue
		var bone_y: float = _bone_y(str((slots[slot_id] as Dictionary).get("bone",
			((slots[slot_id] as Dictionary).get("bone_pair", ["root"]) as Array)[0])), bones)
		for entry: Variant in Config.part(str(part_id)).get("hitboxes", []) as Array:
			var box: Dictionary = entry as Dictionary
			if str(box.get("type", "")) != "hurtbox":
				continue
			var half: float = float(box["radius"]) if str(box.get("shape", "")) == "circle" \
				else float((box["extents"] as Array)[1])
			var centre: float = bone_y + float((box.get("offset", [0, 0]) as Array)[1])
			top = minf(top, centre - half)
			bottom = maxf(bottom, centre + half)
	return 0.0 if top >= bottom else bottom - top


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


## Every loadout the catalogue can legally build for a blueprint, optionally
## restricted to the part ids in `allowed`.
##
## This is the reference implementation: obviously correct, and the thing
## `LoadoutSpace` is tested against in `tests/test_loadout_space.gd`. It is not
## on any hot path — the count is the product of the per-slot choices, which for
## the shipped catalogue is 286,720 for the biped and 327,680 for the quadruped,
## so calling it unrestricted will exhaust memory rather than answer. Use it to
## check a claim over a slice of the catalogue, never to make one.
static func every_loadout(blueprint_id: String = "biped",
		allowed: Dictionary = {}) -> Array[Dictionary]:
	var slots: Dictionary = Config.blueprint(blueprint_id)["slots"] as Dictionary
	var options: Dictionary = {}
	for slot_id: Variant in slots:
		var slot: String = str(slot_id)
		var choices: Array = []
		if not bool((slots[slot] as Dictionary).get("required", false)):
			choices.append(null)
		for part_id: Variant in Config.parts:
			var part: Dictionary = Config.parts[part_id] as Dictionary
			if str(part["slot"]) != slot \
					or not (part["fits_blueprints"] as Array).has(blueprint_id):
				continue
			if allowed.is_empty() or allowed.has(part_id):
				choices.append(str(part_id))
		options[slot] = choices

	var loadouts: Array[Dictionary] = [{}]
	for slot_id: Variant in options:
		var expanded: Array[Dictionary] = []
		for base: Dictionary in loadouts:
			for choice: Variant in options[slot_id] as Array:
				var next: Dictionary = base.duplicate()
				next[str(slot_id)] = choice
				expanded.append(next)
		loadouts = expanded
	return loadouts
