extends TestCase

## M10: the catalogue has to be *varied*, and variety is a property you can
## check rather than hope for.
##
## Every claim in `docs/PARTS_TREE.md` §5 is asserted here. A part list is easy
## to grow and hard to keep honest — it is entirely possible to add twenty parts
## and leave a slot with one real choice, an archetype no build can commit to,
## or an effect that exists only on a body that cannot equip it.

## Effects that define an archetype. A build "is" an archetype when it can carry
## the whole set on one body.
const ARCHETYPES: Dictionary = {
	"brute": ["thick_hide", "heavy_landing"],
	"skitter": ["speed_boost", "jump_boost", "dodge_roll"],
	"reach": ["long_reach", "quick_strike"],
	"rigger": ["can_glide", "double_jump", "air_dash"],
}

## `can_climb` is deliberately biped-only: a quadruped has no arms and crosses
## vertical ground by pouncing (DESIGN §4.3).
const BIPED_ONLY_EFFECTS: Array[String] = ["can_climb"]

const MIN_PARTS_PER_SLOT: int = 4


# --- size and shape ------------------------------------------------------------

func test_the_catalogue_is_the_size_the_tree_says() -> void:
	eq(Config.parts.size(), 61, "61 parts, per docs/PARTS_TREE.md")


func test_every_slot_of_every_body_offers_a_real_choice() -> void:
	for blueprint_id: Variant in Config.blueprints:
		for slot_id: Variant in (Config.blueprint(str(blueprint_id))["slots"] as Dictionary):
			var count: int = _parts_for(str(blueprint_id), str(slot_id)).size()
			is_true(count >= MIN_PARTS_PER_SLOT,
				"%s/%s offers %d parts (minimum %d)"
					% [blueprint_id, slot_id, count, MIN_PARTS_PER_SLOT])


func test_no_two_parts_share_a_name_or_a_texture() -> void:
	var names: Dictionary = {}
	var textures: Dictionary = {}
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		is_false(names.has(part["name"]),
			"'%s' is the only part called that" % part["name"])
		is_false(textures.has(part["texture_path"]),
			"'%s' has its own texture" % part_id)
		names[part["name"]] = part_id
		textures[part["texture_path"]] = part_id


# --- reachability --------------------------------------------------------------

func test_every_weight_class_is_reachable_on_both_bodies() -> void:
	for blueprint_id: Variant in Config.blueprints:
		var reachable: Dictionary = _reachable_classes(str(blueprint_id))
		for class_id: Variant in (Config.cfg("movement.weight_classes") as Dictionary):
			is_true(reachable.has(str(class_id)),
				"a legal %s can be %s" % [blueprint_id, class_id])


func test_every_archetype_can_be_committed_to_on_both_bodies() -> void:
	for blueprint_id: Variant in Config.blueprints:
		for archetype: Variant in ARCHETYPES:
			var wanted: Array = ARCHETYPES[archetype] as Array
			var missing: PackedStringArray = PackedStringArray()
			for effect_id: Variant in wanted:
				if _parts_with_effect(str(blueprint_id), str(effect_id)).is_empty():
					missing.append(str(effect_id))
			is_true(missing.is_empty(),
				"a %s can be a %s (missing: %s)" % [blueprint_id, archetype, missing])


func test_every_effect_is_carried_by_a_part_that_fits_each_body() -> void:
	for effect_id: Variant in Config.effects:
		var effect: Dictionary = Config.effects[effect_id] as Dictionary
		if str(effect["category"]) == "passive" \
				and not _is_carried_anywhere(str(effect_id)):
			fail("effect '%s' exists but no part carries it" % effect_id)
			continue
		for blueprint_id: Variant in Config.blueprints:
			if BIPED_ONLY_EFFECTS.has(str(effect_id)) and str(blueprint_id) != "biped":
				continue
			is_false(_parts_with_effect(str(blueprint_id), str(effect_id)).is_empty(),
				"a %s can carry '%s'" % [blueprint_id, effect_id])


func test_every_part_can_actually_be_obtained() -> void:
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		var free: bool = int(part["unlock_cost"]) == 0
		var starter: bool = bool(part.get("starter", false))
		# Free parts are granted with the body they fit; priced parts appear at
		# the Unlock Desk. A priced part nobody can find would be dead weight.
		is_true(starter or free or int(part["unlock_cost"]) > 0,
			"'%s' is reachable in play" % part_id)
		if free and not starter:
			var granted: bool = false
			for blueprint_id: Variant in (part["fits_blueprints"] as Array):
				if Config.free_part_ids(str(blueprint_id)).has(str(part_id)):
					granted = true
			is_true(granted, "free part '%s' is granted with a body" % part_id)


func test_the_starter_kit_is_still_exactly_three_parts() -> void:
	eq(Config.starter_part_ids().size(), 3, "DESIGN §8 — three always-unlocked parts")


# --- the things a growing catalogue quietly breaks -----------------------------

func test_every_part_still_has_a_hurtbox() -> void:
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		var hurtboxes: Array = (part["hitboxes"] as Array).filter(
			func(box: Variant) -> bool: return str((box as Dictionary)["type"]) == "hurtbox")
		is_true(not hurtboxes.is_empty(), "'%s' can be hit" % part_id)


func test_every_attack_part_has_both_a_damage_box_and_timings() -> void:
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		var is_attack: bool = false
		for effect_id: Variant in (part["effects"] as Array):
			if str((Config.effect(str(effect_id))).get("category", "")) == "attack":
				is_attack = true
		if not is_attack:
			continue
		is_true(part.has("attack"), "'%s' declares its attack timings" % part_id)
		is_true(float((part["stats"] as Dictionary).get("attack_power", 0.0)) > 0.0,
			"'%s' has attack power" % part_id)
		var damage: Array = (part["hitboxes"] as Array).filter(
			func(box: Variant) -> bool: return str((box as Dictionary)["type"]) == "damage")
		is_true(not damage.is_empty(), "'%s' has a damage box" % part_id)


func test_the_boot_validator_is_still_silent() -> void:
	var data: Dictionary = {}
	for file_name: String in ["parts_db", "blueprints", "effects", "enemies",
			"game_config", "levels"]:
		data[file_name] = JsonLoader.load_object(
			"res://data/%s.json" % file_name).value as Dictionary
	data["parts_schema"] = JsonLoader.load_object(
		"res://data/parts_db.schema.json").value as Dictionary
	var issues: Array[Dictionary] = DataValidator.validate(data, {})
	var described: PackedStringArray = PackedStringArray()
	for issue: Dictionary in issues:
		described.append("[%s] %s" % [issue["severity"], issue["message"]])
	eq(issues.size(), 0, "61 parts and 18 effects raise nothing: %s" % [described])


func test_a_crawl_tunnel_is_a_lock_again() -> void:
	# The D6 ruling made rolling through a tunnel work, which — with only three
	# legs parts, all of which rolled or crouched — left the tunnel gating
	# nothing. The catalogue has to put the lock back.
	var without: PackedStringArray = PackedStringArray()
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) != "legs":
			continue
		var effects: Array = part["effects"] as Array
		if not effects.has("dodge_roll") and not effects.has("crouch"):
			without.append(str(part_id))
	is_true(without.size() >= 1,
		"at least one legs part opens no tunnel, so the tunnel is a real gate: %s"
			% [without])


# --- helpers -------------------------------------------------------------------

func _parts_for(blueprint_id: String, slot: String) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if str(part["slot"]) == slot \
				and (part["fits_blueprints"] as Array).has(blueprint_id):
			ids.append(str(part_id))
	return ids


func _parts_with_effect(blueprint_id: String, effect_id: String) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for part_id: Variant in Config.parts:
		var part: Dictionary = Config.parts[part_id] as Dictionary
		if (part["effects"] as Array).has(effect_id) \
				and (part["fits_blueprints"] as Array).has(blueprint_id):
			ids.append(str(part_id))
	return ids


func _is_carried_anywhere(effect_id: String) -> bool:
	for part_id: Variant in Config.parts:
		if ((Config.parts[part_id] as Dictionary)["effects"] as Array).has(effect_id):
			return true
	return false


## Which weight classes some legal build actually lands in.
##
## Every reachable *total*, found by folding the slots together — a subset sum,
## not a walk over loadouts, so it stays instant at catalogue scale. Part weights
## are whole numbers, which is what makes the set finite and small.
func _reachable_classes(blueprint_id: String) -> Dictionary:
	var totals: Dictionary = {0: true}
	var slots: Dictionary = Config.blueprint(blueprint_id)["slots"] as Dictionary
	for slot_id: Variant in slots:
		var slot: String = str(slot_id)
		var choices: Array[int] = []
		if not bool((slots[slot] as Dictionary).get("required", false)):
			choices.append(0)  # left empty
		for part_id: String in _parts_for(blueprint_id, slot):
			choices.append(int(round(float(Config.part(part_id)["weight"]))))

		var next: Dictionary = {}
		for carried: Variant in totals:
			for weight: int in choices:
				next[int(carried) + weight] = true
		totals = next

	var reachable: Dictionary = {}
	for total: Variant in totals:
		reachable[WeightClass.class_for_weight(float(total))] = true
	return reachable
