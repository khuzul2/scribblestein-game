extends TestCase

## M11: the level format, its loader, and the geometry analysis the gate proofs
## now rest on.
##
## The claim under test is the one that makes an editor possible at all: a level
## is *data*, there is exactly one representation of it, and the thing the editor
## writes is the thing the game reads. Anywhere those diverge, someone draws a
## level that does not play.

const LEVEL_ID: String = "level_01_margins"


# --- the format ----------------------------------------------------------------

func test_the_shipped_level_parses_and_validates() -> void:
	var problems: PackedStringArray = PackedStringArray()
	var level: LevelData = LevelData.load_from(LevelData.find(LEVEL_ID), problems)
	not_null(level, "level_01 loads: %s" % [problems])
	if level == null:
		return
	eq(level.id, LEVEL_ID, "it knows its own id")
	is_true(level.terrain.size() > 0, "it has terrain")
	is_true(level.doors.size() > 0, "and a way out")


func test_a_level_round_trips_through_json_unchanged() -> void:
	# The editor's save path. If this loses anything, it loses somebody's work.
	var problems: PackedStringArray = PackedStringArray()
	var original: LevelData = LevelData.load_from(LevelData.find(LEVEL_ID), problems)
	not_null(original, "loaded")
	if original == null:
		return

	var written: Dictionary = original.to_dictionary()
	var reloaded: LevelData = LevelData.from_dictionary(written)
	eq(JSON.stringify(reloaded.to_dictionary()), JSON.stringify(written),
		"parsing what we wrote produces what we wrote")

	eq(reloaded.terrain.size(), original.terrain.size(), "every polygon survived")
	eq(reloaded.enemies.size(), original.enemies.size(), "every enemy survived")
	eq(reloaded.pickups.size(), original.pickups.size(), "every pickup survived")
	eq(reloaded.signs.size(), original.signs.size(), "every sign survived")
	is_true(reloaded.spawn.is_equal_approx(original.spawn), "the spawn point survived")


func test_saving_to_disk_and_loading_back_is_lossless() -> void:
	var level: LevelData = _sample_level()
	var path: String = "user://levels/test_round_trip.json"
	var problems: PackedStringArray = level.save(path)
	is_true(problems.is_empty(), "it saved: %s" % [problems])

	var reloaded: LevelData = LevelData.load_from(path, problems)
	not_null(reloaded, "and loaded back: %s" % [problems])
	if reloaded != null:
		eq(JSON.stringify(reloaded.to_dictionary()), JSON.stringify(level.to_dictionary()),
			"byte for byte the same level")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_level_the_game_could_not_read_cannot_be_saved() -> void:
	# The editor's guard rail: better to refuse the write than to produce a file
	# that fails at the start of someone's playtest.
	var level: LevelData = _sample_level()
	level.id = "Not A Valid Id"
	var problems: PackedStringArray = level.save("user://levels/test_bad.json")
	is_false(problems.is_empty(), "the save was refused")
	is_false(FileAccess.file_exists("user://levels/test_bad.json"),
		"and nothing was written")


func test_the_schema_rejects_the_mistakes_it_exists_to_catch() -> void:
	var base: Dictionary = _sample_level().to_dictionary()

	var no_points: Dictionary = base.duplicate(true)
	((no_points["terrain"] as Array)[0] as Dictionary)["points"] = [[0, 0], [10, 0]]
	is_false(LevelData.validate(no_points).is_empty(), "a two-point polygon is refused")

	var bad_kind: Dictionary = base.duplicate(true)
	((bad_kind["terrain"] as Array)[0] as Dictionary)["kind"] = "jelly"
	is_false(LevelData.validate(bad_kind).is_empty(), "an unknown terrain kind is refused")

	var too_much_music: Dictionary = base.duplicate(true)
	too_much_music["music"] = {"tracks": ["a.ogg", "b.ogg", "c.ogg", "d.ogg",
		"e.ogg", "f.ogg"]}
	is_false(LevelData.validate(too_much_music).is_empty(),
		"a sixth song is refused — five per level")

	var sketch_without_part: Dictionary = base.duplicate(true)
	sketch_without_part["pickups"] = [{"kind": "sketch", "at": [0, 0]}]
	is_false(LevelData.validate(sketch_without_part).is_empty(),
		"a blueprint sketch of nothing is refused")


# --- geometry ------------------------------------------------------------------

func test_the_analyser_finds_the_ground_you_can_stand_on() -> void:
	var level: LevelData = _sample_level()
	var surfaces: Array[LevelGeometry.Surface] = LevelGeometry.surfaces(level)
	is_true(surfaces.size() >= 2, "both slabs have a top edge")
	for surface: LevelGeometry.Surface in surfaces:
		is_true(surface.left.x < surface.right.x, "surfaces run left to right")


func test_the_analyser_measures_a_gap_it_was_given() -> void:
	# A drawn level has no constants to compare against, so the analyser has to
	# recover the numbers. Build a known gap and check it reports that gap.
	var level: LevelData = LevelData.new()
	level.id = "gap_probe"
	level.name = "Gap"
	level.spawn = Vector2(0.0, -100.0)
	_slab(level, Rect2(0.0, 0.0, 600.0, 200.0))
	_slab(level, Rect2(1000.0, 300.0, 600.0, 200.0))
	_door(level, Vector2(1200.0, 300.0))

	var widest: LevelGeometry.Gap = LevelGeometry.widest_gap(level)
	almost(widest.width(), 400.0, 1.0, "the 400 px gap is measured as 400 px")
	almost(widest.drop(), 300.0, 1.0, "and the 300 px drop as 300 px")


func test_a_wide_floor_that_starts_behind_you_is_still_a_landing() -> void:
	# Walking off a lip onto a chasm floor that began further back is not a leap.
	# Reading only where a surface *starts* misses it and invents a huge gap.
	var level: LevelData = LevelData.new()
	level.id = "ledge_probe"
	level.name = "Ledge"
	level.spawn = Vector2(0.0, -100.0)
	_slab(level, Rect2(0.0, 0.0, 600.0, 200.0))
	_slab(level, Rect2(-400.0, 800.0, 2000.0, 300.0))
	_door(level, Vector2(1200.0, 800.0))

	var widest: LevelGeometry.Gap = LevelGeometry.widest_gap(level)
	is_true(widest.width() < 100.0,
		"stepping off the lip is not a %.0f px jump" % widest.width())


func test_reachability_agrees_with_the_jump_maths() -> void:
	var stats: CreatureStats = PartAssembler.preview_stats(
		CreatureFixture.loadout(), "biped")
	var reach: float = JumpMath.horizontal_reach(stats, 0.0, "biped")

	var easy: LevelData = _two_ledges(reach * 0.5)
	is_true(LevelGeometry.walkable_to_exit(easy, stats),
		"a gap at half the build's reach is walkable")

	var impossible: LevelData = _two_ledges(reach * 2.0)
	is_false(LevelGeometry.walkable_to_exit(impossible, stats),
		"a gap at twice its reach is not")


func test_the_shipped_level_is_walkable_with_the_starter_kit() -> void:
	var problems: PackedStringArray = PackedStringArray()
	var level: LevelData = LevelData.load_from(LevelData.find(LEVEL_ID), problems)
	not_null(level, "loaded")
	if level == null:
		return
	var starter: CreatureStats = PartAssembler.preview_stats(
		CreatureFixture.loadout(), "biped")
	is_true(LevelGeometry.walkable_to_exit(level, starter),
		"the exported Level 01 reaches its exit on foot")


# --- helpers -------------------------------------------------------------------

func _slab(level: LevelData, rect: Rect2) -> void:
	var piece: LevelData.Terrain = LevelData.Terrain.new()
	piece.kind = "solid"
	piece.points = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])
	level.terrain.append(piece)


func _door(level: LevelData, at: Vector2) -> void:
	var door: LevelData.Door = LevelData.Door.new()
	door.at = at
	level.doors.append(door)


func _two_ledges(gap: float) -> LevelData:
	var level: LevelData = LevelData.new()
	level.id = "reach_probe"
	level.name = "Reach"
	level.spawn = Vector2(100.0, -100.0)
	_slab(level, Rect2(0.0, 0.0, 600.0, 200.0))
	_slab(level, Rect2(600.0 + gap, 0.0, 600.0, 200.0))
	_door(level, Vector2(600.0 + gap + 300.0, 0.0))
	return level


func _sample_level() -> LevelData:
	var level: LevelData = LevelData.new()
	level.id = "sample"
	level.name = "Sample"
	level.spawn = Vector2(0.0, -120.0)
	_slab(level, Rect2(-400.0, 0.0, 1200.0, 300.0))
	_slab(level, Rect2(1000.0, -200.0, 600.0, 300.0))
	_door(level, Vector2(1300.0, -200.0))

	var rope: LevelData.Rope = LevelData.Rope.new()
	rope.at = Vector2(900.0, -600.0)
	rope.length = 500.0
	level.ropes.append(rope)

	var enemy: LevelData.EnemySpawn = LevelData.EnemySpawn.new()
	enemy.id = "enemy_scribble_grunt"
	enemy.at = Vector2(200.0, -60.0)
	enemy.patrol = 300.0
	enemy.facing = -1
	level.enemies.append(enemy)

	var ink: LevelData.PickupSpawn = LevelData.PickupSpawn.new()
	ink.kind = "ink"
	ink.at = Vector2(400.0, -60.0)
	ink.amount = 15
	level.pickups.append(ink)

	var scrawl: LevelData.Sign = LevelData.Sign.new()
	scrawl.at = Vector2(0.0, -300.0)
	scrawl.text = "mind the gap"
	level.signs.append(scrawl)
	return level
