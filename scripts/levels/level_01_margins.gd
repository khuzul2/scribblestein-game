extends PlayScene

## Level 01 — "The Margins": where the doodles go when they run out of page.
##
## The critical path is completable with the starter kit alone, so a player can
## never be stranded by an anatomy they have not unlocked yet (DESIGN §3). The
## two anatomical gates guard *caches*, not progress: a climb shaft over an ink
## stash, and a glide ledge out over the chasm holding a Blueprint Sketch. That
## is the loop's teaching moment — you can see the reward, and you come back for
## it once you have the part.
##
## Every gate dimension below is checked against `JumpMath` over all 648 legal
## loadouts in `tests/test_level_01.gd`, so "impassable without a glide part" is
## a proof rather than a hope.

# --- gate dimensions, all proved in tests/test_level_01.gd ---------------------
## Horizontal reach to the glide ledge, and how far below the launch lip it sits.
## The best non-glide build in the game reaches 461 px at this drop; the *worst*
## glide build reaches 628. 540 sits between them.
const GLIDE_GAP: float = 540.0
const GLIDE_DROP: float = 380.0
## Head-room in the crawl tunnel. Legal builds stand 366-462 px tall and crouch
## to half that, so 300 admits every crouching or rolling creature and no
## standing one.
const TUNNEL_CLEARANCE: float = 300.0
## The climb shaft is taller than any jump in the game can reach (the best is
## 378 px, including a double jump), so it is a pure `can_climb` gate.
const SHAFT_HEIGHT: float = 760.0

const GROUND_DEPTH: float = 400.0

var exit_door: ExitDoor = null

var _chasm_floor_y: float = 0.0


func _build_world() -> void:
	level_id = "level_01_margins"
	spawn_point = Vector2(-420.0, -80.0)

	_build_entrance()
	_build_climb_shaft()
	_build_crawl_tunnel()
	_build_chasm()
	_build_exit()


func _on_world_ready() -> void:
	Audio.music("mus_level01_loop")
	_populate()
	exit_door.reached.connect(_on_exit_reached)


# --- geometry ------------------------------------------------------------------

## The margin of the page: a flat run to learn the controls and meet a Grunt.
func _build_entrance() -> void:
	add_ground(Rect2(-1150.0, 0.0, 2050.0, GROUND_DEPTH))
	add_warning_sketch(Vector2(-560.0, -880.0),
		"THE MARGINS\n\nno rebuilding past this point\nbring: claws (ink stash) · wings (sketch)")
	add_warning_sketch(Vector2(560.0, -700.0), "something lives here")

	# A short hop, to say out loud that gaps are jumpable. 150 px is well inside
	# the starter kit's 204 px reach, so it teaches rather than tests.
	add_ground(Rect2(1050.0, 0.0, 1350.0, GROUND_DEPTH))


## Optional: a shaft no jump can clear, with an ink stash on the ledge above.
##
## It stands at the far LEFT of the level, behind the entrance, so it is a
## detour you choose rather than a wall across the only road. A player without
## claws walks right and never touches it; a player with claws goes back for it.
func _build_climb_shaft() -> void:
	var base_x: float = -1060.0
	add_warning_sketch(Vector2(base_x + 120.0, -SHAFT_HEIGHT - 300.0), "claws\nonly")
	add_climbable_wall(Rect2(base_x, -SHAFT_HEIGHT, 90.0, SHAFT_HEIGHT))
	add_ground(Rect2(base_x, -SHAFT_HEIGHT - 70.0, 520.0, 70.0))

	# The reward you can see from the ground.
	for index: int in range(4):
		_place_ink(Vector2(base_x + 120.0 + 80.0 * float(index), -SHAFT_HEIGHT - 140.0), 12)


## The corridor that runs to the chasm lip. The crawl tunnel itself is down in
## the chasm (see `_build_chasm`), off to the left of where you land, so ducking
## is a choice rather than a toll — see DECISIONS_NEEDED.md D6.
func _build_crawl_tunnel() -> void:
	add_ground(Rect2(2400.0, 0.0, 1500.0, GROUND_DEPTH))


## The chasm. Falling in is safe and is the way onward; the ledge out over it
## holds a Blueprint Sketch and can only be reached on a glide.
func _build_chasm() -> void:
	var lip_x: float = 3900.0
	_chasm_floor_y = 760.0

	add_warning_sketch(Vector2(lip_x - 260.0, -760.0), "wings\nreach the ledge")
	add_ground(Rect2(lip_x - 500.0, _chasm_floor_y, 2400.0, GROUND_DEPTH))

	# The crawl tunnel: back to the LEFT of where you land, so the way out is
	# never behind it. Duck under and there is ink in the dark.
	add_warning_sketch(Vector2(lip_x - 300.0, _chasm_floor_y - 640.0), "duck\n(ink back there)")
	add_ground(Rect2(lip_x - 460.0, _chasm_floor_y - TUNNEL_CLEARANCE - 420.0, 420.0, 420.0))
	for index: int in range(3):
		_place_ink(Vector2(lip_x - 400.0 + 70.0 * float(index), _chasm_floor_y - 60.0), 14)

	# The glide-only ledge, GLIDE_GAP across and GLIDE_DROP down from the lip.
	add_ground(Rect2(lip_x + GLIDE_GAP, GLIDE_DROP, 300.0, 60.0))
	_place_sketch(Vector2(lip_x + GLIDE_GAP + 150.0, GLIDE_DROP - 70.0), "arms_climber_claws")
	_place_ink(Vector2(lip_x + GLIDE_GAP + 60.0, GLIDE_DROP - 70.0), 20)

	# A cracked floor over a shallow stash, for a Heavy build to stomp through.
	# The stash is only 180 px down and has a step out, so dropping in is a
	# reward rather than a trap — nothing in this level can strand a player.
	add_warning_sketch(Vector2(lip_x + 980.0, _chasm_floor_y - 420.0), "heavy?")
	add_cracked_floor(Rect2(lip_x + 900.0, _chasm_floor_y, 260.0, 70.0))
	add_ground(Rect2(lip_x + 900.0, _chasm_floor_y + 180.0, 260.0, GROUND_DEPTH))
	add_ground(Rect2(lip_x + 1160.0, _chasm_floor_y + 90.0, 120.0, GROUND_DEPTH))
	for index: int in range(5):
		_place_ink(Vector2(lip_x + 930.0 + 50.0 * float(index), _chasm_floor_y + 110.0), 16)


func _build_exit() -> void:
	var at: Vector2 = Vector2(5500.0, _chasm_floor_y)
	add_warning_sketch(Vector2(at.x - 40.0, _chasm_floor_y - 460.0), "out")
	exit_door = ExitDoor.new()
	exit_door.name = "ExitDoor"
	exit_door.position = at
	add_child(exit_door)


# --- inhabitants ---------------------------------------------------------------

func _populate() -> void:
	# One of each, in the order that teaches them: a walker, a climber, a flier.
	add_enemy("enemy_scribble_grunt", Vector2(620.0, -120.0))
	add_enemy("enemy_scribble_grunt", Vector2(1900.0, -120.0))
	add_enemy("enemy_wall_crawler", Vector2(3100.0, -120.0))
	add_enemy("enemy_stinger", Vector2(4300.0, _chasm_floor_y - 220.0))
	add_enemy("enemy_wall_crawler", Vector2(5000.0, _chasm_floor_y - 120.0))


func _place_ink(at: Vector2, amount: int) -> void:
	var pickup: Pickups.Ink = Pickups.Ink.create(amount)
	pickup.position = at
	add_child(pickup)


func _place_sketch(at: Vector2, part_id: String) -> void:
	var pickup: Pickups.BlueprintSketch = Pickups.BlueprintSketch.create(part_id)
	pickup.position = at
	add_child(pickup)


func _on_exit_reached(_by: Creature) -> void:
	mark_completed()
	exit_requested.emit()
