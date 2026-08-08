extends TestCase

## M3 acceptance: editor → Scratchpad → editor in under three seconds, with the
## loadout intact (DESIGN §11 — "Instant, no fade > 0.3 s").

const MAIN_SCENE: String = "res://scenes/main.tscn"
const ROUND_TRIP_BUDGET_MS: int = 3000

var _saved_profile: Dictionary = {}
var _game: Node = null


func before_each() -> void:
	_saved_profile = SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()


func after_each() -> void:
	if is_instance_valid(_game):
		_game.get_parent().remove_child(_game)
		_game.queue_free()
	_game = null
	SaveManager.data = _saved_profile


func _boot() -> Node:
	_game = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(_game)
	return _game


func _settle(frames: int = 30) -> void:
	for _i: int in range(frames):
		await tree.process_frame


## Wait for the router to finish a transition. `goto_*` is a coroutine that fades
## out, swaps and fades in, and ignores a second request while one is in flight,
## so a test must wait for the scene to actually be up before asking for another.
func _await_scene(game: Node, scene_id: String, limit: int = 240) -> Node:
	for _i: int in range(limit):
		await tree.process_frame
		if str(game.get("current_scene_id")) == scene_id \
				and game.call("current_scene") != null \
				and not bool(game.call("is_busy")):
			return game.call("current_scene") as Node
	return null


func test_the_fade_budget_is_within_the_design_limit() -> void:
	# Out and back in — DESIGN §11 allows 0.3 s total.
	is_true(load("res://scripts/core/game.gd").get("FADE_SECONDS") * 2.0 <= 0.3,
		"the whole transition fits in 0.3 s")


func test_editor_to_scratchpad_and_back_keeps_the_loadout() -> void:
	SaveManager.unlock_part("tail_scorpion")
	SaveManager.set_loadout(CreatureFixture.loadout({"tail": "tail_scorpion"}))

	var game: Node = _boot()
	not_null(await _await_scene(game, "lab"), "the game boots into the Lab")

	var started: int = Time.get_ticks_msec()

	game.call("goto_level", "scratchpad")
	var scratchpad: PlayScene = await _await_scene(game, "scratchpad") as PlayScene
	not_null(scratchpad, "Play in Lab reaches the Scratchpad")
	not_null(scratchpad.player, "and spawned the player")
	eq(str(scratchpad.player.stats.loadout["tail"]), "tail_scorpion",
		"wearing the loadout committed in the editor")

	game.call("goto_lab")
	var lab: Lab = await _await_scene(game, "lab") as Lab
	var elapsed: int = Time.get_ticks_msec() - started
	not_null(lab, "and comes back to the Lab")
	eq(str(lab.current_loadout()["tail"]), "tail_scorpion", "with the loadout intact")
	is_true(elapsed <= ROUND_TRIP_BUDGET_MS,
		"the round trip took %d ms, within the %d ms budget" % [elapsed, ROUND_TRIP_BUDGET_MS])


func test_the_scratchpad_carries_one_of_every_obstacle() -> void:
	var game: Node = _boot()
	await _await_scene(game, "lab")
	game.call("goto_level", "scratchpad")
	var scratchpad: PlayScene = await _await_scene(game, "scratchpad") as PlayScene
	not_null(scratchpad, "the Scratchpad instantiated")
	if scratchpad == null:
		return

	var cracked: int = 0
	var climbable: int = 0
	var ground: int = 0
	for child: Node in scratchpad.get_children():
		if child is CrackedFloor:
			cracked += 1
		elif child is Area2D and child.name == "Climbable":
			climbable += 1
		elif child is StaticBody2D:
			ground += 1
	is_true(cracked >= 1, "there is a cracked floor to stomp")
	is_true(climbable >= 1, "there is a wall to climb")
	is_true(ground >= 8, "and enough geometry for stairs, a gap and a tunnel")
	not_null(scratchpad.get("dummy"), "and a dummy to hit")


func test_the_scratchpad_dummy_shows_its_health() -> void:
	var game: Node = _boot()
	await _await_scene(game, "lab")
	game.call("goto_level", "scratchpad")
	var scratchpad: PlayScene = await _await_scene(game, "scratchpad") as PlayScene
	not_null(scratchpad, "the Scratchpad instantiated")
	if scratchpad == null:
		return
	var dummy: Creature = scratchpad.get("dummy") as Creature
	not_null(dummy, "the dummy exists")
	almost(dummy.health.maximum, 60.0, 0.001,
		"at the hp_override from enemies.json, not the computed total")
	is_false(dummy.is_player, "and it is not the player")


func test_entering_a_level_from_the_map_routes_through_the_game() -> void:
	var game: Node = _boot()
	var lab: Lab = await _await_scene(game, "lab") as Lab
	not_null(lab, "the Lab is up")
	if lab == null:
		return
	lab.world_map.level_chosen.emit("scratchpad")
	not_null(await _await_scene(game, "scratchpad"), "the map table launches the scene")
