class_name CrackedFloor
extends StaticBody2D

## A floor tile only a Heavy creature can stomp through (DESIGN §5, §9).
##
## It sits on the `world_cracked` physics layer so every creature can stand on
## it; what breaks it is the landing itself — `Locomotion` checks the lander's
## weight class and fall speed against that class' `crack_break_min_land_speed`.
## Light and Medium creatures never break it, however far they fall.
##
## Levels restore their cracked floors on restart, so a secret stays a secret
## only until the run that opens it.

signal shattered(by: Node)

## Level-unique id, so a level can restore its floors after a restart.
@export var floor_id: String = ""

var is_broken: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collider: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	LineBoil.apply(_sprite)
	collision_layer = Layers.bit(Layers.WORLD_CRACKED)
	collision_mask = 0
	add_to_group("cracked_floors")


## Break it. Safe to call twice; only the first call does anything.
func shatter(by: Node = null) -> void:
	if is_broken:
		return
	is_broken = true
	_collider.set_deferred("disabled", true)
	_sprite.visible = false
	shattered.emit(by)


func restore() -> void:
	is_broken = false
	_collider.set_deferred("disabled", false)
	_sprite.visible = true
