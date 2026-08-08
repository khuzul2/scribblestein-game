class_name PlayerInput
extends Node

## Reads the InputMap into a `MovementIntent` (TECH_SPEC §5).
##
## This node is the *only* difference between the player and an enemy
## (Mandate B2) — swap it for `AIBrain` and the same creature fights back.
## It runs at a negative physics priority so the intent is always fresh before
## `Locomotion` consumes it: input to movement within one tick (Mandate B6).

const PRIORITY: int = -10

@export var enabled: bool = true

var creature: Creature = null
var locomotion: Locomotion = null


func _ready() -> void:
	creature = get_parent() as Creature
	locomotion = creature.get_node_or_null("Locomotion") as Locomotion
	process_physics_priority = PRIORITY
	set_physics_process(enabled and creature.is_player)


func _physics_process(_delta: float) -> void:
	if locomotion == null:
		return
	var intent: MovementIntent = locomotion.intent
	intent.move_axis = Input.get_axis("move_left", "move_right")
	intent.jump_held = Input.is_action_pressed("jump_glide")
	intent.climb_held = Input.is_action_pressed("climb_up")
	intent.crouch_held = Input.is_action_pressed("crouch_roll")
	if Input.is_action_just_pressed("jump_glide"):
		intent.jump_pressed = true
	if Input.is_action_just_pressed("crouch_roll"):
		intent.crouch_pressed = true

	if creature.attack_controller.has_attack("attack_primary") \
			and Input.is_action_just_pressed("attack_primary"):
		creature.attack_controller.request("attack_primary")
	if creature.attack_controller.has_attack("attack_secondary") \
			and Input.is_action_just_pressed("attack_secondary"):
		creature.attack_controller.request("attack_secondary")


## Turn player control on or off — used by the Lab, by cutscene-free transitions,
## and by tests that drive the intent themselves.
func set_enabled(value: bool) -> void:
	enabled = value
	set_physics_process(value and creature != null and creature.is_player)
	if not value and locomotion != null:
		locomotion.intent.clear()
