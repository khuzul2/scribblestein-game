class_name LevelData
extends RefCounted

## One level, in memory: the parsed form of a `data/levels/<id>.json` file.
##
## Both directions live here. The editor builds a `LevelData` as you draw and
## calls `save()`; the game calls `load_from()` and hands the result to
## `DataLevel`, which builds the scene. Because there is exactly one
## representation, a level that saves is a level that plays — the editor cannot
## produce something the loader does not understand.
##
## Every field is plain data. Nothing here knows about nodes, physics or the
## scene tree; `scripts/world/data_level.gd` is the only thing that does.

const SCHEMA_VERSION: int = 1
const SCHEMA_PATH: String = "res://data/level.schema.json"
## Shipped levels live in the repository; anything authored in an exported build
## goes next to the save file. `find(id)` looks in the user directory first, so a
## player's edit shadows the shipped copy rather than fighting it.
const SHIPPED_DIR: String = "res://data/levels"
const USER_DIR: String = "user://levels"
## `music.tracks` is capped here rather than in prose: five per level.
const MAX_TRACKS: int = 5

var id: String = ""
var name: String = ""
var order: int = 0
var requires: PackedStringArray = PackedStringArray()
var keys: PackedStringArray = PackedStringArray()
var spawn: Vector2 = Vector2.ZERO

var terrain: Array[Terrain] = []
var ropes: Array[Rope] = []
var enemies: Array[EnemySpawn] = []
var pickups: Array[PickupSpawn] = []
var doors: Array[Door] = []
var signs: Array[Sign] = []
var music: Music = Music.new()

## Where this level was read from, so `save()` can write it back.
var source_path: String = ""


class Terrain extends RefCounted:
	## `solid` · `oneway` · `climbable` · `cracked` · `hazard`
	var kind: String = "solid"
	var points: PackedVector2Array = PackedVector2Array()

	func duplicate_terrain() -> Terrain:
		var copy: Terrain = Terrain.new()
		copy.kind = kind
		copy.points = points.duplicate()
		return copy

	## Axis-aligned bounds, for culling, framing and the geometry analysis.
	func bounds() -> Rect2:
		if points.is_empty():
			return Rect2()
		var box: Rect2 = Rect2(points[0], Vector2.ZERO)
		for point: Vector2 in points:
			box = box.expand(point)
		return box


class Rope extends RefCounted:
	var at: Vector2 = Vector2.ZERO
	var length: float = 400.0


class EnemySpawn extends RefCounted:
	var id: String = ""
	var at: Vector2 = Vector2.ZERO
	var facing: int = 1
	## Half-width of the patrol beat in pixels; 0 means "stands where it is put".
	var patrol: float = 0.0


class PickupSpawn extends RefCounted:
	## `ink` · `sketch` · `fluid`
	var kind: String = "ink"
	var at: Vector2 = Vector2.ZERO
	var amount: int = 10
	var part: String = ""


class Door extends RefCounted:
	var kind: String = "exit"
	var at: Vector2 = Vector2.ZERO


class Sign extends RefCounted:
	var at: Vector2 = Vector2.ZERO
	var text: String = ""
	var size: int = 26


class Music extends RefCounted:
	var tracks: PackedStringArray = PackedStringArray()
	var shuffle: bool = false
	var crossfade_seconds: float = 1.5


# --- reading -------------------------------------------------------------------

## Parse one level file. Returns null and fills `out_errors` when the file is
## missing, unparseable or fails the schema — never a half-built level, for the
## same reason assembly is atomic.
static func load_from(path: String, out_errors: PackedStringArray) -> LevelData:
	var result: JsonLoader.Result = JsonLoader.load_object(path)
	if not result.ok:
		out_errors.append(result.error)
		return null

	var raw: Dictionary = result.value as Dictionary
	var problems: PackedStringArray = validate(raw)
	if not problems.is_empty():
		for problem: String in problems:
			out_errors.append("%s: %s" % [path, problem])
		return null

	var level: LevelData = from_dictionary(raw)
	level.source_path = path
	return level


## Schema check only — cross-references (does this enemy exist?) are
## `DataValidator`'s job, because they need the rest of the data set.
static func validate(raw: Dictionary) -> PackedStringArray:
	var schema: JsonLoader.Result = JsonLoader.load_object(SCHEMA_PATH)
	if not schema.ok:
		return PackedStringArray([schema.error])
	return JsonSchema.validate(raw, schema.value as Dictionary, schema.value as Dictionary)


static func from_dictionary(raw: Dictionary) -> LevelData:
	var level: LevelData = LevelData.new()
	level.id = str(raw["id"])
	level.name = str(raw["name"])
	level.order = int(raw.get("order", 0))
	level.requires = PackedStringArray(raw.get("requires", []) as Array)
	level.keys = PackedStringArray(raw.get("keys", []) as Array)
	level.spawn = _point(raw["spawn"] as Array)

	for entry: Variant in raw.get("terrain", []) as Array:
		var piece: Dictionary = entry as Dictionary
		var shape: Terrain = Terrain.new()
		shape.kind = str(piece["kind"])
		for point: Variant in piece["points"] as Array:
			shape.points.append(_point(point as Array))
		level.terrain.append(shape)

	for entry: Variant in raw.get("ropes", []) as Array:
		var record: Dictionary = entry as Dictionary
		var rope: Rope = Rope.new()
		rope.at = _point(record["at"] as Array)
		rope.length = float(record["length"])
		level.ropes.append(rope)

	for entry: Variant in raw.get("enemies", []) as Array:
		var record: Dictionary = entry as Dictionary
		var spawn_point: EnemySpawn = EnemySpawn.new()
		spawn_point.id = str(record["id"])
		spawn_point.at = _point(record["at"] as Array)
		spawn_point.facing = int(record.get("facing", 1))
		spawn_point.patrol = float(record.get("patrol", 0.0))
		level.enemies.append(spawn_point)

	for entry: Variant in raw.get("pickups", []) as Array:
		var record: Dictionary = entry as Dictionary
		var pickup: PickupSpawn = PickupSpawn.new()
		pickup.kind = str(record["kind"])
		pickup.at = _point(record["at"] as Array)
		pickup.amount = int(record.get("amount", 10))
		pickup.part = str(record.get("part", ""))
		level.pickups.append(pickup)

	for entry: Variant in raw.get("doors", []) as Array:
		var record: Dictionary = entry as Dictionary
		var door: Door = Door.new()
		door.kind = str(record["kind"])
		door.at = _point(record["at"] as Array)
		level.doors.append(door)

	for entry: Variant in raw.get("signs", []) as Array:
		var record: Dictionary = entry as Dictionary
		var scrawl: Sign = Sign.new()
		scrawl.at = _point(record["at"] as Array)
		scrawl.text = str(record["text"])
		scrawl.size = int(record.get("size", 26))
		level.signs.append(scrawl)

	var music_raw: Dictionary = raw.get("music", {}) as Dictionary
	level.music.tracks = PackedStringArray(music_raw.get("tracks", []) as Array)
	level.music.shuffle = bool(music_raw.get("shuffle", false))
	level.music.crossfade_seconds = float(music_raw.get("crossfade_seconds", 1.5))
	return level


# --- writing -------------------------------------------------------------------

func to_dictionary() -> Dictionary:
	var raw: Dictionary = {
		"schema": SCHEMA_VERSION,
		"id": id,
		"name": name,
		"order": order,
		"spawn": [spawn.x, spawn.y],
		"terrain": [],
	}
	if not requires.is_empty():
		raw["requires"] = Array(requires)
	if not keys.is_empty():
		raw["keys"] = Array(keys)

	for shape: Terrain in terrain:
		var points: Array = []
		for point: Vector2 in shape.points:
			points.append([point.x, point.y])
		(raw["terrain"] as Array).append({"kind": shape.kind, "points": points})

	if not ropes.is_empty():
		raw["ropes"] = []
		for rope: Rope in ropes:
			(raw["ropes"] as Array).append({"at": [rope.at.x, rope.at.y],
				"length": rope.length})

	if not enemies.is_empty():
		raw["enemies"] = []
		for spawn_point: EnemySpawn in enemies:
			var record: Dictionary = {"id": spawn_point.id,
				"at": [spawn_point.at.x, spawn_point.at.y],
				"facing": spawn_point.facing}
			if spawn_point.patrol > 0.0:
				record["patrol"] = spawn_point.patrol
			(raw["enemies"] as Array).append(record)

	if not pickups.is_empty():
		raw["pickups"] = []
		for pickup: PickupSpawn in pickups:
			var record: Dictionary = {"kind": pickup.kind,
				"at": [pickup.at.x, pickup.at.y]}
			if pickup.kind == "ink":
				record["amount"] = pickup.amount
			elif pickup.kind == "sketch":
				record["part"] = pickup.part
			(raw["pickups"] as Array).append(record)

	if not doors.is_empty():
		raw["doors"] = []
		for door: Door in doors:
			(raw["doors"] as Array).append({"kind": door.kind,
				"at": [door.at.x, door.at.y]})

	if not signs.is_empty():
		raw["signs"] = []
		for scrawl: Sign in signs:
			(raw["signs"] as Array).append({"at": [scrawl.at.x, scrawl.at.y],
				"text": scrawl.text, "size": scrawl.size})

	if not music.tracks.is_empty() or music.shuffle:
		raw["music"] = {
			"tracks": Array(music.tracks),
			"shuffle": music.shuffle,
			"crossfade_seconds": music.crossfade_seconds,
		}
	return raw


## Write to `path`, or back to where this level came from. Validates first: the
## editor must never be able to save a file the game would refuse to load.
func save(path: String = "") -> PackedStringArray:
	var target: String = source_path if path == "" else path
	if target == "":
		target = USER_DIR.path_join("%s.json" % id)

	var raw: Dictionary = to_dictionary()
	var problems: PackedStringArray = validate(raw)
	if not problems.is_empty():
		return problems

	if target.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())

	# Same atomic dance the save file uses: a crash mid-write must not be able
	# to destroy a level that was fine a moment ago.
	var temp: String = "%s.tmp" % target
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return PackedStringArray(["cannot open %s for writing (error %d)"
			% [temp, FileAccess.get_open_error()]])
	file.store_string("%s\n" % JSON.stringify(raw, "  "))
	file.close()

	var dir: DirAccess = DirAccess.open(target.get_base_dir())
	if dir == null or dir.rename(temp.get_file(), target.get_file()) != OK:
		return PackedStringArray(["cannot move %s into place" % temp])
	source_path = target
	return PackedStringArray()


# --- finding levels ------------------------------------------------------------

## Where `level_id` lives, preferring an edited copy over the shipped one.
static func find(level_id: String) -> String:
	var edited: String = USER_DIR.path_join("%s.json" % level_id)
	if FileAccess.file_exists(edited):
		return edited
	var shipped: String = SHIPPED_DIR.path_join("%s.json" % level_id)
	return shipped if ResourceLoader.exists(shipped) or FileAccess.file_exists(shipped) else ""


## Every level id the game can offer, shipped and edited, in `order` then id.
static func catalogue() -> PackedStringArray:
	var ids: Dictionary = {}
	for directory: String in [SHIPPED_DIR, USER_DIR]:
		var dir: DirAccess = DirAccess.open(directory)
		if dir == null:
			continue
		for file_name: String in dir.get_files():
			if file_name.ends_with(".json"):
				ids[file_name.get_basename()] = true
	var sorted: PackedStringArray = PackedStringArray(ids.keys())
	sorted.sort()
	return sorted


static func _point(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))
