class_name CreatureStats
extends RefCounted

## Everything a creature *is*, derived purely from its equipped parts.
##
## The assembly IS the character sheet (DESIGN §1): nothing here is authored,
## every field is recomputed from `parts_db.json` on each `assemble()`. Mandate
## B4 — no capability is hardcoded in a scene.

## `torso.base_hp + Σ part.hp_bonus` (DESIGN §6).
var max_hp: float = 0.0
## `Σ part.defense`, the subtrahend in the damage formula.
var total_defense: float = 0.0
## `Σ part.weight`, which selects the movement preset (DESIGN §5).
var total_weight: float = 0.0
## Product of every equipped part's `stats.speed_mod`.
var speed_mod: float = 1.0
## Product of every equipped part's `stats.jump_mod`.
var jump_mod: float = 1.0

## Effect id -> the part id that granted it.
var effects: Dictionary = {}
## Effect id -> how many equipped parts carry it. Stacking passives read this.
var effect_counts: Dictionary = {}
## Input action ("attack_primary"/"attack_secondary") -> {part_id, slot, attack_power, attack}.
var attacks: Dictionary = {}
## Slot -> part id, for readouts and save round-trips.
var loadout: Dictionary = {}


## Fold one equipped part into the sheet.
func absorb(slot: String, part_id: String, part: Dictionary, wired_to: String) -> void:
	loadout[slot] = part_id
	var part_stats: Dictionary = part.get("stats", {}) as Dictionary

	max_hp += float(part_stats.get("base_hp", 0.0)) + float(part_stats.get("hp_bonus", 0.0))
	total_defense += float(part_stats.get("defense", 0.0))
	total_weight += float(part.get("weight", 0.0))
	speed_mod *= float(part_stats.get("speed_mod", 1.0))
	jump_mod *= float(part_stats.get("jump_mod", 1.0))

	for effect_id: Variant in part.get("effects", []) as Array:
		effects[str(effect_id)] = part_id
		effect_counts[str(effect_id)] = int(effect_counts.get(str(effect_id), 0)) + 1

	if wired_to != "" and part.has("attack"):
		attacks[wired_to] = {
			"part_id": part_id,
			"slot": slot,
			"attack_power": float(part_stats.get("attack_power", 0.0)),
			"attack": part["attack"],
		}


func has_effect(effect_id: String) -> bool:
	return effects.has(effect_id)


## How many equipped parts carry an effect. Passives that scale a number —
## `thick_hide`, `ink_magnet`, `quick_strike`, `long_reach` — stack once per
## part, so armouring four slots is meaningfully different from armouring one.
func effect_count(effect_id: String) -> int:
	return int(effect_counts.get(effect_id, 0))


## A stacking multiplier: `per_part` applied once for each part carrying the
## effect, or 1.0 when nothing does.
func stacked(effect_id: String, per_part: float) -> float:
	var layers: int = effect_count(effect_id)
	return 1.0 if layers <= 0 else pow(per_part, float(layers))


## The attack wired to an input action, or an empty Dictionary when that button
## is inert because the slot is empty (DESIGN §4.2).
func attack_for(action: String) -> Dictionary:
	return attacks.get(action, {}) as Dictionary


## `max(1, attack_power − total_defense)` (Decision 5). The floor is what stops a
## heavily armoured target from being literally unkillable.
static func damage_against(attack_power: float, defender_defense: float) -> int:
	return int(maxf(1.0, attack_power - defender_defense))


func describe() -> String:
	return "HP %d · DEF %d · WEIGHT %d · speed x%.2f · jump x%.2f · effects [%s]" % [
		int(max_hp), int(total_defense), int(total_weight), speed_mod, jump_mod,
		", ".join(PackedStringArray(effects.keys()))]
