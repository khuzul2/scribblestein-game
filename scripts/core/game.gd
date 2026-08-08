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
		elif requested == "editor":
			goto_editor(str(DevTools.option("level")) if DevTools.has_option("level") else "")
		elif LevelData.find(requested) != "":
			goto_level(requested)
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
	lab.editor_requested.connect(goto_editor)


## Enter a level. A level file under `data/levels/` wins over a hand-coded
## scene, so porting a level to the editor's format is a matter of writing the
## file — and a level someone edits shadows the shipped copy without replacing
## it (`LevelData.find`).
func goto_level(level_id: String) -> void:
	var scene: PlayScene = null
	if LevelData.find(level_id) != "":
		var problems: PackedStringArray = PackedStringArray()
		var data_level: DataLevel = DataLevel.create(level_id, problems)
		if data_level == null:
			push_error("Cannot open level '%s': %s" % [level_id, ", ".join(problems)])
			return
		scene = await _transition_to_node(level_id, data_level) as PlayScene
	elif Config.levels.has(level_id):
		scene = await _transition_to(level_id, str(Config.level(level_id)["scene"])) as PlayScene
	else:
		push_error("No level '%s' — neither a level file nor an entry in data/levels.json"
			% level_id)
		return
	if scene == null:
		return
	scene.level_id = level_id
	scene.exit_requested.connect(func() -> void: goto_lab())


## Open the level editor. Playtesting from inside it enters the level for real
## and comes back here, so the round trip is one button each way.
func goto_editor(level_id: String = "") -> void:
	var editor: LevelEditor = LevelEditor.new()
	editor.name = "LevelEditor"
	var opened: LevelEditor = await _transition_to_node("editor", editor) as LevelEditor
	if opened == null:
		return
	if level_id != "":
		opened.open(level_id)
	opened.closed.connect(func() -> void: goto_lab())
	opened.playtest_requested.connect(func(level: LevelData) -> void:
		_playtest(level.id))


## Play a level from the editor, and return to the editor on the way out rather
## than to the Lab — a playtest is part of editing, not a trip to the hub.
func _playtest(level_id: String) -> void:
	var problems: PackedStringArray = PackedStringArray()
	var data_level: DataLevel = DataLevel.create(level_id, problems)
	if data_level == null:
		push_error("Cannot playtest '%s': %s" % [level_id, ", ".join(problems)])
		return
	var scene: PlayScene = await _transition_to_node(level_id, data_level) as PlayScene
	if scene == null:
		return
	scene.exit_requested.connect(func() -> void: goto_editor(level_id))


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


## Swap in a node built in code rather than loaded from a `.tscn` — which is
## what a data level and the editor are.
func _transition_to_node(scene_id: String, node: Node) -> Node:
	while _switching:
		await get_tree().process_frame
	_switching = true

	await _fade_to(1.0)
	_clear_current()

	_current = node
	scene_root.add_child(_current)
	current_scene_id = scene_id
	scene_changed.emit(scene_id)

	await _fade_to(0.0)
	_switching = false
	return _current


func _clear_current() -> void:
	if _current != null:
		scene_root.remove_child(_current)
		_current.queue_free()
		_current = null


func _transition_to(scene_id: String, path: String) -> Node:
	# Queue behind any transition already running rather than dropping the
	# request — a click during a fade should still take you where you asked.
	while _switching:
		await get_tree().process_frame
	_switching = true

	await _fade_to(1.0)

	_clear_current()

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
