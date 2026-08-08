class_name Lab
extends Control

## The Lab — the hub (Decision 1, DESIGN §3, §11).
##
## It holds the three stations the loop needs: the sketchbook editor, the unlock
## desk, and the world map table. "Play in Lab" hands off to the Scratchpad and
## comes straight back, which is the round trip DESIGN §11 asks to stay under
## three seconds.
##
## Rebuilding the creature is possible *only here*. Entering a level from the map
## is a loadout commitment.

signal level_requested(level_id: String)
signal scratchpad_requested

const SCRATCHPAD_LEVEL_ID: String = "scratchpad"

var editor: SketchbookEditor = null
var unlock_desk: UnlockDesk = null
var world_map: WorldMap = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Audio.music("mus_lab_loop")

	editor = SketchbookEditor.new()
	editor.name = "SketchbookEditor"
	add_child(editor)
	editor.play_requested.connect(_on_play_requested)
	editor.unlock_requested.connect(_show.bind("unlock"))
	editor.map_requested.connect(_show.bind("map"))

	unlock_desk = UnlockDesk.new()
	unlock_desk.name = "UnlockDesk"
	unlock_desk.visible = false
	add_child(unlock_desk)
	unlock_desk.closed.connect(_show.bind("editor"))
	unlock_desk.part_unlocked.connect(_on_part_unlocked)
	unlock_desk.blueprint_bought.connect(_on_blueprint_bought)

	world_map = WorldMap.new()
	world_map.name = "WorldMap"
	world_map.visible = false
	add_child(world_map)
	world_map.closed.connect(_show.bind("editor"))
	world_map.level_chosen.connect(_on_level_chosen)


func _show(station: String) -> void:
	editor.visible = station == "editor"
	unlock_desk.visible = station == "unlock"
	world_map.visible = station == "map"
	if station == "editor":
		editor.refresh()
	elif station == "unlock":
		unlock_desk.refresh()
	elif station == "map":
		world_map.refresh()


func _on_play_requested() -> void:
	scratchpad_requested.emit()


func _on_level_chosen(level_id: String) -> void:
	SaveManager.request_save()
	level_requested.emit(level_id)


## A freshly unlocked part should be pickable the moment you walk back to the
## sketchbook, without a reload.
func _on_part_unlocked(_part_id: String) -> void:
	editor.refresh()


## Buying a body type adds a tab to the sketchbook, which is part of the page's
## structure rather than its contents — so the whole editor is rebuilt.
func _on_blueprint_bought(blueprint_id: String) -> void:
	editor.switch_blueprint(blueprint_id)


## The loadout the player has committed to, for whatever scene comes next.
func current_loadout() -> Dictionary:
	return editor.loadout
