class_name WorldFixture
extends RefCounted

## Minimal physics scenery for movement tests: a floor to land on, a wall to
## climb, a cracked tile to stomp through.

const CRACKED_FLOOR_SCENE: String = "res://scenes/world/cracked_floor.tscn"


## A wide static floor whose *top surface* sits at `surface_y`.
static func floor_at(parent: Node, surface_y: float, width: float = 8000.0) -> StaticBody2D:
	return _slab(parent, Vector2(0.0, surface_y + 200.0), Vector2(width, 400.0),
		Layers.bit(Layers.WORLD), "Floor")


## A vertical wall whose *left face* sits at `face_x`.
static func wall_at(parent: Node, face_x: float, centre_y: float,
		height: float = 2000.0) -> StaticBody2D:
	return _slab(parent, Vector2(face_x + 100.0, centre_y), Vector2(200.0, height),
		Layers.bit(Layers.WORLD), "Wall")


## A climbable region — an Area2D on the `climbable` layer, which is what
## `can_climb` looks for. Pair it with a wall to make a scalable surface.
static func climbable_region(parent: Node, centre: Vector2, size: Vector2) -> Area2D:
	var area: Area2D = Area2D.new()
	area.name = "Climbable"
	area.position = centre
	area.collision_layer = Layers.bit(Layers.CLIMBABLE)
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape
	area.add_child(shape_node)
	parent.add_child(area)
	return area


## A cracked tile whose top surface sits at `surface_y`.
static func cracked_floor(parent: Node, centre_x: float, surface_y: float) -> CrackedFloor:
	var tile: CrackedFloor = (load(CRACKED_FLOOR_SCENE) as PackedScene).instantiate() as CrackedFloor
	tile.position = Vector2(centre_x, surface_y + 64.0)
	parent.add_child(tile)
	return tile


static func _slab(parent: Node, centre: Vector2, size: Vector2,
		layer: int, slab_name: String) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = slab_name
	body.position = centre
	body.collision_layer = layer
	body.collision_mask = 0

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	return body


## A throwaway container so a test can free all its scenery in one call.
static func stage(tree: SceneTree) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = "TestStage"
	tree.root.add_child(node)
	return node


static func clear(stage_node: Node2D) -> void:
	if is_instance_valid(stage_node):
		stage_node.get_parent().remove_child(stage_node)
		stage_node.queue_free()
