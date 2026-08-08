extends Node

## Root of `scenes/main.tscn` — the process-wide scene router.
##
## Everything the player sees (Lab, Scratchpad, levels) is swapped in under
## `SceneRoot` rather than via `SceneTree.change_scene_to_file`, so autoloads,
## the pause layer and transition timing stay under our control (DESIGN §11
## requires the editor -> Scratchpad round trip to fade in under 0.3 s).

signal scene_changed(scene_id: String)

## Stable scene ids -> resources. Save data, the world map and `--scene=` all
## address scenes by id, never by path.
const SCENES: Dictionary = {
	"rig_preview": "res://scenes/dev/rig_preview.tscn",
}

@onready var scene_root: Node = $SceneRoot

var current_scene_id: String = ""

var _current: Node = null


func _ready() -> void:
	if not Config.is_loaded:
		# Config already reported and terminated; do not paper over it.
		return
	print("Scribblestein booted — %d parts, %d blueprints, %d enemies, %d effects." % [
		Config.parts.size(), Config.blueprints.size(),
		Config.enemies.size(), Config.effects.size()])

	if DevTools.has_option("scene"):
		var requested: String = str(DevTools.option("scene"))
		if SCENES.has(requested):
			goto(requested, str(SCENES[requested]))
		else:
			push_error("Unknown --scene='%s'. Known: %s"
				% [requested, ", ".join(PackedStringArray(SCENES.keys()))])


## Swap the active scene. `scene_id` is a stable key used by save data and the
## world map; `path` is the scene resource to instantiate.
func goto(scene_id: String, path: String) -> Node:
	if _current != null:
		_current.queue_free()
		scene_root.remove_child(_current)
		_current = null

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Cannot load scene '%s' at %s" % [scene_id, path])
		return null

	_current = packed.instantiate()
	scene_root.add_child(_current)
	current_scene_id = scene_id
	scene_changed.emit(scene_id)
	return _current


func current_scene() -> Node:
	return _current
