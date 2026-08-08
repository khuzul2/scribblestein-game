extends TestCase

## M2 acceptance: the camera zoom follows TECH_SPEC §6 for the smallest and the
## largest creature the part catalogue can build (Mandate A4).

## The smallest legal biped: required slots only, lightest parts.
const SMALLEST: Dictionary = {
	"torso": "torso_ribby", "legs": "legs_scribble_sprint",
	"head": null, "tail": null, "arms": null, "back": null,
}
## The largest: every slot filled with the biggest part that fits it.
const LARGEST: Dictionary = {
	"torso": "torso_barrel", "legs": "legs_tree_trunks", "head": "head_anvil",
	"tail": "tail_eraser_club", "arms": "arms_climber_claws", "back": "back_sketch_thrusters",
}

var _creature: Creature = null


func after_each() -> void:
	CreatureFixture.despawn(_creature)
	_creature = null


func _expected_zoom(height: float) -> float:
	return clampf(Config.cfg_float("camera.ref_height") / height,
		Config.cfg_float("camera.zoom_min"), Config.cfg_float("camera.zoom_max"))


func test_the_formula_clamps_at_both_ends() -> void:
	var minimum: float = Config.cfg_float("camera.zoom_min")
	var maximum: float = Config.cfg_float("camera.zoom_max")
	almost(CreatureCamera.zoom_for_height(100000.0), minimum, 0.0001,
		"an enormous creature pulls the camera out to zoom_min")
	almost(CreatureCamera.zoom_for_height(1.0), maximum, 0.0001,
		"a speck pulls it in to zoom_max")
	almost(CreatureCamera.zoom_for_height(Config.cfg_float("camera.ref_height")), 1.0, 0.0001,
		"a creature exactly ref_height tall renders 1:1")


func test_a_minimum_size_creature_frames_to_the_formula() -> void:
	_creature = CreatureFixture.spawn(tree, SMALLEST, true)
	await tree.process_frame
	var height: float = _creature.visual_height()
	is_true(height > 0.0, "the creature has a measurable bounding box")
	almost(_creature.camera.target_zoom(), _expected_zoom(height), 0.0001,
		"target zoom for a %d px creature" % int(height))


func test_a_maximum_size_creature_frames_to_the_formula() -> void:
	_creature = CreatureFixture.spawn(tree, LARGEST, true)
	await tree.process_frame
	var height: float = _creature.visual_height()
	almost(_creature.camera.target_zoom(), _expected_zoom(height), 0.0001,
		"target zoom for a %d px creature" % int(height))


func test_a_bigger_creature_gets_a_wider_view() -> void:
	_creature = CreatureFixture.spawn(tree, SMALLEST, true)
	await tree.process_frame
	var small_height: float = _creature.visual_height()
	var small_zoom: float = _creature.camera.target_zoom()

	_creature.assemble(LARGEST)
	await tree.process_frame
	var large_height: float = _creature.visual_height()

	is_true(large_height > small_height,
		"the maximal build (%d px) is taller than the minimal one (%d px)"
		% [int(large_height), int(small_height)])
	is_true(_creature.camera.target_zoom() < small_zoom,
		"and the camera zooms out to hold it")


func test_the_zoom_is_lerped_never_snapped() -> void:
	# Mandate A4: zoom changes are smoothed. The boil may stutter; framing may not.
	_creature = CreatureFixture.spawn(tree, SMALLEST, true)
	_creature.camera.snap_to_target()
	await tree.process_frame
	var before: float = _creature.camera.zoom.x

	_creature.assemble(LARGEST)
	await tree.process_frame
	var after_one_frame: float = _creature.camera.zoom.x
	ne(after_one_frame, _creature.camera.target_zoom(),
		"one frame does not reach the new target")
	is_true(absf(after_one_frame - before) < absf(_creature.camera.target_zoom() - before),
		"it moves part of the way there")

	for _i: int in range(240):
		await tree.process_frame
	almost(_creature.camera.zoom.x, _creature.camera.target_zoom(), 0.005,
		"and settles on it")


func test_the_camera_looks_ahead_in_the_facing_direction() -> void:
	_creature = CreatureFixture.spawn(tree, SMALLEST, true)
	_creature.facing = 1
	_creature.camera.snap_to_target()
	await tree.process_frame
	almost(_creature.camera.offset.x, Config.cfg_float("camera.lookahead_px"), 0.001,
		"facing right, the camera leads to the right")

	_creature.facing = -1
	_creature.camera.snap_to_target()
	await tree.process_frame
	almost(_creature.camera.offset.x, -Config.cfg_float("camera.lookahead_px"), 0.001,
		"facing left, it leads to the left")


func test_enemies_do_not_carry_a_live_camera() -> void:
	_creature = CreatureFixture.spawn(tree, SMALLEST, false)
	await tree.process_frame
	is_false(_creature.camera.enabled, "only the player's camera is enabled")
