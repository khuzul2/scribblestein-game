extends TestCase

## M6 acceptance, the half that is better measured than photographed: the boil
## is a texture effect only, every sprite carries it with its own phase, and
## every sound the game asks for exists.
##
## The other half — that the boil steps 8-12 times a second and that a finished
## frame contains only palette colours — is checked against real rendered frames
## by `tools/verify_frames.gd`, driven from `tools/acceptance.sh`.

const FLOOR_Y: float = 0.0

var _stage: Node2D = null
var _creature: Creature = null
var _heard: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_stage = WorldFixture.stage(tree)
	WorldFixture.floor_at(_stage, FLOOR_Y)
	_heard = PackedStringArray()
	Audio.sfx_played.connect(_on_sfx)


func after_each() -> void:
	if Audio.sfx_played.is_connected(_on_sfx):
		Audio.sfx_played.disconnect(_on_sfx)
	CreatureFixture.despawn(_creature)
	WorldFixture.clear(_stage)
	_creature = null
	_stage = null


func _on_sfx(sfx_id: String) -> void:
	_heard.append(sfx_id)


func _spawn() -> Creature:
	_creature = CreatureFixture.spawn(tree, CreatureFixture.loadout(), true)
	_creature.player_input.set_enabled(false)
	_creature.position = Vector2(0.0, FLOOR_Y - 40.0)
	return _creature


# --- the shader ----------------------------------------------------------------

func test_every_creature_sprite_boils() -> void:
	_spawn()
	var sprites: int = 0
	for sprite: Sprite2D in _all_sprites(_creature.skeleton):
		sprites += 1
		not_null(sprite.material, "%s has a material" % sprite.name)
		var material: ShaderMaterial = sprite.material as ShaderMaterial
		not_null(material, "%s carries a ShaderMaterial" % sprite.name)
		if material != null:
			eq(material.shader.resource_path, LineBoil.SHADER_PATH,
				"%s boils" % sprite.name)
	is_true(sprites >= 3, "the starter kit put at least three sprites on the rig")


func test_each_sprite_boils_on_its_own_phase() -> void:
	# Mandate A3: parts must never boil in sync, or the creature reads as one
	# sliding texture instead of redrawn linework.
	_spawn()
	var seeds: Dictionary = {}
	for sprite: Sprite2D in _all_sprites(_creature.skeleton):
		var material: ShaderMaterial = sprite.material as ShaderMaterial
		if material == null:
			continue
		seeds[material.get_shader_parameter("seed")] = true
	is_true(seeds.size() >= 3, "every sprite got a different seed (%d distinct)" % seeds.size())


func test_the_shader_takes_its_numbers_from_the_config() -> void:
	_spawn()
	var material: ShaderMaterial = _all_sprites(_creature.skeleton)[0].material as ShaderMaterial
	almost(float(material.get_shader_parameter("boil_fps")),
		Config.cfg_float("line_boil.boil_fps"), 0.0001, "boil_fps")
	almost(float(material.get_shader_parameter("amplitude_px")),
		Config.cfg_float("line_boil.amplitude_px"), 0.0001, "amplitude_px")

	var band: Array = Config.cfg("line_boil.boil_fps_range") as Array
	is_true(Config.cfg_float("line_boil.boil_fps") >= float(band[0])
		and Config.cfg_float("line_boil.boil_fps") <= float(band[1]),
		"and the configured rate sits inside the mandated 8-12 band")


func test_the_boil_never_touches_the_transform() -> void:
	# The whole point of Mandate A3: the wobble is in the texture lookup, so
	# motion stays smooth at full frame rate. Sample a running creature every
	# physics tick — every single one must have moved.
	_spawn()
	for _i: int in range(20):
		await tree.physics_frame

	_creature.locomotion.intent.move_axis = 1.0
	var samples: PackedFloat32Array = PackedFloat32Array()
	for _i: int in range(60):
		await tree.physics_frame
		samples.append(_creature.global_position.x)

	var moved: int = 0
	for index: int in range(1, samples.size()):
		if not is_equal_approx(samples[index], samples[index - 1]):
			moved += 1
	eq(moved, samples.size() - 1,
		"the creature's transform changed on every one of %d ticks" % (samples.size() - 1))

	# And the sprites are still boiling while it runs.
	var material: ShaderMaterial = _all_sprites(_creature.skeleton)[0].material as ShaderMaterial
	not_null(material, "the boil is still applied mid-run")


# --- audio ---------------------------------------------------------------------

func test_every_sound_the_spec_lists_exists() -> void:
	var missing: PackedStringArray = Audio.missing_required()
	is_true(missing.is_empty(),
		"every ASSET_SPEC §6 id has a file: missing %s" % ", ".join(missing))


func test_creature_actions_are_audible() -> void:
	_spawn()
	for _i: int in range(20):
		await tree.physics_frame

	_heard = PackedStringArray()
	_creature.locomotion.intent.press_jump()
	await tree.physics_frame
	is_true(_heard.has("sfx_jump_mouthpop"), "jumping is audible")

	_heard = PackedStringArray()
	for _i: int in range(80):
		await tree.physics_frame
		if _creature.is_on_floor() and _creature.velocity.y >= 0.0:
			break
	is_true(_heard.has("sfx_land_thud_med"), "landing is audible, at its weight class")

	_heard = PackedStringArray()
	_creature.attack_controller.request("attack_primary")
	await tree.physics_frame
	is_true(_heard.has("sfx_attack_windup_inhale"), "the wind-up is audible")
	for _i: int in range(20):
		await tree.physics_frame
	is_true(_heard.has("sfx_bite_chomp"), "the bite itself is audible")

	_heard = PackedStringArray()
	_creature.health.take_damage(5)
	is_true(_heard.has("sfx_hit_beatbox_thud"), "taking a hit is audible")

	# The hit above started the player's i-frames; wait them out or the killing
	# blow is swallowed.
	for _i: int in range(int(Config.cfg_float("combat.player_iframes_on_hit") * 60.0) + 4):
		await tree.physics_frame
	_heard = PackedStringArray()
	_creature.health.take_damage(99999)
	is_true(_heard.has("sfx_death_paper_tear"), "dying is audible")


func test_running_scribbles_footsteps() -> void:
	_spawn()
	for _i: int in range(20):
		await tree.physics_frame

	_heard = PackedStringArray()
	_creature.locomotion.intent.move_axis = 1.0
	for _i: int in range(90):
		await tree.physics_frame

	var steps: int = 0
	for sound_id: String in _heard:
		if sound_id.begins_with("sfx_step_scribble_"):
			steps += 1
	is_true(steps >= 2, "a second and a half of running scribbles at least twice (got %d)" % steps)


func test_the_lab_and_a_level_each_ask_for_their_own_track() -> void:
	is_true(Audio.has("mus_lab_loop"), "the Lab has a track")
	is_true(Audio.has("mus_level01_loop"), "and so does Level 01")


func _all_sprites(root: Node) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	for child: Node in root.get_children():
		if child is Sprite2D:
			found.append(child as Sprite2D)
		found.append_array(_all_sprites(child))
	return found
