class_name ExitDoor
extends Area2D

## The way out of a level. Touching it clears the level, which marks it on the
## sketchbook map and persists (DESIGN §11).

signal reached(by: Creature)

var _used: bool = false


func _ready() -> void:
	collision_layer = Layers.bit(Layers.PICKUP)
	collision_mask = Layers.bit(Layers.PLAYER_BODY)
	monitoring = true
	body_entered.connect(_on_body_entered)

	var frame: Line2D = Line2D.new()
	frame.width = 8.0
	frame.default_color = Paper.INK
	frame.closed = true
	frame.points = PackedVector2Array([
		Vector2(-90, 40), Vector2(-78, -250), Vector2(84, -262), Vector2(96, 34)])
	add_child(frame)

	var label: Label = Paper.label("OUT", 40)
	label.position = Vector2(-46, -170)
	add_child(label)

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(190, 300)
	shape_node.shape = shape
	shape_node.position = Vector2(0, -110)
	add_child(shape_node)


func _on_body_entered(body: Node2D) -> void:
	var creature: Creature = body as Creature
	if _used or creature == null or not creature.is_player:
		return
	_used = true
	Audio.sfx("sfx_ui_stamp")
	reached.emit(creature)
