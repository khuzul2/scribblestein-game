class_name JsonLoader
extends RefCounted

## Reads `res://data/*.json` from disk with precise, quotable error messages.
##
## Nothing here silently defaults (Mandate B1): a file that is missing,
## unreadable, malformed, or the wrong shape comes back as a failed result
## carrying the file name and the reason, which `Config` turns into a loud crash.


## Result of one load attempt. `value` is only meaningful when `ok` is true.
class Result extends RefCounted:
	var ok: bool = false
	var value: Variant = null
	var error: String = ""

	static func success(v: Variant) -> Result:
		var r: Result = Result.new()
		r.ok = true
		r.value = v
		return r

	static func failure(msg: String) -> Result:
		var r: Result = Result.new()
		r.ok = false
		r.error = msg
		return r


## Load and parse a JSON file, requiring the top level to be an object.
static func load_object(path: String) -> Result:
	var raw: Result = load_any(path)
	if not raw.ok:
		return raw
	if not raw.value is Dictionary:
		return Result.failure("%s: top level must be a JSON object, got %s"
			% [path, type_string(typeof(raw.value))])
	return raw


## Load and parse a JSON file of any top-level type.
static func load_any(path: String) -> Result:
	if not FileAccess.file_exists(path):
		return Result.failure("%s: file does not exist" % path)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("%s: cannot open for reading (error %d)"
			% [path, FileAccess.get_open_error()])

	var text: String = file.get_as_text()
	file.close()

	var parser: JSON = JSON.new()
	var parse_error: int = parser.parse(text)
	if parse_error != OK:
		return Result.failure("%s: line %d: %s"
			% [path, parser.get_error_line(), parser.get_error_message()])

	return Result.success(parser.data)


## Fetch a required sub-object, e.g. the `parts` key of `parts_db.json`.
static func require_object(container: Dictionary, key: String, source: String) -> Result:
	if not container.has(key):
		return Result.failure("%s: missing required top-level key '%s'" % [source, key])
	if not container[key] is Dictionary:
		return Result.failure("%s: key '%s' must be an object, got %s"
			% [source, key, type_string(typeof(container[key]))])
	return Result.success(container[key])


## Recursively lock a parsed structure so gameplay code cannot mutate config.
static func deep_freeze(value: Variant) -> void:
	if value is Dictionary:
		var dict: Dictionary = value as Dictionary
		for key: Variant in dict:
			deep_freeze(dict[key])
		dict.make_read_only()
	elif value is Array:
		var arr: Array = value as Array
		for item: Variant in arr:
			deep_freeze(item)
		arr.make_read_only()
