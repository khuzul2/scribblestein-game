class_name Creature
extends CharacterBody2D

## The one creature scene, for the player and for every enemy (Mandate B2).
##
## The only difference between the two is which controller node is attached —
## `PlayerInput` or `AIBrain`. Damage, hitboxes, weight class, effects and the
## assembly pipeline are the same code for both, always.

signal assembled(stats: CreatureStats)
signal assembly_failed(problems: PackedStringArray)
signal facing_changed(facing: int)

## How far past the body box the climb sensor reaches, in pixels.
const CLIMB_SENSOR_MARGIN_PX: float = 6.0

@export var blueprint_id: String = "biped"
@export var is_player: bool = false

@onready var skeleton: Skeleton2D = $Skeleton2D
@onready var hitbox_root: HitboxRoot = $HitboxRoot
@onready var health: Health = $Health
@onready var attack_controller: AttackController = $AttackController
@onready var weight_class: WeightClass = $WeightClass
@onready var body_collider: CollisionShape2D = $BodyCollider
@onready var locomotion: Locomotion = $Locomotion
@onready var player_input: PlayerInput = $PlayerInput
@onready var camera: CreatureCamera = $CreatureCamera
@onready var climb_sensor: Area2D = $ClimbSensor

var stats: CreatureStats = CreatureStats.new()

## +1 faces right, -1 faces left. Flipping the skeleton takes the sprites *and*
## the bone-local hitboxes with it, so an attack always reaches where it looks.
var facing: int = 1:
	set(value):
		var normalised: int = 1 if value >= 0 else -1
		if normalised == facing:
			return
		facing = normalised
		if skeleton != null:
			skeleton.scale.x = float(facing)
		facing_changed.emit(facing)

var _visual_bounds: Rect2 = Rect2()
var _crouched: bool = false
## Where the feet sit while standing, in creature-local space. The crouch squash
## pivots on this so the soles never leave the floor.
var _standing_feet_y: float = 0.0


func _ready() -> void:
	collision_layer = Layers.body_layer(is_player)
	# Bodies collide with the world and with each other; they never carry damage
	# semantics (TECH_SPEC §4, Decision 4).
	collision_mask = Layers.mask([Layers.WORLD, Layers.WORLD_CRACKED,
		Layers.PLAYER_BODY, Layers.ENEMY_BODY])
	health.is_player = is_player
	attack_controller.setup(hitbox_root)
	climb_sensor.collision_layer = 0
	climb_sensor.collision_mask = Layers.bit(Layers.CLIMBABLE)
	health.died.connect(func() -> void: attack_controller.cancel())


## Build this creature from a loadout. Returns the problems found, empty on
## success. Callers that treat a failure as fatal should say so themselves — the
## Lab wants to show the message, a level wants to refuse to start.
func assemble(loadout: Dictionary, refill_health: bool = true) -> PackedStringArray:
	var problems: PackedStringArray = PartAssembler.assemble(self, loadout)
	if not problems.is_empty():
		for problem: String in problems:
			push_error("Assembly rejected: %s" % problem)
		assembly_failed.emit(problems)
		return problems
	if refill_health:
		health.set_maximum(stats.max_hp, true)
	return problems


## Called by the assembler once the rig is built. Also the seam an enemy uses to
## apply its `hp_override` (enemies.json) without touching the pipeline.
func apply_stats(new_stats: CreatureStats) -> void:
	stats = new_stats
	weight_class.apply(stats)
	attack_controller.apply_stats(stats)
	health.set_maximum(stats.max_hp, health.maximum <= 1.0)
	_fit_body_collider()
	_recompute_visual_bounds()
	skeleton.scale.x = float(facing)
	assembled.emit(stats)


func has_effect(effect_id: String) -> bool:
	return stats.has_effect(effect_id)


## Squash the whole rig vertically while crouching. Scaling the skeleton takes
## the sprites, the bone-local hurtboxes and (via the refit) the body collider
## with it in one move, which is exactly what `crouch.hurtbox_height_mult` asks
## for — and it reads as a cartoon squash, which suits a doodle.
##
## The squash pivots on the *feet*, not on the creature origin. Pivoting on the
## origin would lift the soles off the floor, the creature would read as airborne
## for a frame, crouch would drop, and the whole thing would chatter at 30 Hz.
func set_crouched(crouched: bool) -> void:
	if crouched == _crouched:
		return
	_crouched = crouched
	var squash: float = Config.cfg_float("movement.crouch.hurtbox_height_mult") \
		if crouched else 1.0
	skeleton.scale.y = squash
	skeleton.position.y = _standing_feet_y * (1.0 - squash)
	_fit_body_collider()
	_recompute_visual_bounds()


func is_crouched() -> bool:
	return _crouched


## Visual bounding box in creature-local space, recomputed on every assembly.
## The camera zooms off its height (Mandate A4, TECH_SPEC §6).
func visual_bounds() -> Rect2:
	return _visual_bounds


func visual_height() -> float:
	return _visual_bounds.size.y


# --- internals -----------------------------------------------------------------

## The body collider is derived from the union of the creature's hurtboxes, so a
## bigger anatomy really is a bigger obstacle — no authored capsule to forget.
func _fit_body_collider() -> void:
	var union: Rect2 = _union_of(hitbox_root.hurtboxes())
	if union.size == Vector2.ZERO:
		return
	var shape: RectangleShape2D = body_collider.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		body_collider.shape = shape
	shape.size = union.size
	body_collider.position = union.get_center()
	if not _crouched:
		_standing_feet_y = union.end.y
	_fit_climb_sensor(union)


## The climb sensor is the body box grown slightly outwards, so a creature that
## is *touching* a climbable wall registers it without needing to overlap.
func _fit_climb_sensor(union: Rect2) -> void:
	if climb_sensor == null:
		return
	var shape_node: CollisionShape2D = climb_sensor.get_node("CollisionShape2D") as CollisionShape2D
	var shape: RectangleShape2D = shape_node.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		shape_node.shape = shape
	shape.size = union.size + Vector2(CLIMB_SENSOR_MARGIN_PX * 2.0, 0.0)
	climb_sensor.position = union.get_center()


func _recompute_visual_bounds() -> void:
	var bounds: Rect2 = Rect2()
	var started: bool = false
	var to_local_space: Transform2D = global_transform.affine_inverse()

	for sprite: Sprite2D in _sprites():
		if sprite.texture == null:
			continue
		# Measure the *ink*, not the canvas: a part's transparent margin must not
		# inflate the box the camera zooms off (Mandate A4).
		var ink: Rect2i = _ink_rect(sprite.texture)
		var rect: Rect2 = Rect2(sprite.offset + Vector2(ink.position), Vector2(ink.size))
		var transform: Transform2D = to_local_space * sprite.global_transform
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y),
				rect.end, Vector2(rect.position.x, rect.end.y)]:
			var point: Vector2 = transform * corner
			if not started:
				bounds = Rect2(point, Vector2.ZERO)
				started = true
			else:
				bounds = bounds.expand(point)
	_visual_bounds = bounds


## Opaque bounds of a texture, cached per resource — decoding an image is far
## too slow to do on every assembly, and part textures never change at runtime.
static var _ink_rects: Dictionary = {}


static func _ink_rect(texture: Texture2D) -> Rect2i:
	var key: String = texture.resource_path
	if _ink_rects.has(key):
		return _ink_rects[key] as Rect2i
	var image: Image = texture.get_image()
	var rect: Rect2i = Rect2i(Vector2i.ZERO, texture.get_size())
	if image != null:
		var used: Rect2i = image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			rect = used
	_ink_rects[key] = rect
	return rect


func _sprites() -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	var queue: Array[Node] = [skeleton]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		for child: Node in node.get_children():
			if child is Sprite2D:
				found.append(child as Sprite2D)
			queue.append(child)
	return found


func _union_of(boxes: Array[Hitbox]) -> Rect2:
	var union: Rect2 = Rect2()
	var started: bool = false
	var to_local_space: Transform2D = global_transform.affine_inverse()
	for box: Hitbox in boxes:
		var extents: Vector2 = box.half_extents()
		var transform: Transform2D = to_local_space * box.global_transform
		for corner: Vector2 in [-extents, Vector2(extents.x, -extents.y),
				extents, Vector2(-extents.x, extents.y)]:
			var point: Vector2 = transform * corner
			if not started:
				union = Rect2(point, Vector2.ZERO)
				started = true
			else:
				union = union.expand(point)
	return union
