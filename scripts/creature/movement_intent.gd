class_name MovementIntent
extends RefCounted

## What a controller wants this tick. `PlayerInput` fills it from the InputMap,
## `AIBrain` fills it from its FSM, and `Locomotion` is the only thing that reads
## it — so the player and every enemy move through identical code (Mandate B2).

## -1 … +1. Analogue sticks pass through unrounded.
var move_axis: float = 0.0
## True on the tick `jump_glide` went down. Drives jumps and double jumps.
var jump_pressed: bool = false
## True while `jump_glide` is down. Drives gliding.
var jump_held: bool = false
## True while `climb_up` is down.
var climb_held: bool = false
## True on the tick `crouch_roll` went down. Starts a roll.
var crouch_pressed: bool = false
## True while `crouch_roll` is down. Holds a crouch.
var crouch_held: bool = false


func clear() -> void:
	move_axis = 0.0
	jump_pressed = false
	jump_held = false
	climb_held = false
	crouch_pressed = false
	crouch_held = false


## Everything a fresh press implies, without the axis — handy for one-shot tests
## and for AI that only ever taps.
func press_jump() -> void:
	jump_pressed = true
	jump_held = true
