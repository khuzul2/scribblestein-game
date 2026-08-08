extends TestCase

## M11: the editor itself — drawing, selecting, undo, and the promise that what
## you draw is what you get.
##
## The canvas is driven through the same methods the mouse drives, rather than
## by faking input events, so these tests exercise the editing logic without
## depending on where a button happens to sit on screen.

var _canvas: EditorCanvas = null
var _level: LevelData = null
var _edits: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_level = _blank()
	_canvas = EditorCanvas.new()
	tree.root.add_child(_canvas)
	_canvas.set_level(_level)
	_edits = PackedStringArray()
	_canvas.level_edited.connect(func(label: String) -> void: _edits.append(label))


func after_each() -> void:
	if is_instance_valid(_canvas):
		_canvas.get_parent().remove_child(_canvas)
		_canvas.queue_free()
	_canvas = null
	_level = null


# --- drawing -------------------------------------------------------------------

func test_drawing_a_polygon_adds_terrain_of_the_chosen_kind() -> void:
	_canvas.tool = EditorCanvas.Tool.TERRAIN_SOLID
	for point: Vector2 in [Vector2(0, 0), Vector2(400, 0), Vector2(400, 200)]:
		_canvas.primary_pressed(point)
	eq(_level.terrain.size(), 0, "nothing lands until the shape is closed")

	_canvas.close_draft()
	eq(_level.terrain.size(), 1, "closing the shape adds it")
	eq(_level.terrain[0].kind, "solid", "of the tool's kind")
	eq(_level.terrain[0].points.size(), 3, "with the points that were clicked")
	any_contains(_edits, PackedStringArray(["draw solid"]), "and the edit is named")


func test_every_terrain_tool_draws_its_own_kind() -> void:
	var expected: Dictionary = {
		EditorCanvas.Tool.TERRAIN_ONEWAY: "oneway",
		EditorCanvas.Tool.TERRAIN_CLIMBABLE: "climbable",
		EditorCanvas.Tool.TERRAIN_CRACKED: "cracked",
		EditorCanvas.Tool.TERRAIN_HAZARD: "hazard",
	}
	for which: Variant in expected:
		_canvas.tool = which as EditorCanvas.Tool
		_draw_box(Vector2(0, 0), Vector2(200, 100))
	for kind: Variant in expected.values():
		var count: int = 0
		for piece: LevelData.Terrain in _level.terrain:
			if piece.kind == str(kind):
				count += 1
		eq(count, 1, "one '%s' polygon was drawn" % kind)


func test_a_two_point_polygon_is_refused() -> void:
	_canvas.tool = EditorCanvas.Tool.TERRAIN_SOLID
	_canvas.primary_pressed(Vector2(0, 0))
	_canvas.primary_pressed(Vector2(100, 0))
	_canvas.close_draft()
	eq(_level.terrain.size(), 0, "a line is not a shape")


func test_clicking_back_on_the_first_point_closes_the_shape() -> void:
	_canvas.tool = EditorCanvas.Tool.TERRAIN_SOLID
	_canvas.primary_pressed(Vector2(0, 0))
	_canvas.primary_pressed(Vector2(400, 0))
	_canvas.primary_pressed(Vector2(400, 200))
	_canvas.primary_pressed(Vector2(6, 6))  # within CLOSE_RADIUS of the start
	eq(_level.terrain.size(), 1, "the shape closed itself")


func test_escape_abandons_a_half_drawn_shape() -> void:
	_canvas.tool = EditorCanvas.Tool.TERRAIN_SOLID
	_canvas.primary_pressed(Vector2(0, 0))
	_canvas.primary_pressed(Vector2(400, 0))
	_canvas.cancel_draft()
	_canvas.close_draft()
	eq(_level.terrain.size(), 0, "the abandoned points are gone")


func test_snapping_rounds_points_to_the_grid() -> void:
	_canvas.tool = EditorCanvas.Tool.TERRAIN_SOLID
	_canvas.snap_to_grid = true
	_canvas.primary_pressed(Vector2(13, 7))
	_canvas.primary_pressed(Vector2(397, 3))
	_canvas.primary_pressed(Vector2(390, 190))
	_canvas.close_draft()
	for point: Vector2 in _level.terrain[0].points:
		almost(fmod(point.x, EditorCanvas.GRID_STEP), 0.0, 0.001, "x is on the grid")
		almost(fmod(point.y, EditorCanvas.GRID_STEP), 0.0, 0.001, "y is on the grid")


# --- placing -------------------------------------------------------------------

func test_placing_each_kind_of_thing() -> void:
	_canvas.enemy_id = "enemy_scribble_grunt"
	_canvas.sketch_part_id = "head_anvil"

	_canvas.tool = EditorCanvas.Tool.ENEMY
	_canvas.primary_pressed(Vector2(100, -50))
	eq(_level.enemies.size(), 1, "an enemy was placed")
	eq(_level.enemies[0].id, "enemy_scribble_grunt", "of the chosen kind")

	_canvas.tool = EditorCanvas.Tool.INK
	_canvas.primary_pressed(Vector2(200, -50))
	_canvas.tool = EditorCanvas.Tool.SKETCH
	_canvas.primary_pressed(Vector2(300, -50))
	_canvas.tool = EditorCanvas.Tool.FLUID
	_canvas.primary_pressed(Vector2(400, -50))
	eq(_level.pickups.size(), 3, "three pickups")
	eq(_level.pickups[1].part, "head_anvil", "the sketch knows its part")

	_canvas.tool = EditorCanvas.Tool.ROPE
	_canvas.primary_pressed(Vector2(500, -400))
	eq(_level.ropes.size(), 1, "a rope was hung")

	_canvas.tool = EditorCanvas.Tool.SIGN
	_canvas.primary_pressed(Vector2(600, -300))
	eq(_level.signs.size(), 1, "a sign was scrawled")

	_canvas.tool = EditorCanvas.Tool.SPAWN
	_canvas.primary_pressed(Vector2(-100, -80))
	is_true(_level.spawn.is_equal_approx(Vector2(-100, -80)), "the start moved")


func test_a_second_exit_moves_the_first_rather_than_adding_one() -> void:
	_canvas.tool = EditorCanvas.Tool.DOOR
	_canvas.primary_pressed(Vector2(800, 0))
	_canvas.primary_pressed(Vector2(900, 0))
	eq(_level.doors.size(), 1, "still one way out")
	is_true(_level.doors[0].at.is_equal_approx(Vector2(900, 0)), "and it moved")


func test_a_sketch_without_a_part_chosen_is_refused_with_a_reason() -> void:
	var said: PackedStringArray = PackedStringArray()
	_canvas.status.connect(func(message: String) -> void: said.append(message))
	_canvas.sketch_part_id = ""
	_canvas.tool = EditorCanvas.Tool.SKETCH
	_canvas.primary_pressed(Vector2(100, 0))
	eq(_level.pickups.size(), 0, "nothing was placed")
	is_true(said.size() > 0, "and the editor said why")


# --- selecting, moving, deleting -----------------------------------------------

func test_dragging_a_vertex_reshapes_the_polygon() -> void:
	_draw_box(Vector2(0, 0), Vector2(400, 200))
	var before: Vector2 = _level.terrain[0].points[0]

	_canvas.tool = EditorCanvas.Tool.SELECT
	_canvas.primary_pressed(before)
	_canvas.cursor_moved(before + Vector2(60, -40))
	_canvas.primary_released()

	is_true(_level.terrain[0].points[0].is_equal_approx(before + Vector2(60, -40)),
		"the grabbed corner followed the cursor")
	eq(_level.terrain[0].points.size(), 4, "and no points were added or lost")


func test_dragging_the_body_of_a_shape_moves_the_whole_thing() -> void:
	_draw_box(Vector2(0, 0), Vector2(400, 200))
	var before: PackedVector2Array = _level.terrain[0].points.duplicate()

	_canvas.tool = EditorCanvas.Tool.SELECT
	_canvas.primary_pressed(Vector2(200, 100))  # inside, not on a corner
	_canvas.cursor_moved(Vector2(260, 140))
	_canvas.primary_released()

	for index: int in range(before.size()):
		is_true(_level.terrain[0].points[index].is_equal_approx(
			before[index] + Vector2(60, 40)), "every point moved together")


func test_deleting_the_selection() -> void:
	_canvas.enemy_id = "enemy_scribble_grunt"
	_canvas.tool = EditorCanvas.Tool.ENEMY
	_canvas.primary_pressed(Vector2(100, -50))

	_canvas.tool = EditorCanvas.Tool.SELECT
	_canvas.primary_pressed(Vector2(100, -50))
	_canvas.primary_released()
	_canvas.delete_selected()
	eq(_level.enemies.size(), 0, "the enemy is gone")


func test_the_start_cannot_be_deleted() -> void:
	_canvas.tool = EditorCanvas.Tool.SELECT
	_canvas.primary_pressed(_level.spawn)
	_canvas.primary_released()
	_canvas.delete_selected()
	not_null(_level.spawn, "a level always has somewhere to start")


# --- undo ----------------------------------------------------------------------

func test_undo_and_redo_walk_the_edits() -> void:
	var history: EditorHistory = EditorHistory.new()
	history.begin(_level)
	is_false(history.can_undo(), "nothing to undo yet")

	_draw_box(Vector2(0, 0), Vector2(400, 200))
	history.record(_level, "draw solid")
	_draw_box(Vector2(600, 0), Vector2(1000, 200))
	history.record(_level, "draw solid")
	eq(_level.terrain.size(), 2, "two shapes drawn")

	var once: LevelData = history.undo()
	eq(once.terrain.size(), 1, "one step back")
	var twice: LevelData = history.undo()
	eq(twice.terrain.size(), 0, "two steps back, to the empty level")
	is_false(history.can_undo(), "and that is the beginning")

	var forward: LevelData = history.redo()
	eq(forward.terrain.size(), 1, "redo goes forward again")


func test_a_no_op_edit_is_not_a_step() -> void:
	var history: EditorHistory = EditorHistory.new()
	history.begin(_level)
	history.record(_level, "clicked nothing")
	is_false(history.can_undo(), "clicking on empty space is not an edit")


func test_a_new_edit_discards_the_redo_trail() -> void:
	var history: EditorHistory = EditorHistory.new()
	history.begin(_level)
	_draw_box(Vector2(0, 0), Vector2(400, 200))
	history.record(_level, "draw")
	history.undo()
	is_true(history.can_redo(), "there is something to redo")
	_draw_box(Vector2(600, 0), Vector2(1000, 200))
	history.record(_level, "draw something else")
	is_false(history.can_redo(), "and now there is not")


# --- what you draw is what you play --------------------------------------------

func test_a_level_drawn_here_saves_loads_and_plays() -> void:
	_canvas.enemy_id = "enemy_scribble_grunt"
	_draw_box(Vector2(-400, 0), Vector2(1600, 400))
	_canvas.tool = EditorCanvas.Tool.ENEMY
	_canvas.primary_pressed(Vector2(600, -60))
	_canvas.tool = EditorCanvas.Tool.DOOR
	_canvas.primary_pressed(Vector2(1400, 0))

	_level.id = "test_drawn_level"
	_level.name = "Drawn"
	var path: String = "user://levels/test_drawn_level.json"
	is_true(_level.save(path).is_empty(), "it saved")

	var problems: PackedStringArray = PackedStringArray()
	var scene: DataLevel = DataLevel.create("test_drawn_level", problems)
	not_null(scene, "and built into a scene: %s" % [problems])
	if scene != null:
		tree.root.add_child(scene)
		await tree.process_frame
		await tree.physics_frame
		not_null(scene.player, "with a player in it")
		eq(scene.enemies().size(), 1, "and the enemy that was placed")
		scene.get_parent().remove_child(scene)
		scene.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- helpers -------------------------------------------------------------------

func _draw_box(top_left: Vector2, bottom_right: Vector2) -> void:
	var was: EditorCanvas.Tool = _canvas.tool
	if not EditorCanvas.TOOL_TERRAIN_KIND.has(was):
		_canvas.tool = EditorCanvas.Tool.TERRAIN_SOLID
	for point: Vector2 in [top_left, Vector2(bottom_right.x, top_left.y),
			bottom_right, Vector2(top_left.x, bottom_right.y)]:
		_canvas.primary_pressed(point)
	_canvas.close_draft()
	_canvas.tool = was


func _blank() -> LevelData:
	# Deliberately empty of terrain: every test here counts what *it* drew, and a
	# starting polygon would make each assertion an off-by-one puzzle.
	var level: LevelData = LevelData.new()
	level.id = "editor_probe"
	level.name = "Probe"
	level.spawn = Vector2(0.0, -120.0)
	return level
