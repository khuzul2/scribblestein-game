class_name Pickups
extends RefCounted

## The four things a level can drop, and the one factory that makes them.
## Every amount and duration comes from `game_config.json` or `enemies.json`.


## DNA Ink. Auto-collected on contact, and magnetised so a kill's spatter walks
## itself into the wallet rather than being hunted pixel by pixel (DESIGN §8).
class Ink extends Pickup:
	var amount: int = 1

	static func create(value: int) -> Ink:
		var pickup: Ink = Ink.new()
		pickup.name = "InkPickup"
		pickup.amount = maxi(1, value)
		pickup.magnet_speed = 520.0
		pickup.magnet_radius = Config.cfg_float("economy.ink_pickup_magnet_radius")
		return pickup

	func _collect(_by: Creature) -> bool:
		SaveManager.add_ink(amount)
		Audio.sfx("sfx_ink_slurp", 0.15)
		return true


## Correction Fluid: white-out that redraws your linework. Heals a fixed amount
## and gives up after `correction_fluid.despawn_seconds` (Decision 9).
class CorrectionFluid extends Pickup:
	static func create() -> CorrectionFluid:
		var pickup: CorrectionFluid = CorrectionFluid.new()
		pickup.name = "CorrectionFluid"
		pickup.despawn_seconds = Config.cfg_float("economy.correction_fluid.despawn_seconds")
		return pickup

	func _texture_path() -> String:
		return "res://assets/fx/fx_correction_fluid.png"

	func _radius() -> float:
		return 32.0

	## Refused at full health, so a pickup is never wasted by walking over it.
	func _collect(by: Creature) -> bool:
		if by.health.current >= by.health.maximum:
			return false
		by.health.heal(Config.cfg_int("economy.correction_fluid.heal"))
		Audio.sfx("sfx_correction_squeak")
		return true


## A Blueprint Sketch: permission to buy a part at the unlock desk. Picking up a
## sketch for something already found or owned converts to ink instead, so a
## duplicate is never a dead drop (DESIGN §8).
class BlueprintSketch extends Pickup:
	var part_id: String = ""

	static func create(for_part: String) -> BlueprintSketch:
		var pickup: BlueprintSketch = BlueprintSketch.new()
		pickup.name = "BlueprintSketch"
		pickup.part_id = for_part
		pickup.magnet_speed = 300.0
		pickup.magnet_radius = Config.cfg_float("economy.ink_pickup_magnet_radius") * 1.5
		return pickup

	func _texture_path() -> String:
		return "res://assets/fx/fx_blueprint_sketch.png"

	func _radius() -> float:
		return 32.0

	func _collect(_by: Creature) -> bool:
		if SaveManager.has_blueprint_sketch(part_id) or SaveManager.is_unlocked(part_id):
			SaveManager.add_ink(Config.cfg_int("economy.blueprint_duplicate_ink_bonus"))
			Audio.sfx("sfx_ink_slurp")
			return true
		SaveManager.add_blueprint_sketch(part_id)
		SaveManager.request_save()
		Audio.sfx("sfx_blueprint_found_gasp")
		return true


## The whole wallet, splattered where you died. It persists per level across a
## restart, a trip to the hub and a relaunch, and dying again overwrites it —
## the old ink is gone forever (Decision 7).
class DeathBlob extends Pickup:
	var amount: int = 0
	var level_id: String = ""

	static func create(value: int, for_level: String) -> DeathBlob:
		var pickup: DeathBlob = DeathBlob.new()
		pickup.name = "DeathBlob"
		pickup.amount = maxi(0, value)
		pickup.level_id = for_level
		pickup.magnet_speed = 260.0
		pickup.magnet_radius = Config.cfg_float("economy.ink_pickup_magnet_radius") * 2.0
		return pickup

	func _texture_path() -> String:
		return "res://assets/fx/fx_ink_blob.png"

	func _radius() -> float:
		return 48.0

	func _collect(_by: Creature) -> bool:
		SaveManager.add_ink(amount)
		SaveManager.clear_death_blob(level_id)
		Audio.sfx("sfx_blob_recover_bigslurp")
		return true
