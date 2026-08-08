extends Node

## Autoload `SaveManager` — owns `user://save.json` exactly as specified in
## TECH_SPEC §8. Writes are atomic (temp file, then rename) so a crash mid-save
## can never leave a half-written profile.
##
## Save triggers (DESIGN §7/§8): level complete, death, unlock, exit-to-lab and
## loadout change. Call `request_save()` from those points.

const SAVE_PATH: String = "user://save.json"
const TEMP_PATH: String = "user://save.json.tmp"
const SAVE_VERSION: int = 1

signal saved
signal loaded
signal ink_changed(amount: int)
signal loadout_changed(loadout: Dictionary)

var data: Dictionary = {}


func _ready() -> void:
	if not Config.is_loaded:
		# Config has already reported the failure and asked the tree to quit;
		# do not build a profile on top of data we know is wrong.
		return
	load_game()


## Build the starting profile: the always-unlocked kit worn, no ink, no progress.
func default_save() -> Dictionary:
	var starters: PackedStringArray = Config.starter_part_ids()
	var loadout: Dictionary = _empty_loadout()
	for part_id: String in starters:
		var slot: String = str(Config.part(part_id).get("slot", ""))
		if loadout.has(slot):
			loadout[slot] = part_id

	var counters: Dictionary = {}
	for enemy_id: Variant in Config.enemies:
		counters[str(enemy_id)] = {"kills": 0, "since_drop": 0}

	return {
		"version": SAVE_VERSION,
		"ink": 0,
		"unlocked_parts": Array(starters),
		"blueprints_found": [],
		"kill_counters": counters,
		"loadout": loadout,
		"blueprint_unlocked": ["biped"],
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


func loadout() -> Dictionary:
	return data.get("loadout", {}) as Dictionary


func set_loadout(new_loadout: Dictionary) -> void:
	data["loadout"] = new_loadout.duplicate(true)
	loadout_changed.emit(loadout())
	request_save()


func set_loadout_slot(slot: String, part_id: Variant) -> void:
	var current: Dictionary = loadout()
	current[slot] = part_id
	data["loadout"] = current
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

func _empty_loadout() -> Dictionary:
	var loadout_template: Dictionary = {}
	for slot_id: Variant in (Config.blueprint("biped").get("slots", {}) as Dictionary):
		loadout_template[str(slot_id)] = null
	return loadout_template


## Fill in anything a newer build expects but an older save lacks. Never drops
## unknown keys — a downgrade must not destroy progress.
func _migrate(loaded_data: Dictionary) -> Dictionary:
	var merged: Dictionary = default_save()
	for key: Variant in loaded_data:
		merged[key] = loaded_data[key]
	merged["version"] = SAVE_VERSION

	var loadout_data: Dictionary = merged.get("loadout", {}) as Dictionary
	for slot: Variant in _empty_loadout():
		if not loadout_data.has(slot):
			loadout_data[slot] = null
	merged["loadout"] = loadout_data
	return merged
