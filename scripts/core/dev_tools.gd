extends Node

## Autoload `DevTools` — command-line driven capture and scripted boot, so the
## visual acceptance criteria can be checked by a machine instead of by eye.
##
##   godot --rendering-driver opengl3 -- --shot=user://shot.png
##   godot --rendering-driver opengl3 -- --shot=user://boil --shot-count=60 --shot-stride=1
##   godot --rendering-driver opengl3 -- --scene=scratchpad --quit-after=3
##
## On a headless machine, wrap the command in `xvfb-run -a`; the dummy renderer
## `--headless` uses cannot produce a frame to grab.
##
## Everything here is inert unless a flag asks for it, so it costs a normal run
## nothing but one dictionary parse at boot.

## Emitted once the requested captures are done, before the run quits.
signal captures_finished(paths: PackedStringArray)

const DEFAULT_WARMUP_FRAMES: int = 12

var options: Dictionary = {}
var captured: PackedStringArray = PackedStringArray()

## Accumulated process delta — the same clock a shader's `TIME` runs on. It is
## neither the wall clock (which races ahead when a frame takes a long time to
## encode) nor the frame count (which says nothing about pacing), and using
## either of those instead makes a boil-rate measurement meaningless.
var engine_time: float = 0.0


func _process(delta: float) -> void:
	engine_time += delta


func _ready() -> void:
	options = parse(OS.get_cmdline_user_args())
	if options.has("scene"):
		# Applied by Game once it is in the tree; stored here so both agree.
		print("DevTools: boot scene override -> %s" % options["scene"])
	if options.has("shot"):
		_run_capture.call_deferred()
	elif options.has("quit-after"):
		_quit_after(float(options["quit-after"]))


## `--flag=value` and bare `--flag` (which becomes true).
static func parse(arguments: PackedStringArray) -> Dictionary:
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


func option(key: String, fallback: Variant = null) -> Variant:
	return options.get(key, fallback)


func has_option(key: String) -> bool:
	return options.has(key)


## Grab the current frame. Returns the path written, or "" on failure.
func capture(path: String) -> String:
	await RenderingServer.frame_post_draw
	var viewport: Viewport = get_viewport()
	if viewport == null:
		push_error("DevTools: no viewport to capture")
		return ""
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		push_error("DevTools: the renderer produced no image — is this a headless run?")
		return ""
	var directory: String = path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	if image.save_png(path) != OK:
		push_error("DevTools: could not write %s" % path)
		return ""
	return path


func _run_capture() -> void:
	var target: String = str(options["shot"])
	var count: int = int(options.get("shot-count", 1))
	var stride: int = maxi(1, int(options.get("shot-stride", 1)))
	var warmup: int = int(options.get("shot-after", DEFAULT_WARMUP_FRAMES))

	for _i: int in range(warmup):
		await get_tree().process_frame

	# Encoding a PNG takes longer than a frame, so captures are not evenly spaced.
	# Stamp each with the engine clock the shader itself reads, so a rate measured
	# against these stamps is exactly what the shader did.
	var stamps: Array[int] = []

	for index: int in range(count):
		var path: String = target if count == 1 else "%s_%03d.png" % [target, index]
		stamps.append(int(engine_time * 1000000.0))
		var written: String = await capture(path)
		if written != "":
			captured.append(written)
			print("DevTools: captured %s" % ProjectSettings.globalize_path(written))
		for _s: int in range(stride - 1):
			await get_tree().process_frame

	if count > 1:
		_write_frame_manifest(target, stamps)

	captures_finished.emit(captured)
	if not options.has("keep-running"):
		get_tree().quit(0)


## When each capture was taken, in microseconds, so a verifier can turn a count
## of image changes into a rate per second of the same clock the shader reads.
func _write_frame_manifest(target: String, stamps: Array[int]) -> void:
	var file: FileAccess = FileAccess.open("%s_frames.json" % target, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"stamps_usec": stamps}))
	file.close()


func _quit_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	get_tree().quit(0)
