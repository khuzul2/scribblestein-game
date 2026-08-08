class_name Hitbox
extends Area2D

## One Area2D generated from a `hitboxes[]` entry in `parts_db.json`.
##
## Hitboxes are children of the `Bone2D` they belong to, so their transform *is*
## bone-local and they rotate with the bone for free (Mandate B4). Nothing about
## their shape or placement exists outside the JSON.
##
## `damage` boxes are created disabled and are only ever enabled by
## `AttackController` during an attack's active window (Mandate B5). `hurtbox`
## boxes are live from birth, minus i-frames.

const TYPE_DAMAGE: String = "damage"
const TYPE_HURTBOX: String = "hurtbox"

## Which part authored this box, for debug readouts and damage attribution.
var part_id: String = ""
var slot: String = ""
var hitbox_type: String = TYPE_HURTBOX
## The raw JSON entry, kept so the debug overlay can prove the shape matches it.
var source: Dictionary = {}

var _shape_node: CollisionShape2D = null


## Build from one JSON hitbox entry. `is_player` picks the physics layers.
static func create(entry: Dictionary, owning_part_id: String, owning_slot: String,
		is_player: bool) -> Hitbox:
	var box: Hitbox = Hitbox.new()
	box.part_id = owning_part_id
	box.slot = owning_slot
	box.hitbox_type = str(entry.get("type", TYPE_HURTBOX))
	box.source = entry
	box.name = "%s_%s_%s" % [box.hitbox_type.capitalize(), owning_slot, owning_part_id]

	var offset: Array = entry.get("offset", [0, 0]) as Array
	box.position = Vector2(float(offset[0]), float(offset[1]))

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	shape_node.name = "Shape"
	shape_node.shape = _build_shape(entry)
	box.add_child(shape_node)
	box._shape_node = shape_node

	box.monitorable = true
	if box.hitbox_type == TYPE_DAMAGE:
		box.collision_layer = Layers.damage_layer(is_player)
		box.collision_mask = Layers.damage_mask(is_player)
		# Mandate B5: dormant until an attack's active phase says otherwise.
		box.set_enabled(false)
	else:
		box.collision_layer = Layers.hurtbox_layer(is_player)
		box.collision_mask = Layers.hurtbox_mask(is_player)
		box.monitoring = false  # a hurtbox is *seen*; it does not scan
		box.set_enabled(true)
	return box


static func _build_shape(entry: Dictionary) -> Shape2D:
	if str(entry.get("shape", "")) == "circle":
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = float(entry["radius"])
		return circle
	var extents: Array = entry["extents"] as Array
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	# parts_db stores half-extents; RectangleShape2D wants the full size.
	rectangle.size = Vector2(float(extents[0]) * 2.0, float(extents[1]) * 2.0)
	return rectangle


## Turn the box on or off without reparenting or freeing it.
##
## Applied immediately rather than deferred, so `is_enabled()` and the debug
## overlay always agree with reality within the same tick — which is what makes
## the attack-window rule testable. Only ever called from `_physics_process` and
## from assembly, never from inside a physics query callback.
func set_enabled(enabled: bool) -> void:
	if _shape_node == null:
		return
	_shape_node.disabled = not enabled
	if hitbox_type == TYPE_DAMAGE:
		monitoring = enabled


func is_enabled() -> bool:
	return _shape_node != null and not _shape_node.disabled


## Half-extents for a rectangle, or (radius, radius) for a circle — used by the
## debug overlay and the body-collider fit.
func half_extents() -> Vector2:
	if source.get("shape", "") == "circle":
		var radius: float = float(source["radius"])
		return Vector2(radius, radius)
	var extents: Array = source["extents"] as Array
	return Vector2(float(extents[0]), float(extents[1]))
