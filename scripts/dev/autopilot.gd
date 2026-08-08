class_name Autopilot
extends Node

## A deliberately dumb bot that walks a level from the entrance to the exit.
##
## It exists to prove completability (MILESTONES M7 — "completable with the
## intended loadouts") without a human. It knows only what a first-time player
## can see: keep heading right, jump at a wall or a ledge, duck under a low
## ceiling, and hit whatever is in the way. It has no map and no knowledge of
## the level's layout, so if it finishes, the route really is walkable.
##
## Attach it to a `PlayScene` after the player exists.

const PRIORITY: int = -20
## How far ahead it looks for walls and ceilings, in pixels.
const PROBE: float = 90.0
## Ledges are probed much closer. Jumping the moment a gap comes into view
## wastes most of the leap on ground you were already standing on.
const LEDGE_PROBE: float = 25.0
## Give up steering right for a moment after this long without progress, and
## try a jump instead — the bot's only unsticking trick.
const STUCK_SECONDS: float = 0.8
## How long it reverses when it decides it is wedged.
const BACK_OFF_SECONDS: float = 0.5

var scene: PlayScene = null
var player: Creature = null
var reached_exit: bool = false
var elapsed: float = 0.0

var _furthest_x: float = -INF
var _stuck_for: float = 0.0
var _backing_off: float = 0.0


func drive(play_scene: PlayScene) -> void:
	scene = play_scene
	player = play_scene.player
	player.player_input.set_enabled(false)
	process_physics_priority = PRIORITY
	var door: ExitDoor = play_scene.get("exit_door") as ExitDoor
	if door != null:
		door.reached.connect(func(_by: Creature) -> void: reached_exit = true)


func _physics_process(delta: float) -> void:
	if player == null or reached_exit or player.health.is_dead():
		return
	elapsed += delta

	var intent: MovementIntent = player.locomotion.intent
	intent.clear()

	if player.global_position.x > _furthest_x + 8.0:
		_furthest_x = player.global_position.x
		_stuck_for = 0.0
		_backing_off = 0.0
	else:
		_stuck_for += delta

	# Wedged against something? Give ground for a moment and come at it again
	# with a run-up. This is the only unsticking trick it has, and it is the one
	# a real player uses.
	if _backing_off > 0.0:
		_backing_off -= delta
		intent.move_axis = -1.0
		_swing_at_anything_close()
		return
	if _stuck_for > STUCK_SECONDS * 2.0:
		_backing_off = BACK_OFF_SECONDS
		_stuck_for = 0.0
		return

	intent.move_axis = 1.0
	if _low_ceiling_ahead():
		intent.crouch_held = true
		intent.crouch_pressed = true
	elif (_wall_ahead() or _ledge_ahead() or _stuck_for > STUCK_SECONDS) and player.is_on_floor():
		intent.press_jump()
		_stuck_for = 0.0
	elif not player.is_on_floor() and player.has_effect("can_glide"):
		intent.jump_held = true

	_swing_at_anything_close()


## Solid world at chest height, just ahead.
func _wall_ahead() -> bool:
	var from: Vector2 = player.global_position + Vector2(0, -120.0)
	return _hit(from, from + Vector2(PROBE, 0))


## No floor past the toes. The bot jumps rather than trusting the drop.
func _ledge_ahead() -> bool:
	if not player.is_on_floor():
		return false
	var from: Vector2 = player.global_position + Vector2(LEDGE_PROBE, -20.0)
	return not _hit(from, from + Vector2(0, 200.0))


## Something overhead close enough that standing up would meet it.
func _low_ceiling_ahead() -> bool:
	var from: Vector2 = player.global_position + Vector2(PROBE * 0.6, -20.0)
	return _hit(from, from + Vector2(0, -320.0))


func _hit(from: Vector2, to: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to,
		Layers.mask([Layers.WORLD, Layers.WORLD_CRACKED]))
	query.exclude = [player.get_rid()]
	return not space.intersect_ray(query).is_empty()


## Swing whenever an enemy is within a body length. The bot does not aim.
func _swing_at_anything_close() -> void:
	if player.attack_controller.phase != AttackController.Phase.IDLE:
		return
	for enemy: Creature in scene.enemies():
		if player.global_position.distance_to(enemy.global_position) > 260.0:
			continue
		player.facing = 1 if enemy.global_position.x > player.global_position.x else -1
		for action: String in player.attack_controller.armed_actions():
			if player.attack_controller.request(action):
				return
