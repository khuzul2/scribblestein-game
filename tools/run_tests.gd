extends SceneTree

## Test runner.
##
##     godot --headless -s tools/run_tests.gd            # everything
##     godot --headless -s tools/run_tests.gd -- creature  # only matching files
##
## Discovers `res://tests/test_*.gd`, runs every `test_*` method, and exits
## non-zero if any assertion failed. Test methods may await.

const TESTS_DIR: String = "res://tests"

var _passed: int = 0
var _failed: int = 0
var _assertions: int = 0
var _failure_lines: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	# Deferred so the runner can await frames without blocking engine start-up.
	_run.call_deferred()


func _run() -> void:
	var filter: String = ""
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		filter = user_args[0]

	var files: PackedStringArray = _discover(filter)
	if files.is_empty():
		printerr("No test files matched '%s' under %s" % [filter, TESTS_DIR])
		quit(1)
		return

	print("Running %d test file(s)%s\n" % [files.size(), "" if filter == "" else " matching '%s'" % filter])

	for path: String in files:
		await _run_file(path)

	print("\n%s" % "-".repeat(70))
	if _failed == 0:
		print("PASSED — %d test(s), %d assertion(s)." % [_passed, _assertions])
		quit(0)
		return

	printerr("FAILED — %d of %d test(s) failed (%d assertions):\n"
		% [_failed, _passed + _failed, _assertions])
	for line: String in _failure_lines:
		printerr(line)
	printerr("")
	quit(1)


func _run_file(path: String) -> void:
	var script: GDScript = load(path) as GDScript
	if script == null:
		_failed += 1
		_failure_lines.append("  %s: could not be loaded" % path)
		return

	var method_names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in script.get_script_method_list():
		var method_name: String = str(entry["name"])
		if method_name.begins_with("test_") and not method_names.has(method_name):
			method_names.append(method_name)
	method_names.sort()

	print("%s" % path.get_file())
	for method_name: String in method_names:
		var case: TestCase = script.new() as TestCase
		if case == null:
			_failed += 1
			_failure_lines.append("  %s: does not extend TestCase" % path)
			return
		case.tree = self

		await case.before_each()
		await case.call(method_name)
		await case.after_each()

		_assertions += case.assertions
		if case.failures.is_empty():
			_passed += 1
			print("  ok   %s (%d)" % [method_name, case.assertions])
		else:
			_failed += 1
			print("  FAIL %s (%d)" % [method_name, case.assertions])
			for failure: String in case.failures:
				_failure_lines.append("  %s :: %s\n      %s" % [path.get_file(), method_name, failure])


func _discover(filter: String) -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(TESTS_DIR)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("test_") and entry.ends_with(".gd") and entry != "test_case.gd" \
				and (filter == "" or entry.contains(filter)):
			files.append(TESTS_DIR.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files
