extends SceneTree

## The machine that makes "asset discipline" safe (Decision 12, ASSET_SPEC §5).
##
##     godot --headless -s tools/validate_assets.gd
##
## Exits non-zero on any violation. Runs in CI, and must be run before any
## texture is committed. Checks, in order:
##   1. Every pixel of every PNG under assets/ is in that path's colour allowlist.
##   2. Part canvases match the slot table.
##   3. File naming matches ASSET_SPEC §3.
##   4. Every `texture_path` in parts_db.json exists; orphan part textures warn.
##   5. Import settings: mipmaps off, lossless, no 3D detection; and the
##      project-wide Nearest texture filter (see DECISIONS_NEEDED.md D3).

const ASSET_SPEC_PATH: String = "res://data/asset_spec.json"
const PARTS_DB_PATH: String = "res://data/parts_db.json"
const ASSETS_ROOT: String = "res://assets"

var _spec: Dictionary = {}
var _errors: PackedStringArray = PackedStringArray()
var _warnings: PackedStringArray = PackedStringArray()
var _checked: int = 0
var _images: Dictionary = {}


## Read the PNG *source* file, not its imported .ctex — the point of this tool is
## to police what lands in git. Decoding the bytes ourselves also sidesteps the
## "loaded resource as image file" warning `Image.load_from_file` prints.
func _source_image(path: String) -> Image:
	if _images.has(path):
		return _images[path] as Image
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var image: Image = Image.new()
	if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
		_images[path] = null
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_images[path] = image
	return image


func _initialize() -> void:
	var spec_result: JsonLoader.Result = JsonLoader.load_object(ASSET_SPEC_PATH)
	var parts_result: JsonLoader.Result = JsonLoader.load_object(PARTS_DB_PATH)
	if not spec_result.ok:
		_fatal(spec_result.error)
		return
	if not parts_result.ok:
		_fatal(parts_result.error)
		return
	_spec = spec_result.value as Dictionary

	var pngs: PackedStringArray = _collect_pngs(ASSETS_ROOT)
	pngs.sort()

	for path: String in pngs:
		_check_palette(path)
		_check_naming(path)
		_check_import_settings(path)

	_check_part_textures((parts_result.value as Dictionary)["parts"] as Dictionary, pngs)
	_check_project_settings()

	_report()


# --- 1. palette ----------------------------------------------------------------

func _check_palette(path: String) -> void:
	var image: Image = _source_image(path)
	if image == null:
		_errors.append("%s: cannot be decoded as a PNG" % path)
		return
	_checked += 1

	var allowed: Dictionary = {}
	for hex: String in _allowlist_for(path):
		allowed[Color(hex).to_rgba32()] = hex

	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var value: int = image.get_pixel(x, y).to_rgba32()
			if allowed.has(value):
				continue
			var colour: Color = image.get_pixel(x, y)
			_errors.append(
				"%s: first offending pixel at (%d, %d) is #%s — allowed here: %s"
				% [path, x, y, colour.to_html(true), ", ".join(_allowlist_for(path))])
			return


func _allowlist_for(path: String) -> PackedStringArray:
	var best_prefix: String = ""
	var best_colors: Array = _spec["default_allowlist"] as Array
	for entry: Variant in _spec["path_allowlists"] as Array:
		var rule: Dictionary = entry as Dictionary
		var prefix: String = str(rule["prefix"])
		if path.begins_with(prefix) and prefix.length() > best_prefix.length():
			best_prefix = prefix
			best_colors = rule["colors"] as Array
	var colours: PackedStringArray = PackedStringArray()
	for colour: Variant in best_colors:
		colours.append(str(colour))
	return colours


# --- 2 & 3. canvas sizes and naming --------------------------------------------

func _check_naming(path: String) -> void:
	var file_name: String = path.get_file()
	for entry: Variant in _spec["naming_patterns"] as Array:
		var rule: Dictionary = entry as Dictionary
		if not path.begins_with(str(rule["prefix"])):
			continue
		var regex: RegEx = RegEx.new()
		if regex.compile(str(rule["pattern"])) != OK:
			_errors.append("asset_spec.json: naming pattern '%s' does not compile" % rule["pattern"])
			return
		if regex.search(file_name) == null:
			_errors.append("%s: file name breaks the ASSET_SPEC §3 pattern '%s'"
				% [path, rule["pattern"]])
		return


func _check_canvas(path: String, slot: String) -> void:
	var canvas_sizes: Dictionary = _spec["canvas_sizes"] as Dictionary
	if not canvas_sizes.has(slot):
		_errors.append("%s: no canvas size is specified for slot '%s'" % [path, slot])
		return
	var expected: Array = canvas_sizes[slot] as Array
	var image: Image = _source_image(path)
	if image == null:
		return
	if image.get_width() != int(expected[0]) or image.get_height() != int(expected[1]):
		_errors.append("%s: canvas is %dx%d, slot '%s' requires %dx%d (ASSET_SPEC §1)"
			% [path, image.get_width(), image.get_height(), slot, int(expected[0]), int(expected[1])])


# --- 4. parts_db cross-check ---------------------------------------------------

func _check_part_textures(parts: Dictionary, pngs: PackedStringArray) -> void:
	var referenced: Dictionary = {}
	for part_id: Variant in parts:
		var part: Dictionary = parts[part_id] as Dictionary
		var texture_path: String = str(part["texture_path"])
		referenced[texture_path] = true
		if not FileAccess.file_exists(texture_path):
			_errors.append("data/parts_db.json /parts/%s/texture_path: '%s' does not exist"
				% [part_id, texture_path])
			continue
		_check_canvas(texture_path, str(part["slot"]))

		var expected_folder: String = str((_spec["part_folders"] as Dictionary)[str(part["slot"])])
		if texture_path.get_base_dir() != expected_folder:
			_errors.append("data/parts_db.json /parts/%s/texture_path: slot '%s' textures belong in %s"
				% [part_id, part["slot"], expected_folder])

	for path: String in pngs:
		if path.begins_with("res://assets/parts/") and not referenced.has(path):
			_warnings.append("%s: orphan part texture — no part in parts_db.json references it" % path)


# --- 5. import settings --------------------------------------------------------

func _check_import_settings(path: String) -> void:
	var import_path: String = path + ".import"
	if not FileAccess.file_exists(import_path):
		_errors.append("%s: no .import file — run `godot --headless --import` first" % path)
		return

	var config: ConfigFile = ConfigFile.new()
	if config.load(import_path) != OK:
		_errors.append("%s: cannot be parsed" % import_path)
		return

	for key: Variant in _spec["import_requirements"] as Dictionary:
		var required: Variant = (_spec["import_requirements"] as Dictionary)[key]
		var section: String = str(key).get_slice("/", 0)
		var option: String = str(key).substr(section.length() + 1)
		var actual: Variant = config.get_value(section, option, null)
		if actual == null:
			_errors.append("%s: missing import option '%s' (expected %s)" % [import_path, key, required])
		elif not _same_value(actual, required):
			_errors.append("%s: import option '%s' is %s, must be %s (Mandate A1)"
				% [import_path, key, actual, required])


func _check_project_settings() -> void:
	for key: Variant in _spec["project_setting_requirements"] as Dictionary:
		var required: Variant = (_spec["project_setting_requirements"] as Dictionary)[key]
		var actual: Variant = ProjectSettings.get_setting(str(key), null)
		if actual == null or not _same_value(actual, required):
			_errors.append("project.godot: '%s' is %s, must be %s (Mandate A1 / DECISIONS_NEEDED.md D3)"
				% [key, actual, required])


# --- plumbing ------------------------------------------------------------------

func _collect_pngs(root: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = root.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_collect_pngs(full))
		elif entry.get_extension().to_lower() == "png":
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _same_value(actual: Variant, required: Variant) -> bool:
	if required is bool:
		return bool(actual) == bool(required)
	if required is float or required is int:
		return is_equal_approx(float(actual), float(required))
	return str(actual) == str(required)


func _fatal(message: String) -> void:
	printerr("ASSET VALIDATION ABORTED: %s" % message)
	quit(1)


func _report() -> void:
	for warning: String in _warnings:
		print("  WARN  %s" % warning)
	if _errors.is_empty():
		print("Asset validation passed: %d texture(s), 0 violations." % _checked)
		if not _warnings.is_empty():
			print("  (%d warning(s) — not fatal)" % _warnings.size())
		quit(0)
		return
	printerr("\nASSET VALIDATION FAILED — %d violation(s) across %d texture(s):"
		% [_errors.size(), _checked])
	for index: int in range(_errors.size()):
		printerr("  %d) %s" % [index + 1, _errors[index]])
	printerr("")
	quit(1)
