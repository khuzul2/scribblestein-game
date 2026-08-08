extends SceneTree

## Machine-checks the two visual criteria that can only be judged from rendered
## frames (MILESTONES M6).
##
##   godot --headless -s tools/verify_frames.gd -- --boil=user://boil --count=60
##   godot --headless -s tools/verify_frames.gd -- --palette=user://lab.png
##
## `--boil` counts how many consecutive frames differ across a one-second
## capture: the line boil must step 8-12 times, no more and no less.
## `--palette` asserts every pixel of a finished frame is a colour ASSET_SPEC §2
## allows.

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	# Autoload identifiers are not in scope for a `--script` main script, so this
	# tool reads its arguments and its config directly rather than through
	# DevTools and Config.
	var options: Dictionary = _parse(OS.get_cmdline_user_args())
	if options.has("boil"):
		_check_boil(str(options["boil"]), int(options.get("count", 180)))
	if options.has("palette"):
		_check_palette(str(options["palette"]))
	if options.is_empty():
		printerr("Nothing to verify. Pass --boil=<prefix> or --palette=<png>.")
		quit(1)
		return

	if _failures.is_empty():
		print("Frame verification passed.")
		quit(0)
		return
	printerr("\nFRAME VERIFICATION FAILED:")
	for failure: String in _failures:
		printerr("  - %s" % failure)
	quit(1)


## Across one second of 60 fps frames, the number of *changes* is the boil rate.
func _check_boil(prefix: String, count: int) -> void:
	var previous: PackedByteArray = PackedByteArray()
	var changes: int = 0
	var read: int = 0

	for index: int in range(count):
		var path: String = "%s_%03d.png" % [prefix, index]
		var image: Image = _load(path)
		if image == null:
			continue
		read += 1
		var data: PackedByteArray = image.get_data()
		if not previous.is_empty() and data != previous:
			changes += 1
		previous = data

	if read < count:
		_failures.append("only %d of %d frames were captured at '%s'" % [read, count, prefix])
		return

	# Convert to a rate using the engine frames the captures actually spanned.
	# Encoding a PNG outlasts a frame, so counting captures would understate the
	# elapsed time and overstate the rate.
	var seconds: float = _captured_seconds(prefix, read)
	var rate: float = float(changes) / maxf(seconds, 0.0001)

	var band: Array = _boil_band()
	var low: float = float(band[0])
	var high: float = float(band[1])
	print("Boil: %d changes across %.2f s of engine time = %.1f steps/s."
		% [changes, seconds, rate])
	if rate < low or rate > high:
		_failures.append(
			"the boil stepped %.1f times a second; Mandate A3 requires %d-%d"
			% [rate, int(low), int(high)])
	if changes == read - 1:
		_failures.append("the image changed every frame — that is not a boil, that is noise")


## Every pixel must be ink or paper. Anything else means a gradient, an alpha
## blend or antialiasing crept in (Mandate A1).
func _check_palette(path: String) -> void:
	var image: Image = _load(path)
	if image == null:
		_failures.append("cannot read '%s'" % path)
		return

	var spec: JsonLoader.Result = JsonLoader.load_object("res://data/asset_spec.json")
	var allowed: Dictionary = {}
	var names: PackedStringArray = PackedStringArray()
	for key: Variant in (spec.value as Dictionary)["palette"] as Dictionary:
		var hex: String = str(((spec.value as Dictionary)["palette"] as Dictionary)[key])
		if hex.ends_with("00"):
			continue  # transparency cannot appear in a composited frame
		allowed[Color(hex).to_rgba32()] = true
		names.append(hex)

	var offenders: Dictionary = {}
	var first: Vector2i = Vector2i(-1, -1)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var value: int = image.get_pixel(x, y).to_rgba32()
			if allowed.has(value):
				continue
			offenders[value] = int(offenders.get(value, 0)) + 1
			if first.x < 0:
				first = Vector2i(x, y)

	if offenders.is_empty():
		print("Palette: %s is entirely %s." % [path.get_file(), ", ".join(names)])
		return
	var total: int = 0
	for count: Variant in offenders.values():
		total += int(count)
	_failures.append("%s has %d pixel(s) in %d colour(s) outside the palette; first at (%d, %d)"
		% [path.get_file(), total, offenders.size(), first.x, first.y])


static func _parse(arguments: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for argument: String in arguments:
		if not argument.begins_with("--"):
			continue
		var body: String = argument.substr(2)
		var split: int = body.find("=")
		if split == -1:
			parsed[body] = true
		else:
			parsed[body.substr(0, split)] = body.substr(split + 1)
	return parsed


## How long the capture actually spanned, on the same clock the shader's `TIME`
## reads, taken from the manifest DevTools wrote alongside the frames.
func _captured_seconds(prefix: String, captured: int) -> float:
	var fallback: float = float(captured) / 60.0
	var result: JsonLoader.Result = JsonLoader.load_object("%s_frames.json" % prefix)
	if not result.ok:
		return fallback
	var stamps: Array = (result.value as Dictionary).get("stamps_usec", []) as Array
	if stamps.size() < 2:
		return fallback
	return float(int(stamps[stamps.size() - 1]) - int(stamps[0])) / 1000000.0


func _boil_band() -> Array:
	var result: JsonLoader.Result = JsonLoader.load_object("res://data/game_config.json")
	if not result.ok:
		return [8.0, 12.0]
	return ((result.value as Dictionary)["line_boil"] as Dictionary)["boil_fps_range"] as Array


func _load(path: String) -> Image:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image: Image = Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image
