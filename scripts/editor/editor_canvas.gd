class_name EditorCanvas
extends Control

## The drawing surface of the level editor: it renders the level being edited and
## turns mouse input into edits.
##
## It draws the level rather than instantiating it. A live `DataLevel` would drag
## physics, enemy AI and audio into an editing session, and would make it
## impossible to show the things an editor must show and a player must not — the
## spawn point, a polygon mid-draw, the vertex you are about to grab. So this is
## a plain `_draw()` in world space, and Playtest is what builds the real thing.
##
## It is a `Control` that applies its own pan/zoom transform, rather than a
## `Node2D` under a camera in a `SubViewport`. A SubViewport composites through a
## texture, and when its size lands on a fractional control rect that composite
## is filtered — which puts greys on every line in the editor. There is no grey
## in this palette (Mandate A1), so the indirection had to go.

signal level_edited(label: String)
signal selection_changed
signal status(message: String)

enum Tool {
	SELECT, TERRAIN_SOLID, TERRAIN_ONEWAY, TERRAIN_CLIMBABLE, TERRAIN_CRACKED,
	TERRAIN_HAZARD, ROPE, ENEMY, INK, SKETCH, FLUID, DOOR, SIGN, SPAWN,
}

const TOOL_TERRAIN_KIND: Dictionary = {
	Tool.TERRAIN_SOLID: "solid", Tool.TERRAIN_ONEWAY: "oneway",
	Tool.TERRAIN_CLIMBABLE: "climbable", Tool.TERRAIN_CRACKED: "cracked",
	Tool.TERRAIN_HAZARD: "hazard",
}
const TOOL_PICKUP_KIND: Dictionary = {
	Tool.INK: "ink", Tool.SKETCH: "sketch", Tool.FLUID: "fluid",
}

## Snapping is optional and off by default — the terrain is free-form by design
## (a drawn game should be drawn) — but a grid is what makes two ledges line up.
const GRID_STEP: float = 40.0
## How close the cursor must be to grab an existing vertex or marker.
const GRAB_RADIUS: float = 22.0
## A polygon closes when you click back within this of its first point.
const CLOSE_RADIUS: float = 28.0
## Zoom limits, so the view can never be lost.
const ZOOM_MIN: float = 0.08
const ZOOM_MAX: float = 3.0

var level: LevelData = LevelData.new()
var tool: Tool = Tool.SELECT
var snap_to_grid: bool = false
var show_grid: bool = true
## What a newly placed enemy or sketch will be. Set by the editor's side panel.
var enemy_id: String = ""
var sketch_part_id: String = ""
var ink_amount: int = 12
var sign_text: String = "look out"

## The polygon being drawn, empty when not drawing.
var _draft: PackedVector2Array = PackedVector2Array()
## What the SELECT tool is holding: a kind ("terrain"/"enemy"/…), an index, and
## for terrain the vertex being dragged (-1 for the whole shape).
var _selected_kind: String = ""
var _selected_index: int = -1
var _selected_vertex: int = -1
var _dragging: bool = false
var _drag_from: Vector2 = Vector2.ZERO

var _cursor: Vector2 = Vector2.ZERO
## Pan and zoom, applied to everything drawn. The editor owns the values; this
## owns the drawing.
var view: Transform2D = Transform2D.IDENTITY


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the editor routes input here


## Screen (control-local) point to world point.
func to_world(local_point: Vector2) -> Vector2:
	return view.affine_inverse() * local_point


## Look at `centre` at `zoom`. World point p is drawn at `p * zoom + origin`,
## with the origin chosen so `centre` lands in the middle of the control.
func set_view(centre: Vector2, zoom: float) -> void:
	view = Transform2D(0.0, Vector2.ONE * zoom, 0.0, size * 0.5 - centre * zoom)
	queue_redraw()


func set_level(new_level: LevelData) -> void:
	level = new_level
	_draft.clear()
	clear_selection()
	queue_redraw()


func clear_selection() -> void:
	_selected_kind = ""
	_selected_index = -1
	_selected_vertex = -1
	selection_changed.emit()
	queue_redraw()


func selected_kind() -> String:
	return _selected_kind


func selected_index() -> int:
	return _selected_index


## Abandon a half-drawn polygon. Bound to Escape.
func cancel_draft() -> void:
	if _draft.is_empty():
		return
	_draft.clear()
	status.emit("polygon abandoned")
	queue_redraw()


# --- input ---------------------------------------------------------------------

## Called by the editor with the cursor already converted to world space, because
## the canvas does not own the camera.
func cursor_moved(world_position: Vector2) -> void:
	_cursor = _snapped(world_position)
	if _dragging:
		_drag_to(_cursor)
	queue_redraw()


func primary_pressed(world_position: Vector2) -> void:
	var at: Vector2 = _snapped(world_position)
	if tool == Tool.SELECT:
		_begin_select(at)
		return
	if TOOL_TERRAIN_KIND.has(tool):
		_add_draft_point(at)
		return
	_place(at)


func primary_released() -> void:
	if _dragging:
		_dragging = false
		level_edited.emit("move %s" % _selected_kind)


## Right click removes whatever is under the cursor, or the last drafted point.
func secondary_pressed(world_position: Vector2) -> void:
	if not _draft.is_empty():
		_draft.remove_at(_draft.size() - 1)
		queue_redraw()
		return
	var at: Vector2 = _snapped(world_position)
	if _pick(at) and _delete_selected():
		level_edited.emit("delete")


## Close the polygon being drawn. Also bound to Enter, because clicking exactly
## back on the first point is a precision task and closing a shape is not.
func close_draft() -> void:
	if _draft.size() < 3:
		status.emit("a polygon needs at least three points")
		return
	var piece: LevelData.Terrain = LevelData.Terrain.new()
	piece.kind = str(TOOL_TERRAIN_KIND.get(tool, "solid"))
	piece.points = _draft.duplicate()
	level.terrain.append(piece)
	_draft.clear()
	level_edited.emit("draw %s" % piece.kind)
	queue_redraw()


func delete_selected() -> void:
	if _delete_selected():
		level_edited.emit("delete")


# --- placing -------------------------------------------------------------------

func _place(at: Vector2) -> void:
	match tool:
		Tool.SPAWN:
			level.spawn = at
			level_edited.emit("move spawn")
		Tool.DOOR:
			# One way out per level: placing another moves the existing one,
			# which is what someone clicking a second time means.
			var door: LevelData.Door = level.doors[0] if not level.doors.is_empty() \
				else LevelData.Door.new()
			door.at = at
			if level.doors.is_empty():
				level.doors.append(door)
			level_edited.emit("place exit")
		Tool.ROPE:
			var rope: LevelData.Rope = LevelData.Rope.new()
			rope.at = at
			rope.length = 400.0
			level.ropes.append(rope)
			level_edited.emit("hang rope")
		Tool.ENEMY:
			if enemy_id == "":
				status.emit("pick an enemy in the panel first")
				return
			var spawn_record: LevelData.EnemySpawn = LevelData.EnemySpawn.new()
			spawn_record.id = enemy_id
			spawn_record.at = at
			level.enemies.append(spawn_record)
			level_edited.emit("place %s" % enemy_id)
		Tool.SIGN:
			var scrawl: LevelData.Sign = LevelData.Sign.new()
			scrawl.at = at
			scrawl.text = sign_text
			level.signs.append(scrawl)
			level_edited.emit("scrawl a sign")
		_:
			_place_pickup(at)
	queue_redraw()


func _place_pickup(at: Vector2) -> void:
	if not TOOL_PICKUP_KIND.has(tool):
		return
	var pickup: LevelData.PickupSpawn = LevelData.PickupSpawn.new()
	pickup.kind = str(TOOL_PICKUP_KIND[tool])
	pickup.at = at
	pickup.amount = ink_amount
	pickup.part = sketch_part_id
	if pickup.kind == "sketch" and sketch_part_id == "":
		status.emit("pick a part for the sketch in the panel first")
		return
	level.pickups.append(pickup)
	level_edited.emit("place %s" % pickup.kind)


func _add_draft_point(at: Vector2) -> void:
	if _draft.size() >= 3 and at.distance_to(_draft[0]) <= CLOSE_RADIUS:
		close_draft()
		return
	_draft.append(at)
	queue_redraw()


# --- selecting and dragging ----------------------------------------------------

func _begin_select(at: Vector2) -> void:
	if not _pick(at):
		clear_selection()
		return
	_dragging = true
	_drag_from = at
	selection_changed.emit()
	queue_redraw()


## Find whatever is under `at`, nearest first, and select it. Vertices win over
## whole shapes so a polygon can be reshaped without moving it.
func _pick(at: Vector2) -> bool:
	for index: int in range(level.terrain.size()):
		var piece: LevelData.Terrain = level.terrain[index]
		for vertex: int in range(piece.points.size()):
			if piece.points[vertex].distance_to(at) <= GRAB_RADIUS:
				_selected_kind = "terrain"
				_selected_index = index
				_selected_vertex = vertex
				return true

	for index: int in range(level.enemies.size()):
		if level.enemies[index].at.distance_to(at) <= GRAB_RADIUS * 2.0:
			return _select("enemy", index)
	for index: int in range(level.pickups.size()):
		if level.pickups[index].at.distance_to(at) <= GRAB_RADIUS:
			return _select("pickup", index)
	for index: int in range(level.ropes.size()):
		if level.ropes[index].at.distance_to(at) <= GRAB_RADIUS:
			return _select("rope", index)
	for index: int in range(level.doors.size()):
		if level.doors[index].at.distance_to(at) <= GRAB_RADIUS * 2.0:
			return _select("door", index)
	for index: int in range(level.signs.size()):
		if level.signs[index].at.distance_to(at) <= GRAB_RADIUS * 2.0:
			return _select("sign", index)
	if level.spawn.distance_to(at) <= GRAB_RADIUS * 2.0:
		return _select("spawn", 0)

	for index: int in range(level.terrain.size()):
		if Geometry2D.is_point_in_polygon(at, level.terrain[index].points):
			_selected_kind = "terrain"
			_selected_index = index
			_selected_vertex = -1
			return true
	return false


func _select(kind: String, index: int) -> bool:
	_selected_kind = kind
	_selected_index = index
	_selected_vertex = -1
	return true


func _drag_to(at: Vector2) -> void:
	var delta: Vector2 = at - _drag_from
	_drag_from = at
	match _selected_kind:
		"terrain":
			var piece: LevelData.Terrain = level.terrain[_selected_index]
			if _selected_vertex >= 0:
				piece.points[_selected_vertex] = at
			else:
				for vertex: int in range(piece.points.size()):
					piece.points[vertex] += delta
		"enemy":
			level.enemies[_selected_index].at += delta
		"pickup":
			level.pickups[_selected_index].at += delta
		"rope":
			level.ropes[_selected_index].at += delta
		"door":
			level.doors[_selected_index].at += delta
		"sign":
			level.signs[_selected_index].at += delta
		"spawn":
			level.spawn += delta


func _delete_selected() -> bool:
	if _selected_index < 0:
		return false
	match _selected_kind:
		"terrain":
			var piece: LevelData.Terrain = level.terrain[_selected_index]
			# Deleting a vertex from a triangle would leave a line, so past three
			# points the whole shape goes.
			if _selected_vertex >= 0 and piece.points.size() > 3:
				piece.points.remove_at(_selected_vertex)
			else:
				level.terrain.remove_at(_selected_index)
		"enemy":
			level.enemies.remove_at(_selected_index)
		"pickup":
			level.pickups.remove_at(_selected_index)
		"rope":
			level.ropes.remove_at(_selected_index)
		"door":
			level.doors.remove_at(_selected_index)
		"sign":
			level.signs.remove_at(_selected_index)
		"spawn":
			status.emit("a level needs somewhere to start; move it instead")
			return false
	clear_selection()
	queue_redraw()
	return true


func _snapped(world_position: Vector2) -> Vector2:
	if not snap_to_grid:
		return world_position
	return (world_position / GRID_STEP).round() * GRID_STEP


# --- drawing -------------------------------------------------------------------

func _draw() -> void:
	draw_set_transform_matrix(view)
	if show_grid:
		_draw_grid()
	for index: int in range(level.terrain.size()):
		_draw_terrain(level.terrain[index], index)
	for rope: LevelData.Rope in level.ropes:
		draw_line(rope.at, rope.at + Vector2(0.0, rope.length), Paper.INK, 4.0)
		draw_circle(rope.at, 8.0, Paper.INK)
	for index: int in range(level.enemies.size()):
		_draw_marker(level.enemies[index].at, "enemy", index,
			level.enemies[index].id.replace("enemy_", ""))
		_draw_patrol(level.enemies[index])
	for index: int in range(level.pickups.size()):
		_draw_marker(level.pickups[index].at, "pickup", index, level.pickups[index].kind)
	for index: int in range(level.doors.size()):
		_draw_marker(level.doors[index].at, "door", index, "OUT")
	for index: int in range(level.signs.size()):
		_draw_marker(level.signs[index].at, "sign", index, level.signs[index].text)
	_draw_marker(level.spawn, "spawn", 0, "START")
	_draw_draft()


## Crosses at the grid intersections rather than full rules. A grid of solid
## black lines would drown the level it is meant to help you place; a scattering
## of ticks reads as graph paper, which is what it is.
func _draw_grid() -> void:
	var step: float = GRID_STEP * 4.0
	var scale: float = maxf(view.get_scale().x, 0.001)
	if scale < 0.25:
		return  # zoomed out far enough that the ticks would merge into a smear
	var origin: Vector2 = (to_world(Vector2.ZERO) / step).floor() * step
	var span: Vector2 = size / scale
	var tick: float = 4.0
	for column: int in range(int(span.x / step) + 2):
		for row: int in range(int(span.y / step) + 2):
			var at: Vector2 = origin + Vector2(float(column), float(row)) * step
			draw_line(at - Vector2(tick, 0.0), at + Vector2(tick, 0.0), Paper.INK, 1.0)
			draw_line(at - Vector2(0.0, tick), at + Vector2(0.0, tick), Paper.INK, 1.0)


## Terrain kinds are told apart by *hatching*, not by tint. There is no grey in
## this game (Mandate A1), and an alpha-blended fill is grey — so each kind gets
## a hatch pattern the way a drawn map would, dense for the dangerous ones.
const HATCH_SPACING: Dictionary = {
	"solid": 34.0, "oneway": 60.0, "climbable": 26.0, "cracked": 30.0,
	"hazard": 16.0,
}


func _draw_terrain(piece: LevelData.Terrain, index: int) -> void:
	var selected: bool = _selected_kind == "terrain" and _selected_index == index
	# Paper first, so a shape drawn on top of another reads as being on top.
	draw_colored_polygon(piece.points, Paper.PAPER)
	_draw_hatching(piece)
	draw_polyline(_closed(piece.points), Paper.INK, 5.0 if selected else 2.0)

	for vertex: int in range(piece.points.size()):
		var grabbed: bool = selected and vertex == _selected_vertex
		draw_circle(piece.points[vertex], 9.0 if grabbed else 5.0, Paper.INK)

	if not piece.points.is_empty():
		_draw_label(piece.bounds().get_center(), piece.kind)


## Diagonal hatching clipped to the polygon, so a shape's fill stops at its own
## edge instead of at its bounding box.
func _draw_hatching(piece: LevelData.Terrain) -> void:
	var box: Rect2 = piece.bounds()
	var step: float = float(HATCH_SPACING.get(piece.kind, 34.0))
	var reach: float = box.size.x + box.size.y
	var lines: int = int(reach / step) + 1
	for index: int in range(lines):
		var offset: float = float(index) * step
		var from: Vector2 = Vector2(box.position.x + offset, box.position.y)
		var to: Vector2 = Vector2(box.position.x + offset - box.size.y, box.end.y)
		for segment: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(
				PackedVector2Array([from, to]), piece.points):
			if segment.size() >= 2:
				draw_polyline(segment, Paper.INK, 1.5)


func _draw_patrol(spawn_record: LevelData.EnemySpawn) -> void:
	if spawn_record.patrol <= 0.0:
		return
	var faint: Color = Paper.INK
	var left: Vector2 = spawn_record.at - Vector2(spawn_record.patrol, 0.0)
	var right: Vector2 = spawn_record.at + Vector2(spawn_record.patrol, 0.0)
	draw_line(left, right, faint, 2.0)
	draw_line(left + Vector2(0.0, -14.0), left + Vector2(0.0, 14.0), faint, 2.0)
	draw_line(right + Vector2(0.0, -14.0), right + Vector2(0.0, 14.0), faint, 2.0)


func _draw_marker(at: Vector2, kind: String, index: int, label: String) -> void:
	var selected: bool = _selected_kind == kind and _selected_index == index
	draw_circle(at, 14.0, Paper.PAPER)
	draw_arc(at, 14.0, 0.0, TAU, 20, Paper.INK, 4.0 if selected else 2.0)
	draw_line(at + Vector2(-20.0, 0.0), at + Vector2(20.0, 0.0), Paper.INK, 1.5)
	draw_line(at + Vector2(0.0, -20.0), at + Vector2(0.0, 20.0), Paper.INK, 1.5)
	_draw_label(at + Vector2(0.0, -34.0), label)


func _draw_label(at: Vector2, text: String) -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, at + Vector2(-40.0, 0.0), text, HORIZONTAL_ALIGNMENT_CENTER,
		80.0, 16, Paper.INK)


func _draw_draft() -> void:
	if _draft.is_empty():
		return
	var live: PackedVector2Array = _draft.duplicate()
	live.append(_cursor)
	draw_polyline(live, Paper.INK, 2.0)
	for point: Vector2 in _draft:
		draw_circle(point, 5.0, Paper.INK)
	# Show where it would close, so "click near the start" is visible advice.
	if _draft.size() >= 3:
		draw_arc(_draft[0], CLOSE_RADIUS, 0.0, TAU, 24, Paper.INK, 2.0)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var loop: PackedVector2Array = points.duplicate()
	if not loop.is_empty():
		loop.append(loop[0])
	return loop
