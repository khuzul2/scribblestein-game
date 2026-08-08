class_name LevelGeometry
extends RefCounted

## Measures a level's shape, so a hand-drawn one can still be *proved* rather
## than played and hoped for.
##
## The slice's levels were built from rectangles written in GDScript, so their
## gaps were constants you could compare against `JumpMath` directly. An editor
## that draws free-form polygons has no such constants: the gap between two
## ledges is an emergent property of two outlines. This class recovers those
## numbers from the geometry itself — gaps, drops, head-room — so
## `LoadoutSpace`'s reach bounds still have something to be checked against and
## DESIGN §9's lock-and-key promise survives the move to a drawing tool.
##
## Everything here is pure geometry over `LevelData`. It never touches physics,
## so it runs headlessly and instantly.

## Surfaces flatter than this are walkable; anything steeper is a wall.
const MAX_WALKABLE_SLOPE: float = 0.7
## Edges shorter than this are corners and joins rather than places to stand.
const MIN_SURFACE_LENGTH: float = 24.0
## How far above a surface to look for a ceiling.
const HEADROOM_PROBE: float = 2000.0


## A stretch of ground a creature can stand on, as a left-to-right segment.
class Surface extends RefCounted:
	var left: Vector2 = Vector2.ZERO
	var right: Vector2 = Vector2.ZERO
	var kind: String = "solid"

	func length() -> float:
		return left.distance_to(right)

	func height_at(x: float) -> float:
		if is_equal_approx(right.x, left.x):
			return minf(left.y, right.y)
		var t: float = clampf((x - left.x) / (right.x - left.x), 0.0, 1.0)
		return lerpf(left.y, right.y, t)


## Somewhere the ground stops and starts again: how far across, and how far down.
class Gap extends RefCounted:
	var from: Vector2 = Vector2.ZERO
	var to: Vector2 = Vector2.ZERO

	func width() -> float:
		return to.x - from.x

	## Positive when the far side is *below* the near side, which is the sense
	## `JumpMath.horizontal_reach` takes its `drop` in.
	func drop() -> float:
		return to.y - from.y


# --- surfaces ------------------------------------------------------------------

## Every walkable top edge in the level, sorted left to right.
##
## A polygon edge is walkable when it is flat enough to stand on and nothing in
## the same polygon sits directly above it — the underside of a slab is an edge
## too, and standing on it is not a thing.
static func surfaces(level: LevelData) -> Array[Surface]:
	var found: Array[Surface] = []
	for piece: LevelData.Terrain in level.terrain:
		if piece.kind == "hazard" or piece.kind == "climbable":
			continue  # you do not stand on spikes, and a wall face is not a floor
		found.append_array(_walkable_edges(piece))
	found.sort_custom(func(a: Surface, b: Surface) -> bool: return a.left.x < b.left.x)
	return found


static func _walkable_edges(piece: LevelData.Terrain) -> Array[Surface]:
	var edges: Array[Surface] = []
	var count: int = piece.points.size()
	# Consistent winding first: with clockwise points in +Y-down space, a top
	# edge always runs left to right, which is what makes "is this a floor or a
	# ceiling?" answerable without a raycast.
	var points: PackedVector2Array = _clockwise(piece.points)

	for index: int in range(count):
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % count]
		if b.x <= a.x:
			continue  # right to left is the underside
		var run: float = b.x - a.x
		var rise: float = b.y - a.y
		if run <= 0.0 or absf(rise / run) > MAX_WALKABLE_SLOPE:
			continue
		if a.distance_to(b) < MIN_SURFACE_LENGTH:
			continue
		var surface: Surface = Surface.new()
		surface.left = a
		surface.right = b
		surface.kind = piece.kind
		edges.append(surface)
	return edges


## Points in clockwise order (in screen space, +Y down).
static func _clockwise(points: PackedVector2Array) -> PackedVector2Array:
	return points if _signed_area(points) < 0.0 else _reversed(points)


static func _signed_area(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for index: int in range(points.size()):
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % points.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


static func _reversed(points: PackedVector2Array) -> PackedVector2Array:
	var flipped: PackedVector2Array = PackedVector2Array()
	for index: int in range(points.size() - 1, -1, -1):
		flipped.append(points[index])
	return flipped


# --- gaps ----------------------------------------------------------------------

## Every place a creature walking right runs out of ground and has to leap.
##
## Only the *next* landing to the right is considered, because that is the jump
## a player actually attempts. Gaps narrower than `minimum_width` are steps
## rather than gates and are left out.
static func gaps(level: LevelData, minimum_width: float = 80.0) -> Array[Gap]:
	var found: Array[Gap] = []
	var walkable: Array[Surface] = surfaces(level)
	for edge: Surface in walkable:
		var landing: Surface = _next_surface(walkable, edge)
		if landing == null:
			continue
		var gap: Gap = Gap.new()
		gap.from = edge.right
		gap.to = _landing_point(landing, edge)
		if gap.width() >= minimum_width:
			found.append(gap)
	return found


## The widest gap a player must cross to get through the level, and how far it
## drops — the pair a gate is designed around.
static func widest_gap(level: LevelData) -> Gap:
	var widest: Gap = Gap.new()
	for gap: Gap in gaps(level):
		if gap.width() > widest.width():
			widest = gap
	return widest


## The nearest place to the right of `edge` where there is ground again.
##
## A surface counts if any part of it lies to the right, not only if it *starts*
## there — a wide chasm floor that begins behind you and runs on past the drop is
## still what you land on. Getting that wrong makes the analyser skip the real
## landing and report the gap to whatever comes after it, which turns a walk-off
## ledge into a phantom 1,590 px leap.
static func _next_surface(walkable: Array[Surface], edge: Surface) -> Surface:
	var best: Surface = null
	var best_point: Vector2 = Vector2.INF
	for other: Surface in walkable:
		if other == edge or other.right.x <= edge.right.x:
			continue
		var landing: Vector2 = _landing_point(other, edge)
		# Only ground at or below the lip: a shelf overhead is not a landing.
		if landing.y < edge.right.y - 1.0:
			continue
		if best == null or landing.x < best_point.x:
			best = other
			best_point = landing
	return best


## Where walking right off `edge` first meets `landing`.
static func _landing_point(landing: Surface, edge: Surface) -> Vector2:
	var x: float = maxf(landing.left.x, edge.right.x)
	return Vector2(x, landing.height_at(x))


# --- head-room -----------------------------------------------------------------

## The smallest head-room anywhere along the walkable ground: the tightest
## squeeze in the level, which is what a crawl tunnel is.
##
## Returns `INF` when nothing overhangs anything, which is the normal case for
## an open level.
static func tightest_headroom(level: LevelData) -> float:
	var tightest: float = INF
	for edge: LevelGeometry.Surface in surfaces(level):
		var samples: int = maxi(2, int(edge.length() / 40.0))
		for step: int in range(samples + 1):
			var x: float = lerpf(edge.left.x, edge.right.x, float(step) / float(samples))
			var ceiling: float = _ceiling_above(level, Vector2(x, edge.height_at(x) - 4.0))
			if ceiling < INF:
				tightest = minf(tightest, edge.height_at(x) - ceiling)
	return tightest


## The lowest solid underside above `from`, or `INF` for open sky.
static func _ceiling_above(level: LevelData, from: Vector2) -> float:
	var lowest: float = -INF
	for piece: LevelData.Terrain in level.terrain:
		if piece.kind == "hazard" or piece.kind == "climbable" or piece.kind == "oneway":
			continue  # you pass up through a one-way, so it is not a ceiling
		var box: Rect2 = piece.bounds()
		if from.x < box.position.x or from.x > box.end.x:
			continue
		if box.end.y > from.y or box.end.y < from.y - HEADROOM_PROBE:
			continue
		lowest = maxf(lowest, _underside_at(piece, from.x))
	return INF if lowest == -INF else lowest


## Where a polygon's lowest downward-facing edge sits at `x`.
static func _underside_at(piece: LevelData.Terrain, x: float) -> float:
	var points: PackedVector2Array = _clockwise(piece.points)
	var lowest: float = -INF
	for index: int in range(points.size()):
		var a: Vector2 = points[index]
		var b: Vector2 = points[(index + 1) % points.size()]
		if b.x >= a.x:
			continue  # left-to-right is a top edge
		if x > a.x or x < b.x:
			continue
		var t: float = 0.0 if is_equal_approx(a.x, b.x) else (x - a.x) / (b.x - a.x)
		lowest = maxf(lowest, lerpf(a.y, b.y, t))
	return lowest


# --- reachability --------------------------------------------------------------

## Whether a build with `stats` could walk and jump from the spawn to the exit.
##
## A forward sweep over the walkable surfaces: stand on one, and cross to the
## next if the gap is inside this build's reach. Deliberately conservative — it
## never assumes a wall-jump, a climb or a glide chain — so a level it passes is
## genuinely completable, while one it fails may still be, by a route this does
## not model. It answers "is this definitely fine?", never "is this impossible?".
static func walkable_to_exit(level: LevelData, stats: CreatureStats,
		blueprint_id: String = "biped") -> bool:
	if level.doors.is_empty():
		return false
	var exit_x: float = level.doors[0].at.x
	var walkable: Array[Surface] = surfaces(level)
	if walkable.is_empty():
		return false

	var standing: Surface = _surface_under(walkable, level.spawn)
	if standing == null:
		return false

	var guard: int = walkable.size() + 2
	while guard > 0:
		guard -= 1
		if standing.left.x <= exit_x and exit_x <= standing.right.x:
			return true
		var next: Surface = _next_surface(walkable, standing)
		if next == null:
			return false
		var landing: Vector2 = _landing_point(next, standing)
		var drop: float = landing.y - standing.right.y
		var reach: float = JumpMath.horizontal_reach(stats, maxf(drop, 0.0), blueprint_id)
		if landing.x - standing.right.x > reach:
			return false
		standing = next
	return false


static func _surface_under(walkable: Array[Surface], point: Vector2) -> Surface:
	var best: Surface = null
	for edge: Surface in walkable:
		if point.x < edge.left.x or point.x > edge.right.x:
			continue
		if edge.height_at(point.x) < point.y:
			continue  # above the point, so not what it is standing on
		if best == null or edge.height_at(point.x) < best.height_at(point.x):
			best = edge
	return best


# --- bounds --------------------------------------------------------------------

## Everything the level occupies, for framing the editor's view and for placing
## the fall-catch line below the lowest ground.
static func bounds(level: LevelData) -> Rect2:
	var box: Rect2 = Rect2(level.spawn, Vector2.ZERO)
	for piece: LevelData.Terrain in level.terrain:
		box = box.merge(piece.bounds()) if piece.points.size() > 0 else box
	for door: LevelData.Door in level.doors:
		box = box.expand(door.at)
	for spawn_point: LevelData.EnemySpawn in level.enemies:
		box = box.expand(spawn_point.at)
	return box
