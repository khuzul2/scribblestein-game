class_name Projectile
extends Area2D

## A thrown or spat attack (`effects.json → spit_attack`).
##
## The only thing in the game that can deal damage away from the creature that
## owns it, so it carries the same three numbers a melee box does — attack power,
## knockback, hitstun — and resolves through the same `Combat` code. A ranged
## attack must not be a second damage model.
##
## Mandate B5 still holds: a projectile only exists during an attack's ACTIVE
## phase and afterwards, and it hits exactly one target before it dies. It is
## never a lingering damage box attached to the creature.

signal hit(defender: Creature, damage: int)
signal expired

const TEXTURE_PATH: String = "res://assets/fx/fx_spit.png"

var attacker: Creature = null
var attack_power: float = 0.0
var knockback: float = 0.0
var hitstun: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var gravity_mult: float = 0.0

var _life_remaining: float = 0.0
var _spent: bool = false


## Spawn one travelling `direction`, parented to the attacker's own parent so it
## keeps flying when the creature turns, moves, or dies.
static func fire(from: Creature, action: String, direction: float) -> Projectile:
	var attack: Dictionary = from.stats.attack_for(action)
	if attack.is_empty():
		return null

	var shot: Projectile = Projectile.new()
	shot.name = "Spit"
	shot.attacker = from
	shot.attack_power = float(attack.get("attack_power", 0.0))
	var timing: Dictionary = attack.get("attack", {}) as Dictionary
	shot.knockback = float(timing.get("knockback", 0.0))
	shot.hitstun = float(timing.get("hitstun", 0.0))
	shot.gravity_mult = Config.cfg_float("combat.spit.gravity_mult")
	shot.velocity = Vector2(signf(direction) * Config.cfg_float("combat.spit.speed"), 0.0)
	shot._life_remaining = Config.cfg_float("combat.spit.lifetime")

	shot.global_position = _muzzle(from, action, direction)
	shot.collision_layer = Layers.damage_layer(from.is_player)
	# Hurtboxes to hit, plus solid world so a shot stops at a wall.
	shot.collision_mask = Layers.damage_mask(from.is_player) \
		| Layers.mask([Layers.WORLD, Layers.WORLD_CRACKED])

	var parent: Node = from.get_parent()
	if parent == null:
		return null
	parent.add_child(shot)
	return shot


## Where the shot leaves the creature: the middle of the attack's own damage box,
## so a part with a longer muzzle really does fire from further forward.
static func _muzzle(from: Creature, action: String, direction: float) -> Vector2:
	var slot: String = str(from.stats.attack_for(action).get("slot", ""))
	for box: Hitbox in from.hitbox_root.damage_boxes_for_slot(slot):
		return box.global_position
	return from.global_position + Vector2(signf(direction) * 60.0, -120.0)


func _ready() -> void:
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = Config.cfg_float("combat.spit.radius")
	shape_node.shape = shape
	add_child(shape_node)

	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load(TEXTURE_PATH) as Texture2D
	LineBoil.apply(sprite)
	add_child(sprite)

	monitoring = true
	# Left monitorable on purpose. It looks redundant — nothing scans for the
	# damage layer, since hurtboxes are seen rather than seeing — but clearing it
	# also stops this area detecting *bodies*, and the shot would sail through
	# walls forever. Nothing else in the game scans this layer, so leaving it on
	# costs nothing.
	monitorable = true
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_life_remaining -= delta
	if _life_remaining <= 0.0:
		_die()
		return
	velocity.y += Config.cfg_float("movement.gravity") * gravity_mult * delta
	global_position += velocity * delta


func _on_area_entered(area: Area2D) -> void:
	var target: Hitbox = area as Hitbox
	if _spent or target == null or target.hitbox_type != Hitbox.TYPE_HURTBOX:
		return
	var defender: Creature = target.creature()
	if defender == null or defender == attacker:
		return

	# Through `Combat`, so the damage formula, i-frames, hitstun, knockback and
	# hitstop are all exactly what a melee hit would have produced.
	var damage: int = Combat.resolve_direct(attacker, defender, attack_power,
		knockback, hitstun)
	if damage > 0:
		hit.emit(defender, damage)
	_die()


func _on_body_entered(_body: Node2D) -> void:
	_die()  # a wall stops it


func _die() -> void:
	if _spent:
		return
	_spent = true
	set_deferred("monitoring", false)
	expired.emit()
	queue_free()
