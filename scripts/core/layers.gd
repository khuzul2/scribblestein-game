class_name Layers
extends RefCounted

## Physics layer numbers from TECH_SPEC §4, mirrored from `project.godot`.
##
## These are engine wiring, not balance, so they live in code — but
## `tests/test_layers.gd` asserts that every constant still matches the layer
## name registered in the project settings, so the two can never drift.

const WORLD: int = 1
const WORLD_CRACKED: int = 2
const CLIMBABLE: int = 3
const PLAYER_BODY: int = 4
const ENEMY_BODY: int = 5
const PLAYER_HURTBOX: int = 6
const ENEMY_HURTBOX: int = 7
const PLAYER_DAMAGE: int = 8
const ENEMY_DAMAGE: int = 9
const PICKUP: int = 10
const HAZARD: int = 11

## Layer number -> the name it must carry in project.godot.
const NAMES: Dictionary = {
	1: "world", 2: "world_cracked", 3: "climbable", 4: "player_body",
	5: "enemy_body", 6: "player_hurtbox", 7: "enemy_hurtbox",
	8: "player_damage", 9: "enemy_damage", 10: "pickup", 11: "hazard",
}


## Bitmask for a set of layer numbers: `Layers.mask([Layers.WORLD, Layers.HAZARD])`.
static func mask(layer_numbers: Array[int]) -> int:
	var bits: int = 0
	for number: int in layer_numbers:
		bits |= 1 << (number - 1)
	return bits


static func bit(layer_number: int) -> int:
	return 1 << (layer_number - 1)


## The layer a creature's body occupies.
static func body_layer(is_player: bool) -> int:
	return bit(PLAYER_BODY) if is_player else bit(ENEMY_BODY)


## The layer a creature's hurtboxes sit on, so the other side's damage boxes see them.
static func hurtbox_layer(is_player: bool) -> int:
	return bit(PLAYER_HURTBOX) if is_player else bit(ENEMY_HURTBOX)


## The layer a creature's damage boxes sit on.
static func damage_layer(is_player: bool) -> int:
	return bit(PLAYER_DAMAGE) if is_player else bit(ENEMY_DAMAGE)


## What a damage box scans for: the opposing side's hurtboxes only. Bodies push,
## they never hurt (Decision 4).
static func damage_mask(is_player: bool) -> int:
	return bit(ENEMY_HURTBOX) if is_player else bit(PLAYER_HURTBOX)


## What a hurtbox scans for: the opposing side's damage boxes, plus environment
## hazards, which are exempt from the attack-window rule (Mandate B5).
static func hurtbox_mask(is_player: bool) -> int:
	return (bit(ENEMY_DAMAGE) if is_player else bit(PLAYER_DAMAGE)) | bit(HAZARD)
