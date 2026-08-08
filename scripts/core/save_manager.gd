extends Node

## Autoload `SaveManager` — owns `user://save.json` exactly as specified in
## TECH_SPEC §8. Writes are atomic (temp file, then rename) so a crash mid-save
## can never leave a half-written profile.
##
## Save triggers (DESIGN §7/§8): level complete, death, unlock, exit-to-lab and
## loadout change. Call `request_save()` from those points.

const SAVE_PATH: String = "user://save.json"
const TEMP_PATH: String = "user://save.json.tmp"
## Bumped to 2 in M9: `loadout` became `loadouts`, one per blueprint, alongside
## `active_blueprint`. `_migrate` folds a version-1 save in without loss.
const SAVE_VERSION: int = 2
## The body type every profile starts in and falls back to.
const DEFAULT_BLUEPRINT: String = "biped"

signal saved
signal loaded
signal ink_changed(amount: int)
signal loadout_changed(loadout: Dictionary)
signal blueprint_changed(blueprint_id: String)
signal blueprint_unlocked(blueprint_id: String)

var data: Dictionary = {}


func _ready() -> void:
	if not Config.is_loaded:
		# Config has already reported the failure and asked the tree to quit;
		# do not build a profile on top of data we know is wrong.
		return
	load_game()


## Build the starting profile: the always-unlocked kit worn, no ink, no progress.
func default_save() -> Dictionary:
	var counters: Dictionary = {}
	for enemy_id: Variant in Config.enemies:
		counters[str(enemy_id)] = {"kills": 0, "since_drop": 0}

	var unlocked_blueprints: Array = []
	for blueprint_id: Variant in Config.blueprints:
		if bool((Config.blueprints[blueprint_id] as Dictionary).get("unlocked_by_default", false)):
			unlocked_blueprints.append(str(blueprint_id))

	return {
		"version": SAVE_VERSION,
		"ink": 0,
		"unlocked_parts": Array(Config.starter_part_ids()),
		"blueprints_found": [],
		"kill_counters": counters,
		# One loadout per body type, because their slots differ. Switching
		# blueprints in the Lab must not throw away the build you had.
		"loadouts": _default_loadouts(),
		"active_blueprint": DEFAULT_BLUEPRINT,
		"blueprint_unlocked": unlocked_blueprints,
		"levels": {},
		"settings": {"volume_master": 1.0, "volume_music": 0.8, "volume_sfx": 1.0},
	}


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		data = default_save()
		loaded.emit()
		return

	var result: JsonLoader.Result = JsonLoader.load_object(SAVE_PATH)
	if not result.ok:
		push_warning("Save file unreadable (%s) — starting a fresh profile." % result.error)
		data = default_save()
		loaded.emit()
		return

	data = _migrate(result.value as Dictionary)
	loaded.emit()


## Atomic write: temp file first, rename on top of the real one only once the
## bytes are flushed and closed.
func save_game() -> bool:
	var file: FileAccess = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open %s for writing (error %d)" % [TEMP_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()

	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("Cannot open user:// to finalise the save")
		return false
	var rename_error: int = dir.rename(TEMP_PATH.get_file(), SAVE_PATH.get_file())
	if rename_error != OK:
		push_error("Cannot rename %s onto %s (error %d)" % [TEMP_PATH, SAVE_PATH, rename_error])
		return false

	saved.emit()
	return true


func request_save() -> void:
	save_game()


func reset_profile() -> void:
	data = default_save()
	save_game()


# --- wallet --------------------------------------------------------------------

var ink: int:
	get:
		return int(data.get("ink", 0))
	set(value):
		data["ink"] = maxi(0, value)
		ink_changed.emit(int(data["ink"]))


func add_ink(amount: int) -> void:
	ink = ink + amount


## Spend if affordable. Returns false and changes nothing when it is not.
func spend_ink(amount: int) -> bool:
	if amount > ink:
		return false
	ink = ink - amount
	return true


# --- parts & loadout -----------------------------------------------------------

func unlocked_parts() -> Array:
	return data.get("unlocked_parts", []) as Array


func is_unlocked(part_id: String) -> bool:
	return unlocked_parts().has(part_id)


func unlock_part(part_id: String) -> void:
	if not is_unlocked(part_id):
		unlocked_parts().append(part_id)


func blueprints_found() -> Array:
	return data.get("blueprints_found", []) as Array


func has_blueprint_sketch(part_id: String) -> bool:
	return blueprints_found().has(part_id)


func add_blueprint_sketch(part_id: String) -> void:
	if not has_blueprint_sketch(part_id):
		blueprints_found().append(part_id)


# --- blueprints ----------------------------------------------------------------

## Which body type the player is currently building and playing.
func active_blueprint() -> String:
	var active: String = str(data.get("active_blueprint", DEFAULT_BLUEPRINT))
	# A save that names a blueprint this build no longer ships, or one the player
	# has not unlocked, must not strand them with an unbuildable creature.
	if not Config.blueprints.has(active) or not is_blueprint_unlocked(active):
		return DEFAULT_BLUEPRINT
	return active


func unlocked_blueprints() -> Array:
	return data.get("blueprint_unlocked", [DEFAULT_BLUEPRINT]) as Array


func is_blueprint_unlocked(blueprint_id: String) -> bool:
	return unlocked_blueprints().has(blueprint_id)


## Discovering a body type also grants its free parts. Without that you could
## own the Crooked Quadruped and have nothing to stand it on, since its legs live
## in slots no biped part can fill.
func unlock_blueprint(blueprint_id: String) -> void:
	if not Config.blueprints.has(blueprint_id) or is_blueprint_unlocked(blueprint_id):
		return
	unlocked_blueprints().append(blueprint_id)
	for part_id: String in Config.free_part_ids(blueprint_id):
		unlock_part(part_id)
	loadouts()[blueprint_id] = _starting_loadout(blueprint_id)
	blueprint_unlocked.emit(blueprint_id)
	request_save()


## Switch body type. Refused — with a `false` return, not a crash — for an
## unknown or still-locked blueprint.
func set_active_blueprint(blueprint_id: String) -> bool:
	if not Config.blueprints.has(blueprint_id) or not is_blueprint_unlocked(blueprint_id):
		return false
	if blueprint_id == active_blueprint():
		return true
	data["active_blueprint"] = blueprint_id
	blueprint_changed.emit(blueprint_id)
	loadout_changed.emit(loadout())
	request_save()
	return true


# --- loadouts ------------------------------------------------------------------

## Every stored loadout, keyed by blueprint id.
func loadouts() -> Dictionary:
	if not data.has("loadouts"):
		data["loadouts"] = _default_loadouts()
	return data["loadouts"] as Dictionary


## The loadout for the active body type, or for `blueprint_id` if given.
func loadout(blueprint_id: String = "") -> Dictionary:
	var key: String = active_blueprint() if blueprint_id == "" else blueprint_id
	var all: Dictionary = loadouts()
	if not all.has(key):
		all[key] = _empty_loadout(key)
	return all[key] as Dictionary


func set_loadout(new_loadout: Dictionary, blueprint_id: String = "") -> void:
	var key: String = active_blueprint() if blueprint_id == "" else blueprint_id
	loadouts()[key] = new_loadout.duplicate(true)
	if key == active_blueprint():
		loadout_changed.emit(loadout())
	request_save()


func set_loadout_slot(slot: String, part_id: Variant, blueprint_id: String = "") -> void:
	var key: String = active_blueprint() if blueprint_id == "" else blueprint_id
	var current: Dictionary = loadout(key)
	current[slot] = part_id
	if key == active_blueprint():
		loadout_changed.emit(current)
	request_save()


# --- kill counters (pity timer, DESIGN §8) -------------------------------------

func kill_counter(enemy_id: String) -> Dictionary:
	var counters: Dictionary = data.get("kill_counters", {}) as Dictionary
	if not counters.has(enemy_id):
		counters[enemy_id] = {"kills": 0, "since_drop": 0}
		data["kill_counters"] = counters
	return counters[enemy_id] as Dictionary


# --- per-level state -----------------------------------------------------------

func level_state(level_id: String) -> Dictionary:
	var levels: Dictionary = data.get("levels", {}) as Dictionary
	if not levels.has(level_id):
		levels[level_id] = {"completed": false, "death_blob": null}
		data["levels"] = levels
	return levels[level_id] as Dictionary


func is_level_completed(level_id: String) -> bool:
	return bool(level_state(level_id).get("completed", false))


func mark_level_completed(level_id: String) -> void:
	level_state(level_id)["completed"] = true
	request_save()


func death_blob(level_id: String) -> Variant:
	return level_state(level_id).get("death_blob", null)


## One blob per level; a second death overwrites the first (DESIGN §7).
func set_death_blob(level_id: String, position: Vector2, amount: int) -> void:
	level_state(level_id)["death_blob"] = {
		"x": position.x, "y": position.y, "amount": amount,
	}
	request_save()


func clear_death_blob(level_id: String) -> void:
	level_state(level_id)["death_blob"] = null
	request_save()


# --- settings ------------------------------------------------------------------

func settings() -> Dictionary:
	return data.get("settings", {}) as Dictionary


# --- internals -----------------------------------------------------------------

func _empty_loadout(blueprint_id: String = DEFAULT_BLUEPRINT) -> Dictionary:
	var loadout_template: Dictionary = {}
	if not Config.blueprints.has(blueprint_id):
		return loadout_template
	for slot_id: Variant in (Config.blueprint(blueprint_id).get("slots", {}) as Dictionary):
		loadout_template[str(slot_id)] = null
	return loadout_template


## What a body type is wearing the first time you build one: its free parts, one
## per slot. A part only lands in a blueprint that has its slot *and* that it
## declares it fits, so the quadruped starts on its own legs.
func _starting_loadout(blueprint_id: String) -> Dictionary:
	var loadout_template: Dictionary = _empty_loadout(blueprint_id)
	for part_id: String in Config.free_part_ids(blueprint_id):
		var slot: String = str(Config.part(part_id).get("slot", ""))
		if loadout_template.has(slot) and loadout_template[slot] == null:
			loadout_template[slot] = part_id
	return loadout_template


func _default_loadouts() -> Dictionary:
	var all: Dictionary = {}
	for blueprint_id: Variant in Config.blueprints:
		all[str(blueprint_id)] = _starting_loadout(str(blueprint_id))
	return all


## Fill in anything a newer build expects but an older save lacks. Never drops
## unknown keys — a downgrade must not destroy progress.
func _migrate(loaded_data: Dictionary) -> Dictionary:
	var merged: Dictionary = default_save()
	for key: Variant in loaded_data:
		merged[key] = loaded_data[key]
	merged["version"] = SAVE_VERSION

	# Saves written before per-blueprint loadouts kept a single `loadout` at the
	# top level, which was always the biped's. Fold it in rather than lose it.
	if loaded_data.has("loadout") and not loaded_data.has("loadouts"):
		var legacy: Dictionary = (merged["loadouts"] as Dictionary).duplicate(true)
		legacy[DEFAULT_BLUEPRINT] = (loaded_data["loadout"] as Dictionary).duplicate(true)
		merged["loadouts"] = legacy
	merged.erase("loadout")

	# Every blueprint gets a complete loadout, with unknown slots dropped and
	# missing ones nulled, so assembly never sees a shape it cannot build.
	var stored: Dictionary = merged.get("loadouts", {}) as Dictionary
	var rebuilt: Dictionary = {}
	for blueprint_id: Variant in Config.blueprints:
		var key: String = str(blueprint_id)
		var slots: Dictionary = _empty_loadout(key)
		var previous: Dictionary = stored.get(key, {}) as Dictionary
		for slot: Variant in slots:
			var part_id: Variant = previous.get(slot, null)
			slots[slot] = part_id if part_id == null or Config.parts.has(part_id) else null
		rebuilt[key] = slots
	merged["loadouts"] = rebuilt
	return merged
