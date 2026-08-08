class_name DropTable
extends RefCounted

## What a dead enemy leaves behind (DESIGN §8).
##
## Ink by tier, a Correction Fluid on a percentage roll, and a Blueprint Sketch
## on an RNG roll *backed by a pity timer*: a per-enemy-type kill counter lives
## in the save, and the drop is guaranteed on the `pity_kills`-th kill if the RNG
## has not fired first. The counter resets on any drop.
##
## `rng` is injectable, and `chance_override` pins every percentage roll to a
## fixed value — set it to 1.0 and no chance can succeed, which is how the pity
## timer's promise is proved on its own. Gameplay leaves it at -1.
static var chance_override: float = -1.0


static func _chance(generator: RandomNumberGenerator) -> float:
	return chance_override if chance_override >= 0.0 else generator.randf()



## Roll the drops for one kill and update the save's counters. Returns a list of
## `{kind, ...}` descriptors; `spawn_all` turns them into nodes.
static func roll(enemy_id: String, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var generator: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		generator.randomize()

	var enemy: Dictionary = Config.enemy(enemy_id)
	var drops: Dictionary = enemy.get("drops", {}) as Dictionary
	var result: Array[Dictionary] = []

	var ink: Dictionary = drops.get("ink", {}) as Dictionary
	if not ink.is_empty():
		result.append({"kind": "ink",
			"amount": generator.randi_range(int(ink["min"]), int(ink["max"]))})

	if _chance(generator) < float(drops.get("correction_fluid_chance", 0.0)):
		result.append({"kind": "correction_fluid"})

	var counter: Dictionary = SaveManager.kill_counter(enemy_id)
	counter["kills"] = int(counter.get("kills", 0)) + 1
	counter["since_drop"] = int(counter.get("since_drop", 0)) + 1

	var blueprint: Dictionary = drops.get("blueprint", {}) as Dictionary
	if not blueprint.is_empty():
		var pity: int = int(blueprint.get("pity_kills", 0))
		var lucky: bool = _chance(generator) < float(blueprint.get("drop_chance", 0.0))
		var owed: bool = pity > 0 and int(counter["since_drop"]) >= pity
		if lucky or owed:
			counter["since_drop"] = 0
			result.append({"kind": "blueprint", "part_id": str(blueprint["part"])})

	SaveManager.request_save()
	return result


## Instantiate the descriptors around `at`, spread so they do not stack.
static func spawn_all(drops: Array[Dictionary], parent: Node, at: Vector2,
		rng: RandomNumberGenerator = null) -> Array[Pickup]:
	var generator: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	var spawned: Array[Pickup] = []
	for index: int in range(drops.size()):
		var drop: Dictionary = drops[index]
		var pickup: Pickup = spawn_one(drop, parent,
			at + Vector2(generator.randf_range(-70.0, 70.0), -40.0 - 30.0 * float(index)))
		if pickup != null:
			spawned.append(pickup)
	return spawned


static func spawn_one(drop: Dictionary, parent: Node, at: Vector2) -> Pickup:
	var pickup: Pickup = null
	match str(drop["kind"]):
		"ink":
			pickup = Pickups.Ink.create(int(drop["amount"]))
		"correction_fluid":
			pickup = Pickups.CorrectionFluid.create()
		"blueprint":
			pickup = Pickups.BlueprintSketch.create(str(drop["part_id"]))
		_:
			push_error("Unknown drop kind '%s'" % drop["kind"])
			return null
	pickup.position = at
	parent.add_child(pickup)
	return pickup
