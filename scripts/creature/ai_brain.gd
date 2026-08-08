class_name AIBrain
extends Node

## The other controller (Mandate B2). Swap this in for `PlayerInput` and the
## same creature, the same locomotion and the same attacks fight back.
##
## FSM per TECH_SPEC §3: PATROL → CHASE when the player is inside `aggro_radius`
## and roughly in line of sight → ATTACK inside `attack_range` → COOLDOWN →
## re-evaluate, dropping back to PATROL past `deaggro_radius`. Every number comes
## from that enemy's `ai` block in `enemies.json`.
##
## The profile decides *how* it moves, but never *what it can do*: a Wall Crawler
## climbs because it wears Climber Claws, and a Stinger glides because it wears
## Bat Wing Scraps. Take the part away and the behaviour goes with it.

signal state_changed(state: State)

enum State { PATROL, CHASE, ATTACK, COOLDOWN }

const PRIORITY: int = -10
## How far ahead to probe for a ledge or a wall while patrolling, in pixels.
const PROBE_DISTANCE: float = 70.0
## Vertical slack within which the target counts as "roughly in line of sight".
const SIGHT_BAND_PX: float = 420.0

var creature: Creature = null
var locomotion: Locomotion = null
var target: Creature = null
var state: State = State.PATROL
var ai: Dictionary = {}
var profile: String = "ground_chaser"

var _cooldown_remaining: float = 0.0
var _patrol_direction: float = 1.0
var _repath_remaining: float = 0.0


func _ready() -> void:
	creature = get_parent() as Creature
	locomotion = creature.get_node_or_null("Locomotion") as Locomotion
	process_physics_priority = PRIORITY


## Give the brain its numbers. Called by the factory right after assembly.
func configure(enemy: Dictionary) -> void:
	ai = enemy.get("ai", {}) as Dictionary
	profile = str(ai.get("profile", "ground_chaser"))
	_patrol_direction = float(creature.facing)


## Who to hunt. Levels hand over the player; without one the brain just patrols.
func set_target(new_target: Creature) -> void:
	target = new_target


func _physics_process(delta: float) -> void:
	if locomotion == null or ai.is_empty() or creature.health.is_dead():
		if locomotion != null:
			locomotion.intent.clear()
		return

	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	_repath_remaining = maxf(0.0, _repath_remaining - delta)

	var intent: MovementIntent = locomotion.intent
	intent.clear()

	_choose_state()
	match state:
		State.PATROL:
			_patrol(intent)
		State.CHASE:
			_chase(intent)
		State.ATTACK:
			_attack(intent)
		State.COOLDOWN:
			_back_off(intent)


# --- transitions ---------------------------------------------------------------

func _choose_state() -> void:
	var next: State = state
	var distance: float = distance_to_target()

	if target == null or target.health.is_dead() or distance > deaggro_radius():
		next = State.PATROL
	elif _cooldown_remaining > 0.0:
		next = State.COOLDOWN
	elif distance <= attack_range() and _has_line_of_sight():
		next = State.ATTACK
	elif distance <= aggro_radius() and _has_line_of_sight():
		next = State.CHASE
	elif state == State.CHASE and distance <= deaggro_radius():
		next = State.CHASE
	else:
		next = State.PATROL

	if next != state:
		state = next
		state_changed.emit(state)


func distance_to_target() -> float:
	if target == null:
		return INF
	return creature.global_position.distance_to(target.global_position)


## "Roughly line of sight" (TECH_SPEC §3): within a vertical band and not behind
## solid world geometry.
func _has_line_of_sight() -> bool:
	if target == null:
		return false
	if absf(target.global_position.y - creature.global_position.y) > SIGHT_BAND_PX:
		return false

	var space: PhysicsDirectSpaceState2D = creature.get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		creature.global_position + Vector2(0, -80.0),
		target.global_position + Vector2(0, -80.0),
		Layers.mask([Layers.WORLD]))
	query.exclude = [creature.get_rid(), target.get_rid()]
	return space.intersect_ray(query).is_empty()


# --- behaviours ----------------------------------------------------------------

func _patrol(intent: MovementIntent) -> void:
	if _blocked_ahead() or _ledge_ahead():
		_patrol_direction = -_patrol_direction
	intent.move_axis = _axis_for_speed(patrol_speed()) * _patrol_direction
	# A wall patroller keeps climbing while it has a wall to climb.
	if creature.has_effect("can_climb") and locomotion.touching_climbable():
		intent.climb_held = true


func _chase(intent: MovementIntent) -> void:
	var direction: float = signf(target.global_position.x - creature.global_position.x)
	intent.move_axis = _axis_for_speed(chase_speed()) * direction
	_patrol_direction = direction if not is_zero_approx(direction) else _patrol_direction

	var height_gap: float = creature.global_position.y - target.global_position.y

	# Climb towards a target that is above, if it brought claws.
	if creature.has_effect("can_climb") and locomotion.touching_climbable() and height_gap > 60.0:
		intent.climb_held = true
		return

	# Hop a wall or a ledge that is in the way.
	if _blocked_ahead() and creature.is_on_floor():
		intent.press_jump()
	elif height_gap > 120.0 and creature.is_on_floor() and _repath_remaining <= 0.0:
		intent.press_jump()
		_repath_remaining = 0.6

	# A glider holds the button on the way down and drifts in (glide_harasser).
	if creature.has_effect("can_glide") and not creature.is_on_floor() and creature.velocity.y > 0.0:
		intent.jump_held = true


func _attack(intent: MovementIntent) -> void:
	intent.move_axis = 0.0
	creature.facing = 1 if target.global_position.x > creature.global_position.x else -1
	if creature.has_effect("can_glide") and not creature.is_on_floor():
		intent.jump_held = true

	if creature.attack_controller.phase != AttackController.Phase.IDLE:
		return
	for action: String in creature.attack_controller.armed_actions():
		if creature.attack_controller.request(action):
			_cooldown_remaining = attack_cooldown()
			return
	# No attack slot filled: back off rather than stand there uselessly.
	_cooldown_remaining = attack_cooldown()


## After swinging, give ground — this is what makes the Stinger read as a
## harasser rather than a shover.
func _back_off(intent: MovementIntent) -> void:
	if target == null:
		return
	var away: float = signf(creature.global_position.x - target.global_position.x)
	if distance_to_target() < attack_range() * 0.8:
		intent.move_axis = _axis_for_speed(patrol_speed()) * away
	if creature.has_effect("can_glide") and not creature.is_on_floor() and creature.velocity.y > 0.0:
		intent.jump_held = true


# --- probes --------------------------------------------------------------------

## Solid world directly in front, at chest height.
func _blocked_ahead() -> bool:
	var from: Vector2 = creature.global_position + Vector2(0, -90.0)
	return _ray(from, from + Vector2(PROBE_DISTANCE * _patrol_direction, 0.0),
		Layers.mask([Layers.WORLD, Layers.WORLD_CRACKED]))


## No floor just past the toes — turn round rather than walk off.
func _ledge_ahead() -> bool:
	if not creature.is_on_floor():
		return false
	var from: Vector2 = creature.global_position + Vector2(PROBE_DISTANCE * _patrol_direction, -20.0)
	return not _ray(from, from + Vector2(0, 160.0),
		Layers.mask([Layers.WORLD, Layers.WORLD_CRACKED]))


func _ray(from: Vector2, to: Vector2, mask: int) -> bool:
	var space: PhysicsDirectSpaceState2D = creature.get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, mask)
	query.exclude = [creature.get_rid()]
	return not space.intersect_ray(query).is_empty()


## Locomotion works in -1…+1 of the weight class' own top speed, so an AI speed
## from `enemies.json` becomes the fraction of that class' maximum it wants.
func _axis_for_speed(speed: float) -> float:
	var maximum: float = creature.weight_class.max_speed()
	if maximum <= 0.0:
		return 1.0
	return clampf(speed / maximum, 0.0, 1.0)


# --- tuning accessors ----------------------------------------------------------

func patrol_speed() -> float:
	return float(ai.get("patrol_speed", 0.0))


func chase_speed() -> float:
	return float(ai.get("chase_speed", 0.0))


func aggro_radius() -> float:
	return float(ai.get("aggro_radius", 0.0))


func deaggro_radius() -> float:
	return float(ai.get("deaggro_radius", 0.0))


func attack_range() -> float:
	return float(ai.get("attack_range", 0.0))


func attack_cooldown() -> float:
	return float(ai.get("attack_cooldown", 0.0))


func state_name() -> String:
	return State.keys()[state]
