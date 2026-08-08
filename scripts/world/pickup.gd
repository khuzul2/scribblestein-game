class_name Pickup
extends Area2D

## Base for everything the player can pick up: ink, Correction Fluid, Blueprint
## Sketches and the death blob.
##
## All of them sit on the `pickup` physics layer and watch for the player's body,
## so nothing about collecting goes through the damage system.

signal collected(by: Creature)

## Seconds before this pickup gives up and vanishes; <= 0 means it waits forever.
@export var despawn_seconds: float = 0.0
## Pixels per second the pickup drifts towards a nearby player. 0 disables it.
@export var magnet_speed: float = 0.0
## How close the player must be for the magnet to take hold.
@export var magnet_radius: float = 0.0

var _collected: bool = false
var _age: float = 0.0
var _player: Creature = null


func _ready() -> void:
	collision_layer = Layers.bit(Layers.PICKUP)
	collision_mask = Layers.bit(Layers.PLAYER_BODY)
	monitoring = true
	body_entered.connect(_on_body_entered)
	_build_visual()


func _physics_process(delta: float) -> void:
	if _collected:
		return
	_age += delta
	if despawn_seconds > 0.0 and _age >= despawn_seconds:
		_expire()
		return
	if magnet_speed > 0.0:
		_seek_player(delta)


## Subclass hook: what actually happens on contact. Return false to refuse the
## pickup (the blob refuses nothing; a full-health player refuses healing).
func _collect(_by: Creature) -> bool:
	return true


## Subclass hook: the sprite. Kept separate so a subclass can pick its texture
## without repeating the Area2D plumbing.
func _texture_path() -> String:
	return "res://assets/fx/fx_ink_drop.png"


func _radius() -> float:
	return 24.0


func _build_visual() -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load(_texture_path()) as Texture2D
	add_child(sprite)

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = _radius()
	shape_node.shape = shape
	add_child(shape_node)


func _seek_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return
	var offset: Vector2 = _player.global_position + Vector2(0, -120.0) - global_position
	if offset.length() > magnet_radius:
		return
	global_position += offset.normalized() * magnet_speed * delta


func _find_player() -> Creature:
	for node: Node in get_tree().get_nodes_in_group("player"):
		if node is Creature:
			return node as Creature
	return null


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	var creature: Creature = body as Creature
	if creature == null or not creature.is_player or creature.health.is_dead():
		return
	if not _collect(creature):
		return
	_collected = true
	collected.emit(creature)
	queue_free()


func _expire() -> void:
	_collected = true
	queue_free()
