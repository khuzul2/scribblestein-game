extends Node

## Autoload `Config` — the read-only single source of truth for every gameplay
## number (Mandate B1). Loads `res://data/*.json` at boot, validates it, and
## crashes loudly with file + JSON path + reason if anything is wrong
## (TECH_SPEC §9). Gameplay code reads from here and never hardcodes a value.

const DATA_DIR: String = "res://data"
const WAIVERS_PATH: String = "res://data/validation_waivers.json"

const FILES: Dictionary = {
	"parts_db": "res://data/parts_db.json",
	"parts_schema": "res://data/parts_db.schema.json",
	"blueprints": "res://data/blueprints.json",
	"effects": "res://data/effects.json",
	"enemies": "res://data/enemies.json",
	"game_config": "res://data/game_config.json",
	"levels": "res://data/levels.json",
}

## Emitted once the data set is loaded and validated.
signal loaded

var parts: Dictionary = {}
var blueprints: Dictionary = {}
var effects: Dictionary = {}
var enemies: Dictionary = {}
var game: Dictionary = {}
var levels: Dictionary = {}

var is_loaded: bool = false
var warnings: PackedStringArray = PackedStringArray()

var _raw: Dictionary = {}


func _ready() -> void:
	load_all()


## Load + validate everything. Returns true on success; on failure it reports and
## terminates the process with exit code 1.
func load_all() -> bool:
	var raw: Dictionary = {}
	var load_errors: PackedStringArray = PackedStringArray()

	for stem: String in FILES:
		var result: JsonLoader.Result = JsonLoader.load_object(str(FILES[stem]))
		if result.ok:
			raw[stem] = result.value
		else:
			load_errors.append(result.error)

	if not load_errors.is_empty():
		_fail("could not read the data set", load_errors)
		return false

	var issues: Array[Dictionary] = DataValidator.validate(raw, _load_waivers())
	var errors: Array[Dictionary] = DataValidator.errors_of(issues)

	warnings = PackedStringArray()
	for warning: Dictionary in DataValidator.warnings_of(issues):
		warnings.append("[%s] %s" % [warning["id"], warning["message"]])
	for warning_text: String in warnings:
		push_warning("Scribblestein data warning: %s" % warning_text)
		print_rich("[color=yellow]DATA WARNING[/color] %s" % warning_text)

	if not errors.is_empty():
		var messages: PackedStringArray = PackedStringArray()
		for issue: Dictionary in errors:
			messages.append("[%s] %s" % [issue["id"], issue["message"]])
		_fail("data validation failed", messages)
		return false

	_raw = raw
	parts = (raw["parts_db"] as Dictionary)["parts"] as Dictionary
	blueprints = (raw["blueprints"] as Dictionary)["blueprints"] as Dictionary
	effects = (raw["effects"] as Dictionary)["effects"] as Dictionary
	enemies = (raw["enemies"] as Dictionary)["enemies"] as Dictionary
	game = raw["game_config"] as Dictionary
	levels = (raw["levels"] as Dictionary)["levels"] as Dictionary

	JsonLoader.deep_freeze(raw)
	is_loaded = true
	loaded.emit()
	return true


# --- lookups -------------------------------------------------------------------

func part(part_id: String) -> Dictionary:
	assert(parts.has(part_id), "Unknown part id '%s'" % part_id)
	return parts.get(part_id, {}) as Dictionary


func blueprint(blueprint_id: String) -> Dictionary:
	assert(blueprints.has(blueprint_id), "Unknown blueprint id '%s'" % blueprint_id)
	return blueprints.get(blueprint_id, {}) as Dictionary


func effect(effect_id: String) -> Dictionary:
	assert(effects.has(effect_id), "Unknown effect id '%s'" % effect_id)
	return effects.get(effect_id, {}) as Dictionary


func enemy(enemy_id: String) -> Dictionary:
	assert(enemies.has(enemy_id), "Unknown enemy id '%s'" % enemy_id)
	return enemies.get(enemy_id, {}) as Dictionary


func level(level_id: String) -> Dictionary:
	assert(levels.has(level_id), "Unknown level id '%s'" % level_id)
	return levels.get(level_id, {}) as Dictionary


## Level ids that appear on the sketchbook world map, in play order.
func map_level_ids() -> PackedStringArray:
	var ids: Array = []
	for level_id: Variant in levels:
		if bool((levels[level_id] as Dictionary).get("on_map", false)):
			ids.append(str(level_id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(level(a).get("order", 0)) < int(level(b).get("order", 0)))
	return PackedStringArray(ids)


## Ids of every part whose `starter` flag is set — the always-unlocked kit.
func starter_part_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for part_id: Variant in parts:
		if bool((parts[part_id] as Dictionary).get("starter", false)):
			ids.append(str(part_id))
	ids.sort()
	return ids


## Read a dotted path out of `game_config.json`, e.g. `cfg("movement.gravity")`.
## Missing paths are a programming error, not a tuning gap: assert, never default.
func cfg(dotted_path: String) -> Variant:
	var node: Variant = game
	for key: String in dotted_path.split("."):
		if not node is Dictionary or not (node as Dictionary).has(key):
			assert(false, "game_config.json has no value at '%s'" % dotted_path)
			return null
		node = (node as Dictionary)[key]
	return node


func cfg_float(dotted_path: String) -> float:
	return float(cfg(dotted_path))


func cfg_int(dotted_path: String) -> int:
	return int(cfg(dotted_path))


func cfg_vec2(dotted_path: String) -> Vector2:
	var pair: Array = cfg(dotted_path) as Array
	return Vector2(float(pair[0]), float(pair[1]))


# --- failure -------------------------------------------------------------------

func _load_waivers() -> Dictionary:
	if not FileAccess.file_exists(WAIVERS_PATH):
		return {}
	var result: JsonLoader.Result = JsonLoader.load_object(WAIVERS_PATH)
	if not result.ok:
		_fail("could not read the validation waivers", PackedStringArray([result.error]))
		return {}
	var waivers: Dictionary = {}
	for entry: Variant in (result.value as Dictionary).get("waivers", []) as Array:
		var record: Dictionary = entry as Dictionary
		waivers[str(record.get("id", ""))] = str(record.get("reason", "no reason given"))
	return waivers


func _fail(headline: String, details: PackedStringArray) -> void:
	var banner: String = "\n".join(PackedStringArray([
		"",
		"================================================================",
		"  SCRIBBLESTEIN BOOT FAILURE — %s" % headline,
		"  %d problem(s). Fix the data; the game will not start until you do." % details.size(),
		"================================================================",
	]))
	printerr(banner)
	for index: int in range(details.size()):
		printerr("  %d) %s" % [index + 1, details[index]])
	printerr("================================================================\n")
	push_error("Scribblestein boot failure — %s (%d problems, see stderr)" % [headline, details.size()])

	is_loaded = false
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.quit(1)
	else:
		OS.crash("Scribblestein boot failure — %s" % headline)
