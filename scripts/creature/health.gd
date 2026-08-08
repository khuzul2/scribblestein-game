class_name Health
extends Node

## HP, invulnerability windows and death, for player and enemies alike
## (Mandate B2 — identical code paths).
##
## `max_hp` comes from the assembly (`torso.base_hp + Σ hp_bonus`), or from an
## enemy's `hp_override`. The i-frame durations come from `game_config.json`;
## nothing here is a literal.

signal damaged(amount: int, from: Node)
signal healed(amount: int)
signal changed(current: float, maximum: float)
signal died

@export var is_player: bool = false

var maximum: float = 1.0
var current: float = 1.0

var _iframes_remaining: float = 0.0
var _dead: bool = false


func _physics_process(delta: float) -> void:
	if _iframes_remaining > 0.0:
		_iframes_remaining = maxf(0.0, _iframes_remaining - delta)


## Set the ceiling, keeping the fill ratio when the creature is rebuilt mid-run.
func set_maximum(value: float, refill: bool = true) -> void:
	var ratio: float = 1.0 if refill or maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	maximum = maxf(1.0, value)
	current = maximum if refill else maximum * ratio
	_dead = false
	changed.emit(current, maximum)


## Apply damage that has already been through the formula. Returns the amount
## actually taken; 0 means i-frames swallowed it.
func take_damage(amount: int, from: Node = null) -> int:
	if _dead or is_invulnerable() or amount <= 0:
		return 0
	current = maxf(0.0, current - float(amount))
	_iframes_remaining = iframe_duration()
	damaged.emit(amount, from)
	changed.emit(current, maximum)
	if current <= 0.0:
		_dead = true
		died.emit()
	return amount


func heal(amount: int) -> int:
	if _dead or amount <= 0:
		return 0
	var before: float = current
	current = minf(maximum, current + float(amount))
	var gained: int = int(current - before)
	if gained > 0:
		healed.emit(gained)
		changed.emit(current, maximum)
	return gained


## 0.5 s for the player, 0.2 s for enemies (DESIGN §6, values in game_config).
func iframe_duration() -> float:
	return Config.cfg_float(
		"combat.player_iframes_on_hit" if is_player else "combat.enemy_iframes_on_hit")


func is_invulnerable() -> bool:
	return _iframes_remaining > 0.0


## Grant invulnerability outside of being hit — the roll's i-frames, for one.
func grant_iframes(duration: float) -> void:
	_iframes_remaining = maxf(_iframes_remaining, duration)


func is_dead() -> bool:
	return _dead


func fraction() -> float:
	return 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
