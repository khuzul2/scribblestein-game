extends TestCase

## M11: a level loaded from data is a real, playable level.
##
## The format round-trip is proved in `test_level_format.gd`; this is the other
## half — that `DataLevel` turns the file into the same working scene the
## hand-coded level was. If these pass, the editor's output is playable by
## construction, because the editor writes exactly this format.

const LEVEL_ID: String = "level_01_margins"
## The autopilot needs real time to walk a level; this is generous.
const AUTOPILOT_SECONDS: float = 90.0

var _scene: DataLevel = null


func after_each() -> void:
	if is_instance_valid(_scene):
		_scene.get_parent().remove_child(_scene)
		_scene.queue_free()
	_scene = null
	MusicDirector.stop()


func test_the_shipped_level_builds_from_its_file() -> void:
	var problems: PackedStringArray = PackedStringArray()
	_scene = DataLevel.create(LEVEL_ID, problems)
	not_null(_scene, "the level was created: %s" % [problems])
	if _scene == null:
		return

	tree.root.add_child(_scene)
	await tree.process_frame
	await tree.physics_frame

	not_null(_scene.player, "a player was spawned")
	eq(_scene.level_id, LEVEL_ID, "it knows which level it is")
	not_null(_scene.exit_door, "the exit door was placed")
	# A frame of physics has run, so it has settled a little rather than being
	# exactly on the mark.
	is_true(_scene.player.global_position.distance_to(_scene.data.spawn) < 40.0,
		"the player starts at the level's spawn point (%.0f px away)"
			% _scene.player.global_position.distance_to(_scene.data.spawn))


func test_every_authored_thing_reaches_the_scene() -> void:
	var problems: PackedStringArray = PackedStringArray()
	_scene = DataLevel.create(LEVEL_ID, problems)
	tree.root.add_child(_scene)
	await tree.process_frame
	await tree.physics_frame

	var bodies: int = 0
	var pickups: int = 0
	for child: Node in _scene.get_children():
		if child is StaticBody2D:
			bodies += 1
		elif child is Pickup:
			pickups += 1

	# A hazard is an Area2D rather than a body; everything else, cracked floors
	# included, is something you stand on.
	var expected_bodies: int = 0
	for piece: LevelData.Terrain in _scene.data.terrain:
		if piece.kind != "hazard":
			expected_bodies += 1
	eq(bodies, expected_bodies, "one body per solid polygon")
	eq(pickups, _scene.data.pickups.size(), "one pickup per authored pickup")
	eq(_scene.enemies().size(), _scene.data.enemies.size(),
		"one enemy per authored enemy")


func test_terrain_kinds_land_on_the_right_physics_layers() -> void:
	var level: LevelData = _probe_level()
	_scene = DataLevel.from_data(level)
	tree.root.add_child(_scene)
	await tree.process_frame
	await tree.physics_frame

	var found: Dictionary = {}
	for child: Node in _scene.get_children():
		var body: StaticBody2D = child as StaticBody2D
		if body != null:
			found[body.collision_layer] = true
		var area: Area2D = child as Area2D
		if area != null:
			found[area.collision_layer] = true

	is_true(found.has(Layers.bit(Layers.WORLD)), "solid ground is on the world layer")
	is_true(found.has(Layers.bit(Layers.CLIMBABLE)),
		"a climbable wall carries a climbable marker")
	is_true(found.has(Layers.bit(Layers.HAZARD)), "a hazard is on the hazard layer")


func test_a_one_way_platform_is_solid_only_from_above() -> void:
	var level: LevelData = _probe_level()
	_scene = DataLevel.from_data(level)
	tree.root.add_child(_scene)
	await tree.process_frame

	var one_way: int = 0
	for child: Node in _scene.get_children():
		var body: StaticBody2D = child as StaticBody2D
		if body == null:
			continue
		for grandchild: Node in body.get_children():
			var shape: CollisionPolygon2D = grandchild as CollisionPolygon2D
			if shape != null and shape.one_way_collision:
				one_way += 1
	eq(one_way, 1, "exactly the platform is one-way, and nothing else is")


func test_a_rope_is_climbable() -> void:
	var level: LevelData = _probe_level()
	_scene = DataLevel.from_data(level)
	tree.root.add_child(_scene)
	await tree.process_frame

	var ropes: int = 0
	for child: Node in _scene.get_children():
		if child.name.begins_with("Rope"):
			ropes += 1
			eq((child as Area2D).collision_layer, Layers.bit(Layers.CLIMBABLE),
				"a rope is something to hold, on the climbable layer")
	eq(ropes, level.ropes.size(), "every rope was hung")


func test_a_placed_enemy_keeps_the_beat_it_was_given() -> void:
	var level: LevelData = _probe_level()
	_scene = DataLevel.from_data(level)
	tree.root.add_child(_scene)
	await tree.process_frame
	await tree.physics_frame

	var enemies: Array[Creature] = _scene.enemies()
	is_true(enemies.size() > 0, "an enemy was placed")
	if enemies.is_empty():
		return
	var brain: AIBrain = enemies[0].get_node_or_null("AIBrain") as AIBrain
	not_null(brain, "it has a brain")
	if brain == null:
		return
	almost(brain.patrol_half_width, level.enemies[0].patrol, 0.001,
		"and the patrol width the level asked for")


func test_a_missing_level_fails_with_a_message_rather_than_a_crash() -> void:
	var problems: PackedStringArray = PackedStringArray()
	var missing: DataLevel = DataLevel.create("no_such_level", problems)
	is_null(missing, "nothing was built")
	is_false(problems.is_empty(), "and the reason was reported")


func test_the_autopilot_clears_the_level_loaded_from_data() -> void:
	# The whole claim in one test: a level that exists only as a JSON file is
	# completable by a bot that knows nothing about it, wearing the starter kit.
	SaveManager.data = SaveManager.default_save()
	var problems: PackedStringArray = PackedStringArray()
	_scene = DataLevel.create(LEVEL_ID, problems)
	not_null(_scene, "level built: %s" % [problems])
	if _scene == null:
		return
	tree.root.add_child(_scene)
	await tree.process_frame

	var bot: Autopilot = Autopilot.new()
	_scene.add_child(bot)
	bot.drive(_scene)

	var ticks: int = int(AUTOPILOT_SECONDS * 60.0)
	for _i: int in range(ticks):
		await tree.physics_frame
		if bot.reached_exit:
			break
	is_true(bot.reached_exit,
		"the bot reached the exit in %.1f s (it got as far as x=%.0f)"
			% [bot.elapsed, _scene.player.global_position.x])


# --- a small level exercising every element type -------------------------------

func _probe_level() -> LevelData:
	var level: LevelData = LevelData.new()
	level.id = "probe"
	level.name = "Probe"
	level.spawn = Vector2(0.0, -120.0)

	_slab(level, "solid", Rect2(-400.0, 0.0, 1600.0, 300.0))
	_slab(level, "oneway", Rect2(200.0, -400.0, 300.0, 40.0))
	_slab(level, "climbable", Rect2(900.0, -600.0, 80.0, 600.0))
	_slab(level, "cracked", Rect2(600.0, 0.0, 200.0, 60.0))
	_slab(level, "hazard", Rect2(1300.0, 0.0, 200.0, 100.0))

	var rope: LevelData.Rope = LevelData.Rope.new()
	rope.at = Vector2(1100.0, -700.0)
	rope.length = 600.0
	level.ropes.append(rope)

	var enemy: LevelData.EnemySpawn = LevelData.EnemySpawn.new()
	enemy.id = "enemy_scribble_grunt"
	enemy.at = Vector2(300.0, -60.0)
	enemy.patrol = 250.0
	level.enemies.append(enemy)

	var ink: LevelData.PickupSpawn = LevelData.PickupSpawn.new()
	ink.kind = "ink"
	ink.at = Vector2(500.0, -60.0)
	ink.amount = 12
	level.pickups.append(ink)

	var door: LevelData.Door = LevelData.Door.new()
	door.at = Vector2(1150.0, 0.0)
	level.doors.append(door)
	return level


func _slab(level: LevelData, kind: String, rect: Rect2) -> void:
	var piece: LevelData.Terrain = LevelData.Terrain.new()
	piece.kind = kind
	piece.points = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])
	level.terrain.append(piece)
