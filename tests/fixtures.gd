class_name Fixtures
extends RefCounted

## Freshly parsed, *mutable* copies of the shipped data files, so a test can
## corrupt one value and assert that the validator notices. `Config` holds the
## frozen production copy and must never be mutated.


## The full data set in the shape `DataValidator.validate()` expects.
static func data_set() -> Dictionary:
	return {
		"parts_db": load_data("res://data/parts_db.json"),
		"parts_schema": load_data("res://data/parts_db.schema.json"),
		"blueprints": load_data("res://data/blueprints.json"),
		"effects": load_data("res://data/effects.json"),
		"enemies": load_data("res://data/enemies.json"),
		"game_config": load_data("res://data/game_config.json"),
		"levels": load_data("res://data/levels.json"),
	}


## The production waiver table, so tests see the same picture the game boots with.
static func waivers() -> Dictionary:
	var table: Dictionary = {}
	for entry: Variant in load_data("res://data/validation_waivers.json")["waivers"] as Array:
		var record: Dictionary = entry as Dictionary
		table[str(record["id"])] = str(record["reason"])
	return table


static func load_data(path: String) -> Dictionary:
	var result: JsonLoader.Result = JsonLoader.load_object(path)
	assert(result.ok, "Fixture load failed: %s" % result.error)
	return result.value as Dictionary


## Every error message produced for `data`, flattened for substring assertions.
static func error_messages(data: Dictionary) -> PackedStringArray:
	var messages: PackedStringArray = PackedStringArray()
	for issue: Dictionary in DataValidator.errors_of(DataValidator.validate(data, waivers())):
		messages.append(str(issue["message"]))
	return messages


static func part(data: Dictionary, part_id: String) -> Dictionary:
	return ((data["parts_db"] as Dictionary)["parts"] as Dictionary)[part_id] as Dictionary


static func enemy(data: Dictionary, enemy_id: String) -> Dictionary:
	return ((data["enemies"] as Dictionary)["enemies"] as Dictionary)[enemy_id] as Dictionary


static func blueprint(data: Dictionary, blueprint_id: String) -> Dictionary:
	return ((data["blueprints"] as Dictionary)["blueprints"] as Dictionary)[blueprint_id] as Dictionary
