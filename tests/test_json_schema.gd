extends TestCase

## Unit tests for the JSON Schema subset that guards `parts_db.json`.


func test_type_mismatch_names_the_path() -> void:
	var schema: Dictionary = {"type": "object", "properties": {"weight": {"type": "number"}}}
	var errors: PackedStringArray = JsonSchema.validate({"weight": "heavy"}, schema)
	eq(errors.size(), 1, "one error for one bad value")
	any_contains(errors, PackedStringArray(["/weight", "expected type number"]),
		"names the offending path and the reason")


func test_required_keys() -> void:
	var schema: Dictionary = {"type": "object", "required": ["name", "slot"]}
	var errors: PackedStringArray = JsonSchema.validate({"name": "x"}, schema)
	any_contains(errors, PackedStringArray(["missing required key 'slot'"]), "reports the missing key")
	is_true(JsonSchema.validate({"name": "x", "slot": "head"}, schema).is_empty(),
		"complete object passes")


func test_additional_properties_false_rejects_unknown_keys() -> void:
	var schema: Dictionary = {
		"type": "object", "properties": {"a": {"type": "number"}}, "additionalProperties": false}
	any_contains(JsonSchema.validate({"a": 1, "typo": 2}, schema),
		PackedStringArray(["unknown key 'typo'"]), "unknown keys are rejected")


func test_enum_and_pattern() -> void:
	var enum_schema: Dictionary = {"enum": ["damage", "hurtbox"]}
	any_contains(JsonSchema.validate("healbox", enum_schema),
		PackedStringArray(["is not one of"]), "enum rejects an unlisted value")
	is_true(JsonSchema.validate("damage", enum_schema).is_empty(), "enum accepts a listed value")

	var pattern_schema: Dictionary = {"type": "string", "pattern": "^res://assets/parts/.+\\.png$"}
	is_true(JsonSchema.validate("res://assets/parts/heads/x.png", pattern_schema).is_empty(),
		"matching path passes")
	any_contains(JsonSchema.validate("res://sprites/x.png", pattern_schema),
		PackedStringArray(["does not match pattern"]), "non-matching path fails")


func test_numeric_bounds() -> void:
	any_contains(JsonSchema.validate(-1, {"type": "number", "minimum": 0}),
		PackedStringArray(["below the minimum"]), "minimum is enforced")
	any_contains(JsonSchema.validate(0, {"type": "number", "exclusiveMinimum": 0}),
		PackedStringArray(["must be greater than"]), "exclusiveMinimum is enforced")
	is_true(JsonSchema.validate(0, {"type": "number", "minimum": 0}).is_empty(),
		"minimum is inclusive")


func test_integer_accepts_json_floats() -> void:
	# Godot's JSON parser can hand back 120 as a float; that is still an integer.
	is_true(JsonSchema.validate(120.0, {"type": "integer"}).is_empty(), "120.0 is an integer")
	any_contains(JsonSchema.validate(120.5, {"type": "integer"}),
		PackedStringArray(["expected type integer"]), "120.5 is not")


func test_array_bounds_and_items() -> void:
	var schema: Dictionary = {
		"type": "array", "minItems": 2, "maxItems": 2, "items": {"type": "number"}}
	any_contains(JsonSchema.validate([1], schema),
		PackedStringArray(["at least 2 items"]), "minItems is enforced")
	any_contains(JsonSchema.validate([1, 2, 3], schema),
		PackedStringArray(["at most 2 items"]), "maxItems is enforced")
	any_contains(JsonSchema.validate([1, "two"], schema),
		PackedStringArray(["/1", "expected type number"]), "item index appears in the path")


func test_local_ref_resolution() -> void:
	var schema: Dictionary = {
		"type": "object",
		"properties": {"part": {"$ref": "#/definitions/part"}},
		"definitions": {"part": {"type": "object", "required": ["name"]}},
	}
	any_contains(JsonSchema.validate({"part": {}}, schema),
		PackedStringArray(["/part", "missing required key 'name'"]), "$ref resolves and reports through")


func test_if_then_conditional() -> void:
	# Mirrors the schema rule "a circle hitbox must carry a radius".
	var schema: Dictionary = {
		"type": "object",
		"properties": {"shape": {"enum": ["circle", "rectangle"]}},
		"allOf": [{
			"if": {"properties": {"shape": {"const": "circle"}}},
			"then": {"required": ["radius"]},
		}],
	}
	any_contains(JsonSchema.validate({"shape": "circle"}, schema),
		PackedStringArray(["missing required key 'radius'"]), "circle without radius fails")
	is_true(JsonSchema.validate({"shape": "rectangle"}, schema).is_empty(),
		"rectangle without radius passes")


func test_contains_keyword() -> void:
	var schema: Dictionary = {"type": "array", "contains": {"properties": {"type": {"const": "damage"}}}}
	is_true(JsonSchema.validate([{"type": "damage"}], schema).is_empty(), "matching item satisfies contains")
	any_contains(JsonSchema.validate([{"type": "hurtbox"}], schema),
		PackedStringArray(["no item satisfies"]), "no matching item fails contains")


func test_shipped_parts_db_satisfies_its_schema() -> void:
	var data: Dictionary = Fixtures.data_set()
	var errors: PackedStringArray = JsonSchema.validate(
		data["parts_db"] as Dictionary, data["parts_schema"] as Dictionary)
	is_true(errors.is_empty(), "shipped parts_db.json is schema clean: %s" % str(errors))
