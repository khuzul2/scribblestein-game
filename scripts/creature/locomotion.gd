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
signal dashed

enum State { GROUND, AIR, GLIDE, CLIMB, ROLL, CROUCH, CLING, DASH }

## Pixels between footsteps, and how often the wings and claws are heard.
const STEP_SPACING_PX: float = 110.0
const GLIDE_FLAP_SECONDS: float = 0.45
const CLIMB_SCRATCH_SECONDS: float = 0.32
## How far the standing-height ceiling probe is pulled in on each side, so the
## floor underfoot and a wall being brushed never read as an overhang.
const CEILING_PROBE_INSET_PX: float = 4.0

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
## `movement.profiles.<id>` for the creature's blueprint, or empty for the
## default feel. Cached on assembly — a blueprint cannot change mid-life.
var _profile: Dictionary = {}
## True from a pounce's launch until it lands or its overspeed is spent.
var _launching: bool = false
## Whether the current launch has actually left the floor yet — a launch is set
## on the frame the jump fires, while the creature is still grounded.
var _launch_left_ground: bool = false
## Air dash: how much of the burst is left, and whether it has been spent this
## airtime. Both reset the moment the creature touches ground or holds a wall.
var _dash_remaining: float = 0.0
var _dash_used: bool = false


func _ready() -> void:
	creature = get_parent() as Creature
	_climb_sensor = creature.get_node_or_null("ClimbSensor") as Area2D
	refresh_profile()


## Re-read the blueprint's movement profile. `Creature` calls this on assembly,
## because the blueprint is what selects the profile.
func refresh_profile() -> void:
	_profile = {}
	if creature == null or not Config.is_loaded:
		return
	if not Config.blueprints.has(creature.blueprint_id):
		return
	var override_id: String = str(Config.blueprint(creature.blueprint_id)
		.get("movement_profile_override", ""))
	if override_id == "":
		return
	var profiles: Variant = Config.cfg("movement.profiles")
	if profiles == null or not (profiles as Dictionary).has(override_id):
		push_error("Blueprint '%s' asks for movement profile '%s', which "
			% [creature.blueprint_id, override_id]
			+ "data/game_config.json /movement/profiles does not define.")
		return
	_profile = (profiles as Dictionary)[override_id] as Dictionary


## A profile number, or `fallback` when this blueprint uses the default feel.
func _profile_float(key: String, fallback: float) -> float:
	return float(_profile.get(key, fallback))


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
		_reset_air_moves()
	if intent.jump_pressed:
		_jump_buffer_remaining = Config.cfg_float("movement.jump_buffer")

	var climbing: bool = _update_climb(on_floor)
	var clinging: bool = not climbing and _update_cling(on_floor)
	var rolling: bool = _update_roll(on_floor, delta)
	var dashing: bool = _update_dash(on_floor, climbing or clinging)
	_update_crouch(on_floor, rolling, climbing)

	if not climbing and not clinging and not rolling and not dashing:
		_update_jump(on_floor, climbing)

	if not dashing:
		_move_horizontally(delta, on_floor, climbing, rolling)

	if climbing:
		creature.velocity.y = -Config.cfg_float("movement.climb.climb_speed") \
			if intent.climb_held else 0.0
		_reset_air_moves()
	elif clinging:
		# A cling holds the face and slides; it never lifts you.
		creature.velocity.y = Config.cfg_float("movement.wall_cling.slide_speed")
		_reset_air_moves()
	elif dashing:
		creature.velocity.y = 0.0  # a dash is flat; gravity is suspended for it
	elif not rolling or not on_floor:
		_apply_gravity(delta, _fall_cap())

	var before_move: float = creature.velocity.y
	creature.move_and_slide()
	if not dashing:
		_finish_gravity(delta, climbing or clinging)
	_detect_landing(before_move)
	_set_state(on_floor, climbing, rolling, clinging, dashing)

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
	_dash_remaining = maxf(0.0, _dash_remaining - delta)
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
		creature.velocity.y = creature.weight_class.jump_velocity() \
			* _profile_float("jump_velocity_mult", 1.0)
		_launch(on_floor)
		_jump_buffer_remaining = 0.0
		_coyote_remaining = 0.0
		jumped.emit("pounce" if _profile.has("launch_speed_mult") else "jump")
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


## A pounce commits the body forward as it leaves the ground: the horizontal
## velocity is set to `launch_speed_mult` of running speed toward the direction
## being asked for, and `_move_horizontally` bleeds the overspeed off again.
## Blueprints without a `launch_speed_mult` jump normally and this does nothing.
func _launch(on_floor: bool) -> void:
	if not _profile.has("launch_speed_mult") or not on_floor:
		return
	var direction: float = signf(intent.move_axis) if absf(intent.move_axis) > 0.2 \
		else float(creature.facing)
	creature.velocity.x = direction * _current_max_speed() \
		* _profile_float("launch_speed_mult", 1.0)
	_launching = true
	_launch_left_ground = false


## Bleed a pounce's launch overspeed back down to running speed. Without this a
## leap would either stop dead the moment `move_toward` caught up, or carry its
## burst for the whole flight — neither reads as an animal landing.
func _decay_launch(delta: float) -> void:
	var cap: float = _current_max_speed()
	if absf(creature.velocity.x) <= cap:
		return
	var decay: float = _profile_float("launch_decay", 0.0) * cap * delta
	creature.velocity.x = move_toward(creature.velocity.x, signf(creature.velocity.x) * cap, decay)


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

	var control: float = 1.0 if on_floor \
		else creature.weight_class.air_control() * _profile_float("air_control_mult", 1.0)
	if is_gliding():
		control *= Config.cfg_float("movement.glide.glide_air_control")

	var target: float = 0.0 if stun_remaining > 0.0 \
		else clampf(intent.move_axis, -1.0, 1.0) * _current_max_speed()

	# A launch's overspeed is bled off on its own schedule; steering must not be
	# able to cancel it, and letting go of the stick must not stop it dead.
	#
	# Gated on an actual launch, not merely on being over the speed cap: knockback
	# also puts a creature over its cap, and it must keep decaying at the weight
	# class' deceleration like it always has.
	if _launching:
		if on_floor and _launch_left_ground:
			_launching = false
		elif absf(creature.velocity.x) <= _current_max_speed():
			_launching = false
		else:
			if not on_floor:
				_launch_left_ground = true
			_decay_launch(delta)
			if absf(intent.move_axis) > 0.2 and stun_remaining <= 0.0:
				creature.facing = 1 if intent.move_axis > 0.0 else -1
			return

	var rate: float = creature.weight_class.acceleration() if absf(target) > 0.01 \
		else creature.weight_class.deceleration()
	creature.velocity.x = move_toward(creature.velocity.x, target, rate * control * delta)

	if absf(intent.move_axis) > 0.2 and stun_remaining <= 0.0:
		creature.facing = 1 if intent.move_axis > 0.0 else -1


func _current_max_speed() -> float:
	var speed: float = creature.weight_class.max_speed() \
		* _profile_float("max_speed_mult", 1.0)
	if _crouched:
		speed *= Config.cfg_float("movement.crouch.speed_mult")
	return speed


# --- roll & crouch -------------------------------------------------------------

func _update_roll(on_floor: bool, _delta: float) -> bool:
	if _roll_remaining > 0.0:
		creature.velocity.x = float(creature.facing) * _roll_speed()
		return true

	# One roll covers `roll.distance` (190 px) and a creature is 110-150 px wide,
	# so a crawl tunnel longer than ~80 px would leave the creature standing up
	# inside its ceiling halfway through, with a 0.5 s cooldown spent stuck.
	# Under an overhang the cooldown is suspended and *holding* crouch keeps the
	# roll going, which is what `effects.json -> dodge_roll` promises and what
	# DESIGN §9 means by "Light class + roll" (DECISIONS_NEEDED D6).
	var ducked: bool = _ceiling_overhead()
	var can_roll: bool = creature.has_effect("dodge_roll") and on_floor \
		and stun_remaining <= 0.0 \
		and (ducked or _roll_cooldown_remaining <= 0.0)
	if (intent.crouch_pressed or (ducked and intent.crouch_held)) and can_roll:
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
	# A roll ducks too: effects.json promises a roll "fits under crawl tunnels
	# only while rolling", which is only true if it actually shrinks the creature.
	#
	# Staying ducked while a ceiling is overhead is what stops a creature that
	# rolled into a tunnel from standing straight into the rock the moment the
	# roll expires. It is not a way *in* — a creature with neither `crouch` nor
	# `dodge_roll` can never get under the overhang in the first place, so the
	# gate still holds.
	var should_crouch: bool = rolling \
		or (_crouched and _ceiling_overhead()) \
		or (creature.has_effect("crouch") and on_floor and intent.crouch_held and not climbing)
	if should_crouch == _crouched:
		return
	_crouched = should_crouch
	creature.set_crouched(_crouched)


## True when standing up at the current position would put the creature's body
## inside solid world — i.e. it is under a crawl tunnel's ceiling.
##
## The probe is the *standing* body box, shrunk by `CEILING_PROBE_INSET_PX` on
## every side so the floor it is resting on and the walls it is brushing do not
## read as a ceiling.
func _ceiling_overhead() -> bool:
	var box: Rect2 = creature.standing_body_box()
	var inset: Vector2 = Vector2.ONE * (CEILING_PROBE_INSET_PX * 2.0)
	if box.size.x <= inset.x or box.size.y <= inset.y:
		return false
	var world: World2D = creature.get_world_2d()
	if world == null:
		return false

	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = box.size - inset
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, creature.global_position + box.get_center())
	query.collision_mask = Layers.mask([Layers.WORLD, Layers.WORLD_CRACKED])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not world.direct_space_state.intersect_shape(query, 1).is_empty()


func is_crouched() -> bool:
	return _crouched


func is_rolling() -> bool:
	return _roll_remaining > 0.0


# --- air dash & wall cling -----------------------------------------------------

## Everything you get back by touching solid ground — or a wall, if you can hold
## one. Kept in one place so a new air move cannot be forgotten in one of them.
func _reset_air_moves() -> void:
	_double_jump_used = false
	_dash_used = false


## One committed horizontal burst per airtime (`effects.json → air_dash`).
##
## Fired by a crouch press in the air, which is otherwise a dead input while
## airborne — a roll needs the ground. Gravity is suspended for the burst, which
## is what makes a dash a distinct traversal key rather than a fast fall.
func _update_dash(on_floor: bool, on_wall: bool) -> bool:
	if _dash_remaining > 0.0:
		creature.velocity.x = float(creature.facing) * _dash_speed()
		return true

	if on_floor or on_wall or _dash_used or stun_remaining > 0.0:
		return false
	if not intent.crouch_pressed or not creature.has_effect("air_dash"):
		return false

	if absf(intent.move_axis) > 0.2:
		creature.facing = 1 if intent.move_axis > 0.0 else -1
	_dash_remaining = Config.cfg_float("movement.air_dash.duration")
	_dash_used = true
	var iframes: float = Config.cfg_float("movement.air_dash.iframes")
	if iframes > 0.0:
		creature.health.grant_iframes(iframes)
	Audio.sfx("sfx_roll_swish", 0.15)
	creature.velocity = Vector2(float(creature.facing) * _dash_speed(), 0.0)
	dashed.emit()
	return true


## Fixed distance over a fixed duration, exactly like a roll.
func _dash_speed() -> float:
	return Config.cfg_float("movement.air_dash.distance") \
		/ Config.cfg_float("movement.air_dash.duration")


## Hold a climbable face and slide instead of falling (`effects.json →
## wall_cling`). It only ever holds — ascending needs `can_climb` — so a cling
## build reaches a ledge by clinging, dropping to the bottom of its slide and
## jumping again, not by going up the wall.
func _update_cling(on_floor: bool) -> bool:
	if on_floor or not creature.has_effect("wall_cling") or stun_remaining > 0.0:
		return false
	if not touching_climbable():
		return false
	# Pressing into the wall, or already falling onto it with no input.
	if absf(intent.move_axis) > 0.2 and signf(intent.move_axis) != signf(float(creature.facing)):
		return false
	return creature.velocity.y >= 0.0


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


## Heavy stomps through cracked floors above the landing speed its preset names
## (DESIGN §5, §9 — this is a level-design key), and so does anything wearing
## `heavy_landing`, which is how a light build buys its way through the same
## door. The speed threshold still applies: you have to actually drop onto it.
func _try_break_cracked_floor(fall_speed: float) -> void:
	var by_class: bool = creature.weight_class.breaks_cracked_floors()
	if not by_class and not creature.has_effect("heavy_landing"):
		return
	var threshold: float = creature.weight_class.crack_break_min_land_speed() if by_class \
		else Config.cfg_float("movement.weight_classes.heavy.crack_break_min_land_speed")
	if fall_speed < threshold:
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

func _set_state(on_floor: bool, climbing: bool, rolling: bool,
		clinging: bool = false, dashing: bool = false) -> void:
	var next: State = State.AIR
	if dashing:
		next = State.DASH
	elif rolling:
		next = State.ROLL
	elif climbing:
		next = State.CLIMB
	elif clinging:
		next = State.CLING
	elif on_floor:
		next = State.CROUCH if _crouched else State.GROUND
	elif is_gliding():
		next = State.GLIDE
	if next != state:
		state = next
		state_changed.emit(state)


func state_name() -> String:
	return State.keys()[state]
