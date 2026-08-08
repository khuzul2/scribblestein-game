extends TestCase

## M1 acceptance: hitboxes sit within 1 px of their JSON offsets and rotate with
## their bones (Mandate B4 — bone-local space, generated at assembly time).

const TOLERANCE_PX: float = 1.0

var _creature: Creature = null


func after_each() -> void:
	CreatureFixture.despawn(_creature)
	_creature = null


func test_skeleton_matches_the_blueprint_bone_tree() -> void:
	_creature = CreatureFixture.spawn(tree)
	var bones: Dictionary = Config.blueprint("biped")["bones"] as Dictionary

	for bone_id: Variant in bones:
		var bone: Bone2D = CreatureFixture.bone(_creature, str(bone_id))
		not_null(bone, "bone '%s' exists in the rig" % bone_id)
		if bone == null:
			continue
		var spec: Dictionary = bones[bone_id] as Dictionary
		var expected: Array = spec["position"] as Array
		almost(bone.position.x, float(expected[0]), 0.001, "bone '%s' local x" % bone_id)
		almost(bone.position.y, float(expected[1]), 0.001, "bone '%s' local y" % bone_id)

		var parent_id: Variant = spec.get("parent", null)
		if parent_id == null:
			eq(bone.get_parent(), _creature.skeleton, "the root bone hangs off Skeleton2D")
		else:
			eq(bone.get_parent().name, StringName(str(parent_id)),
				"bone '%s' is parented to '%s'" % [bone_id, parent_id])


func test_every_hitbox_sits_on_its_json_offset() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({
		"tail": "tail_scorpion", "arms": "arms_climber_claws", "back": "back_bat_scraps"}))

	for box: Hitbox in _creature.hitbox_root.all():
		var offset: Array = box.source["offset"] as Array
		# The mirrored far half of a bone pair reflects its offset by design.
		var expected_x: float = absf(float(offset[0]))
		almost(absf(box.position.x), expected_x, TOLERANCE_PX,
			"%s local x matches parts_db" % box.name)
		almost(box.position.y, float(offset[1]), TOLERANCE_PX,
			"%s local y matches parts_db" % box.name)


func test_hitbox_shapes_match_the_json() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({"tail": "tail_scorpion"}))

	for box: Hitbox in _creature.hitbox_root.all():
		var shape: Shape2D = (box.get_child(0) as CollisionShape2D).shape
		if str(box.source["shape"]) == "circle":
			almost((shape as CircleShape2D).radius, float(box.source["radius"]), 0.001,
				"%s radius" % box.name)
		else:
			var extents: Array = box.source["extents"] as Array
			# parts_db stores half-extents; the shape stores full size.
			almost((shape as RectangleShape2D).size.x, float(extents[0]) * 2.0, 0.001,
				"%s width" % box.name)
			almost((shape as RectangleShape2D).size.y, float(extents[1]) * 2.0, 0.001,
				"%s height" % box.name)


func test_hitboxes_rotate_with_their_bone() -> void:
	_creature = CreatureFixture.spawn(tree)
	var head_bone: Bone2D = CreatureFixture.bone(_creature, "head")
	var box: Hitbox = CreatureFixture.boxes_for_slot(_creature, "head").filter(
		func(candidate: Hitbox) -> bool: return candidate.hitbox_type == Hitbox.TYPE_DAMAGE)[0]
	var local_offset: Vector2 = box.position

	# The 12° head-bone dip a bite performs (effects.json → bite_attack).
	for angle_degrees: float in [0.0, 12.0, 90.0, -45.0]:
		head_bone.rotation = deg_to_rad(angle_degrees)
		await tree.process_frame
		var expected: Vector2 = head_bone.global_transform * local_offset
		var actual: Vector2 = box.global_position
		almost(actual.distance_to(expected), 0.0, TOLERANCE_PX,
			"the damage box follows the head bone at %.0f°" % angle_degrees)

	head_bone.rotation = 0.0


func test_flipping_the_creature_carries_its_hitboxes() -> void:
	_creature = CreatureFixture.spawn(tree)
	var box: Hitbox = CreatureFixture.boxes_for_slot(_creature, "head").filter(
		func(candidate: Hitbox) -> bool: return candidate.hitbox_type == Hitbox.TYPE_DAMAGE)[0]

	_creature.facing = 1
	await tree.process_frame
	var reach_right: float = box.global_position.x - _creature.global_position.x
	is_true(reach_right > 0.0, "facing right, the bite reaches to the right")

	_creature.facing = -1
	await tree.process_frame
	var reach_left: float = box.global_position.x - _creature.global_position.x
	is_true(reach_left < 0.0, "facing left, it reaches to the left")
	almost(absf(reach_left), absf(reach_right), TOLERANCE_PX, "by the same distance")


func test_damage_boxes_start_dormant_and_hurtboxes_start_live() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({"tail": "tail_scorpion"}))

	is_true(_creature.hitbox_root.all_damage_boxes_dormant(),
		"no damage box is live outside an attack (Mandate B5)")
	is_true(_creature.hitbox_root.damage_boxes().size() >= 2,
		"but the head and tail damage boxes do exist")
	for box: Hitbox in _creature.hitbox_root.hurtboxes():
		is_true(box.is_enabled(), "%s is live from birth" % box.name)


func test_hitboxes_land_on_the_right_physics_layers() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	for box: Hitbox in _creature.hitbox_root.all():
		if box.hitbox_type == Hitbox.TYPE_DAMAGE:
			eq(box.collision_layer, Layers.bit(Layers.PLAYER_DAMAGE), "%s layer" % box.name)
			eq(box.collision_mask, Layers.bit(Layers.ENEMY_HURTBOX), "%s only sees enemies" % box.name)
		else:
			eq(box.collision_layer, Layers.bit(Layers.PLAYER_HURTBOX), "%s layer" % box.name)
	CreatureFixture.despawn(_creature)

	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout(), false)
	for box: Hitbox in _creature.hitbox_root.all():
		if box.hitbox_type == Hitbox.TYPE_DAMAGE:
			eq(box.collision_layer, Layers.bit(Layers.ENEMY_DAMAGE), "%s layer" % box.name)
			eq(box.collision_mask, Layers.bit(Layers.PLAYER_HURTBOX), "%s only sees the player" % box.name)


func test_part_sprites_glue_their_pivot_to_the_bone_origin() -> void:
	_creature = CreatureFixture.spawn(tree)
	for slot: String in ["torso", "legs", "head"]:
		var bone_name: String = str((Config.blueprint("biped")["slots"] as Dictionary)[slot]["bone"])
		var sprite: Sprite2D = CreatureFixture.sprite_on_bone(_creature, bone_name)
		not_null(sprite, "slot '%s' mounted a sprite on bone '%s'" % [slot, bone_name])
		if sprite == null:
			continue
		var pivot: Dictionary = Config.part(str(_creature.stats.loadout[slot]))["pivot"] as Dictionary
		is_false(sprite.centered, "%s draws from its offset, not its centre" % slot)
		almost(sprite.offset.x, -float(pivot["x"]), 0.001, "%s pivot x lands on the bone" % slot)
		almost(sprite.offset.y, -float(pivot["y"]), 0.001, "%s pivot y lands on the bone" % slot)


func test_arms_mount_on_both_bones_from_one_part() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({"arms": "arms_climber_claws"}))
	not_null(CreatureFixture.sprite_on_bone(_creature, "arm_l"), "the left arm is drawn")
	not_null(CreatureFixture.sprite_on_bone(_creature, "arm_r"), "the right arm is drawn")
	almost(CreatureFixture.sprite_on_bone(_creature, "arm_l").scale.x, -1.0, 0.001,
		"the far arm is mirrored so one texture reads as a pair")
	eq(CreatureFixture.boxes_for_slot(_creature, "arms").size(), 2,
		"and each arm carries its own hurtbox")


func test_the_tail_sprite_trails_behind_the_creature() -> void:
	# ASSET_SPEC §1 authors tails root-at-left facing right; parts_db puts the
	# sting hitbox at -115 x. The sprite must mirror to agree with the hitbox.
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({"tail": "tail_scorpion"}))
	var sprite: Sprite2D = CreatureFixture.sprite_on_bone(_creature, "tail")
	not_null(sprite, "the tail is drawn")
	almost(sprite.scale.x, -1.0, 0.001, "mirrored about its root")

	var damage_box: Hitbox = CreatureFixture.boxes_for_slot(_creature, "tail").filter(
		func(box: Hitbox) -> bool: return box.hitbox_type == Hitbox.TYPE_DAMAGE)[0]
	await tree.process_frame
	is_true(damage_box.global_position.x < _creature.global_position.x,
		"and the sting sits behind a right-facing creature")


func test_the_body_collider_is_derived_from_the_hurtboxes() -> void:
	_creature = CreatureFixture.spawn(tree)
	var small: Vector2 = (_creature.body_collider.shape as RectangleShape2D).size

	_creature.assemble(CreatureFixture.loadout({"torso": "torso_barrel", "legs": "legs_tree_trunks"}))
	var large: Vector2 = (_creature.body_collider.shape as RectangleShape2D).size
	is_true(large.x > small.x, "a barrel-chested creature is a wider obstacle")


func test_rebuilding_leaves_no_orphaned_hitboxes() -> void:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout({"tail": "tail_scorpion"}))
	var first: int = _creature.hitbox_root.all().size()

	for _i: int in range(3):
		_creature.assemble(CreatureFixture.loadout({"tail": "tail_scorpion"}))
	await tree.process_frame

	eq(_creature.hitbox_root.all().size(), first, "the registry does not grow on rebuild")
	var areas: int = 0
	for node: Node in _find_all(_creature.skeleton):
		if node is Hitbox:
			areas += 1
	eq(areas, first, "and no stale Area2D is left in the tree")


func _find_all(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		found.append(child)
		found.append_array(_find_all(child))
	return found
