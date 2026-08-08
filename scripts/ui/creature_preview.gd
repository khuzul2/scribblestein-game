class_name CreaturePreview
extends SubViewportContainer

## A live, assembled creature rendered inside the sketchbook (DESIGN §11).
##
## It is the real `creature.tscn` running the real assembly pipeline — not an
## illustration — so what the right page shows is literally what the Scratchpad
## will spawn. Physics, input and the camera are switched off; only the rig is.

const PREVIEW_SIZE: Vector2i = Vector2i(620, 700)
## Where the creature's feet stand inside the preview viewport.
const STAND_POINT: Vector2i = Vector2i(310, 640)

var creature: Creature = null

var _viewport: SubViewport = null


func _ready() -> void:
	# No stretching, and nearest sampling on the way out: rescaling a viewport
	# blends its pixels, and a blend between ink and paper is a grey — which
	# Mandate A1 forbids anywhere on screen.
	stretch = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(PREVIEW_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport = SubViewport.new()
	_viewport.size = PREVIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.canvas_item_default_texture_filter = \
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The preview must never step the world; it is a mannequin, not a creature.
	_viewport.physics_object_picking = false
	add_child(_viewport)

	creature = (load(CreaturePreviewScene.PATH) as PackedScene).instantiate() as Creature
	creature.is_player = false
	creature.position = Vector2(STAND_POINT)
	_viewport.add_child(creature)

	creature.locomotion.set_physics_process(false)
	creature.player_input.set_enabled(false)
	creature.set_physics_process(false)
	creature.camera.enabled = false


## Rebuild the mannequin. Rejected loadouts leave the previous pose standing.
func show_loadout(loadout: Dictionary) -> PackedStringArray:
	return creature.assemble(loadout)


func show_hitboxes(visible_boxes: bool) -> void:
	creature.hitbox_root.draw_debug = visible_boxes


## Scale the mannequin so any build fits the page, using the same bounding-box
## measurement the real camera zooms off.
func fit() -> void:
	var height: float = creature.visual_height()
	if height <= 0.0:
		return
	# Quantised so the mannequin is only ever drawn at a clean fraction; an
	# arbitrary scale would land ink on half-pixels.
	var scale_factor: float = snappedf(
		clampf(float(PREVIEW_SIZE.y - 80) / height, 0.25, 1.0), 0.25)
	creature.scale = Vector2(scale_factor, scale_factor)


class CreaturePreviewScene:
	const PATH: String = "res://scenes/creature/creature.tscn"
