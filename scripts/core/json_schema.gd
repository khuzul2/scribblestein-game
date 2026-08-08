class_name JsonSchema
extends RefCounted

## Minimal JSON Schema (draft-07 subset) validator.
##
## Implements exactly the keywords used by `data/parts_db.schema.json`:
## $ref (local pointers only), type, enum, const, required, properties,
## additionalProperties, minProperties, minLength, minimum, maximum,
## exclusiveMinimum, exclusiveMaximum, pattern, items, minItems, maxItems,
## contains, allOf, anyOf, oneOf, not, if/then/else.
##
## Errors are reported as `<json pointer>: <reason>` so a boot failure can name
## the exact key that is wrong (Mandate B1).


## Validate `instance` against `schema`. `root` is the document `$ref` resolves
## against; it defaults to `schema` itself.
static func validate(instance: Variant, schema: Dictionary, root: Dictionary = {}) -> PackedStringArray:
	var document: Dictionary = root if not root.is_empty() else schema
	var errors: PackedStringArray = PackedStringArray()
	_validate_node(instance, schema, document, "", errors)
	return errors


static func _validate_node(instance: Variant, schema: Dictionary, root: Dictionary,
		path: String, errors: PackedStringArray) -> void:
	if schema.has("$ref"):
		var ref: String = str(schema["$ref"])
		var resolved: Variant = _resolve_ref(ref, root)
		if resolved == null:
			errors.append("%s: unresolvable $ref '%s'" % [_p(path), ref])
			return
		_validate_node(instance, resolved as Dictionary, root, path, errors)
		return

	if schema.has("type") and not _matches_type(instance, schema["type"]):
		errors.append("%s: expected type %s, got %s (%s)" % [
			_p(path), _type_label(schema["type"]), _godot_type_name(instance), _preview(instance)])
		return

	if schema.has("const") and not _deep_equal(instance, schema["const"]):
		errors.append("%s: must equal %s, got %s" % [_p(path), _preview(schema["const"]), _preview(instance)])

	if schema.has("enum"):
		var allowed: Array = schema["enum"] as Array
		var found: bool = false
		for candidate: Variant in allowed:
			if _deep_equal(instance, candidate):
				found = true
				break
		if not found:
			errors.append("%s: %s is not one of %s" % [_p(path), _preview(instance), str(allowed)])

	if instance is Dictionary:
		_validate_object(instance as Dictionary, schema, root, path, errors)
	elif instance is Array:
		_validate_array(instance as Array, schema, root, path, errors)
	elif instance is String:
		_validate_string(instance as String, schema, path, errors)
	elif instance is int or instance is float:
		_validate_number(float(instance), schema, path, errors)

	_validate_combinators(instance, schema, root, path, errors)


static func _validate_object(instance: Dictionary, schema: Dictionary, root: Dictionary,
		path: String, errors: PackedStringArray) -> void:
	if schema.has("required"):
		for key: Variant in schema["required"] as Array:
			if not instance.has(key):
				errors.append("%s: missing required key '%s'" % [_p(path), str(key)])

	if schema.has("minProperties") and instance.size() < int(schema["minProperties"]):
		errors.append("%s: needs at least %d properties, has %d" % [
			_p(path), int(schema["minProperties"]), instance.size()])

	var properties: Dictionary = schema.get("properties", {}) as Dictionary
	for key: Variant in instance:
		var child_path: String = "%s/%s" % [path, str(key)]
		if properties.has(key):
			_validate_node(instance[key], properties[key] as Dictionary, root, child_path, errors)
		elif schema.has("additionalProperties"):
			var extra: Variant = schema["additionalProperties"]
			if extra is bool:
				if not bool(extra):
					errors.append("%s: unknown key '%s' is not allowed here" % [_p(path), str(key)])
			else:
				_validate_node(instance[key], extra as Dictionary, root, child_path, errors)


static func _validate_array(instance: Array, schema: Dictionary, root: Dictionary,
		path: String, errors: PackedStringArray) -> void:
	if schema.has("minItems") and instance.size() < int(schema["minItems"]):
		errors.append("%s: needs at least %d items, has %d" % [
			_p(path), int(schema["minItems"]), instance.size()])
	if schema.has("maxItems") and instance.size() > int(schema["maxItems"]):
		errors.append("%s: allows at most %d items, has %d" % [
			_p(path), int(schema["maxItems"]), instance.size()])

	if schema.has("items"):
		var item_schema: Dictionary = schema["items"] as Dictionary
		for i: int in range(instance.size()):
			_validate_node(instance[i], item_schema, root, "%s/%d" % [path, i], errors)

	if schema.has("contains"):
		var contains_schema: Dictionary = schema["contains"] as Dictionary
		var any_match: bool = false
		for i: int in range(instance.size()):
			var probe: PackedStringArray = PackedStringArray()
			_validate_node(instance[i], contains_schema, root, "", probe)
			if probe.is_empty():
				any_match = true
				break
		if not any_match:
			errors.append("%s: no item satisfies the 'contains' constraint" % _p(path))


static func _validate_string(instance: String, schema: Dictionary,
		path: String, errors: PackedStringArray) -> void:
	if schema.has("minLength") and instance.length() < int(schema["minLength"]):
		errors.append("%s: string shorter than %d characters" % [_p(path), int(schema["minLength"])])
	if schema.has("pattern"):
		var regex: RegEx = RegEx.new()
		var pattern: String = str(schema["pattern"])
		if regex.compile(pattern) != OK:
			errors.append("%s: schema pattern '%s' does not compile" % [_p(path), pattern])
		elif regex.search(instance) == null:
			errors.append("%s: '%s' does not match pattern '%s'" % [_p(path), instance, pattern])


static func _validate_number(value: float, schema: Dictionary,
		path: String, errors: PackedStringArray) -> void:
	if schema.has("minimum") and value < float(schema["minimum"]):
		errors.append("%s: %s is below the minimum of %s" % [_p(path), value, schema["minimum"]])
	if schema.has("maximum") and value > float(schema["maximum"]):
		errors.append("%s: %s is above the maximum of %s" % [_p(path), value, schema["maximum"]])
	if schema.has("exclusiveMinimum") and value <= float(schema["exclusiveMinimum"]):
		errors.append("%s: %s must be greater than %s" % [_p(path), value, schema["exclusiveMinimum"]])
	if schema.has("exclusiveMaximum") and value >= float(schema["exclusiveMaximum"]):
		errors.append("%s: %s must be less than %s" % [_p(path), value, schema["exclusiveMaximum"]])


static func _validate_combinators(instance: Variant, schema: Dictionary, root: Dictionary,
		path: String, errors: PackedStringArray) -> void:
	if schema.has("allOf"):
		for sub: Variant in schema["allOf"] as Array:
			_validate_node(instance, sub as Dictionary, root, path, errors)

	if schema.has("anyOf"):
		var any_ok: bool = false
		for sub: Variant in schema["anyOf"] as Array:
			var probe: PackedStringArray = PackedStringArray()
			_validate_node(instance, sub as Dictionary, root, path, probe)
			if probe.is_empty():
				any_ok = true
				break
		if not any_ok:
			errors.append("%s: matches none of the 'anyOf' alternatives" % _p(path))

	if schema.has("oneOf"):
		var match_count: int = 0
		for sub: Variant in schema["oneOf"] as Array:
			var probe: PackedStringArray = PackedStringArray()
			_validate_node(instance, sub as Dictionary, root, path, probe)
			if probe.is_empty():
				match_count += 1
		if match_count != 1:
			errors.append("%s: matches %d 'oneOf' alternatives, expected exactly 1" % [_p(path), match_count])

	if schema.has("not"):
		var probe_not: PackedStringArray = PackedStringArray()
		_validate_node(instance, schema["not"] as Dictionary, root, path, probe_not)
		if probe_not.is_empty():
			errors.append("%s: must NOT match the 'not' schema" % _p(path))

	if schema.has("if"):
		var probe_if: PackedStringArray = PackedStringArray()
		_validate_node(instance, schema["if"] as Dictionary, root, path, probe_if)
		if probe_if.is_empty():
			if schema.has("then"):
				_validate_node(instance, schema["then"] as Dictionary, root, path, errors)
		elif schema.has("else"):
			_validate_node(instance, schema["else"] as Dictionary, root, path, errors)


static func _resolve_ref(ref: String, root: Dictionary) -> Variant:
	if not ref.begins_with("#/"):
		return null
	var node: Variant = root
	for raw: String in ref.substr(2).split("/"):
		var token: String = raw.replace("~1", "/").replace("~0", "~")
		if node is Dictionary and (node as Dictionary).has(token):
			node = (node as Dictionary)[token]
		elif node is Array and token.is_valid_int():
			node = (node as Array)[token.to_int()]
		else:
			return null
	return node


static func _matches_type(instance: Variant, type_spec: Variant) -> bool:
	if type_spec is Array:
		for one: Variant in type_spec as Array:
			if _matches_type(instance, one):
				return true
		return false
	match str(type_spec):
		"object":
			return instance is Dictionary
		"array":
			return instance is Array
		"string":
			return instance is String or instance is StringName
		"boolean":
			return instance is bool
		"null":
			return instance == null
		"number":
			return (instance is int or instance is float) and not instance is bool
		"integer":
			if instance is bool:
				return false
			if instance is int:
				return true
			# Godot's JSON parser hands back floats; accept integral values.
			return instance is float and is_equal_approx(float(instance), roundf(float(instance)))
	return false


static func _deep_equal(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float) and not (a is bool or b is bool):
		return is_equal_approx(float(a), float(b))
	return a == b


static func _type_label(type_spec: Variant) -> String:
	if type_spec is Array:
		return " or ".join(PackedStringArray((type_spec as Array).map(func(t: Variant) -> String: return str(t))))
	return str(type_spec)


static func _godot_type_name(instance: Variant) -> String:
	return type_string(typeof(instance))


static func _preview(instance: Variant) -> String:
	var text: String = JSON.stringify(instance)
	return text if text.length() <= 80 else text.substr(0, 77) + "..."


static func _p(path: String) -> String:
	return path if path != "" else "<root>"
