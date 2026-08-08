class_name DataValidator
extends RefCounted

## Boot-time validation of everything under `res://data/` (Mandate B1, TECH_SPEC §9).
##
## Two layers:
##   1. `parts_db.json` against `parts_db.schema.json` (JSON Schema draft-07 subset).
##   2. Cross-file structural checks that a schema cannot express — effect ids,
##      slot kinds, blueprint bones, enemy assemblies, config completeness.
##
## Every issue names the file, the JSON path, and the reason. Nothing defaults
## silently. Issues whose id appears in `data/validation_waivers.json` are
## downgraded to warnings and re-printed on every boot so they stay visible —
## see `DECISIONS_NEEDED.md`.

const SEVERITY_ERROR: String = "error"
const SEVERITY_WARNING: String = "warning"

const KNOWN_AI_PROFILES: Array[String] = [
	"ground_chaser", "wall_patroller", "glide_harasser",
]
const REQUIRED_WEIGHT_CLASS_KEYS: Array[String] = [
	"max_total_weight", "max_speed", "accel", "decel",
	"jump_velocity", "air_control", "knockback_taken_mult",
]


## `data` holds the parsed files keyed by stem: parts_db, parts_schema,
## blueprints, effects, enemies, game_config. `waivers` maps issue id -> reason.
## Returns an Array of {severity, id, message} dictionaries.
static func validate(data: Dictionary, waivers: Dictionary = {}) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []

	_check_parts_schema(data, issues)
	_check_effects_file(data, issues)
	_check_blueprints(data, issues)
	_check_parts_cross_refs(data, issues)
	_check_enemies(data, issues)
	_check_game_config(data, issues)
	_check_weight_classes_are_reachable(data, issues)

	for issue: Dictionary in issues:
		if waivers.has(issue["id"]):
			issue["severity"] = SEVERITY_WARNING
			issue["message"] = "%s\n    WAIVED: %s (see DECISIONS_NEEDED.md)" % [
				issue["message"], str(waivers[issue["id"]])]
	return issues


static func errors_of(issues: Array[Dictionary]) -> Array[Dictionary]:
	return issues.filter(func(i: Dictionary) -> bool: return i["severity"] == SEVERITY_ERROR)


static func warnings_of(issues: Array[Dictionary]) -> Array[Dictionary]:
	return issues.filter(func(i: Dictionary) -> bool: return i["severity"] == SEVERITY_WARNING)


# --- layer 1: schema -----------------------------------------------------------

static func _check_parts_schema(data: Dictionary, issues: Array[Dictionary]) -> void:
	var parts_db: Dictionary = data.get("parts_db", {}) as Dictionary
	var schema: Dictionary = data.get("parts_schema", {}) as Dictionary
	if parts_db.is_empty() or schema.is_empty():
		_add(issues, SEVERITY_ERROR, "parts_db:unloaded",
			"parts_db.json or parts_db.schema.json was not loaded")
		return
	for message: String in JsonSchema.validate(parts_db, schema):
		_add(issues, SEVERITY_ERROR, "schema:%s" % message.split(":")[0],
			"data/parts_db.json %s" % message)


# --- layer 2: cross-file -------------------------------------------------------

static func _check_effects_file(data: Dictionary, issues: Array[Dictionary]) -> void:
	var effects: Dictionary = _effects(data)
	var game_config: Dictionary = data.get("game_config", {}) as Dictionary
	for effect_id: Variant in effects:
		var effect: Dictionary = effects[effect_id] as Dictionary
		for key: String in ["category", "slot_kinds", "description"]:
			if not effect.has(key):
				_add(issues, SEVERITY_ERROR, "effect_shape:%s:%s" % [effect_id, key],
					"data/effects.json /effects/%s: missing required key '%s'" % [effect_id, key])
		if effect.has("params_from"):
			var reference: String = str(effect["params_from"])
			if not reference.begins_with("game_config."):
				_add(issues, SEVERITY_ERROR, "effect_params_prefix:%s" % effect_id,
					"data/effects.json /effects/%s/params_from: '%s' must start with 'game_config.'"
					% [effect_id, reference])
			elif _dig(game_config, reference.substr("game_config.".length()).split(".")) == null:
				_add(issues, SEVERITY_ERROR, "effect_params_missing:%s" % effect_id,
					"data/effects.json /effects/%s/params_from: '%s' does not resolve in data/game_config.json"
					% [effect_id, reference])


static func _check_blueprints(data: Dictionary, issues: Array[Dictionary]) -> void:
	var blueprints: Dictionary = _blueprints(data)
	if blueprints.is_empty():
		_add(issues, SEVERITY_ERROR, "blueprints:empty", "data/blueprints.json declares no blueprints")
		return
	for blueprint_id: Variant in blueprints:
		var blueprint: Dictionary = blueprints[blueprint_id] as Dictionary
		var bones: Dictionary = blueprint.get("bones", {}) as Dictionary
		var path: String = "data/blueprints.json /blueprints/%s" % blueprint_id

		if bones.is_empty():
			_add(issues, SEVERITY_ERROR, "blueprint_bones:%s" % blueprint_id,
				"%s/bones: a blueprint needs at least one bone" % path)
			continue

		var roots: int = 0
		for bone_id: Variant in bones:
			var bone: Dictionary = bones[bone_id] as Dictionary
			var parent: Variant = bone.get("parent", null)
			if parent == null:
				roots += 1
			elif not bones.has(parent):
				_add(issues, SEVERITY_ERROR, "blueprint_bone_parent:%s:%s" % [blueprint_id, bone_id],
					"%s/bones/%s/parent: unknown bone '%s'" % [path, bone_id, parent])
			if not bone.has("position") or not bone["position"] is Array \
					or (bone["position"] as Array).size() != 2:
				_add(issues, SEVERITY_ERROR, "blueprint_bone_pos:%s:%s" % [blueprint_id, bone_id],
					"%s/bones/%s/position: expected [x, y]" % [path, bone_id])
		if roots != 1:
			_add(issues, SEVERITY_ERROR, "blueprint_roots:%s" % blueprint_id,
				"%s/bones: expected exactly 1 root bone (parent null), found %d" % [path, roots])

		var slots: Dictionary = blueprint.get("slots", {}) as Dictionary
		if slots.is_empty():
			_add(issues, SEVERITY_ERROR, "blueprint_slots:%s" % blueprint_id,
				"%s/slots: a blueprint needs at least one slot" % path)
		for slot_id: Variant in slots:
			var slot: Dictionary = slots[slot_id] as Dictionary
			if not slot.has("kind"):
				_add(issues, SEVERITY_ERROR, "blueprint_slot_kind:%s:%s" % [blueprint_id, slot_id],
					"%s/slots/%s: missing 'kind'" % [path, slot_id])
			for bone_name: String in _slot_bones(slot):
				if not bones.has(bone_name):
					_add(issues, SEVERITY_ERROR,
						"blueprint_slot_bone:%s:%s:%s" % [blueprint_id, slot_id, bone_name],
						"%s/slots/%s: references unknown bone '%s'" % [path, slot_id, bone_name])
			if _slot_bones(slot).is_empty():
				_add(issues, SEVERITY_ERROR, "blueprint_slot_nobone:%s:%s" % [blueprint_id, slot_id],
					"%s/slots/%s: needs 'bone' or 'bone_pair'" % [path, slot_id])


static func _check_parts_cross_refs(data: Dictionary, issues: Array[Dictionary]) -> void:
	var parts: Dictionary = _parts(data)
	var effects: Dictionary = _effects(data)
	var blueprints: Dictionary = _blueprints(data)

	for part_id: Variant in parts:
		var part: Dictionary = parts[part_id] as Dictionary
		var path: String = "data/parts_db.json /parts/%s" % part_id
		var slot: String = str(part.get("slot", ""))

		if bool(part.get("starter", false)) and int(part.get("unlock_cost", -1)) != 0:
			_add(issues, SEVERITY_ERROR, "starter_cost:%s" % part_id,
				"%s/unlock_cost: starter parts must cost 0, found %s" % [path, part.get("unlock_cost")])

		var slot_kinds: Dictionary = {}
		for blueprint_id: Variant in part.get("fits_blueprints", []) as Array:
			if not blueprints.has(blueprint_id):
				_add(issues, SEVERITY_ERROR, "part_blueprint:%s:%s" % [part_id, blueprint_id],
					"%s/fits_blueprints: unknown blueprint '%s'" % [path, blueprint_id])
				continue
			var blueprint: Dictionary = blueprints[blueprint_id] as Dictionary
			var slots: Dictionary = blueprint.get("slots", {}) as Dictionary
			if not slots.has(slot):
				_add(issues, _stub_severity(blueprint),
					"part_blueprint_slot:%s:%s" % [part_id, blueprint_id],
					"%s: declares slot '%s' but blueprint '%s' has no such slot (has: %s)"
					% [path, slot, blueprint_id, ", ".join(PackedStringArray(slots.keys()))])
				continue
			slot_kinds[str((slots[slot] as Dictionary).get("kind", ""))] = true

		for effect_id: Variant in part.get("effects", []) as Array:
			if not effects.has(effect_id):
				_add(issues, SEVERITY_ERROR, "part_effect:%s:%s" % [part_id, effect_id],
					"%s/effects: unknown effect '%s' (not in data/effects.json)" % [path, effect_id])
				continue
			var legal_kinds: Array = (effects[effect_id] as Dictionary).get("slot_kinds", []) as Array
			for kind: Variant in slot_kinds:
				if not legal_kinds.has(kind):
					_add(issues, SEVERITY_ERROR, "part_effect_slot_kind:%s:%s" % [part_id, effect_id],
						"%s/effects: effect '%s' is legal on slot kinds %s, but slot '%s' is kind '%s'"
						% [path, effect_id, str(legal_kinds), slot, kind])

		var has_damage_box: bool = false
		for hitbox: Variant in part.get("hitboxes", []) as Array:
			if str((hitbox as Dictionary).get("type", "")) == "damage":
				has_damage_box = true
		if has_damage_box:
			for kind: Variant in slot_kinds:
				if str(kind) != "attack":
					_add(issues, SEVERITY_ERROR, "damage_box_slot_kind:%s" % part_id,
						"%s/hitboxes: carries a 'damage' hitbox but sits in slot '%s' of kind '%s'; damage boxes belong to attack slots only (Mandate B5)"
						% [path, slot, kind])


static func _check_enemies(data: Dictionary, issues: Array[Dictionary]) -> void:
	var enemies: Dictionary = _enemies(data)
	var parts: Dictionary = _parts(data)
	var blueprints: Dictionary = _blueprints(data)

	for enemy_id: Variant in enemies:
		var enemy: Dictionary = enemies[enemy_id] as Dictionary
		var path: String = "data/enemies.json /enemies/%s" % enemy_id
		var blueprint_id: String = str(enemy.get("blueprint", ""))

		if not blueprints.has(blueprint_id):
			_add(issues, SEVERITY_ERROR, "enemy_blueprint:%s" % enemy_id,
				"%s/blueprint: unknown blueprint '%s'" % [path, blueprint_id])
			continue

		var slots: Dictionary = (blueprints[blueprint_id] as Dictionary).get("slots", {}) as Dictionary
		var assembly: Dictionary = enemy.get("assembly", {}) as Dictionary

		for slot_id: Variant in slots:
			var slot: Dictionary = slots[slot_id] as Dictionary
			var filled: bool = assembly.has(slot_id) and assembly[slot_id] != null
			if bool(slot.get("required", false)) and not filled:
				_add(issues, SEVERITY_ERROR, "enemy_required_slot:%s:%s" % [enemy_id, slot_id],
					"%s/assembly: required slot '%s' is empty" % [path, slot_id])

		for slot_id: Variant in assembly:
			if not slots.has(slot_id):
				_add(issues, SEVERITY_ERROR, "enemy_unknown_slot:%s:%s" % [enemy_id, slot_id],
					"%s/assembly: blueprint '%s' has no slot '%s'" % [path, blueprint_id, slot_id])
				continue
			var part_id: Variant = assembly[slot_id]
			if part_id == null:
				continue
			if not parts.has(part_id):
				_add(issues, SEVERITY_ERROR, "enemy_part:%s:%s" % [enemy_id, part_id],
					"%s/assembly/%s: unknown part '%s'" % [path, slot_id, part_id])
				continue
			var part: Dictionary = parts[part_id] as Dictionary
			if str(part.get("slot", "")) != str(slot_id):
				_add(issues, SEVERITY_ERROR, "enemy_part_slot:%s:%s" % [enemy_id, part_id],
					"%s/assembly/%s: part '%s' belongs in slot '%s'"
					% [path, slot_id, part_id, part.get("slot")])
			if not (part.get("fits_blueprints", []) as Array).has(blueprint_id):
				_add(issues, SEVERITY_ERROR, "enemy_part_fit:%s:%s" % [enemy_id, part_id],
					"%s/assembly/%s: part '%s' does not fit blueprint '%s'"
					% [path, slot_id, part_id, blueprint_id])

		var ai: Dictionary = enemy.get("ai", {}) as Dictionary
		if not KNOWN_AI_PROFILES.has(str(ai.get("profile", ""))):
			_add(issues, SEVERITY_ERROR, "enemy_ai_profile:%s" % enemy_id,
				"%s/ai/profile: unknown profile '%s' (known: %s)"
				% [path, ai.get("profile"), ", ".join(PackedStringArray(KNOWN_AI_PROFILES))])
		for key: String in ["patrol_speed", "chase_speed", "aggro_radius",
				"deaggro_radius", "attack_range", "attack_cooldown"]:
			if not ai.has(key):
				_add(issues, SEVERITY_ERROR, "enemy_ai_key:%s:%s" % [enemy_id, key],
					"%s/ai: missing required key '%s'" % [path, key])
		if ai.has("aggro_radius") and ai.has("deaggro_radius") \
				and float(ai["deaggro_radius"]) <= float(ai["aggro_radius"]):
			_add(issues, SEVERITY_ERROR, "enemy_ai_radii:%s" % enemy_id,
				"%s/ai: deaggro_radius (%s) must exceed aggro_radius (%s)"
				% [path, ai["deaggro_radius"], ai["aggro_radius"]])

		var drops: Dictionary = enemy.get("drops", {}) as Dictionary
		var ink: Dictionary = drops.get("ink", {}) as Dictionary
		if not ink.has("min") or not ink.has("max"):
			_add(issues, SEVERITY_ERROR, "enemy_ink:%s" % enemy_id,
				"%s/drops/ink: needs 'min' and 'max'" % path)
		elif float(ink["min"]) > float(ink["max"]):
			_add(issues, SEVERITY_ERROR, "enemy_ink_range:%s" % enemy_id,
				"%s/drops/ink: min (%s) exceeds max (%s)" % [path, ink["min"], ink["max"]])

		var blueprint_drop: Dictionary = drops.get("blueprint", {}) as Dictionary
		if not blueprint_drop.is_empty():
			var dropped_part: Variant = blueprint_drop.get("part", null)
			if not parts.has(dropped_part):
				_add(issues, SEVERITY_ERROR, "enemy_drop_part:%s" % enemy_id,
					"%s/drops/blueprint/part: unknown part '%s'" % [path, dropped_part])
			if int(blueprint_drop.get("pity_kills", 0)) <= 0:
				_add(issues, SEVERITY_ERROR, "enemy_pity:%s" % enemy_id,
					"%s/drops/blueprint/pity_kills: must be >= 1" % path)


static func _check_game_config(data: Dictionary, issues: Array[Dictionary]) -> void:
	var config: Dictionary = data.get("game_config", {}) as Dictionary
	var required_paths: PackedStringArray = PackedStringArray([
		"movement.gravity", "movement.coyote_time", "movement.jump_buffer",
		"movement.terminal_fall_speed", "movement.weight_classes",
		"movement.glide.glide_fall_cap", "movement.glide.glide_air_control",
		"movement.double_jump.velocity_mult", "movement.climb.climb_speed",
		"movement.climb.wall_jump_impulse", "movement.roll.distance",
		"movement.roll.duration", "movement.roll.iframes", "movement.roll.cooldown",
		"movement.crouch.speed_mult", "movement.crouch.hurtbox_height_mult",
		"combat.player_iframes_on_hit", "combat.enemy_iframes_on_hit",
		"combat.knockback_decay", "combat.hazard_damage",
		"economy.blueprint_duplicate_ink_bonus", "economy.correction_fluid.heal",
		"economy.correction_fluid.despawn_seconds", "economy.ink_pickup_magnet_radius",
		"camera.ref_height", "camera.zoom_min", "camera.zoom_max",
		"camera.lerp_speed", "camera.lookahead_px", "camera.drag_margin",
		"line_boil.boil_fps", "line_boil.boil_fps_range", "line_boil.amplitude_px",
		"line_boil.ui_amplitude_px",
	])
	for reference: String in required_paths:
		if _dig(config, reference.split(".")) == null:
			_add(issues, SEVERITY_ERROR, "config_missing:%s" % reference,
				"data/game_config.json /%s: missing required value" % reference.replace(".", "/"))

	var classes: Dictionary = _dig(config, PackedStringArray(["movement", "weight_classes"])) as Dictionary \
		if _dig(config, PackedStringArray(["movement", "weight_classes"])) != null else {}
	var previous_threshold: float = -1.0
	for class_name_key: String in ["light", "medium", "heavy"]:
		if not classes.has(class_name_key):
			_add(issues, SEVERITY_ERROR, "config_class:%s" % class_name_key,
				"data/game_config.json /movement/weight_classes: missing class '%s'" % class_name_key)
			continue
		var preset: Dictionary = classes[class_name_key] as Dictionary
		for key: String in REQUIRED_WEIGHT_CLASS_KEYS:
			if not preset.has(key):
				_add(issues, SEVERITY_ERROR, "config_class_key:%s:%s" % [class_name_key, key],
					"data/game_config.json /movement/weight_classes/%s: missing '%s'"
					% [class_name_key, key])
		var threshold: float = float(preset.get("max_total_weight", 0.0))
		if threshold <= previous_threshold:
			_add(issues, SEVERITY_ERROR, "config_class_order:%s" % class_name_key,
				"data/game_config.json /movement/weight_classes/%s/max_total_weight: %s must exceed the previous class' %s"
				% [class_name_key, threshold, previous_threshold])
		previous_threshold = threshold
		if float(preset.get("jump_velocity", -1.0)) >= 0.0:
			_add(issues, SEVERITY_ERROR, "config_class_jump:%s" % class_name_key,
				"data/game_config.json /movement/weight_classes/%s/jump_velocity: must be negative (up is -Y)"
				% class_name_key)

	# Mandate A3: the boil must stutter between 8 and 12 FPS, never outside it.
	var boil: Dictionary = config.get("line_boil", {}) as Dictionary
	if boil.has("boil_fps") and boil.has("boil_fps_range"):
		var boil_range: Array = boil["boil_fps_range"] as Array
		var fps: float = float(boil["boil_fps"])
		if boil_range.size() != 2 or float(boil_range[0]) < 8.0 or float(boil_range[1]) > 12.0:
			_add(issues, SEVERITY_ERROR, "config_boil_range",
				"data/game_config.json /line_boil/boil_fps_range: must sit inside [8, 12] (Mandate A3), found %s"
				% str(boil_range))
		elif fps < float(boil_range[0]) or fps > float(boil_range[1]):
			_add(issues, SEVERITY_ERROR, "config_boil_fps",
				"data/game_config.json /line_boil/boil_fps: %s is outside boil_fps_range %s"
				% [fps, str(boil_range)])


## DESIGN §5 promises three playable weight classes. If the lightest legal
## assembly cannot reach a band, that band is dead content — worth saying out
## loud rather than discovering it in a playtest.
static func _check_weight_classes_are_reachable(data: Dictionary, issues: Array[Dictionary]) -> void:
	var parts: Dictionary = _parts(data)
	var blueprints: Dictionary = _blueprints(data)
	var classes: Dictionary = _dig(data.get("game_config", {}),
		PackedStringArray(["movement", "weight_classes"])) as Dictionary
	if classes.is_empty() or parts.is_empty():
		return

	for blueprint_id: Variant in blueprints:
		var blueprint: Dictionary = blueprints[blueprint_id] as Dictionary
		if str(blueprint.get("status", "")).begins_with("STUB"):
			continue
		var slots: Dictionary = blueprint.get("slots", {}) as Dictionary

		var lightest_total: float = 0.0
		var lightest_build: PackedStringArray = PackedStringArray()
		for slot_id: Variant in slots:
			if not bool((slots[slot_id] as Dictionary).get("required", false)):
				continue
			var best_id: String = ""
			var best_weight: float = INF
			for part_id: Variant in parts:
				var part: Dictionary = parts[part_id] as Dictionary
				if str(part.get("slot", "")) != str(slot_id):
					continue
				if not (part.get("fits_blueprints", []) as Array).has(blueprint_id):
					continue
				if float(part.get("weight", 0.0)) < best_weight:
					best_weight = float(part.get("weight", 0.0))
					best_id = str(part_id)
			if best_id != "":
				lightest_total += best_weight
				lightest_build.append("%s (%d)" % [best_id, int(best_weight)])

		var lightest_class: String = ""
		for candidate: String in ["light", "medium", "heavy"]:
			if classes.has(candidate) \
					and lightest_total <= float((classes[candidate] as Dictionary).get("max_total_weight", 0.0)):
				lightest_class = candidate
				break

		for candidate: String in ["light", "medium", "heavy"]:
			if candidate == lightest_class:
				break
			_add(issues, SEVERITY_WARNING, "weight_class_unreachable:%s:%s" % [blueprint_id, candidate],
				"data/game_config.json /movement/weight_classes/%s: unreachable on blueprint '%s'. The lightest legal build is %s = %d, past this class' ceiling of %d."
				% [candidate, blueprint_id, ", ".join(lightest_build), int(lightest_total),
					int((classes[candidate] as Dictionary).get("max_total_weight", 0.0))])


# --- helpers -------------------------------------------------------------------

static func _add(issues: Array[Dictionary], severity: String, id: String, message: String) -> void:
	issues.append({"severity": severity, "id": id, "message": message})


## Cross-reference failures against a blueprint still marked STUB are warnings:
## the rig does not exist yet (quadruped lands in M8), so they cannot be verified.
static func _stub_severity(blueprint: Dictionary) -> String:
	return SEVERITY_WARNING if str(blueprint.get("status", "")).begins_with("STUB") else SEVERITY_ERROR


static func _slot_bones(slot: Dictionary) -> PackedStringArray:
	var bones: PackedStringArray = PackedStringArray()
	if slot.has("bone"):
		bones.append(str(slot["bone"]))
	for bone: Variant in slot.get("bone_pair", []) as Array:
		bones.append(str(bone))
	return bones


static func _dig(root: Variant, keys: PackedStringArray) -> Variant:
	var node: Variant = root
	for key: String in keys:
		if not node is Dictionary or not (node as Dictionary).has(key):
			return null
		node = (node as Dictionary)[key]
	return node


static func _parts(data: Dictionary) -> Dictionary:
	return (data.get("parts_db", {}) as Dictionary).get("parts", {}) as Dictionary


static func _effects(data: Dictionary) -> Dictionary:
	return (data.get("effects", {}) as Dictionary).get("effects", {}) as Dictionary


static func _blueprints(data: Dictionary) -> Dictionary:
	return (data.get("blueprints", {}) as Dictionary).get("blueprints", {}) as Dictionary


static func _enemies(data: Dictionary) -> Dictionary:
	return (data.get("enemies", {}) as Dictionary).get("enemies", {}) as Dictionary
