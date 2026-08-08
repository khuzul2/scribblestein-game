class_name PlayScene
extends Node2D

## Base for every scene the creature is actually played in — the Scratchpad and
## every level. It owns the things they all share: spawning the committed
## assembly, the HUD, the pause menu, and the way out.
##
## Subclasses build their own geometry in `_build_world()`; everything else here
## is identical, so a level cannot accidentally diverge from the Scratchpad in
## how it treats the player.

signal exit_requested
signal level_completed(level_id: String)
signal player_died(at: Vector2, ink_lost: int)
signal enemy_killed(enemy_id: String, at: Vector2)

const CREATURE_SCENE: String = "res://scenes/creature/creature.tscn"

## Which entry in `levels.json` this scene is. Drives save state and music.
@export var level_id: String = ""

var player: Creature = null
var hud: Hud = null
var pause_menu: PauseMenu = null
var spawn_point: Vector2 = Vector2.ZERO
## Injectable so tests can force the blueprint RNG to fail and prove the pity
## timer alone still delivers.
var drop_rng: RandomNumberGenerator = null

## How far below the lowest ground a creature may fall before the level catches
## it. Nothing in Scribblestein is a bottomless pit.
const FALL_MARGIN_PX: float = 900.0

var _enemies: Array[Creature] = []
var _lowest_ground_y: float = -INF
var _last_safe_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	Paper.background_layer(self)
	_build_world()
	_spawn_player()
	_build_ui()
	_restore_death_blob()
	_on_world_ready()


## Subclass hook: lay out the geometry. `spawn_point` should be set here.
func _build_world() -> void:
	pass


## Subclass hook: called once the player and HUD exist.
func _on_world_ready() -> void:
	pass


func _spawn_player() -> void:
	player = (load(CREATURE_SCENE) as PackedScene).instantiate() as Creature
	player.name = "Player"
	player.is_player = true
	# The body type is a save-level choice, so a level plays whichever one was
	# last built in the Lab rather than assuming a biped.
	player.blueprint_id = SaveManager.active_blueprint()
	player.position = spawn_point
	add_child(player)

	player.add_to_group("player")
	player.health.died.connect(_on_player_died)

	var problems: PackedStringArray = player.assemble(SaveManager.loadout())
	if not problems.is_empty():
		# Entering with an illegal loadout is a bug upstream, not something to
		# paper over — say so and bounce the player back to the Lab.
		push_error("Cannot enter '%s': %s" % [level_id, ", ".join(problems)])
		exit_requested.emit.call_deferred()
		return
	_last_safe_position = spawn_point
	player.camera.snap_to_target()


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	hud = Hud.new()
	hud.name = "Hud"
	layer.add_child(hud)
	hud.watch(player)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	layer.add_child(pause_menu)
	pause_menu.return_to_lab.connect(func() -> void: exit_requested.emit())


## Catch anything that falls out of the world. `game_config.json` asks for
## `hazard_respawn_at_last_ground`, so a fall costs hazard damage and puts the
## player back where it last had its feet down — not a death, and never an
## endless drop.
func _physics_process(_delta: float) -> void:
	if player == null or player.health.is_dead():
		return
	if player.is_on_floor():
		_last_safe_position = player.global_position
	elif player.global_position.y > _lowest_ground_y + FALL_MARGIN_PX:
		_catch_fall()


func _catch_fall() -> void:
	player.global_position = _last_safe_position
	player.velocity = Vector2.ZERO
	Combat.resolve_hazard(player, Config.cfg_int("combat.hazard_damage"), _last_safe_position)
	player.camera.snap_to_target()


## Track the lowest floor the level built, so the catch line sits below it.
func _note_ground(rect: Rect2) -> void:
	_lowest_ground_y = maxf(_lowest_ground_y, rect.end.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		pause_menu.toggle()


## Spawn an enemy that hunts the player and drops when it dies.
func add_enemy(enemy_id: String, at: Vector2) -> Creature:
	var enemy: Creature = EnemyFactory.spawn(enemy_id, self, at, player)
	if enemy == null:
		return null
	_enemies.append(enemy)
	enemy.health.died.connect(_on_enemy_died.bind(enemy))
	return enemy


func enemies() -> Array[Creature]:
	return _enemies.filter(func(e: Creature) -> bool: return is_instance_valid(e))


## An enemy dies: roll its drop table, scatter the result, and let the level know.
func _on_enemy_died(enemy: Creature) -> void:
	var enemy_id: String = EnemyFactory.id_of(enemy)
	if enemy_id == "":
		return
	DropTable.spawn_all(DropTable.roll(enemy_id, drop_rng), self,
		enemy.global_position, drop_rng)
	enemy_killed.emit(enemy_id, enemy.global_position)
	_enemies.erase(enemy)
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(enemy):
		enemy.queue_free()


## Death drops the entire wallet as one blob where you fell, and you restart at
## the entrance with full HP. A second death overwrites the first blob — the old
## ink is gone forever (Decision 7, DESIGN §7).
func _on_player_died() -> void:
	var lost: int = SaveManager.ink
	var at: Vector2 = player.global_position
	if level_id != "":
		SaveManager.set_death_blob(level_id, at, lost)
	SaveManager.ink = 0
	player_died.emit(at, lost)

	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return  # the player quit to the Lab before the respawn beat finished
	_clear_blobs()
	_restore_death_blob()
	respawn_player()


## Respawn at the entrance with full HP (DESIGN §7).
func respawn_player() -> void:
	player.position = spawn_point
	player.velocity = Vector2.ZERO
	player.health.set_maximum(player.stats.max_hp, true)
	player.hitbox_root.set_hurtboxes_enabled(true)
	_last_safe_position = spawn_point
	player.camera.snap_to_target()


## Put back the blob this level is holding, if any. Called on entry and after a
## death, so it survives a restart, a hub trip and a relaunch.
func _restore_death_blob() -> void:
	if level_id == "":
		return
	var blob: Variant = SaveManager.death_blob(level_id)
	if blob == null:
		return
	var record: Dictionary = blob as Dictionary
	var pickup: Pickups.DeathBlob = Pickups.DeathBlob.create(int(record["amount"]), level_id)
	pickup.position = Vector2(float(record["x"]), float(record["y"]))
	add_child(pickup)


func _clear_blobs() -> void:
	for child: Node in get_children():
		if child is Pickups.DeathBlob:
			remove_child(child)
			child.queue_free()


func mark_completed() -> void:
	if level_id != "":
		SaveManager.mark_level_completed(level_id)
	level_completed.emit(level_id)


# --- geometry helpers used by every play scene ---------------------------------

## A solid slab of world. `rect` is in world pixels.
func add_ground(rect: Rect2, tile: String = "tile_ground") -> StaticBody2D:
	return _add_slab(rect, Layers.bit(Layers.WORLD), tile, "Ground")


## A wall you can scale, if you brought claws: solid world plus a `climbable`
## marker area on its face.
func add_climbable_wall(rect: Rect2) -> StaticBody2D:
	var wall: StaticBody2D = _add_slab(rect, Layers.bit(Layers.WORLD), "tile_climbable", "Wall")
	var marker: Area2D = Area2D.new()
	marker.name = "Climbable"
	marker.collision_layer = Layers.bit(Layers.CLIMBABLE)
	marker.collision_mask = 0
	marker.monitoring = false
	marker.monitorable = true
	marker.position = rect.get_center()

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	# Reach a little past both faces so a creature touching either side registers.
	shape.size = rect.size + Vector2(24.0, 0.0)
	shape_node.shape = shape
	marker.add_child(shape_node)
	add_child(marker)
	return wall


func add_cracked_floor(rect: Rect2) -> CrackedFloor:
	var tile: CrackedFloor = (load(WorldFixtureScenes.CRACKED_FLOOR) as PackedScene)\
		.instantiate() as CrackedFloor
	tile.position = rect.get_center()
	tile.floor_id = "%s_crack_%d" % [level_id, get_child_count()]
	add_child(tile)
	(tile.get_node("CollisionShape2D") as CollisionShape2D).shape = _box(rect.size)
	var sprite: Sprite2D = tile.get_node("Sprite2D") as Sprite2D
	sprite.scale = rect.size / sprite.texture.get_size()
	return tile


## A scrawled sign that telegraphs what a stretch of level wants (DESIGN §9).
func add_warning_sketch(at: Vector2, text: String) -> Label:
	var sign_label: Label = Paper.label(text, 26)
	sign_label.position = at
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.z_index = -5
	add_child(sign_label)
	return sign_label


func _add_slab(rect: Rect2, layer: int, tile: String, slab_name: String) -> StaticBody2D:
	_note_ground(rect)
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "%s_%d" % [slab_name, get_child_count()]
	body.position = rect.get_center()
	body.collision_layer = layer
	body.collision_mask = 0

	var shape_node: CollisionShape2D = CollisionShape2D.new()
	shape_node.shape = _box(rect.size)
	body.add_child(shape_node)

	var skin: Sprite2D = Sprite2D.new()
	skin.texture = load("res://assets/tiles/%s.png" % tile) as Texture2D
	skin.region_enabled = true
	skin.region_rect = Rect2(Vector2.ZERO, rect.size)
	skin.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	skin.z_index = -10
	LineBoil.apply(skin)
	body.add_child(skin)

	add_child(body)
	return body


func _box(size: Vector2) -> RectangleShape2D:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size
	return shape


class WorldFixtureScenes:
	const CRACKED_FLOOR: String = "res://scenes/world/cracked_floor.tscn"
