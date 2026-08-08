extends TestCase

## M8: the five spec contradictions recorded in `/DECISIONS_NEEDED.md` were ruled
## on by a human and resolved here. Each one gets a test, because a decision that
## only lives in a data file is one careless edit away from coming back.
##
## The rulings, in order: D1 a passive stat flag is legal in any slot · D2 a
## `legs` part is biped-only · D4 the Light weight class must be reachable ·
## D5 the starter attack must be able to touch every shipped enemy · D6 a roll
## carries on under an overhang instead of standing up into it.

const FLOOR_Y: float = 0.0
## Long enough that a single 190 px roll cannot clear it.
const TUNNEL_LENGTH: float = 900.0

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


# --- D1 ------------------------------------------------------------------------

func test_a_passive_stat_flag_is_legal_in_every_slot() -> void:
	# `speed_boost`/`jump_boost` are UI icons for a `stats` multiplier that
	# `WeightClass` applies from any slot, so restricting them to `movement` made
	# a legal, working part illegal.
	for effect_id: String in ["speed_boost", "jump_boost"]:
		var kinds: Array = Config.effect(effect_id)["slot_kinds"] as Array
		for kind: String in ["core", "movement", "attack", "utility"]:
			is_true(kinds.has(kind), "%s is legal in a '%s' slot" % [effect_id, kind])


func test_the_waiver_list_is_empty_now_that_d1_is_settled() -> void:
	var waivers: JsonLoader.Result = JsonLoader.load_object("res://data/validation_waivers.json")
	is_true(waivers.ok, "validation_waivers.json parses")
	eq(((waivers.value as Dictionary)["waivers"] as Array).size(), 0,
		"no issue is being waived any more")


# --- D2 ------------------------------------------------------------------------

func test_no_part_claims_a_blueprint_that_has_no_slot_for_it() -> void:
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		for blueprint_id: Variant in (part["fits_blueprints"] as Array):
			var slots: Dictionary = Config.blueprint(str(blueprint_id))["slots"] as Dictionary
			is_true(slots.has(str(part["slot"])),
				"%s (slot '%s') fits %s, which has that slot"
					% [part_id, part["slot"], blueprint_id])


# --- D4 ------------------------------------------------------------------------

func test_every_weight_class_is_reachable_with_a_legal_build() -> void:
	var seen: Dictionary = {}
	for loadout: Dictionary in JumpMath.every_loadout("biped"):
		var stats: CreatureStats = PartAssembler.preview_stats(loadout, "biped")
		seen[WeightClass.class_for_weight(stats.total_weight)] = true

	var classes: Dictionary = Config.cfg("movement.weight_classes") as Dictionary
	for class_id: Variant in classes:
		is_true(seen.has(str(class_id)),
			"some legal biped lands in the '%s' class" % class_id)


func test_the_light_class_is_reached_without_giving_up_a_required_slot() -> void:
	var ceiling: float = Config.cfg_float("movement.weight_classes.light.max_total_weight")
	var lightest: float = INF
	for loadout: Dictionary in JumpMath.every_loadout("biped"):
		lightest = minf(lightest, PartAssembler.preview_stats(loadout, "biped").total_weight)
	is_true(lightest <= ceiling,
		"the lightest legal biped (%.0f) is at or under the Light ceiling (%.0f)"
			% [lightest, ceiling])


# --- D5 ------------------------------------------------------------------------

func test_the_starter_attack_can_reach_every_shipped_enemy() -> void:
	# The boot validator proves this for every starter attack against every
	# enemy; a zero-issue validation is the assertion.
	var issues: Array[Dictionary] = _validation_issues()
	var reach: Array[Dictionary] = issues.filter(func(issue: Dictionary) -> bool:
		return str(issue["id"]).begins_with("attack_reach:"))
	eq(reach.size(), 0, "no starter attack is geometrically unable to hit an enemy")


func test_every_equipped_part_can_be_hit() -> void:
	# The wings were the only part in the game with no hurtbox at all, so an
	# attack aimed at them passed straight through.
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		var hurtboxes: Array = (part["hitboxes"] as Array).filter(
			func(box: Variant) -> bool: return str((box as Dictionary)["type"]) == "hurtbox")
		is_true(not hurtboxes.is_empty(), "%s has at least one hurtbox" % part_id)


func test_the_shipped_data_raises_no_validation_issues_at_all() -> void:
	eq(_validation_issues().size(), 0, "boot validation is clean, warnings included")


# --- D6 ------------------------------------------------------------------------

func test_a_roll_carries_on_under_an_overhang_instead_of_standing_into_it() -> void:
	# The starter legs carry `dodge_roll` but not `crouch`, so this build is
	# exactly the one DESIGN §9 promised could roll a tunnel and previously
	# could not: one roll covers 190 px and the tunnel is 900 px long.
	_creature = _spawn_on_floor(CreatureFixture.loadout())
	is_true(_creature.has_effect("dodge_roll"), "the starter legs roll")
	is_false(_creature.has_effect("crouch"), "the starter legs cannot crouch")

	var standing: float = _creature.standing_body_box().size.y
	var entrance: float = _creature.global_position.x + 300.0
	WorldFixture.ceiling_at(_stage, FLOOR_Y - standing * 0.75,
		entrance, entrance + TUNNEL_LENGTH)
	await _settle()

	var travelled: float = await _crawl_right(240)
	is_true(travelled > TUNNEL_LENGTH + 300.0,
		"the creature crossed the whole %.0f px tunnel (got %.0f px)"
			% [TUNNEL_LENGTH, travelled])


func test_an_overhang_stops_a_creature_that_does_not_duck() -> void:
	# The gate has to still *be* a gate. Chained rolling is a key, not a hole:
	# a creature that never ducks walks into the overhang and stops.
	_creature = _spawn_on_floor(CreatureFixture.loadout())

	var standing: float = _creature.standing_body_box().size.y
	var entrance: float = _creature.global_position.x + 300.0
	WorldFixture.ceiling_at(_stage, FLOOR_Y - standing * 0.75,
		entrance, entrance + TUNNEL_LENGTH)
	await _settle()

	var travelled: float = await _walk_right(240)
	is_true(travelled < 400.0,
		"the creature was stopped at the overhang (got %.0f px)" % travelled)


func test_every_legs_part_currently_carries_a_duck_key() -> void:
	# Recorded, not asserted as a design goal: with the v1 catalogue all three
	# `legs` parts grant `dodge_roll` or `crouch`, so a crawl tunnel gates
	# nothing today — the D6 ruling made rolling work, and every build rolls.
	# The catalogue in M10 adds legs with neither, at which point the tunnel is a
	# real lock again and this test flips to naming the parts that open it.
	var without: PackedStringArray = PackedStringArray()
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != "legs":
			continue
		var effects: Array = part["effects"] as Array
		if not effects.has("dodge_roll") and not effects.has("crouch"):
			without.append(str(part_id))
	is_true(without.is_empty() or without.size() < _legs_count(),
		"either every legs part ducks, or at least one does — a tunnel is never "
		+ "passable by nothing (legs without a duck key: %s)" % [without])


func test_the_ceiling_probe_reads_clear_in_the_open() -> void:
	# The probe is the standing box at the creature's own position, so it must
	# not see the creature's own floor or its own body as an overhang.
	_creature = _spawn_on_floor(CreatureFixture.loadout())
	await _settle()
	for _tick: int in range(20):
		_creature.locomotion.intent.crouch_held = true
		await tree.physics_frame
	is_false(_creature.locomotion.is_crouched(),
		"standing in the open, nothing forces a duck")


# --- helpers -------------------------------------------------------------------

func _spawn_on_floor(loadout: Dictionary) -> Creature:
	var creature: Creature = CreatureFixture.spawn(tree, loadout, true)
	creature.player_input.set_enabled(false)
	creature.position = Vector2(0.0, FLOOR_Y - 40.0)
	return creature


func _settle(ticks: int = 30) -> void:
	for _i: int in range(ticks):
		await tree.physics_frame


## Hold right and hold crouch for `ticks` physics frames; report how far the
## creature actually got. Crouch is re-asserted every tick because `Locomotion`
## clears the one-shot press at the end of each frame, which is exactly what a
## player holding the key produces.
func _crawl_right(ticks: int) -> float:
	var start_x: float = _creature.global_position.x
	for _i: int in range(ticks):
		_creature.locomotion.intent.move_axis = 1.0
		_creature.locomotion.intent.crouch_pressed = true
		_creature.locomotion.intent.crouch_held = true
		await tree.physics_frame
	return _creature.global_position.x - start_x


## Hold right for `ticks` frames without ever ducking.
func _walk_right(ticks: int) -> float:
	var start_x: float = _creature.global_position.x
	for _i: int in range(ticks):
		_creature.locomotion.intent.move_axis = 1.0
		await tree.physics_frame
	return _creature.global_position.x - start_x


func _legs_count() -> int:
	var total: int = 0
	for part_id: Variant in Config.parts:
		if str((Config.parts[part_id] as Dictionary)["slot"]) == "legs":
			total += 1
	return total


func _validation_issues() -> Array[Dictionary]:
	var data: Dictionary = {}
	for file_name: String in ["parts_db", "blueprints", "effects", "enemies",
			"game_config", "levels"]:
		data[file_name] = JsonLoader.load_object(
			"res://data/%s.json" % file_name).value as Dictionary
	data["parts_schema"] = JsonLoader.load_object(
		"res://data/parts_db.schema.json").value as Dictionary
	return DataValidator.validate(data, {})
