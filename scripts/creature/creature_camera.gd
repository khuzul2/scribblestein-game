class_name CreatureCamera
extends Camera2D

## Dynamic framing (Mandate A4, TECH_SPEC §6).
##
##     target = clamp(REF_HEIGHT / bbox, ZOOM_MIN, ZOOM_MAX)
##     zoom   = lerp(zoom, target, CAMERA_LERP * delta)
##
## `bbox` is the assembled creature's visual bounding-box *height*, recomputed on
## every assembly — a big creature pulls the camera out, a tiny one pulls it in.
## The zoom is lerped and never snapped, and it is never quantised by the boil:
## the line boil is strictly a texture effect (Mandate A3).

var creature: Creature = null

var _target_zoom: float = 1.0


func _ready() -> void:
	creature = get_parent() as Creature
	if creature == null:
		return
	enabled = creature.is_player
	set_process(creature.is_player)
	if not creature.is_player:
		return

	position_smoothing_enabled = true
	position_smoothing_speed = Config.cfg_float("camera.lerp_speed") * 2.0
	var margin: Vector2 = Config.cfg_vec2("camera.drag_margin")
	drag_horizontal_enabled = true
	drag_vertical_enabled = true
	drag_left_margin = margin.x
	drag_right_margin = margin.x
	drag_top_margin = margin.y
	drag_bottom_margin = margin.y

	creature.assembled.connect(_on_assembled)
	if creature.visual_height() > 0.0:
		_on_assembled(creature.stats)
		snap_to_target()


func _process(delta: float) -> void:
	var lerp_speed: float = Config.cfg_float("camera.lerp_speed")
	var factor: float = clampf(lerp_speed * delta, 0.0, 1.0)
	var level: float = lerpf(zoom.x, _target_zoom, factor)
	zoom = Vector2(level, level)

	# Look-ahead in the facing direction, eased rather than snapped.
	var lookahead: float = Config.cfg_float("camera.lookahead_px") * float(creature.facing)
	offset.x = lerpf(offset.x, lookahead, factor)


## The zoom the formula asks for, given the creature currently assembled.
func target_zoom() -> float:
	return _target_zoom


## Skip the lerp — used when entering a scene, so the first frame is framed right.
func snap_to_target() -> void:
	zoom = Vector2(_target_zoom, _target_zoom)
	offset.x = Config.cfg_float("camera.lookahead_px") * float(creature.facing)
	reset_smoothing()


## The formula, isolated so tests can assert against it directly.
static func zoom_for_height(bbox_height: float) -> float:
	if bbox_height <= 0.0:
		return Config.cfg_float("camera.zoom_max")
	return clampf(Config.cfg_float("camera.ref_height") / bbox_height,
		Config.cfg_float("camera.zoom_min"), Config.cfg_float("camera.zoom_max"))


func _on_assembled(_stats: CreatureStats) -> void:
	_target_zoom = zoom_for_height(creature.visual_height())
