extends SceneTree

## Generates every placeholder texture the project needs, straight to PNG.
##
##     godot --headless -s tools/generate_placeholders.gd
##
## Placeholders obey the palette from day one (ASSET_SPEC §4): pure black ink on
## full transparency, jagged and asymmetric (Mandate A2), never a coloured dev
## texture. Output is deterministic — the RNG is seeded from the file name — so
## regenerating never produces a spurious diff.
##
## Add `--check` to fail instead of writing when a file would change.

const ASSET_SPEC_PATH: String = "res://data/asset_spec.json"
const PARTS_DB_PATH: String = "res://data/parts_db.json"

const INK: Color = Color(0, 0, 0, 1)
const CLEAR: Color = Color(0, 0, 0, 0)
const PAPER: Color = Color("#f4f0e6")

var _spec: Dictionary = {}
var _written: int = 0
var _skipped: int = 0


func _initialize() -> void:
	var spec_result: JsonLoader.Result = JsonLoader.load_object(ASSET_SPEC_PATH)
	var parts_result: JsonLoader.Result = JsonLoader.load_object(PARTS_DB_PATH)
	if not spec_result.ok or not parts_result.ok:
		printerr(spec_result.error if not spec_result.ok else parts_result.error)
		quit(1)
		return
	_spec = spec_result.value as Dictionary

	var parts: Dictionary = (parts_result.value as Dictionary)["parts"] as Dictionary
	for part_id: Variant in parts:
		_generate_part(str(part_id), parts[part_id] as Dictionary)

	_generate_paper_background()
	_generate_tiles()
	_generate_fx()

	print("Placeholders: %d written, %d already up to date." % [_written, _skipped])
	quit(0)


# --- creature parts ------------------------------------------------------------

func _generate_part(part_id: String, part: Dictionary) -> void:
	var slot: String = str(part["slot"])
	var canvas_sizes: Dictionary = _spec["canvas_sizes"] as Dictionary
	if not canvas_sizes.has(slot):
		printerr("No canvas size for slot '%s' (part %s)" % [slot, part_id])
		return

	var size: Array = canvas_sizes[slot] as Array
	var width: int = int(size[0])
	var height: int = int(size[1])
	var pivot: Vector2 = Vector2(
		float((part["pivot"] as Dictionary)["x"]),
		float((part["pivot"] as Dictionary)["y"]))

	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(part_id)

	var shapes: Array[PackedVector2Array] = _silhouette(part, slot, Vector2(width, height), pivot, rng)
	var ink: Rect2 = Rect2()
	for polygon: PackedVector2Array in shapes:
		_stroke_closed(image, polygon, rng.randi_range(4, 6), rng)
		_hatch(image, polygon, rng)
		ink = _bounds(polygon) if ink.size == Vector2.ZERO else ink.merge(_bounds(polygon))

	_draw_pivot_tick(image, pivot)
	# Inside the silhouette, never below it: a label floating in the canvas
	# margin would inflate the ink bounds the camera measures.
	_label(image, part_id, ink, rng)

	_save(image, str(part["texture_path"]))


## Rough, deliberately wrong silhouettes, anchored on the part's pivot and sized
## from the part's own hurtbox so the placeholder is *truthful*: what you see is
## the volume that can be hit. Parts with no hurtbox fall back to canvas fractions.
func _silhouette(part: Dictionary, slot: String, canvas: Vector2, pivot: Vector2,
		rng: RandomNumberGenerator) -> Array[PackedVector2Array]:
	var shapes: Array[PackedVector2Array] = []
	var hurt: Dictionary = _hurtbox(part)
	var centre: Vector2 = pivot + _offset_of(hurt)
	var extents: Vector2 = _extents_of(hurt)

	match slot:
		"torso":
			shapes.append(_blob(centre, extents, 13, rng))
		"head":
			# The canvas puts the neck joint at bottom-centre, so the skull is
			# drawn above the pivot even though its hurtbox straddles the joint.
			shapes.append(_blob(pivot + Vector2(0, -extents.y * 1.05), extents * 1.15, 11, rng))
		"legs", "legs_front", "legs_rear", "arms":
			var reach: float = _offset_of(hurt).y + extents.y
			var half_width: float = extents.x * (0.42 if slot == "arms" else 0.46)
			var spread: float = extents.x * (0.0 if slot == "arms" else 0.5)
			shapes.append(_limb(pivot + Vector2(-spread, 0), reach, half_width, rng))
			if slot != "arms":
				shapes.append(_limb(pivot + Vector2(spread, 0), reach, half_width * 0.92, rng))
		"tail":
			# Reach to the far edge of the sting, so the drawing ends where the
			# damage box does. Authored root-at-left facing right (ASSET_SPEC §1).
			var damage: Dictionary = _damage_box(part)
			var span: float = absf(_offset_of(damage).x) + _extents_of(damage).x
			shapes.append(_taper(pivot, Vector2(maxf(span, canvas.x * 0.4), -extents.y * 1.2),
				extents.y * 2.0, rng))
		"back":
			# No hurtbox on the back parts; sized to read as wings behind a torso.
			var wing: Vector2 = Vector2(canvas.x * 0.13, canvas.y * 0.17)
			shapes.append(_blob(pivot + Vector2(-wing.x * 1.15, -wing.y * 0.15), wing, 9, rng))
			shapes.append(_blob(pivot + Vector2(wing.x * 1.15, -wing.y * 0.15), wing, 9, rng))
		_:
			shapes.append(_blob(centre, extents, 10, rng))
	return shapes


func _hurtbox(part: Dictionary) -> Dictionary:
	return _first_box(part, "hurtbox")


func _damage_box(part: Dictionary) -> Dictionary:
	return _first_box(part, "damage")


func _first_box(part: Dictionary, wanted: String) -> Dictionary:
	for entry: Variant in part.get("hitboxes", []) as Array:
		if str((entry as Dictionary).get("type", "")) == wanted:
			return entry as Dictionary
	return {}


func _offset_of(box: Dictionary) -> Vector2:
	var offset: Array = box.get("offset", [0, 0]) as Array
	return Vector2(float(offset[0]), float(offset[1]))


func _extents_of(box: Dictionary) -> Vector2:
	if box.is_empty():
		return Vector2(60.0, 60.0)
	if str(box.get("shape", "")) == "circle":
		var radius: float = float(box["radius"])
		return Vector2(radius, radius)
	var extents: Array = box["extents"] as Array
	return Vector2(float(extents[0]), float(extents[1]))


func _blob(centre: Vector2, radii: Vector2, points: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var polygon: PackedVector2Array = PackedVector2Array()
	for i: int in range(points):
		var angle: float = TAU * float(i) / float(points) + rng.randf_range(-0.12, 0.12)
		var wobble: float = rng.randf_range(0.72, 1.18)
		polygon.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * wobble)
	return polygon


## A crooked vertical limb hanging from `top`.
func _limb(top: Vector2, length: float, half_width: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var polygon: PackedVector2Array = PackedVector2Array()
	var segments: int = 5
	for i: int in range(segments + 1):
		var t: float = float(i) / float(segments)
		polygon.append(Vector2(
			top.x - half_width * rng.randf_range(0.6, 1.25) + rng.randf_range(-8.0, 8.0),
			top.y + length * t))
	for i: int in range(segments, -1, -1):
		var t: float = float(i) / float(segments)
		polygon.append(Vector2(
			top.x + half_width * rng.randf_range(0.6, 1.25) + rng.randf_range(-8.0, 8.0),
			top.y + length * t))
	return polygon


## A tapering appendage from `root` towards `root + reach`.
func _taper(root: Vector2, reach: Vector2, base_width: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var polygon: PackedVector2Array = PackedVector2Array()
	var segments: int = 7
	var normal: Vector2 = reach.orthogonal().normalized()
	var upper: PackedVector2Array = PackedVector2Array()
	var lower: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments + 1):
		var t: float = float(i) / float(segments)
		var spine: Vector2 = root + reach * t + Vector2(0, sin(t * 4.0) * base_width * 0.35)
		var half: float = base_width * 0.5 * (1.0 - t * 0.82) * rng.randf_range(0.8, 1.2)
		upper.append(spine + normal * half)
		lower.append(spine - normal * half)
	polygon.append_array(upper)
	for i: int in range(lower.size() - 1, -1, -1):
		polygon.append(lower[i])
	return polygon


# --- environment & fx ----------------------------------------------------------

func _generate_paper_background() -> void:
	var image: Image = Image.create(512, 512, false, Image.FORMAT_RGBA8)
	image.fill(PAPER)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("paper_bg")
	for _i: int in range(900):
		image.set_pixel(rng.randi_range(0, 511), rng.randi_range(0, 511), INK)
	_save(image, "res://assets/tiles/paper_bg.png")


func _generate_tiles() -> void:
	for tile_name: String in ["tile_ground", "tile_cracked", "tile_climbable", "tile_oneway", "tile_hazard"]:
		var image: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		image.fill(CLEAR)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash(tile_name)
		var border: PackedVector2Array = PackedVector2Array([
			Vector2(2, 2), Vector2(126, 2), Vector2(126, 126), Vector2(2, 126)])
		_stroke_closed(image, border, 4, rng)
		match tile_name:
			"tile_ground":
				for i: int in range(6):
					_stroke_open(image, PackedVector2Array([
						Vector2(8, 20 + i * 18), Vector2(120, 24 + i * 18)]), 3, rng)
			"tile_cracked":
				_stroke_open(image, PackedVector2Array([
					Vector2(10, 110), Vector2(48, 60), Vector2(38, 42), Vector2(84, 14)]), 5, rng)
				_stroke_open(image, PackedVector2Array([
					Vector2(48, 60), Vector2(100, 78), Vector2(118, 40)]), 5, rng)
			"tile_climbable":
				for i: int in range(7):
					_stroke_open(image, PackedVector2Array([
						Vector2(16 + i * 16, 8), Vector2(24 + i * 16, 120)]), 3, rng)
			"tile_oneway":
				_stroke_open(image, PackedVector2Array([
					Vector2(8, 40), Vector2(120, 44)]), 6, rng)
			"tile_hazard":
				for i: int in range(5):
					_stroke_open(image, PackedVector2Array([
						Vector2(8 + i * 28, 120), Vector2(22 + i * 28, 20), Vector2(36 + i * 28, 120)]), 4, rng)
		_save(image, "res://assets/tiles/%s.png" % tile_name)


func _generate_fx() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	rng.seed = hash("fx_ink_blob")
	var blob: Image = Image.create(96, 96, false, Image.FORMAT_RGBA8)
	blob.fill(CLEAR)
	var blob_shape: PackedVector2Array = _blob(Vector2(48, 52), Vector2(34, 26), 12, rng)
	_stroke_closed(blob, blob_shape, 5, rng)
	_hatch(blob, blob_shape, rng)
	_hatch(blob, blob_shape, rng)
	_save(blob, "res://assets/fx/fx_ink_blob.png")

	rng.seed = hash("fx_ink_drop")
	var drop: Image = Image.create(48, 48, false, Image.FORMAT_RGBA8)
	drop.fill(CLEAR)
	_stroke_closed(drop, _blob(Vector2(24, 26), Vector2(14, 12), 9, rng), 4, rng)
	_save(drop, "res://assets/fx/fx_ink_drop.png")

	# The one gameplay sprite allowed paper white — it is literally white-out.
	rng.seed = hash("fx_correction_fluid")
	var fluid: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	fluid.fill(CLEAR)
	var fluid_shape: PackedVector2Array = _blob(Vector2(32, 34), Vector2(22, 18), 11, rng)
	_fill_polygon(fluid, fluid_shape, PAPER)
	_stroke_closed(fluid, fluid_shape, 4, rng)
	_save(fluid, "res://assets/fx/fx_correction_fluid.png")

	rng.seed = hash("fx_blueprint_sketch")
	var sketch: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	sketch.fill(CLEAR)
	_stroke_closed(sketch, PackedVector2Array([
		Vector2(8, 6), Vector2(56, 10), Vector2(52, 58), Vector2(6, 54)]), 4, rng)
	_stroke_open(sketch, PackedVector2Array([
		Vector2(18, 22), Vector2(30, 40), Vector2(42, 18)]), 4, rng)
	_save(sketch, "res://assets/fx/fx_blueprint_sketch.png")


# --- drawing primitives --------------------------------------------------------

func _stroke_closed(image: Image, polygon: PackedVector2Array, thickness: int,
		rng: RandomNumberGenerator) -> void:
	for i: int in range(polygon.size()):
		_wobbly_line(image, polygon[i], polygon[(i + 1) % polygon.size()], thickness, rng)


func _stroke_open(image: Image, points: PackedVector2Array, thickness: int,
		rng: RandomNumberGenerator) -> void:
	for i: int in range(points.size() - 1):
		_wobbly_line(image, points[i], points[i + 1], thickness, rng)


## A line whose thickness and path drift as it goes — inconsistent stroke weight
## is a feature, not a defect (Mandate A2).
func _wobbly_line(image: Image, from: Vector2, to: Vector2, thickness: int,
		rng: RandomNumberGenerator) -> void:
	var length: float = maxf(from.distance_to(to), 1.0)
	var steps: int = int(length * 2.0)
	var drift: Vector2 = Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
	for step: int in range(steps + 1):
		var t: float = float(step) / float(steps)
		var point: Vector2 = from.lerp(to, t) + drift * sin(t * PI)
		var radius: int = maxi(1, int(round(float(thickness) * 0.5 * rng.randf_range(0.65, 1.25))))
		_dot(image, point, radius)


func _dot(image: Image, centre: Vector2, radius: int) -> void:
	var cx: int = int(round(centre.x))
	var cy: int = int(round(centre.y))
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x: int = cx + dx
			var y: int = cy + dy
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, INK)


## Sparse construction hatching inside a shape, so placeholders read as sketches
## rather than as empty outlines.
func _hatch(image: Image, polygon: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var bounds: Rect2 = _bounds(polygon)
	var lines: int = rng.randi_range(2, 5)
	for _i: int in range(lines):
		var y: float = rng.randf_range(bounds.position.y, bounds.end.y)
		var x0: float = rng.randf_range(bounds.position.x, bounds.get_center().x)
		var x1: float = rng.randf_range(bounds.get_center().x, bounds.end.x)
		_wobbly_line(image, Vector2(x0, y), Vector2(x1, y + rng.randf_range(-6.0, 6.0)), 2, rng)


func _fill_polygon(image: Image, polygon: PackedVector2Array, colour: Color) -> void:
	var bounds: Rect2 = _bounds(polygon)
	for y: int in range(int(bounds.position.y), int(bounds.end.y) + 1):
		for x: int in range(int(bounds.position.x), int(bounds.end.x) + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
				image.set_pixel(x, y, colour)


## A small cross at the pivot: the point glued to the bone. Placeholder-only, and
## it makes the M1 hitbox-offset check readable at a glance.
func _draw_pivot_tick(image: Image, pivot: Vector2) -> void:
	for offset: int in range(-7, 8):
		_dot(image, Vector2(pivot.x + offset, pivot.y), 1)
		_dot(image, Vector2(pivot.x, pivot.y + offset), 1)


func _label(image: Image, text: String, ink: Rect2, rng: RandomNumberGenerator) -> void:
	var scale: int = 1
	var width: int = ScribbleFont.measure(text, scale)
	while width > int(ink.size.x) - 4 and scale > 1:
		scale -= 1
		width = ScribbleFont.measure(text, scale)
	var height: int = ScribbleFont.GLYPH_HEIGHT * scale
	var x: int = int(ink.get_center().x - float(width) * 0.5)
	var y: int = int(ink.end.y) - height - 4
	ScribbleFont.draw(image, text, clampi(x, 1, image.get_width() - width - 1),
		clampi(y, 1, image.get_height() - height - 1), scale, rng)


func _bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	return bounds


func _save(image: Image, path: String) -> void:
	var directory: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)

	if FileAccess.file_exists(path):
		var existing: Image = Image.new()
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty() and existing.load_png_from_buffer(bytes) == OK \
				and existing.get_size() == image.get_size() \
				and existing.get_data() == image.get_data():
			_skipped += 1
			return

	var error: int = image.save_png(path)
	if error != OK:
		printerr("Cannot write %s (error %d)" % [path, error])
		return
	_written += 1
	print("  wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
