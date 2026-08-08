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


## The furthest a build can travel horizontally in one leap from flat ground,
## using every jump it has. Glide is handled separately because it converts
## height into an arbitrary amount of time.
static func horizontal_reach(stats: CreatureStats) -> float:
	var weight_class: String = WeightClass.class_for_weight(stats.total_weight)
	var speed: float = Config.cfg_float("movement.weight_classes.%s.max_speed" % weight_class) \
		* stats.speed_mod
	var jump_velocity: float = Config.cfg_float(
		"movement.weight_classes.%s.jump_velocity" % weight_class) * stats.jump_mod
	var gravity: float = Config.cfg_float("movement.gravity")

	if stats.has_effect("can_glide"):
		# Rise, then descend at the glide cap for as long as the height lasts.
		var rise: float = absf(jump_velocity) / gravity
		var height: float = apex_height(jump_velocity)
		var glide_fall: float = height / Config.cfg_float("movement.glide.glide_fall_cap")
		return speed * (rise + glide_fall)

	var seconds: float = airtime(jump_velocity)
	if stats.has_effect("double_jump"):
		# Spend the second jump at the apex: it buys another rise, and the fall
		# is from the combined height.
		var second: float = absf(jump_velocity) * Config.cfg_float("movement.double_jump.velocity_mult")
		var combined: float = apex_height(jump_velocity) + apex_height(second)
		seconds = absf(jump_velocity) / gravity + second / gravity + sqrt(2.0 * combined / gravity)
	return speed * seconds


## The furthest reach of any legal loadout that lacks `effect_id`. This is the
## number a gate keyed to that effect has to beat.
static func best_reach_without(effect_id: String, blueprint_id: String = "biped") -> float:
	var best: float = 0.0
	for loadout: Dictionary in every_loadout(blueprint_id):
		var stats: CreatureStats = PartAssembler.preview_stats(loadout, blueprint_id)
		if stats.has_effect(effect_id):
			continue
		best = maxf(best, horizontal_reach(stats))
	return best


## The furthest reach of any legal loadout that *has* `effect_id`.
static func best_reach_with(effect_id: String, blueprint_id: String = "biped") -> float:
	var best: float = 0.0
	for loadout: Dictionary in every_loadout(blueprint_id):
		var stats: CreatureStats = PartAssembler.preview_stats(loadout, blueprint_id)
		if not stats.has_effect(effect_id):
			continue
		best = maxf(best, horizontal_reach(stats))
	return best


## The shortest reach of any legal loadout carrying `effect_id` — what the
## *worst* build with the key can manage, which is what a gate must let through.
static func worst_reach_with(effect_id: String, blueprint_id: String = "biped") -> float:
	var worst: float = INF
	for loadout: Dictionary in every_loadout(blueprint_id):
		var stats: CreatureStats = PartAssembler.preview_stats(loadout, blueprint_id)
		if not stats.has_effect(effect_id):
			continue
		worst = minf(worst, horizontal_reach(stats))
	return worst if worst < INF else 0.0


## Every loadout the catalogue can legally build for a blueprint. With 14 parts
## across six slots this is a few hundred combinations — small enough to check
## exhaustively, which is the point.
static func every_loadout(blueprint_id: String = "biped") -> Array[Dictionary]:
	var slots: Dictionary = Config.blueprint(blueprint_id)["slots"] as Dictionary
	var options: Dictionary = {}
	for slot_id: Variant in slots:
		var slot: String = str(slot_id)
		var choices: Array = []
		if not bool((slots[slot] as Dictionary).get("required", false)):
			choices.append(null)
		for part_id: Variant in Config.parts:
			var part: Dictionary = Config.parts[part_id] as Dictionary
			if str(part["slot"]) == slot and (part["fits_blueprints"] as Array).has(blueprint_id):
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
