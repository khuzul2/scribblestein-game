class_name AttackController
extends Node

## Owns the attacks an assembly grants and the
## windup → active → recovery → cooldown machine that arms their damage boxes.
##
## Every duration comes from the attacking part's own `attack` block in
## `parts_db.json`; nothing here is timed by a literal. The single invariant this
## class exists to hold: a damage box is live during the ACTIVE phase and at no
## other moment (Mandate B5).

signal attack_started(action: String)
signal attack_phase_changed(action: String, phase: Phase)
signal attack_finished(action: String)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY, COOLDOWN }

var stats: CreatureStats = null
var phase: Phase = Phase.IDLE
var current_action: String = ""

var _hitbox_root: HitboxRoot = null
var _phase_remaining: float = 0.0


func setup(hitbox_root: HitboxRoot) -> void:
	_hitbox_root = hitbox_root


func _physics_process(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	_phase_remaining -= delta
	while _phase_remaining <= 0.0 and phase != Phase.IDLE:
		var overshoot: float = -_phase_remaining
		_advance()
		_phase_remaining -= overshoot


## Begin an attack, if this assembly has one on that button and nothing is
## already running. Returns true when the attack actually starts.
func request(action: String) -> bool:
	if not has_attack(action) or phase != Phase.IDLE:
		return false
	current_action = action
	_enter(Phase.WINDUP)
	attack_started.emit(action)
	return true


## Cut an attack short — death, or a hit that interrupts. Always disarms.
func cancel() -> void:
	if phase == Phase.IDLE:
		return
	var action: String = current_action
	_leave_active()
	phase = Phase.IDLE
	current_action = ""
	_phase_remaining = 0.0
	attack_finished.emit(action)


func is_attacking() -> bool:
	return phase == Phase.WINDUP or phase == Phase.ACTIVE or phase == Phase.RECOVERY


## True only during the window in which damage may be dealt.
func is_active() -> bool:
	return phase == Phase.ACTIVE


func phase_name() -> String:
	return Phase.keys()[phase]


func _advance() -> void:
	match phase:
		Phase.WINDUP:
			_enter(Phase.ACTIVE)
		Phase.ACTIVE:
			_leave_active()
			_enter(Phase.RECOVERY)
		Phase.RECOVERY:
			_enter(Phase.COOLDOWN)
		Phase.COOLDOWN:
			var action: String = current_action
			phase = Phase.IDLE
			current_action = ""
			attack_phase_changed.emit(action, Phase.IDLE)
			attack_finished.emit(action)


func _enter(next: Phase) -> void:
	phase = next
	_phase_remaining = _duration_of(next)
	if next == Phase.ACTIVE:
		_hitbox_root.set_damage_enabled(slot_for(current_action), true)
	attack_phase_changed.emit(current_action, next)


func _leave_active() -> void:
	if _hitbox_root != null and current_action != "":
		_hitbox_root.set_damage_enabled(slot_for(current_action), false)


func _duration_of(which: Phase) -> float:
	var timing: Dictionary = timings(current_action)
	match which:
		Phase.WINDUP:
			return float(timing.get("windup", 0.0))
		Phase.ACTIVE:
			return float(timing.get("active", 0.0))
		Phase.RECOVERY:
			return float(timing.get("recovery", 0.0))
		Phase.COOLDOWN:
			return float(timing.get("cooldown", 0.0))
	return 0.0


func apply_stats(new_stats: CreatureStats) -> void:
	stats = new_stats
	cancel()
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
