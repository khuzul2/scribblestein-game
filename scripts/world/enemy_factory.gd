class_name EnemyFactory
extends RefCounted

## Builds an enemy from `enemies.json` — through the same creature scene and the
## same assembly pipeline the player uses (Mandate B2).
##
## The only things an enemy gets that the player does not are an `AIBrain`
## instead of `PlayerInput`, and an optional `hp_override` for tuning. Everything
## else — stats, hitboxes, attacks, weight class, movement — is derived from the
## parts it wears, exactly as for the player.

const CREATURE_SCENE: String = "res://scenes/creature/creature.tscn"


## Spawn `enemy_id` into `parent` at `position`, hunting `target` (may be null).
static func spawn(enemy_id: String, parent: Node, position: Vector2,
		target: Creature = null) -> Creature:
	var enemy: Dictionary = Config.enemy(enemy_id)

	var creature: Creature = (load(CREATURE_SCENE) as PackedScene).instantiate() as Creature
	creature.name = "%s_%d" % [enemy_id, parent.get_child_count()]
	creature.is_player = false
	creature.blueprint_id = str(enemy.get("blueprint", "biped"))
	creature.position = position
	creature.set_meta("enemy_id", enemy_id)
	parent.add_child(creature)

	var problems: PackedStringArray = creature.assemble(enemy["assembly"] as Dictionary)
	if not problems.is_empty():
		push_error("Cannot spawn '%s': %s" % [enemy_id, ", ".join(problems)])
		creature.queue_free()
		return null

	# hp_override replaces the computed max for tuning; every other stat still
	# derives from the parts (enemies.json → notes).
	if enemy.has("hp_override"):
		creature.health.set_maximum(float(enemy["hp_override"]), true)

	# The controller is the only difference between a player and an enemy
	# (Mandate B2). PlayerInput stays in the tree but inert — freeing it would
	# leave every `creature.player_input` reference dangling for no gain.
	creature.player_input.set_enabled(false)

	var brain: AIBrain = AIBrain.new()
	brain.name = "AIBrain"
	creature.add_child(brain)
	brain.configure(enemy)
	brain.set_target(target)

	return creature


## The enemy id a spawned creature was built from, or "" for the player.
static func id_of(creature: Creature) -> String:
	return str(creature.get_meta("enemy_id", ""))


static func brain_of(creature: Creature) -> AIBrain:
	return creature.get_node_or_null("AIBrain") as AIBrain
