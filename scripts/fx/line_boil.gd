class_name LineBoil
extends RefCounted

## Applies `line_boil.gdshader` to a CanvasItem with its own random phase
## (Mandate A3, TECH_SPEC §7).
##
## Every sprite gets its own `ShaderMaterial` so it can carry its own `seed`;
## that is what stops a creature's parts boiling in lockstep, which reads as a
## sliding texture rather than as redrawn linework.
##
## Every parameter comes from `game_config.json → line_boil`.

const SHADER_PATH: String = "res://scripts/fx/line_boil.gdshader"

## Set false to strip the boil globally — used by the frame-timing check, and
## handy when eyeballing alignment.
static var enabled: bool = true

static var _shader: Shader = null
static var _rng: RandomNumberGenerator = null


## Give `item` its own boiling material. `ui` halves the amplitude for
## legibility (ASSET_SPEC §1).
static func apply(item: CanvasItem, ui: bool = false) -> void:
	if not enabled or item == null:
		return
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _shader_resource()
	material.set_shader_parameter("boil_fps", Config.cfg_float("line_boil.boil_fps"))
	material.set_shader_parameter("amplitude_px", Config.cfg_float(
		"line_boil.ui_amplitude_px" if ui else "line_boil.amplitude_px"))
	material.set_shader_parameter("seed", _next_seed())
	item.material = material


## Apply to every CanvasItem under `root`, sprites and tiles alike.
static func apply_to_tree(root: Node) -> void:
	if not enabled:
		return
	for child: Node in root.get_children():
		if child is Sprite2D:
			apply(child as CanvasItem)
		apply_to_tree(child)


static func _shader_resource() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


static func _next_seed() -> float:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		if Config.cfg("line_boil.per_instance_random_seed"):
			_rng.randomize()
	return _rng.randf_range(0.0, 1000.0)
