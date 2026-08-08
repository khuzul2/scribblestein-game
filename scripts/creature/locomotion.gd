class_name Locomotion
extends Node

## Every way a creature can move. One implementation, shared by the player and
## every enemy (Mandate B2); which abilities are available comes purely from the
## equipped parts' effects, and every number comes from `game_config.json`
## (Mandate B1).
##
## Feel rules (Mandate B6): an intent set this tick takes effect this tick, and
## coyote time plus jump buffering are always on.
##
## Gravity is integrated at the midpoint — half before the move, half after — so
## the jump apex matches `v²/(2g)` instead of overshooting by the ~5% that plain
## semi-implicit Euler costs at 60 Hz.

signal jumped(kind: String)
signal landed(fall_speed: float)
signal state_changed(state: State)
signal broke_cracked_floor(floor_node: Node)

enum State { GROUND, AIR, GLIDE, CLIMB, ROLL, CROUCH }

## Pixels between footsteps, and how often the wings and claws are heard.
const STEP_SPACING_PX: float = 110.0
const GLIDE_FLAP_SECONDS: float = 0.45
const CLIMB_SCRATCH_SECONDS: float = 0.32

var creature: Creature = null
var intent: MovementIntent = MovementIntent.new()
var state: State = State.AIR

## Set by combat: while positive, the creature cannot steer (M4 hitstun).
var stun_remaining: float = 0.0

var _coyote_remaining: float = 0.0
var _jump_buffer_remaining: float = 0.0
var _double_jump_used: bool = false
var _roll_remaining: float = 0.0
var _roll_cooldown_remaining: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _crouched: bool = false
var _climb_sensor: Area2D = null
## Distance walked since the last footstep, in pixels.
var _step_distance: float = 0.0
var _step_index: int = 0
var _glide_cooldown: float = 0.0


func _ready() -> void:
	creature = get_parent() as Creature
	_climb_sensor = creature.get_node_or_null("ClimbSensor") as Area2D


func _physics_process(delta: float) -> void:
	if creature == null or not Config.is_loaded:
		return

	_tick_timers(delta)

	if creature.health.is_dead():
		_apply_gravity(delta, Config.cfg_float("movement.terminal_fall_speed"))
		creature.move_and_slide()
		return

	var on_floor: bool = creature.is_on_floor()
	if on_floor:
		_coyote_remaining = Config.cfg_float("movement.coyote_time")
		_double_jump_used = false
	if intent.jump_pressed:
		_jump_buffer_remaining = Config.cfg_float("movement.jump_buffer")

	var climbing: bool = _update_climb(on_floor)
	var rolling: bool = _update_roll(on_floor, delta)
	_update_crouch(on_floor, rolling, climbing)

	if not climbing and not rolling:
		_update_jump(on_floor, climbing)

	_move_horizontally(delta, on_floor, climbing, rolling)

	if climbing:
		creature.velocity.y = -Config.cfg_float("movement.climb.climb_speed") \
			if intent.climb_held else 0.0
		_double_jump_used = false
	elif not rolling or not on_floor:
		_apply_gravity(delta, _fall_cap())

	var before_move: float = creature.velocity.y
	creature.move_and_slide()
	_finish_gravity(delta, climbing)
	_detect_landing(before_move)
	_set_state(on_floor, climbing, rolling)

	_tick_footsteps(delta)

	intent.jump_pressed = false
	intent.crouch_pressed = false


## Footsteps are spaced by distance travelled, not by a timer, so they stay in
## step whether the creature is a Light sprinter or a Heavy plodder.
func _tick_footsteps(delta: float) -> void:
	_glide_cooldown = maxf(0.0, _glide_cooldown - delta)

	if state == State.GROUND and absf(creature.velocity.x) > 20.0:
		_step_distance += absf(creature.velocity.x) * delta
		if _step_distance >= STEP_SPACING_PX:
			_step_distance = 0.0
			_step_index = _step_index % 4 + 1
			Audio.sfx("sfx_step_scribble_0%d" % _step_index, 0.12)
	else:
		_step_distance = STEP_SPACING_PX * 0.6  # the next step lands promptly

	if state == State.GLIDE and _glide_cooldown <= 0.0:
		_glide_cooldown = GLIDE_FLAP_SECONDS
		Audio.sfx("sfx_glide_flapflap", 0.1)
	elif state == State.CLIMB and _glide_cooldown <= 0.0:
		_glide_cooldown = CLIMB_SCRATCH_SECONDS
		Audio.sfx("sfx_climb_scratch_loop", 0.15)


# --- timers --------------------------------------------------------------------

func _tick_timers(delta: float) -> void:
	_coyote_remaining = maxf(0.0, _coyote_remaining - delta)
	_jump_buffer_remaining = maxf(0.0, _jump_buffer_remaining - delta)
	_roll_remaining = maxf(0.0, _roll_remaining - delta)
	_roll_cooldown_remaining = maxf(0.0, _roll_cooldown_remaining - delta)
	stun_remaining = maxf(0.0, stun_remaining - delta)


# --- vertical ------------------------------------------------------------------

## Half the tick's gravity before the move; `_finish_gravity` adds the rest.
func _apply_gravity(delta: float, cap: float) -> void:
	creature.velocity.y += Config.cfg_float("movement.gravity") * delta * 0.5
	creature.velocity.y = minf(creature.velocity.y, cap)


func _finish_gravity(delta: float, climbing: bool) -> void:
	if climbing or creature.is_on_floor():
		return
	creature.velocity.y += Config.cfg_float("movement.gravity") * delta * 0.5
	creature.velocity.y = minf(creature.velocity.y, _fall_cap())


## Terminal velocity, or the glide cap while actually gliding.
func _fall_cap() -> float:
	if is_gliding():
		return Config.cfg_float("movement.glide.glide_fall_cap")
	return Config.cfg_float("movement.terminal_fall_speed")


## Gliding needs the button *held* while falling — it does not need a fresh
## press, which is what leaves a bare tap free to mean "double jump"
## (effects.json → can_glide / double_jump).
func is_gliding() -> bool:
	return creature != null \
		and creature.has_effect("can_glide") \
		and not creature.is_on_floor() \
		and intent.jump_held \
		and creature.velocity.y > 0.0 \
		and stun_remaining <= 0.0


func _update_jump(on_floor: bool, climbing: bool) -> void:
	if stun_remaining > 0.0:
		return

	var grounded_enough: bool = on_floor or _coyote_remaining > 0.0
	if _jump_buffer_remaining > 0.0 and grounded_enough:
		creature.velocity.y = creature.weight_class.jump_velocity()
		_jump_buffer_remaining = 0.0
		_coyote_remaining = 0.0
		jumped.emit("jump")
		return

	if climbing and _jump_buffer_remaining > 0.0:
		_wall_jump()
		return

	if intent.jump_pressed and not grounded_enough and not _double_jump_used \
			and creature.has_effect("double_jump"):
		creature.velocity.y = creature.weight_class.jump_velocity() \
			* Config.cfg_float("movement.double_jump.velocity_mult")
		_double_jump_used = true
		_jump_buffer_remaining = 0.0
		jumped.emit("double_jump")


func _wall_jump() -> void:
	var impulse: Vector2 = Config.cfg_vec2("movement.climb.wall_jump_impulse")
	creature.velocity = Vector2(-creature.facing * impulse.x, impulse.y)
	_jump_buffer_remaining = 0.0
	_double_jump_used = false
	jumped.emit("wall_jump")


# --- horizontal ----------------------------------------------------------------

func _move_horizontally(delta: float, on_floor: bool, climbing: bool, rolling: bool) -> void:
	if rolling:
		return  # a roll is a committed, fixed-distance move

	if climbing:
		creature.velocity.x = move_toward(creature.velocity.x, 0.0,
			creature.weight_class.deceleration() * delta)
		return

	var control: float = 1.0 if on_floor else creature.weight_class.air_control()
	if is_gliding():
		control *= Config.cfg_float("movement.glide.glide_air_control")

	var target: float = 0.0 if stun_remaining > 0.0 \
		else clampf(intent.move_axis, -1.0, 1.0) * _current_max_speed()

	var rate: float = creature.weight_class.acceleration() if absf(target) > 0.01 \
		else creature.weight_class.deceleration()
	creature.velocity.x = move_toward(creature.velocity.x, target, rate * control * delta)

	if absf(intent.move_axis) > 0.2 and stun_remaining <= 0.0:
		creature.facing = 1 if intent.move_axis > 0.0 else -1


func _current_max_speed() -> float:
	var speed: float = creature.weight_class.max_speed()
	if _crouched:
		speed *= Config.cfg_float("movement.crouch.speed_mult")
	return speed


# --- roll & crouch -------------------------------------------------------------

func _update_roll(on_floor: bool, _delta: float) -> bool:
	if _roll_remaining > 0.0:
		creature.velocity.x = float(creature.facing) * _roll_speed()
		return true

	var can_roll: bool = creature.has_effect("dodge_roll") and on_floor \
		and _roll_cooldown_remaining <= 0.0 and stun_remaining <= 0.0
	if intent.crouch_pressed and can_roll:
		_roll_remaining = Config.cfg_float("movement.roll.duration")
		_roll_cooldown_remaining = Config.cfg_float("movement.roll.cooldown") \
			+ Config.cfg_float("movement.roll.duration")
		creature.health.grant_iframes(Config.cfg_float("movement.roll.iframes"))
		Audio.sfx("sfx_roll_swish", 0.1)
		creature.velocity.x = float(creature.facing) * _roll_speed()
		return true
	return false


## Fixed distance over a fixed duration — a roll always covers `roll.distance`.
func _roll_speed() -> float:
	return Config.cfg_float("movement.roll.distance") / Config.cfg_float("movement.roll.duration")


func _update_crouch(on_floor: bool, rolling: bool, climbing: bool) -> void:
	var should_crouch: bool = creature.has_effect("crouch") and on_floor \
		and intent.crouch_held and not rolling and not climbing
	if should_crouch == _crouched:
		return
	_crouched = should_crouch
	creature.set_crouched(_crouched)


func is_crouched() -> bool:
	return _crouched


func is_rolling() -> bool:
	return _roll_remaining > 0.0


# --- climbing ------------------------------------------------------------------

func _update_climb(_on_floor: bool) -> bool:
	if not creature.has_effect("can_climb") or stun_remaining > 0.0:
		return false
	if not intent.climb_held:
		return false
	# Deliberately allowed from the ground: you walk up to a wall and climb it.
	return touching_climbable()


func touching_climbable() -> bool:
	if _climb_sensor == null:
		return false
	return not _climb_sensor.get_overlapping_bodies().is_empty() \
		or not _climb_sensor.get_overlapping_areas().is_empty()


# --- landing -------------------------------------------------------------------

func _detect_landing(fall_speed_before_move: float) -> void:
	var on_floor: bool = creature.is_on_floor()
	if on_floor and not _was_on_floor:
		_fall_speed = maxf(fall_speed_before_move, 0.0)
		landed.emit(_fall_speed)
		_try_break_cracked_floor(_fall_speed)
	_was_on_floor = on_floor


## Heavy alone stomps through cracked floors, and only above the landing speed
## its preset names (DESIGN §5, §9 — this is a level-design key).
func _try_break_cracked_floor(fall_speed: float) -> void:
	if not creature.weight_class.breaks_cracked_floors():
		return
	if fall_speed < creature.weight_class.crack_break_min_land_speed():
		return
	for index: int in range(creature.get_slide_collision_count()):
		var collision: KinematicCollision2D = creature.get_slide_collision(index)
		var collider: Object = collision.get_collider()
		if collider is CrackedFloor:
			(collider as CrackedFloor).shatter(creature)
			broke_cracked_floor.emit(collider as Node)


func last_fall_speed() -> float:
	return _fall_speed


# --- state ---------------------------------------------------------------------

func _set_state(on_floor: bool, climbing: bool, rolling: bool) -> void:
	var next: State = State.AIR
	if rolling:
		next = State.ROLL
	elif climbing:
		next = State.CLIMB
	elif on_floor:
		next = State.CROUCH if _crouched else State.GROUND
	elif is_gliding():
		next = State.GLIDE
	if next != state:
		state = next
		state_changed.emit(state)


func state_name() -> String:
	return State.keys()[state]
