extends Node2D

## A single static sprite carrying the line boil, on paper, with nothing else in
## the frame at all.
##
## That isolation is the point: capture a second of frames and every difference
## between consecutive images must be the boil and nothing else, so counting the
## changes measures the boil rate directly (Mandate A3). The other half of the
## mandate — that transforms stay smooth at full frame rate — is asserted in
## `tests/test_boil.gd`, where a position can be sampled every physics tick
## instead of inferred from pixels.
##
##   godot --rendering-driver opengl3 -- --scene=boil_probe \
##         --shot=user://boil --shot-count=60 --shot-stride=1

const TEXTURE: String = "res://assets/parts/torsos/torso_ribby.png"

var still: Sprite2D = null

func _ready() -> void:
	Paper.background_layer(self)
	still = Sprite2D.new()
	still.texture = load(TEXTURE) as Texture2D
	still.position = Vector2(960, 540)
	LineBoil.apply(still)
	add_child(still)
