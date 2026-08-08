extends Node2D

## A dev-only turntable for the assembly pipeline.
##
##   godot --rendering-driver opengl3 -- --scene=rig_preview
##   … --loadout=head:head_anvil,tail:tail_scorpion,back:back_bat_scraps
##   … --hitboxes --shot=user://rig.png
##
## It exists so a human (or a screenshot in CI) can see that a loadout produced
## the rig the JSON describes. It ships in the repo but is never reachable from
## the game itself.

const PAPER: Color = Color("#f4f0e6")

## Loadouts to cycle with LEFT / RIGHT, chosen to show each slot doing something.
const SHOWCASE: Array[Dictionary] = [
	{"torso": "torso_ribby", "legs": "legs_scribble_sprint", "head": "head_monster_maw"},
	{"torso": "torso_ribby", "legs": "legs_scribble_sprint", "head": "head_monster_maw",
		"tail": "tail_scorpion", "arms": "arms_climber_claws", "back": "back_bat_scraps"},
	{"torso": "torso_barrel", "legs": "legs_tree_trunks", "head": "head_anvil",
		"tail": "tail_eraser_club"},
	{"torso": "torso_ribby", "legs": "legs_spring_coils", "head": "head_pencil_stub",
		"arms": "arms_noodle_hookers", "back": "back_sketch_thrusters"},
]

var _creature: Creature = null
var _readout: Label = null
var _index: int = 0
var _spin: float = 0.0


func _ready() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = PAPER
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.z_index = -100
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = -10
	layer.add_child(background)
	add_child(layer)

	_creature = (load(CreatureFixture.CREATURE_SCENE) as PackedScene).instantiate() as Creature
	_creature.is_player = true
	_creature.position = Vector2(960, 860)
	add_child(_creature)

	_readout = Label.new()
	_readout.position = Vector2(48, 40)
	_readout.add_theme_font_size_override("font_size", 30)
	_readout.add_theme_color_override("font_color", Color.BLACK)
	var ui: CanvasLayer = CanvasLayer.new()
	ui.add_child(_readout)
	add_child(ui)

	_creature.hitbox_root.draw_debug = DevTools.has_option("hitboxes")
	if DevTools.has_option("loadout"):
		_show(_parse_loadout(str(DevTools.option("loadout"))))
	else:
		_show(SHOWCASE[0])


func _process(delta: float) -> void:
	# A slow bone wobble proves hitboxes are bone-local, not creature-local.
	if not DevTools.has_option("still"):
		_spin += delta
		var head: Bone2D = _creature.skeleton.find_child("head", true, false) as Bone2D
		if head != null:
			head.rotation = deg_to_rad(sin(_spin * 1.6) * 18.0)
		var tail: Bone2D = _creature.skeleton.find_child("tail", true, false) as Bone2D
		if tail != null:
			tail.rotation = deg_to_rad(sin(_spin * 1.1) * 25.0)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action("move_right"):
		_index = (_index + 1) % SHOWCASE.size()
		_show(SHOWCASE[_index])
	elif event.is_action("move_left"):
		_index = (_index - 1 + SHOWCASE.size()) % SHOWCASE.size()
		_show(SHOWCASE[_index])
	elif event.is_action("interact"):
		_creature.hitbox_root.draw_debug = not _creature.hitbox_root.draw_debug
	elif event.is_action("crouch_roll"):
		_creature.facing = -_creature.facing


func _show(loadout: Dictionary) -> void:
	var full: Dictionary = {"torso": null, "legs": null, "head": null,
		"tail": null, "arms": null, "back": null}
	for slot: Variant in loadout:
		full[slot] = loadout[slot]

	var problems: PackedStringArray = _creature.assemble(full)
	if not problems.is_empty():
		_readout.text = "REJECTED:\n  %s" % "\n  ".join(problems)
		return

	var worn: PackedStringArray = PackedStringArray()
	for slot: Variant in _creature.stats.loadout:
		if _creature.stats.loadout[slot] != null:
			worn.append("%s: %s" % [slot, _creature.stats.loadout[slot]])
	_readout.text = "%s\n%s\nclass %s [%s]   bbox %d px   boxes %d" % [
		"\n".join(worn), _creature.stats.describe(),
		_creature.weight_class.class_id.to_upper(), _creature.weight_class.stamp(),
		int(_creature.visual_height()), _creature.hitbox_root.all().size()]


func _parse_loadout(text: String) -> Dictionary:
	var loadout: Dictionary = {}
	for pair: String in text.split(",", false):
		var bits: PackedStringArray = pair.split(":")
		if bits.size() == 2:
			loadout[bits[0].strip_edges()] = bits[1].strip_edges()
	return loadout
