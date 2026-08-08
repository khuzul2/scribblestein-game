extends SceneTree

## One-shot: write `scripts/levels/level_01_margins.gd`'s geometry out as a
## `data/levels/*.json` file, so the hand-coded level becomes an ordinary data
## level like anything the editor produces.
##
##     godot --headless -s tools/export_level_01.gd
##
## Kept in the repository rather than run once and deleted: it is the record of
## how the shipped level's rectangles map onto the level format, and re-running
## it is the way to check that the port still matches the original geometry.

const OUT_PATH: String = "res://data/levels/level_01_margins.json"

# Mirrors of the constants in scripts/levels/level_01_margins.gd. Read from the
# script itself so the two cannot disagree.
var _level_script: GDScript = null


func _initialize() -> void:
	_level_script = load("res://scripts/levels/level_01_margins.gd") as GDScript
	var level: LevelData = LevelData.new()
	level.id = "level_01_margins"
	level.name = "The Margins"
	level.order = 1
	level.keys = PackedStringArray(["can_glide", "can_climb", "crouch"])
	level.spawn = Vector2(-420.0, -80.0)

	_entrance(level)
	_climb_shaft(level)
	_corridor(level)
	_chasm(level)
	_exit(level)
	_inhabitants(level)

	var problems: PackedStringArray = level.save(OUT_PATH)
	if not problems.is_empty():
		for problem: String in problems:
			printerr(problem)
		quit(1)
		return

	print("Wrote %s — %d terrain, %d enemies, %d pickups." % [OUT_PATH,
		level.terrain.size(), level.enemies.size(), level.pickups.size()])
	_report(level)
	quit(0)


func _constant(name: String) -> float:
	return float(_level_script.get(name))


## A rectangle as a clockwise polygon, which is what the format stores.
func _box(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])


func _terrain(level: LevelData, kind: String, rect: Rect2) -> void:
	var piece: LevelData.Terrain = LevelData.Terrain.new()
	piece.kind = kind
	piece.points = _box(rect)
	level.terrain.append(piece)


func _ink(level: LevelData, at: Vector2, amount: int) -> void:
	var pickup: LevelData.PickupSpawn = LevelData.PickupSpawn.new()
	pickup.kind = "ink"
	pickup.at = at
	pickup.amount = amount
	level.pickups.append(pickup)


func _sign(level: LevelData, at: Vector2, text: String) -> void:
	var scrawl: LevelData.Sign = LevelData.Sign.new()
	scrawl.at = at
	scrawl.text = text
	level.signs.append(scrawl)


# --- the level -----------------------------------------------------------------

func _entrance(level: LevelData) -> void:
	var depth: float = _constant("GROUND_DEPTH")
	_terrain(level, "solid", Rect2(-1150.0, 0.0, 2050.0, depth))
	_sign(level, Vector2(-560.0, -880.0),
		"THE MARGINS\n\nno rebuilding past this point\nbring: claws (ink stash) · wings (sketch)")
	_sign(level, Vector2(560.0, -700.0), "something lives here")
	_terrain(level, "solid", Rect2(1050.0, 0.0, 1350.0, depth))


func _climb_shaft(level: LevelData) -> void:
	var shaft: float = _constant("SHAFT_HEIGHT")
	var base_x: float = -1060.0
	_sign(level, Vector2(base_x + 120.0, -shaft - 300.0), "claws\nonly")
	_terrain(level, "climbable", Rect2(base_x, -shaft, 90.0, shaft))
	_terrain(level, "solid", Rect2(base_x, -shaft - 70.0, 520.0, 70.0))
	for index: int in range(4):
		_ink(level, Vector2(base_x + 120.0 + 80.0 * float(index), -shaft - 140.0), 12)


func _corridor(level: LevelData) -> void:
	_terrain(level, "solid", Rect2(2400.0, 0.0, 1500.0, _constant("GROUND_DEPTH")))


func _chasm(level: LevelData) -> void:
	var depth: float = _constant("GROUND_DEPTH")
	var gap: float = _constant("GLIDE_GAP")
	var drop: float = _constant("GLIDE_DROP")
	var clearance: float = _constant("TUNNEL_CLEARANCE")
	var floor_y: float = drop + _constant("LEDGE_CLEARANCE")
	var lip_x: float = 3900.0

	_sign(level, Vector2(lip_x - 260.0, -760.0), "wings\nreach the ledge")
	_terrain(level, "solid", Rect2(lip_x - 500.0, floor_y, 2400.0, depth))

	_sign(level, Vector2(lip_x - 300.0, floor_y - 640.0), "duck\n(ink back there)")
	_terrain(level, "solid", Rect2(lip_x - 460.0, floor_y - clearance - 420.0, 420.0, 420.0))
	for index: int in range(3):
		_ink(level, Vector2(lip_x - 400.0 + 70.0 * float(index), floor_y - 60.0), 14)

	_terrain(level, "solid", Rect2(lip_x + gap, drop, 300.0, _constant("LEDGE_THICKNESS")))
	var sketch: LevelData.PickupSpawn = LevelData.PickupSpawn.new()
	sketch.kind = "sketch"
	sketch.at = Vector2(lip_x + gap + 150.0, drop - 70.0)
	sketch.part = "arms_climber_claws"
	level.pickups.append(sketch)
	_ink(level, Vector2(lip_x + gap + 60.0, drop - 70.0), 20)

	_sign(level, Vector2(lip_x + 980.0, floor_y - 420.0), "heavy?")
	_terrain(level, "cracked", Rect2(lip_x + 900.0, floor_y, 260.0, 70.0))
	_terrain(level, "solid", Rect2(lip_x + 900.0, floor_y + 180.0, 260.0, depth))
	_terrain(level, "solid", Rect2(lip_x + 1160.0, floor_y + 90.0, 120.0, depth))
	for index: int in range(5):
		_ink(level, Vector2(lip_x + 930.0 + 50.0 * float(index), floor_y + 110.0), 16)


func _exit(level: LevelData) -> void:
	var floor_y: float = _constant("GLIDE_DROP") + _constant("LEDGE_CLEARANCE")
	_sign(level, Vector2(5460.0, floor_y - 460.0), "out")
	var door: LevelData.Door = LevelData.Door.new()
	door.at = Vector2(5500.0, floor_y)
	level.doors.append(door)


func _inhabitants(level: LevelData) -> void:
	var floor_y: float = _constant("GLIDE_DROP") + _constant("LEDGE_CLEARANCE")
	var placements: Array[Array] = [
		["enemy_scribble_grunt", Vector2(620.0, -120.0), 420.0],
		["enemy_scribble_grunt", Vector2(1900.0, -120.0), 420.0],
		["enemy_wall_crawler", Vector2(3100.0, -120.0), 300.0],
		["enemy_stinger", Vector2(4300.0, floor_y - 220.0), 500.0],
		["enemy_wall_crawler", Vector2(5000.0, floor_y - 120.0), 300.0],
	]
	for entry: Array in placements:
		var spawn_record: LevelData.EnemySpawn = LevelData.EnemySpawn.new()
		spawn_record.id = str(entry[0])
		spawn_record.at = entry[1] as Vector2
		spawn_record.patrol = float(entry[2])
		spawn_record.facing = -1
		level.enemies.append(spawn_record)


## What the geometry analysis makes of the result, as a sanity read-out.
func _report(level: LevelData) -> void:
	var surfaces: Array[LevelGeometry.Surface] = LevelGeometry.surfaces(level)
	var widest: LevelGeometry.Gap = LevelGeometry.widest_gap(level)
	print("  %d walkable surfaces; widest gap %.0f px with a %.0f px drop; "
		% [surfaces.size(), widest.width(), widest.drop()]
		+ "tightest head-room %.0f px." % LevelGeometry.tightest_headroom(level))
