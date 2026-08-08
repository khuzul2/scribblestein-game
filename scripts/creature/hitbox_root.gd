class_name HitboxRoot
extends Node2D

## Registry and controller for every `Hitbox` a creature owns, plus the debug
## overlay that draws them.
##
## The Area2Ds themselves are children of the `Bone2D` they belong to — that is
## what makes their transform bone-local and makes them rotate with the bone
## (Mandate B4), exactly as TECH_SPEC §3 asks ("parented to follow their bone
## transform"). This node owns them logically: it is the single place that may
## flip a damage box on or off, which is how Mandate B5 stays enforceable.

signal hitboxes_rebuilt

## Set true to draw every hitbox. Development aid only — never on in gameplay,
## so the M6 "screenshot contains only palette colours" criterion is unaffected.
@export var draw_debug: bool = false:
	set(value):
		draw_debug = value
		queue_redraw()

var _boxes: Array[Hitbox] = []


func _process(_delta: float) -> void:
	if draw_debug:
		queue_redraw()


func register(box: Hitbox) -> void:
	_boxes.append(box)


func clear() -> void:
	for box: Hitbox in _boxes:
		if is_instance_valid(box):
			box.queue_free()
	_boxes.clear()


func finish_rebuild() -> void:
	hitboxes_rebuilt.emit()
	queue_redraw()


func all() -> Array[Hitbox]:
	return _boxes.duplicate()


func hurtboxes() -> Array[Hitbox]:
	return _boxes.filter(func(box: Hitbox) -> bool: return box.hitbox_type == Hitbox.TYPE_HURTBOX)


func damage_boxes() -> Array[Hitbox]:
	return _boxes.filter(func(box: Hitbox) -> bool: return box.hitbox_type == Hitbox.TYPE_DAMAGE)


## Damage boxes contributed by one slot — the granularity an attack acts on,
## since each attack slot owns exactly one part.
func damage_boxes_for_slot(slot: String) -> Array[Hitbox]:
	return damage_boxes().filter(func(box: Hitbox) -> bool: return box.slot == slot)


## The only sanctioned way to arm a damage box (Mandate B5).
func set_damage_enabled(slot: String, enabled: bool) -> void:
	for box: Hitbox in damage_boxes_for_slot(slot):
		box.set_enabled(enabled)


func set_hurtboxes_enabled(enabled: bool) -> void:
	for box: Hitbox in hurtboxes():
		box.set_enabled(enabled)


## True when no damage box anywhere on this creature is live. Used by tests to
## prove the attack-window rule holds.
func all_damage_boxes_dormant() -> bool:
	for box: Hitbox in damage_boxes():
		if box.is_enabled():
			return false
	return true


func _draw() -> void:
	if not draw_debug:
		return
	var to_local_space: Transform2D = global_transform.affine_inverse()
	for box: Hitbox in _boxes:
		if not is_instance_valid(box):
			continue
		var transform: Transform2D = to_local_space * box.global_transform
		var colour: Color = _colour_for(box)
		var extents: Vector2 = box.half_extents()

		if str(box.source.get("shape", "")) == "circle":
			draw_set_transform_matrix(transform)
			draw_circle(Vector2.ZERO, extents.x, colour, false, 3.0)
		else:
			draw_set_transform_matrix(transform)
			draw_rect(Rect2(-extents, extents * 2.0), colour, false, 3.0)
		# A tick at the box origin proves the JSON offset landed where it should.
		draw_line(Vector2(-6, 0), Vector2(6, 0), colour, 2.0)
		draw_line(Vector2(0, -6), Vector2(0, 6), colour, 2.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _colour_for(box: Hitbox) -> Color:
	if box.hitbox_type == Hitbox.TYPE_HURTBOX:
		return Color(0.2, 0.6, 1.0, 0.9) if box.is_enabled() else Color(0.2, 0.6, 1.0, 0.25)
	return Color(1.0, 0.2, 0.2, 1.0) if box.is_enabled() else Color(1.0, 0.2, 0.2, 0.22)
