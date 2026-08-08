extends TestCase

## M4 acceptance: each enemy assembles from `enemies.json` through the ordinary
## pipeline and runs the FSM — patrol, chase inside aggro_radius, attack inside
## attack_range (TECH_SPEC §3).

const FLOOR_Y: float = 0.0

var _stage: Node2D = null
var _player: Creature = null
var _enemy: Creature = null


func before_each() -> void:
	_stage = WorldFixture.stage(tree)
	WorldFixture.floor_at(_stage, FLOOR_Y)
	Combat.hitstop_enabled = false


func after_each() -> void:
	Combat.hitstop_enabled = true
	CreatureFixture.despawn(_player)
	if is_instance_valid(_enemy):
		_enemy.get_parent().remove_child(_enemy)
		_enemy.queue_free()
	WorldFixture.clear(_stage)
	_player = null
	_enemy = null
	_stage = null


func _tick(count: int = 1) -> void:
	for _i: int in range(count):
		await tree.physics_frame


func _spawn_player(at_x: float) -> Creature:
	_player = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	_player.player_input.set_enabled(false)
	_player.position = Vector2(at_x, FLOOR_Y - 30.0)
	return _player


func _spawn_enemy(enemy_id: String, at_x: float) -> Creature:
	_enemy = EnemyFactory.spawn(enemy_id, _stage, Vector2(at_x, FLOOR_Y - 30.0), _player)
	return _enemy


func _brain() -> AIBrain:
	return EnemyFactory.brain_of(_enemy)


# --- assembly ------------------------------------------------------------------

func test_all_three_enemies_assemble_from_the_catalogue() -> void:
	for enemy_id: String in ["enemy_scribble_grunt", "enemy_wall_crawler", "enemy_stinger"]:
		var enemy: Dictionary = Config.enemy(enemy_id)
		_spawn_player(-4000.0)
		_spawn_enemy(enemy_id, 0.0)
		not_null(_enemy, "%s spawned" % enemy_id)
		if _enemy == null:
			continue

		almost(_enemy.health.maximum, float(enemy["hp_override"]), 0.001,
			"%s uses its hp_override" % enemy_id)
		is_false(_enemy.is_player, "%s is not the player" % enemy_id)
		not_null(_brain(), "%s has an AIBrain" % enemy_id)
		is_false(_enemy.player_input.is_physics_processing(),
			"%s is not driven by player input — the controller is the only difference"
			% enemy_id)

		for slot: Variant in enemy["assembly"] as Dictionary:
			eq(_enemy.stats.loadout.get(slot), (enemy["assembly"] as Dictionary)[slot],
				"%s wears its %s" % [enemy_id, slot])

		after_each()
		before_each()


func test_enemy_abilities_come_from_the_parts_it_wears() -> void:
	_spawn_player(-4000.0)
	_spawn_enemy("enemy_wall_crawler", 0.0)
	is_true(_enemy.has_effect("can_climb"), "the Wall Crawler climbs because it wears claws")

	after_each()
	before_each()
	_spawn_player(-4000.0)
	_spawn_enemy("enemy_stinger", 0.0)
	is_true(_enemy.has_effect("can_glide"), "the Stinger glides because it wears wings")
	is_true(_enemy.has_effect("sting_attack"), "and stings because it wears a tail")
	is_false(_enemy.attack_controller.has_attack("attack_primary"),
		"with no head, its primary button is inert — exactly like a player build")


# --- the FSM -------------------------------------------------------------------

func test_an_enemy_patrols_when_nothing_is_near() -> void:
	_spawn_player(-6000.0)
	_spawn_enemy("enemy_scribble_grunt", 0.0)
	await _tick(10)
	eq(_brain().state_name(), "PATROL", "far from the player, it patrols")

	var start_x: float = _enemy.position.x
	await _tick(40)
	is_true(absf(_enemy.position.x - start_x) > 40.0, "and it actually walks")


func test_an_enemy_turns_round_at_a_ledge() -> void:
	# A short platform: the only way to stay on it is to notice the edges.
	WorldFixture.clear(_stage)
	_stage = WorldFixture.stage(tree)
	WorldFixture.floor_at(_stage, FLOOR_Y, 700.0)

	_spawn_player(-6000.0)
	_spawn_enemy("enemy_scribble_grunt", 0.0)
	await _tick(240)
	is_true(absf(_enemy.position.x) < 400.0,
		"after four seconds of patrolling it is still on its 700 px platform (x=%d)"
		% int(_enemy.position.x))
	is_true(_enemy.position.y < FLOOR_Y + 200.0, "and has not fallen off")


func test_an_enemy_chases_once_the_player_is_inside_aggro_radius() -> void:
	_spawn_player(-6000.0)
	_spawn_enemy("enemy_scribble_grunt", 0.0)
	await _tick(10)
	eq(_brain().state_name(), "PATROL", "out of range")

	# Step inside the aggro radius but outside attack range.
	var radius: float = _brain().aggro_radius()
	_player.position = Vector2(radius * 0.6, FLOOR_Y - 30.0)
	await _tick(10)
	eq(_brain().state_name(), "CHASE", "inside aggro_radius it gives chase")

	var gap_before: float = absf(_enemy.position.x - _player.position.x)
	await _tick(45)
	is_true(absf(_enemy.position.x - _player.position.x) < gap_before,
		"and it closes the distance")


func test_an_enemy_attacks_once_the_player_is_inside_attack_range() -> void:
	_spawn_player(0.0)
	_spawn_enemy("enemy_scribble_grunt", _brain_range_for("enemy_scribble_grunt") * 0.7)
	await _tick(20)

	var attacked: bool = false
	for _i: int in range(90):
		await tree.physics_frame
		if _enemy.attack_controller.phase != AttackController.Phase.IDLE:
			attacked = true
			break
	is_true(attacked, "inside attack_range it swings")


func test_an_enemy_gives_up_past_the_deaggro_radius() -> void:
	_spawn_player(0.0)
	_spawn_enemy("enemy_scribble_grunt", 300.0)
	await _tick(20)
	ne(_brain().state_name(), "PATROL", "it noticed the player")

	_player.position = Vector2(_brain().deaggro_radius() + 400.0, FLOOR_Y - 30.0)
	await _tick(20)
	eq(_brain().state_name(), "PATROL", "far enough away, it loses interest")


func test_a_dead_enemy_stops_thinking() -> void:
	_spawn_player(0.0)
	_spawn_enemy("enemy_scribble_grunt", 200.0)
	await _tick(20)
	_enemy.health.take_damage(9999)
	await _tick(10)
	is_true(_enemy.health.is_dead(), "the enemy is dead")
	eq(_enemy.attack_controller.phase, AttackController.Phase.IDLE, "and stops attacking")
	almost(_enemy.locomotion.intent.move_axis, 0.0, 0.001, "and stops steering")


func test_an_enemy_walks_at_its_configured_patrol_speed() -> void:
	_spawn_player(-6000.0)
	_spawn_enemy("enemy_scribble_grunt", 0.0)
	await _tick(50)
	within_percent(absf(_enemy.velocity.x), _brain().patrol_speed(), 0.12,
		"patrol speed comes from enemies.json")


func _brain_range_for(enemy_id: String) -> float:
	return float((Config.enemy(enemy_id)["ai"] as Dictionary)["attack_range"])
