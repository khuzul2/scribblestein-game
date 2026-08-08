class_name TestCase
extends RefCounted

## Base class for every test under `res://tests/`.
##
## Subclass it, write `test_*` methods, and run the suite with:
##     godot --headless -s tools/run_tests.gd
##
## Assertions record a failure and keep going, so one run reports every problem
## rather than only the first. Tests that need frames or physics may `await`;
## the runner awaits each test method.

var failures: PackedStringArray = PackedStringArray()
var assertions: int = 0

## Set by the runner so tests can parent nodes and await frames.
var tree: SceneTree = null


## Runs before each `test_*` method.
func before_each() -> void:
	pass


## Runs after each `test_*` method, pass or fail.
func after_each() -> void:
	pass


func check(condition: bool, message: String) -> bool:
	assertions += 1
	if not condition:
		failures.append(message)
	return condition


func eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s — expected %s, got %s" % [message, expected, actual])


func ne(actual: Variant, unexpected: Variant, message: String) -> bool:
	return check(actual != unexpected, "%s — expected anything but %s" % [message, unexpected])


func almost(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
		"%s — expected %s ± %s, got %s (off by %s)"
		% [message, expected, tolerance, actual, absf(actual - expected)])


## Assert `actual` is within `percent` (0.05 = 5%) of `expected`.
func within_percent(actual: float, expected: float, percent: float, message: String) -> bool:
	var tolerance: float = absf(expected) * percent
	return check(absf(actual - expected) <= tolerance,
		"%s — expected %s ± %s%% (± %s), got %s"
		% [message, expected, percent * 100.0, tolerance, actual])


func is_true(condition: bool, message: String) -> bool:
	return check(condition, "%s — expected true" % message)


func is_false(condition: bool, message: String) -> bool:
	return check(not condition, "%s — expected false" % message)


func is_null(value: Variant, message: String) -> bool:
	return check(value == null, "%s — expected null, got %s" % [message, value])


func not_null(value: Variant, message: String) -> bool:
	return check(value != null, "%s — expected a value, got null" % message)


## Assert at least one string in `haystack` contains every fragment.
func any_contains(haystack: PackedStringArray, fragments: PackedStringArray, message: String) -> bool:
	for candidate: String in haystack:
		var all_present: bool = true
		for fragment: String in fragments:
			if not candidate.contains(fragment):
				all_present = false
				break
		if all_present:
			return check(true, message)
	return check(false, "%s — no entry contained all of %s.\n      Candidates: %s"
		% [message, str(fragments), "\n                  ".join(haystack)])


func fail(message: String) -> void:
	assertions += 1
	failures.append(message)


## Wait `count` physics ticks. Only valid when the runner supplied a tree.
func physics_ticks(count: int) -> void:
	for _i: int in range(count):
		await tree.physics_frame
