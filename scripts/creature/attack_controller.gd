class_name AttackController
extends Node

## Owns the attacks an assembly grants and, from M4, the
## windup → active → recovery → cooldown machine that arms their damage boxes.
##
## At M1 it holds the definitions and guarantees the invariant that matters from
## day one: no damage box is ever live outside an attack (Mandate B5). The phase
## machine itself lands in M4.

signal attack_started(action: String)
signal attack_phase_changed(action: String, phase: String)
signal attack_finished(action: String)

var stats: CreatureStats = null

var _hitbox_root: HitboxRoot = null


func setup(hitbox_root: HitboxRoot) -> void:
	_hitbox_root = hitbox_root


func apply_stats(new_stats: CreatureStats) -> void:
	stats = new_stats
	disarm_all()


## Which input actions this assembly actually answers to. An empty attack slot
## leaves its button inert rather than substituting a default (DESIGN §4.2).
func armed_actions() -> PackedStringArray:
	if stats == null:
		return PackedStringArray()
	var actions: PackedStringArray = PackedStringArray(stats.attacks.keys())
	actions.sort()
	return actions


func has_attack(action: String) -> bool:
	return stats != null and stats.attacks.has(action)


## Attack power of the part wired to `action`, or 0 when the slot is empty.
func attack_power(action: String) -> float:
	return float(stats.attack_for(action).get("attack_power", 0.0)) if has_attack(action) else 0.0


## Timing block (windup/active/recovery/cooldown/knockback/hitstun) from the part.
func timings(action: String) -> Dictionary:
	return stats.attack_for(action).get("attack", {}) as Dictionary if has_attack(action) else {}


func slot_for(action: String) -> String:
	return str(stats.attack_for(action).get("slot", "")) if has_attack(action) else ""


## Put every damage box back to sleep. Called on assembly, on death, and at the
## end of every attack.
func disarm_all() -> void:
	if _hitbox_root == null:
		return
	for box: Hitbox in _hitbox_root.damage_boxes():
		box.set_enabled(false)
