class_name Combat
extends RefCounted

## Damage resolution — the one place a hit is turned into a number
## (Decision 5, DESIGN §6).
##
##     damage = max(1, attacker.attack_power − defender.total_defense)
##
## The floor of 1 is what stops a heavily armoured target being literally
## unkillable. Everything else — hitstun, knockback, i-frames, hitstop — comes
## from the attacking part's `attack` block and `game_config.json`; no timing or
## impulse is written here.

## Emitted for any hit anywhere, so HUDs, audio and the corpse-run economy can
## listen without every attacker knowing about them.
static var _hitstop_active: bool = false
## Freezing global time makes wall-clock measurements meaningless, so timing
## tests turn it off. Gameplay always leaves it on.
static var hitstop_enabled: bool = true


## The formula, isolated so it can be asserted directly.
static func damage_for(attack_power: float, total_defense: float) -> int:
	return int(maxf(1.0, attack_power - total_defense))


## Apply one connected hit. Returns the damage actually dealt — 0 when the
## defender's i-frames swallowed it.
static func resolve(attacker: Creature, defender: Creature, action: String) -> int:
	if attacker == null or defender == null or defender.health.is_dead():
		return 0
	if attacker.is_player == defender.is_player:
		return 0  # friendly fire is impossible by layer, but be explicit

	var attack: Dictionary = attacker.stats.attack_for(action)
	if attack.is_empty():
		return 0

	var amount: int = damage_for(float(attack["attack_power"]), defender.stats.total_defense)
	var dealt: int = defender.health.take_damage(amount, attacker)
	if dealt <= 0:
		return 0

	var timing: Dictionary = attack["attack"] as Dictionary
	apply_hitstun(defender, float(timing.get("hitstun", 0.0)))
	apply_knockback(attacker, defender, float(timing.get("knockback", 0.0)))
	hitstop(attacker.get_tree())
	return dealt


## The same resolution, but with the numbers passed in rather than looked up
## from the attacker's current loadout. A projectile outlives the swing that
## fired it — and can outlive a rebuild — so it carries its own damage, and this
## is how it spends it without inventing a second damage model.
static func resolve_direct(attacker: Creature, defender: Creature,
		attack_power: float, knockback: float, hitstun: float) -> int:
	if defender == null or defender.health.is_dead():
		return 0
	if attacker != null and attacker.is_player == defender.is_player:
		return 0

	var amount: int = damage_for(attack_power, defender.stats.total_defense)
	var dealt: int = defender.health.take_damage(amount, attacker)
	if dealt <= 0:
		return 0

	apply_hitstun(defender, hitstun)
	if attacker != null and is_instance_valid(attacker):
		apply_knockback(attacker, defender, knockback)
		hitstop(attacker.get_tree())
	return dealt


## Environment damage (spikes and the like). Hazards are exempt from the
## attack-window rule, so they hit on contact rather than through an attack.
static func resolve_hazard(defender: Creature, amount: int, source_position: Vector2) -> int:
	if defender == null or defender.health.is_dead():
		return 0
	var dealt: int = defender.health.take_damage(amount, null)
	if dealt <= 0:
		return 0
	apply_hitstun(defender, Config.cfg_float("combat.hitstop_seconds") * 4.0)
	_push(defender, signf(defender.global_position.x - source_position.x),
		Config.cfg_float("combat.hazard_damage") * 12.0)
	return dealt


static func apply_hitstun(defender: Creature, seconds: float) -> void:
	if seconds <= 0.0 or defender.locomotion == null:
		return
	defender.locomotion.stun_remaining = maxf(defender.locomotion.stun_remaining, seconds)


## Knockback pushes away from the attacker, scaled by the defender's weight
## class — Light is flung, Heavy barely moves (DESIGN §5).
static func apply_knockback(attacker: Creature, defender: Creature, force: float) -> void:
	if force <= 0.0:
		return
	var direction: float = signf(defender.global_position.x - attacker.global_position.x)
	if is_zero_approx(direction):
		direction = float(attacker.facing)
	_push(defender, direction, force * defender.weight_class.knockback_taken_mult()
		* thick_hide_mult(defender))


## `thick_hide` multiplies knockback taken, once per part carrying it — so
## armouring every slot really does make a creature immovable, and the Lab's
## weight readout is not the only thing that says so.
static func thick_hide_mult(defender: Creature) -> float:
	return defender.stats.stacked("thick_hide",
		Config.cfg_float("combat.thick_hide.knockback_mult"))


static func _push(defender: Creature, direction: float, force: float) -> void:
	defender.velocity.x = direction * force
	# A little lift, so a hit reads as a hit instead of a shove along the floor.
	defender.velocity.y = minf(defender.velocity.y, -force * 0.35)


## A single frame-and-a-bit of frozen time on impact. Real-time so it is exactly
## `combat.hitstop_seconds` however the engine is running.
static func hitstop(tree: SceneTree) -> void:
	if not hitstop_enabled or _hitstop_active or tree == null:
		return
	var seconds: float = Config.cfg_float("combat.hitstop_seconds")
	if seconds <= 0.0:
		return
	_hitstop_active = true
	Engine.time_scale = 0.0
	await tree.create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false
