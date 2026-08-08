extends TestCase

## M5 acceptance: the corpse run, the pity timer, duplicate conversion and
## Correction Fluid (Decisions 7, 8, 9).

const LEVEL: String = "level_01_margins"
const FLOOR_Y: float = 0.0

var _saved_profile: Dictionary = {}
var _stage: Node2D = null
var _player: Creature = null


func before_each() -> void:
	_saved_profile = SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	_stage = WorldFixture.stage(tree)
	WorldFixture.floor_at(_stage, FLOOR_Y)


func after_each() -> void:
	DropTable.chance_override = -1.0
	CreatureFixture.despawn(_player)
	WorldFixture.clear(_stage)
	DirAccess.remove_absolute(SaveManager.SAVE_PATH)
	SaveManager.data = _saved_profile
	_player = null
	_stage = null


func _tick(count: int = 1) -> void:
	for _i: int in range(count):
		await tree.physics_frame


func _spawn_player(at_x: float = 0.0) -> Creature:
	_player = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	_player.player_input.set_enabled(false)
	_player.add_to_group("player")
	_player.position = Vector2(at_x, FLOOR_Y - 30.0)
	return _player


## A deterministic RNG for ink amounts; the chance rolls are pinned separately.
func _fixed_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	return rng


# --- the corpse run ------------------------------------------------------------

func test_dying_drops_the_whole_wallet_where_you_fell() -> void:
	SaveManager.add_ink(47)
	SaveManager.set_death_blob(LEVEL, Vector2(1234.0, -56.0), SaveManager.ink)
	SaveManager.ink = 0

	var blob: Dictionary = SaveManager.death_blob(LEVEL) as Dictionary
	eq(int(blob["amount"]), 47, "the blob holds all 47")
	almost(float(blob["x"]), 1234.0, 0.5, "at the death position")
	eq(SaveManager.ink, 0, "and the wallet is empty")


func test_a_blob_survives_quitting_to_the_lab_and_relaunching() -> void:
	SaveManager.add_ink(47)
	SaveManager.set_death_blob(LEVEL, Vector2(900.0, -120.0), 47)
	SaveManager.ink = 0

	# Relaunch: throw the in-memory profile away and read the file back.
	SaveManager.data = {}
	SaveManager.load_game()

	var blob: Variant = SaveManager.death_blob(LEVEL)
	not_null(blob, "the blob is still there after a relaunch")
	eq(int((blob as Dictionary)["amount"]), 47, "with its ink intact")


func test_dying_again_before_recovery_overwrites_the_old_blob() -> void:
	SaveManager.add_ink(47)
	SaveManager.set_death_blob(LEVEL, Vector2(900.0, -120.0), 47)
	SaveManager.ink = 0

	SaveManager.add_ink(12)
	SaveManager.set_death_blob(LEVEL, Vector2(-400.0, -60.0), 12)
	SaveManager.ink = 0

	var blob: Dictionary = SaveManager.death_blob(LEVEL) as Dictionary
	eq(int(blob["amount"]), 12, "only the newest blob exists")
	almost(float(blob["x"]), -400.0, 0.5, "at the newest death spot")
	is_true(SaveManager.level_state(LEVEL)["death_blob"] != null, "and there is exactly one")


func test_blobs_in_other_levels_are_untouched() -> void:
	SaveManager.set_death_blob(LEVEL, Vector2(10.0, 0.0), 30)
	SaveManager.set_death_blob("scratchpad", Vector2(20.0, 0.0), 8)
	eq(int((SaveManager.death_blob(LEVEL) as Dictionary)["amount"]), 30, "one per level")
	eq(int((SaveManager.death_blob("scratchpad") as Dictionary)["amount"]), 8, "each waiting")


func test_touching_the_blob_recovers_all_of_it_and_clears_it() -> void:
	SaveManager.set_death_blob(LEVEL, Vector2(0.0, FLOOR_Y - 60.0), 47)
	_spawn_player(0.0)

	var blob: Pickups.DeathBlob = Pickups.DeathBlob.create(47, LEVEL)
	blob.position = Vector2(0.0, FLOOR_Y - 60.0)
	_stage.add_child(blob)
	await _tick(20)

	eq(SaveManager.ink, 47, "100% of the blob comes back")
	is_null(SaveManager.death_blob(LEVEL), "and the level no longer holds one")


# --- blueprint drops -----------------------------------------------------------

func test_the_pity_timer_delivers_on_the_sixth_kill_with_no_luck_at_all() -> void:
	var pity: int = int((Config.enemy("enemy_scribble_grunt")["drops"]
		as Dictionary)["blueprint"]["pity_kills"])
	eq(pity, 6, "the Grunt's pity timer is six kills")

	# Pin every chance roll to a certain failure: only the pity timer can deliver.
	DropTable.chance_override = 1.0
	var rng: RandomNumberGenerator = _fixed_rng()
	var sketches: int = 0
	var dropped_on_kill: int = 0
	for kill: int in range(1, pity + 1):
		for drop: Dictionary in DropTable.roll("enemy_scribble_grunt", rng):
			if str(drop["kind"]) == "blueprint":
				sketches += 1
				dropped_on_kill = kill

	eq(sketches, 1, "exactly one sketch across six kills")
	eq(dropped_on_kill, pity, "and it arrives on the sixth")
	eq(int(SaveManager.kill_counter("enemy_scribble_grunt")["since_drop"]), 0,
		"the counter resets on the drop")
	eq(int(SaveManager.kill_counter("enemy_scribble_grunt")["kills"]), pity,
		"the lifetime count keeps climbing")


func test_the_counter_restarts_after_a_drop() -> void:
	DropTable.chance_override = 1.0
	var rng: RandomNumberGenerator = _fixed_rng()
	for _i: int in range(6):
		DropTable.roll("enemy_scribble_grunt", rng)
	eq(int(SaveManager.kill_counter("enemy_scribble_grunt")["since_drop"]), 0, "reset")

	for _i: int in range(5):
		DropTable.roll("enemy_scribble_grunt", rng)
	eq(int(SaveManager.kill_counter("enemy_scribble_grunt")["since_drop"]), 5,
		"and counts up again towards the next guarantee")


func test_a_kill_always_drops_ink_inside_the_configured_band() -> void:
	var band: Dictionary = (Config.enemy("enemy_stinger")["drops"] as Dictionary)["ink"] as Dictionary
	for _i: int in range(20):
		var ink: int = -1
		for drop: Dictionary in DropTable.roll("enemy_stinger"):
			if str(drop["kind"]) == "ink":
				ink = int(drop["amount"])
		is_true(ink >= int(band["min"]) and ink <= int(band["max"]),
			"ink drop %d is inside %s..%s" % [ink, band["min"], band["max"]])


func test_a_duplicate_sketch_converts_to_ink_and_leaves_no_sketch() -> void:
	var bonus: int = Config.cfg_int("economy.blueprint_duplicate_ink_bonus")
	eq(bonus, 15, "a duplicate is worth 15 ink (DESIGN §8)")
	SaveManager.unlock_part("head_monster_maw")
	_spawn_player(0.0)

	var sketch: Pickups.BlueprintSketch = Pickups.BlueprintSketch.create("head_monster_maw")
	sketch.position = Vector2(0.0, FLOOR_Y - 60.0)
	_stage.add_child(sketch)
	await _tick(20)

	eq(SaveManager.ink, bonus, "it converted to ink")
	is_false(SaveManager.has_blueprint_sketch("head_monster_maw"),
		"and left no duplicate sketch behind")


func test_a_first_sketch_is_kept_rather_than_converted() -> void:
	_spawn_player(0.0)
	var sketch: Pickups.BlueprintSketch = Pickups.BlueprintSketch.create("arms_climber_claws")
	sketch.position = Vector2(0.0, FLOOR_Y - 60.0)
	_stage.add_child(sketch)
	await _tick(20)

	is_true(SaveManager.has_blueprint_sketch("arms_climber_claws"), "the sketch is kept")
	eq(SaveManager.ink, 0, "and no ink is granted for it")


# --- correction fluid ----------------------------------------------------------

func test_correction_fluid_heals_the_configured_amount() -> void:
	eq(Config.cfg_int("economy.correction_fluid.heal"), 25, "it heals 25 (DESIGN §8)")
	_spawn_player(0.0)
	_player.health.take_damage(60)
	var wounded: float = _player.health.current

	var fluid: Pickups.CorrectionFluid = Pickups.CorrectionFluid.create()
	fluid.position = Vector2(0.0, FLOOR_Y - 60.0)
	_stage.add_child(fluid)
	await _tick(20)

	almost(_player.health.current, wounded + 25.0, 0.001, "25 HP restored")


func test_correction_fluid_despawns_after_ten_seconds() -> void:
	almost(Config.cfg_float("economy.correction_fluid.despawn_seconds"), 10.0, 0.001,
		"it gives up after 10 s")
	var fluid: Pickups.CorrectionFluid = Pickups.CorrectionFluid.create()
	fluid.position = Vector2(3000.0, FLOOR_Y - 60.0)
	_stage.add_child(fluid)

	# Age it directly rather than waiting ten real seconds.
	await _tick(2)
	is_true(is_instance_valid(fluid), "still there at first")
	fluid._age = 9.9
	await _tick(12)
	is_false(is_instance_valid(fluid), "and gone once its time is up")


func test_correction_fluid_is_refused_at_full_health() -> void:
	_spawn_player(0.0)
	var fluid: Pickups.CorrectionFluid = Pickups.CorrectionFluid.create()
	fluid.position = Vector2(0.0, FLOOR_Y - 60.0)
	_stage.add_child(fluid)
	await _tick(20)
	is_true(is_instance_valid(fluid), "a full-health player leaves it for later")


# --- ink pickups ---------------------------------------------------------------

func test_ink_is_collected_on_contact() -> void:
	_spawn_player(0.0)
	var ink: Pickups.Ink = Pickups.Ink.create(14)
	ink.position = Vector2(0.0, FLOOR_Y - 60.0)
	_stage.add_child(ink)
	await _tick(20)
	eq(SaveManager.ink, 14, "the wallet gained 14")


func test_ink_is_magnetised_towards_a_nearby_player() -> void:
	_spawn_player(0.0)
	var radius: float = Config.cfg_float("economy.ink_pickup_magnet_radius")
	var ink: Pickups.Ink = Pickups.Ink.create(5)
	ink.position = Vector2(radius * 0.8, FLOOR_Y - 140.0)
	_stage.add_child(ink)
	var start: float = ink.position.x
	await _tick(3)
	is_true(ink.position.x < start, "it drifts towards the player")




# --- the whole loop, in a real scene --------------------------------------------

func test_dying_in_a_level_leaves_a_blob_that_is_there_when_you_come_back() -> void:
	SaveManager.add_ink(47)

	var scene: PlayScene = _enter_scratchpad()
	await _tick(20)
	# Die well away from the entrance: dying *on* the spawn point would have the
	# respawn land straight on top of the blob and recover it immediately.
	scene.player.position = scene.spawn_point + Vector2(1500.0, -200.0)
	await _tick(6)
	var death_spot: Vector2 = scene.player.global_position
	scene.player.health.take_damage(99999)
	await _tick(6)

	eq(SaveManager.ink, 0, "the wallet emptied on death")
	var blob: Variant = SaveManager.death_blob("scratchpad")
	not_null(blob, "a blob was left behind")
	almost(float((blob as Dictionary)["x"]), death_spot.x, 4.0, "at the death spot")
	eq(int((blob as Dictionary)["amount"]), 47, "holding all 47")

	_leave(scene)

	# Walk back in: the level rebuilds its blob from the save.
	var revisit: PlayScene = _enter_scratchpad()
	await _tick(10)
	var blobs: int = 0
	for child: Node in revisit.get_children():
		if child is Pickups.DeathBlob:
			blobs += 1
	eq(blobs, 1, "exactly one blob is waiting where it fell")
	_leave(revisit)


func _enter_scratchpad() -> PlayScene:
	var scene: PlayScene = (load("res://scenes/lab/scratchpad.tscn") as PackedScene)\
		.instantiate() as PlayScene
	tree.root.add_child(scene)
	scene.player.player_input.set_enabled(false)
	return scene


func _leave(scene: PlayScene) -> void:
	scene.get_parent().remove_child(scene)
	scene.queue_free()
