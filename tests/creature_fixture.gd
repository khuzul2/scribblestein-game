class_name CreatureFixture
extends RefCounted

## Spawns real `creature.tscn` instances inside the test tree, so assembly tests
## exercise the shipping pipeline rather than a stand-in.

const CREATURE_SCENE: String = "res://scenes/creature/creature.tscn"

## The always-unlocked kit (DESIGN §8), spelled out so a test can mutate a copy.
const STARTER_LOADOUT: Dictionary = {
	"torso": "torso_ribby", "legs": "legs_scribble_sprint", "head": "head_monster_maw",
	"tail": null, "arms": null, "back": null,
}


static func loadout(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = STARTER_LOADOUT.duplicate(true)
	for slot: Variant in overrides:
		result[slot] = overrides[slot]
	return result


## An assembled creature parented under `tree.root`. Free it with `despawn`.
static func spawn(tree: SceneTree, creature_loadout: Dictionary = {},
		is_player: bool = true) -> Creature:
	var creature: Creature = (load(CREATURE_SCENE) as PackedScene).instantiate() as Creature
	creature.is_player = is_player
	tree.root.add_child(creature)
	creature.assemble(loadout() if creature_loadout.is_empty() else creature_loadout)
	return creature


## An un-assembled creature, for tests that want to drive `assemble()` themselves.
static func spawn_bare(tree: SceneTree, is_player: bool = true) -> Creature:
	var creature: Creature = (load(CREATURE_SCENE) as PackedScene).instantiate() as Creature
	creature.is_player = is_player
	tree.root.add_child(creature)
	return creature


static func despawn(creature: Creature) -> void:
	if is_instance_valid(creature):
		creature.get_parent().remove_child(creature)
		creature.queue_free()


## Every hitbox a creature owns whose `slot` matches.
static func boxes_for_slot(creature: Creature, slot: String) -> Array[Hitbox]:
	return creature.hitbox_root.all().filter(func(box: Hitbox) -> bool: return box.slot == slot)


## The sprite mounted on a named bone, or null.
static func sprite_on_bone(creature: Creature, bone_name: String) -> Sprite2D:
	var bone: Node = creature.skeleton.find_child(bone_name, true, false)
	if bone == null:
		return null
	for child: Node in bone.get_children():
		if child is Sprite2D:
			return child as Sprite2D
	return null


static func bone(creature: Creature, bone_name: String) -> Bone2D:
	return creature.skeleton.find_child(bone_name, true, false) as Bone2D
