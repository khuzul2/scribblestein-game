extends PlayScene

## The Scratchpad (DESIGN §11): a whitebox corner of the page holding one of
## every obstacle the game will ask about, so a build can be tested the instant
## it is assembled — platform stairs, a climbable wall, a gap, a crawl tunnel, a
## cracked floor, and a dummy to hit.
##
## It is deliberately not a level: nothing here is scored, saved, or lost.

const FLOOR_Y: float = 0.0
const STEP: Vector2 = Vector2(200.0, 90.0)
const GAP_WIDTH: float = 520.0
const TUNNEL_CLEARANCE: float = 150.0

var dummy: Creature = null

var _dummy_health_label: Label = null


func _build_world() -> void:
	level_id = "scratchpad"
	spawn_point = Vector2(-200.0, FLOOR_Y - 60.0)

	# Entrance floor.
	add_ground(Rect2(-600.0, FLOOR_Y, 1000.0, 300.0))
	add_warning_sketch(Vector2(-380.0, FLOOR_Y - 900.0), "THE SCRATCHPAD\ntry things here")

	# 1. Platform stairs — plain jump height.
	add_warning_sketch(Vector2(430.0, FLOOR_Y - 900.0), "stairs\n(jump)")
	for step: int in range(4):
		add_ground(Rect2(400.0 + STEP.x * float(step), FLOOR_Y - STEP.y * float(step + 1),
			STEP.x, 300.0 + STEP.y * float(step + 1)))

	var landing_x: float = 400.0 + STEP.x * 4.0
	var landing_y: float = FLOOR_Y - STEP.y * 4.0
	add_ground(Rect2(landing_x, landing_y, 700.0, 300.0 + STEP.y * 4.0))

	# 2. Climbable wall — needs claws, or a double jump to skip.
	add_warning_sketch(Vector2(landing_x + 460.0, landing_y - 1000.0), "wall\n(climb)")
	add_climbable_wall(Rect2(landing_x + 700.0, landing_y - 760.0, 90.0, 760.0))
	add_ground(Rect2(landing_x + 700.0, landing_y - 830.0, 620.0, 70.0))

	# 3. Gap — needs a glide, or a long run-up.
	var gap_start: float = landing_x + 1320.0
	add_warning_sketch(Vector2(gap_start + 120.0, landing_y - 1000.0), "gap\n(glide)")
	add_ground(Rect2(gap_start + GAP_WIDTH, landing_y - 830.0, 640.0, 70.0))

	# 4. Crawl tunnel — needs a crouch, or a roll to slip through.
	var tunnel_x: float = gap_start + GAP_WIDTH + 640.0
	add_warning_sketch(Vector2(tunnel_x - 60.0, landing_y - 1000.0), "tunnel\n(crouch / roll)")
	add_ground(Rect2(tunnel_x, landing_y - 830.0, 700.0, 70.0))
	add_ground(Rect2(tunnel_x, landing_y - 830.0 - TUNNEL_CLEARANCE - 260.0, 700.0, 260.0))

	# 5. Cracked floor over a pit — needs Heavy, landing hard.
	var crack_x: float = tunnel_x + 700.0
	add_warning_sketch(Vector2(crack_x + 40.0, landing_y - 1000.0), "cracked\n(heavy stomp)")
	add_cracked_floor(Rect2(crack_x, landing_y - 830.0, 260.0, 70.0))
	add_ground(Rect2(crack_x + 260.0, landing_y - 830.0, 400.0, 70.0))
	add_ground(Rect2(crack_x - 40.0, landing_y - 200.0, 700.0, 300.0))


func _on_world_ready() -> void:
	Audio.music("mus_lab_loop")
	_spawn_dummy()


## A Scribble Grunt assembled through the ordinary pipeline, standing still.
## It has no brain yet — the AI FSM lands in M4 — so it is exactly what DESIGN
## §11 asks for: a dummy with visible HP.
func _spawn_dummy() -> void:
	var enemy: Dictionary = Config.enemy("enemy_scribble_grunt")
	dummy = (load(CREATURE_SCENE) as PackedScene).instantiate() as Creature
	dummy.name = "Dummy"
	dummy.is_player = false
	dummy.position = Vector2(360.0, FLOOR_Y - 60.0)
	add_child(dummy)

	dummy.assemble(enemy["assembly"] as Dictionary)
	if enemy.has("hp_override"):
		dummy.health.set_maximum(float(enemy["hp_override"]), true)
	dummy.facing = -1

	_dummy_health_label = Paper.label("", 26)
	_dummy_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_dummy_health_label)
	dummy.health.changed.connect(_on_dummy_health_changed)
	dummy.health.died.connect(_on_dummy_died)
	_on_dummy_health_changed(dummy.health.current, dummy.health.maximum)


func _on_dummy_health_changed(current: float, maximum: float) -> void:
	_dummy_health_label.text = "%s\n%d / %d" % [
		str(Config.enemy("enemy_scribble_grunt")["name"]), int(current), int(maximum)]
	_dummy_health_label.position = dummy.position + Vector2(-110.0, -640.0)


## The dummy is a test rig, not an enemy: it comes back so the next build can
## also be measured against it.
func _on_dummy_died() -> void:
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(dummy):
		dummy.health.set_maximum(dummy.health.maximum, true)
