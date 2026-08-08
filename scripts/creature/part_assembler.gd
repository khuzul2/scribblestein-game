class_name PartAssembler
extends RefCounted

## Turns a loadout Dictionary into a rigged, hitboxed creature.
##
## This is the one and only assembly pipeline: the player and every enemy go
## through it (Mandate B2). It reads `blueprints.json` for the skeleton and
## `parts_db.json` for what hangs off it; nothing about a creature's capability
## is authored in a scene (Mandate B4).
##
## Validation is atomic. A loadout with any problem is rejected whole, with a
## message per problem, and the creature is left untouched — a half-built
## creature is worse than none.

## Draw order per slot. Presentation only; the blueprint's `z_behind` flag wins
## where it is set.
const SLOT_Z: Dictionary = {
	"back": -30, "tail": -10, "legs": -5, "legs_front": -5, "legs_rear": -6,
	"torso": 0, "arms": 0, "head": 10,
}
## The far half of a bone pair sits behind the torso, the near half in front,
## so a single mirrored texture reads as a pair.
const PAIR_Z_OFFSET: Array[int] = [-20, 20]

## ASSET_SPEC §1 authors tails root-at-left extending right, but a tail trails
## *behind* a creature that faces +X — and `parts_db.json` already places the
## sting hitbox at negative X. So the tail sprite is mirrored about its root.
const MIRRORED_SLOTS: Array[String] = ["tail"]


## Build `loadout` onto `creature`. Returns an empty array on success, or one
## message per problem — the caller decides whether to log, show, or crash.
static func assemble(creature: Creature, loadout: Dictionary) -> PackedStringArray:
	var blueprint_id: String = creature.blueprint_id
	if not Config.blueprints.has(blueprint_id):
		return PackedStringArray(["Unknown blueprint '%s'" % blueprint_id])

	var blueprint: Dictionary = Config.blueprint(blueprint_id)
	var slots: Dictionary = blueprint["slots"] as Dictionary

	var problems: PackedStringArray = validate(loadout, blueprint_id)
	if not problems.is_empty():
		return problems

	_clear(creature)

	var bones: Dictionary = _build_skeleton(creature, blueprint["bones"] as Dictionary)
	var stats: CreatureStats = CreatureStats.new()

	for slot_id: Variant in slots:
		var slot: String = str(slot_id)
		var slot_spec: Dictionary = slots[slot] as Dictionary
		var part_id: Variant = loadout.get(slot, null)
		if part_id == null:
			# An empty attack slot is simply an inert button (DESIGN §4.2).
			stats.loadout[slot] = null
			continue

		var part: Dictionary = Config.part(str(part_id))
		stats.absorb(slot, str(part_id), part, str(slot_spec.get("wired_to", "")))
		_mount(creature, bones, slot, slot_spec, str(part_id), part)

	creature.hitbox_root.finish_rebuild()
	creature.apply_stats(stats)
	return PackedStringArray()


## Everything that can be wrong with a loadout, without touching the scene.
static func validate(loadout: Dictionary, blueprint_id: String) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if not Config.blueprints.has(blueprint_id):
		problems.append("Unknown blueprint '%s'" % blueprint_id)
		return problems

	var blueprint: Dictionary = Config.blueprint(blueprint_id)
	var slots: Dictionary = blueprint["slots"] as Dictionary

	for slot_id: Variant in loadout:
		if not slots.has(slot_id):
			problems.append("Blueprint '%s' has no slot '%s' (slots: %s)"
				% [blueprint_id, slot_id, ", ".join(PackedStringArray(slots.keys()))])

	for slot_id: Variant in slots:
		var slot: String = str(slot_id)
		var slot_spec: Dictionary = slots[slot] as Dictionary
		var part_id: Variant = loadout.get(slot, null)

		if part_id == null:
			if bool(slot_spec.get("required", false)):
				problems.append(
					"Required slot '%s' is empty — a %s needs every required slot filled (DESIGN §4.2)"
					% [slot, str(blueprint.get("name", blueprint_id))])
			continue

		if not Config.parts.has(part_id):
			problems.append("Slot '%s': no such part '%s' in parts_db.json" % [slot, part_id])
			continue

		var part: Dictionary = Config.part(str(part_id))
		if str(part["slot"]) != slot:
			problems.append("Part '%s' belongs in slot '%s', not '%s'" % [part_id, part["slot"], slot])
		if not (part["fits_blueprints"] as Array).has(blueprint_id):
			problems.append("Part '%s' does not fit blueprint '%s' (fits: %s)"
				% [part_id, blueprint_id, ", ".join(PackedStringArray(part["fits_blueprints"] as Array))])
	return problems


## Stats for a loadout without building anything — the Lab's readouts use this
## so what the sketchbook shows is what assembly will produce.
static func preview_stats(loadout: Dictionary, blueprint_id: String) -> CreatureStats:
	var stats: CreatureStats = CreatureStats.new()
	var slots: Dictionary = Config.blueprint(blueprint_id)["slots"] as Dictionary
	for slot_id: Variant in slots:
		var slot: String = str(slot_id)
		var part_id: Variant = loadout.get(slot, null)
		if part_id == null or not Config.parts.has(part_id):
			stats.loadout[slot] = null
			continue
		stats.absorb(slot, str(part_id), Config.part(str(part_id)),
			str((slots[slot] as Dictionary).get("wired_to", "")))
	return stats


# --- rigging -------------------------------------------------------------------

static func _clear(creature: Creature) -> void:
	creature.hitbox_root.clear()
	for child: Node in creature.skeleton.get_children():
		creature.skeleton.remove_child(child)
		child.queue_free()


## Instantiate one Bone2D per blueprint bone, parented per its `parent` field.
static func _build_skeleton(creature: Creature, bone_specs: Dictionary) -> Dictionary:
	var bones: Dictionary = {}
	var pending: Array[String] = []
	for bone_id: Variant in bone_specs:
		pending.append(str(bone_id))

	# Parents before children, however the JSON happens to be ordered.
	var guard: int = pending.size() + 1
	while not pending.is_empty() and guard > 0:
		guard -= 1
		var still_waiting: Array[String] = []
		for bone_id: String in pending:
			var spec: Dictionary = bone_specs[bone_id] as Dictionary
			var parent_id: Variant = spec.get("parent", null)
			if parent_id != null and not bones.has(parent_id):
				still_waiting.append(bone_id)
				continue

			var bone: Bone2D = Bone2D.new()
			bone.name = bone_id
			var position: Array = spec["position"] as Array
			bone.position = Vector2(float(position[0]), float(position[1]))
			bone.rest = Transform2D(0.0, bone.position)
			# We drive bones by transform, not by IK chains; a fixed length keeps
			# Skeleton2D from warning about an unresolvable auto-calculation.
			bone.set_autocalculate_length_and_angle(false)
			bone.set_length(16.0)
			bone.set_bone_angle(0.0)

			var parent: Node = creature.skeleton if parent_id == null else bones[parent_id] as Node
			parent.add_child(bone)
			bones[bone_id] = bone
		pending = still_waiting
	return bones


## Hang one part's sprite(s) and hitbox(es) on the bone(s) its slot names.
static func _mount(creature: Creature, bones: Dictionary, slot: String,
		slot_spec: Dictionary, part_id: String, part: Dictionary) -> void:
	var bone_ids: PackedStringArray = _slot_bones(slot_spec)
	var pivot: Vector2 = Vector2(
		float((part["pivot"] as Dictionary)["x"]), float((part["pivot"] as Dictionary)["y"]))
	var texture: Texture2D = load(str(part["texture_path"])) as Texture2D

	for index: int in range(bone_ids.size()):
		var bone: Bone2D = bones[bone_ids[index]] as Bone2D
		var is_far_half: bool = bone_ids.size() > 1 and index == 0

		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = "Sprite_%s_%s" % [slot, bone_ids[index]]
		sprite.texture = texture
		sprite.centered = false
		# With centered off, `offset` is the texture's top-left in bone space, so
		# -pivot glues the part's pivot exactly onto the bone origin.
		sprite.offset = -pivot
		if MIRRORED_SLOTS.has(slot) or is_far_half:
			sprite.scale.x = -1.0
		sprite.z_index = _slot_z(slot, slot_spec, index, bone_ids.size())
		LineBoil.apply(sprite)
		bone.add_child(sprite)

		for entry: Variant in part.get("hitboxes", []) as Array:
			var box: Hitbox = Hitbox.create(entry as Dictionary, part_id, slot, creature.is_player)
			if is_far_half:
				box.position.x = -box.position.x
			bone.add_child(box)
			creature.hitbox_root.register(box)


static func _slot_bones(slot_spec: Dictionary) -> PackedStringArray:
	if slot_spec.has("bone"):
		return PackedStringArray([str(slot_spec["bone"])])
	var pair: PackedStringArray = PackedStringArray()
	for bone_id: Variant in slot_spec.get("bone_pair", []) as Array:
		pair.append(str(bone_id))
	return pair


static func _slot_z(slot: String, slot_spec: Dictionary, index: int, bone_count: int) -> int:
	if bool(slot_spec.get("z_behind", false)):
		return int(SLOT_Z.get("back", -30))
	var base: int = int(SLOT_Z.get(slot, 0))
	if bone_count > 1:
		return base + PAIR_Z_OFFSET[mini(index, PAIR_Z_OFFSET.size() - 1)]
	return base
