extends Node

## Root of `scenes/main.tscn` — the process-wide scene router.
##
## Everything the player sees (Lab, Scratchpad, levels) is swapped in under
## `SceneRoot` rather than via `SceneTree.change_scene_to_file`, so autoloads,
## the pause layer and transition timing stay under our control. DESIGN §11
## requires the editor → Scratchpad round trip to feel instant, with no fade
## longer than 0.3 s, so the whole transition is budgeted here.

signal scene_changed(scene_id: String)

const LAB_SCENE: String = "res://scenes/lab/lab.tscn"
## Half the fade budget each way: out, swap, in (DESIGN §11).
const FADE_SECONDS: float = 0.12

## Dev-only scenes, addressed by `--scene=`. Levels come from `levels.json`.
const DEV_SCENES: Dictionary = {
	"rig_preview": "res://scenes/dev/rig_preview.tscn",
	"boil_probe": "res://scenes/dev/boil_probe.tscn",
}

@onready var scene_root: Node = $SceneRoot

var current_scene_id: String = ""

var _current: Node = null
var _fade: ColorRect = null
var _switching: bool = false


func _ready() -> void:
	if not Config.is_loaded:
		# Config already reported and terminated; do not paper over it.
		return
	print("Scribblestein booted — %d parts, %d blueprints, %d enemies, %d effects." % [
		Config.parts.size(), Config.blueprints.size(),
		Config.enemies.size(), Config.effects.size()])

	_build_fade_layer()

	if DevTools.has_option("scene"):
		var requested: String = str(DevTools.option("scene"))
		if DEV_SCENES.has(requested):
			goto(requested, str(DEV_SCENES[requested]))
		elif Config.levels.has(requested):
			goto_level(requested)
		elif requested == "lab":
			goto_lab()
		else:
			push_error("Unknown --scene='%s'. Known: %s, lab, %s" % [requested,
				", ".join(PackedStringArray(DEV_SCENES.keys())),
				", ".join(PackedStringArray(Config.levels.keys()))])
		return

	goto_lab()


# --- routing -------------------------------------------------------------------

func goto_lab() -> void:
	var lab: Lab = await _transition_to("lab", LAB_SCENE) as Lab
	if lab == null:
		return
	lab.scratchpad_requested.connect(func() -> void: goto_level(Lab.SCRATCHPAD_LEVEL_ID))
	lab.level_requested.connect(goto_level)


func goto_level(level_id: String) -> void:
	if not Config.levels.has(level_id):
		push_error("No level '%s' in data/levels.json" % level_id)
		return
	var scene_path: String = str(Config.level(level_id)["scene"])
	var scene: PlayScene = await _transition_to(level_id, scene_path) as PlayScene
	if scene == null:
		return
	scene.level_id = level_id
	scene.exit_requested.connect(func() -> void: goto_lab())


## Swap the active scene. `scene_id` is a stable key used by save data and the
## world map; `path` is the scene resource to instantiate.
func goto(scene_id: String, path: String) -> Node:
	return await _transition_to(scene_id, path)


func current_scene() -> Node:
	return _current


# --- transition ----------------------------------------------------------------

## True while a fade/swap/fade is in flight.
func is_busy() -> bool:
	return _switching


func _transition_to(scene_id: String, path: String) -> Node:
	# Queue behind any transition already running rather than dropping the
	# request — a click during a fade should still take you where you asked.
	while _switching:
		await get_tree().process_frame
	_switching = true

	await _fade_to(1.0)

	if _current != null:
		scene_root.remove_child(_current)
		_current.queue_free()
		_current = null

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Cannot load scene '%s' at %s" % [scene_id, path])
		_switching = false
		await _fade_to(0.0)
		return null

	_current = packed.instantiate()
	scene_root.add_child(_current)
	current_scene_id = scene_id
	scene_changed.emit(scene_id)

	await _fade_to(0.0)
	_switching = false
	return _current


func _fade_to(alpha: float) -> void:
	if _fade == null:
		return
	_fade.visible = alpha > 0.0 or _fade.color.a > 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_SECONDS)
	await tween.finished
	_fade.visible = alpha > 0.0


func _build_fade_layer() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Transition"
	layer.layer = 100
	add_child(layer)

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(Paper.PAPER, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	layer.add_child(_fade)
