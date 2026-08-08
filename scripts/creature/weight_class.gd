class_name WeightClass
extends Node

## Buckets `Σ part.weight` into Light / Medium / Heavy and exposes that class'
## full movement preset (Decision 2, DESIGN §5).
##
## Every number comes from `game_config.json → movement.weight_classes`; the
## class boundaries are the `max_total_weight` fields, so re-tuning the bands is
## a data edit. Part modifiers multiply on top per `modifier_rules`.

signal class_changed(class_id: String)

## Ordered lightest-first; the first class whose `max_total_weight` the creature
## does not exceed wins.
const ORDER: Array[String] = ["light", "medium", "heavy"]

var class_id: String = "medium"
var total_weight: float = 0.0
var speed_mod: float = 1.0
var jump_mod: float = 1.0


func apply(stats: CreatureStats) -> void:
	total_weight = stats.total_weight
	speed_mod = stats.speed_mod
	jump_mod = stats.jump_mod
	var new_class: String = class_for_weight(total_weight)
	if new_class != class_id:
		class_id = new_class
		class_changed.emit(class_id)
	else:
		class_id = new_class


static func class_for_weight(weight: float) -> String:
	for candidate: String in ORDER:
		if weight <= Config.cfg_float("movement.weight_classes.%s.max_total_weight" % candidate):
			return candidate
	return ORDER[ORDER.size() - 1]


## The whole preset dictionary for the current class.
func preset() -> Dictionary:
	return Config.cfg("movement.weight_classes.%s" % class_id) as Dictionary


func preset_float(key: String) -> float:
	return Config.cfg_float("movement.weight_classes.%s.%s" % [class_id, key])


## `class.max_speed * product(part.speed_mod)` (game_config → modifier_rules).
func max_speed() -> float:
	return preset_float("max_speed") * speed_mod


## `class.jump_velocity * product(part.jump_mod)`. Negative — up is -Y.
func jump_velocity() -> float:
	return preset_float("jump_velocity") * jump_mod


func acceleration() -> float:
	return preset_float("accel")


func deceleration() -> float:
	return preset_float("decel")


func air_control() -> float:
	return preset_float("air_control")


func knockback_taken_mult() -> float:
	return preset_float("knockback_taken_mult")


## Heavy alone stomps through cracked floors, and only above a landing speed
## (DESIGN §5, §9 — this is a level-design key).
func breaks_cracked_floors() -> bool:
	return bool(preset().get("breaks_cracked_floors", false))


func crack_break_min_land_speed() -> float:
	return float(preset().get("crack_break_min_land_speed", INF))


## "L" / "M" / "H" for the Lab's scribbled class stamp.
func stamp() -> String:
	return class_id.substr(0, 1).to_upper()
