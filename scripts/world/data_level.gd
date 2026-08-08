class_name DataLevel
extends PlayScene

## A level built entirely from a `LevelData` — the only level type the game
## needs from here on.
##
## Everything `level_01_margins.gd` did in GDScript, this does from JSON: draw
## the terrain, hang the ropes, place the enemies and the rewards, put the door
## where the door goes. That is what makes the editor possible — the editor
## writes the same file this reads, so what you drew is exactly what you play,
## with no second implementation to drift.

signal load_failed(problems: PackedStringArray)

## Physics layer and tile texture per terrain kind. Presentation and collision
## in one table, because they are two halves of the same authoring decision.
const TERRAIN_KINDS: Dictionary = {
	"solid": {"layer": Layers.WORLD, "tile": "tile_ground", "one_way": false},
	"oneway": {"layer": Layers.WORLD, "tile": "tile_oneway", "one_way": true},
	"climbable": {"layer": Layers.WORLD, "tile": "tile_climbable", "one_way": false},
	"cracked": {"layer": Layers.WORLD_CRACKED, "tile": "tile_cracked", "one_way": false},
	"hazard": {"layer": Layers.HAZARD, "tile": "tile_hazard", "one_way": false},
}
## How far past a climbable face the climb marker reaches, so a creature that is
## *touching* the wall registers it.
const CLIMB_MARGIN_PX: float = 24.0
## Ropes are thin; this is how wide the climbable region around one is.
const ROPE_GRAB_WIDTH: float = 48.0
## What plays in a level that has no soundtrack of its own. A level authored
## without music should still have some, rather than shipping silence.
const FALLBACK_MUSIC: String = "mus_level01_loop"

var data: LevelData = null

var exit_door: ExitDoor = null

var _load_problems: PackedStringArray = PackedStringArray()


## Build a level scene from an id, ready to be added to the tree. Returns null
## when the level cannot be read; the problems are in `out_errors`.
static func create(level_id: String, out_errors: PackedStringArray) -> DataLevel:
	var path: String = LevelData.find(level_id)
	if path == "":
		out_errors.append("no level file for '%s' in %s or %s"
			% [level_id, LevelData.SHIPPED_DIR, LevelData.USER_DIR])
		return null
	var level_data: LevelData = LevelData.load_from(path, out_errors)
	if level_data == null:
		return null
	return from_data(level_data)


static func from_data(level_data: LevelData) -> DataLevel:
	var scene: DataLevel = DataLevel.new()
	scene.name = "Level_%s" % level_data.id
	scene.data = level_data
	scene.level_id = level_data.id
	return scene


func _build_world() -> void:
	if data == null:
		_load_problems.append("DataLevel was added to the tree with no data")
		return
	level_id = data.id
	spawn_point = data.spawn

	for piece: LevelData.Terrain in data.terrain:
		_build_terrain(piece)
	for rope: LevelData.Rope in data.ropes:
		_build_rope(rope)
	for scrawl: LevelData.Sign in data.signs:
		add_warning_sketch(scrawl.at, scrawl.text)
	for door: LevelData.Door in data.doors:
		_build_door(door)


func _on_world_ready() -> void:
	if not _load_problems.is_empty():
		load_failed.emit(_load_problems)
		return
	for spawn_record: LevelData.EnemySpawn in data.enemies:
		var enemy: Creature = add_enemy(spawn_record.id, spawn_record.at)
		if enemy != null:
			enemy.facing = spawn_record.facing
			_apply_patrol(enemy, spawn_record)
	for pickup: LevelData.PickupSpawn in data.pickups:
		_build_pickup(pickup)
	if exit_door != null:
		exit_door.reached.connect(_on_exit_reached)
	_start_music()


## A level's own soundtrack wins; otherwise the shipped loop. Only ever one of
## them, because two music players talking at once is worse than either.
func _start_music() -> void:
	MusicDirector.play_for(data)
	if MusicDirector.is_playing():
		Audio.stop_music()
	else:
		Audio.music(FALLBACK_MUSIC)


# --- terrain -------------------------------------------------------------------

func _build_terrain(piece: LevelData.Terrain) -> void:
	if piece.points.size() < 3:
		return
	var spec: Dictionary = TERRAIN_KINDS.get(piece.kind, {}) as Dictionary
	if spec.is_empty():
		_load_problems.append("unknown terrain kind '%s'" % piece.kind)
		return

	var box: Rect2 = piece.bounds()
	_note_ground(box)

	if piece.kind == "hazard":
		_build_hazard(piece, box)
		return
	if piece.kind == "cracked":
		_build_cracked(piece, box)
		return

	var body: StaticBody2D = StaticBody2D.new()
	body.name = "%s_%d" % [piece.kind.capitalize(), get_child_count()]
	body.collision_layer = Layers.bit(int(spec["layer"]))
	body.collision_mask = 0

	var shape: CollisionPolygon2D = CollisionPolygon2D.new()
	shape.polygon = piece.points
	# A one-way platform is solid from above and empty from below, which is what
	# lets a player hop up through it and drop back down.
	shape.one_way_collision = bool(spec["one_way"])
	body.add_child(shape)

	body.add_child(_skin(piece.points, str(spec["tile"])))
	add_child(body)

	if piece.kind == "climbable":
		_mark_climbable(piece.points, box)


## The drawing. A `Polygon2D` with a repeating tile, so the outline you drew is
## the outline that is inked — no separate art step, and no way for the picture
## and the collision to disagree.
func _skin(points: PackedVector2Array, tile: String) -> Polygon2D:
	var skin: Polygon2D = Polygon2D.new()
	skin.polygon = points
	skin.texture = load("res://assets/tiles/%s.png" % tile) as Texture2D
	skin.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	skin.z_index = -10
	LineBoil.apply(skin)
	return skin


## A `climbable` marker area over the polygon's face, grown sideways so a
## creature brushing the wall registers it.
func _mark_climbable(points: PackedVector2Array, box: Rect2) -> void:
	var marker: Area2D = Area2D.new()
	marker.name = "Climbable_%d" % get_child_count()
	marker.collision_layer = Layers.bit(Layers.CLIMBABLE)
	marker.collision_mask = 0
	marker.monitoring = false
	marker.monitorable = true

	var shape: CollisionPolygon2D = CollisionPolygon2D.new()
	shape.polygon = _grown(points, box, CLIMB_MARGIN_PX)
	marker.add_child(shape)
	add_child(marker)


## Push every point outwards from the shape's centre by `margin`. Cruder than a
## real polygon offset, and exactly right for the job: the marker only has to be
## a little bigger than the wall it describes.
func _grown(points: PackedVector2Array, box: Rect2, margin: float) -> PackedVector2Array:
	var centre: Vector2 = box.get_center()
	var grown: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		var away: Vector2 = point - centre
		grown.append(point if away.is_zero_approx() else point + away.normalized() * margin)
	return grown


## Spikes and the like: an area that hurts on contact rather than a body that
## stops you. Hazards are exempt from the attack-window rule by design — they
## are the world, not an attack.
func _build_hazard(piece: LevelData.Terrain, _box: Rect2) -> void:
	var area: Area2D = Area2D.new()
	area.name = "Hazard_%d" % get_child_count()
	area.collision_layer = Layers.bit(Layers.HAZARD)
	area.collision_mask = Layers.mask([Layers.PLAYER_BODY])
	area.monitoring = true

	var shape: CollisionPolygon2D = CollisionPolygon2D.new()
	shape.polygon = piece.points
	area.add_child(shape)
	area.add_child(_skin(piece.points, "tile_hazard"))
	area.body_entered.connect(_on_hazard_touched)
	add_child(area)


func _on_hazard_touched(body: Node2D) -> void:
	var creature: Creature = body as Creature
	if creature == null or not creature.is_player or creature.health.is_dead():
		return
	Combat.resolve_hazard(creature, Config.cfg_int("combat.hazard_damage"),
		creature.global_position + Vector2(0.0, 40.0))


## Cracked floors keep their own scene, because breaking is behaviour rather
## than shape. The polygon's bounding box is what the tile is fitted to.
func _build_cracked(piece: LevelData.Terrain, box: Rect2) -> void:
	var tile: CrackedFloor = add_cracked_floor(box)
	tile.floor_id = "%s_crack_%d" % [level_id, get_child_count()]


# --- ropes ---------------------------------------------------------------------

## A rope is a climbable line: no collision to stand on, just somewhere to hold.
## It reuses `can_climb` rather than inventing a second climbing rule, so a
## creature that can scale a wall can also go up a rope, and one that cannot,
## cannot.
func _build_rope(rope: LevelData.Rope) -> void:
	var area: Area2D = Area2D.new()
	area.name = "Rope_%d" % get_child_count()
	area.collision_layer = Layers.bit(Layers.CLIMBABLE)
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.position = rope.at + Vector2(0.0, rope.length * 0.5)

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(ROPE_GRAB_WIDTH, rope.length)
	shape_node.shape = shape
	area.add_child(shape_node)

	var line: Line2D = Line2D.new()
	line.points = PackedVector2Array([
		Vector2(0.0, -rope.length * 0.5), Vector2(0.0, rope.length * 0.5)])
	line.width = 6.0
	line.default_color = Paper.INK
	line.z_index = -5
	area.add_child(line)

	add_child(area)
	_note_ground(Rect2(rope.at, Vector2(ROPE_GRAB_WIDTH, rope.length)))


# --- inhabitants ---------------------------------------------------------------

## A placed enemy patrols a beat centred on where it was put, rather than
## wandering the whole level. `patrol` of 0 leaves it standing guard.
func _apply_patrol(enemy: Creature, record: LevelData.EnemySpawn) -> void:
	var brain: AIBrain = enemy.get_node_or_null("AIBrain") as AIBrain
	if brain == null:
		return
	brain.patrol_origin = record.at
	brain.patrol_half_width = record.patrol


func _build_pickup(record: LevelData.PickupSpawn) -> void:
	var pickup: Node2D = null
	match record.kind:
		"ink":
			pickup = Pickups.Ink.create(record.amount)
		"sketch":
			pickup = Pickups.BlueprintSketch.create(record.part)
		"fluid":
			pickup = Pickups.CorrectionFluid.create()
	if pickup == null:
		_load_problems.append("unknown pickup kind '%s'" % record.kind)
		return
	pickup.position = record.at
	add_child(pickup)


func _build_door(record: LevelData.Door) -> void:
	exit_door = ExitDoor.new()
	exit_door.name = "ExitDoor"
	exit_door.position = record.at
	add_child(exit_door)


func _on_exit_reached(_by: Creature) -> void:
	mark_completed()
	exit_requested.emit()
