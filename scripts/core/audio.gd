extends Node

## Autoload `Audio` — the one place a sound is asked for by id.
##
## Callers say `Audio.sfx("sfx_ui_error_scratch")`; this node finds the stream in
## `assets/audio/sfx/` and plays it on a pooled player. Ids are the exact names
## from ASSET_SPEC §6, so the manifest doubles as the audio to-do list.
##
## A missing file is deliberately *not* an error: it emits `sfx_played` and warns
## once. That keeps gameplay wiring testable and honest while the recorded set is
## still being made (it lands in M6), instead of pretending silence is success.

signal sfx_played(sfx_id: String)
signal music_changed(music_id: String)

const SFX_DIR: String = "res://assets/audio/sfx"
const MUSIC_DIR: String = "res://assets/audio/music"
const POOL_SIZE: int = 12
const SUPPORTED_EXTENSIONS: Array[String] = ["ogg", "wav"]

var missing_ids: Dictionary = {}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _music: AudioStreamPlayer = null
var _current_music: String = ""


func _ready() -> void:
	for index: int in range(POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Sfx%02d" % index
		player.bus = "Master"
		add_child(player)
		_pool.append(player)

	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = "Master"
	add_child(_music)

	_index_directory(SFX_DIR)
	_index_directory(MUSIC_DIR)
	_apply_volumes()
	if SaveManager.has_signal("loaded"):
		SaveManager.loaded.connect(_apply_volumes)


## Play a one-shot effect. `pitch_variance` keeps repeated sounds — footsteps,
## chomps — from machine-gunning identically.
func sfx(sfx_id: String, pitch_variance: float = 0.0, volume_db: float = 0.0) -> void:
	sfx_played.emit(sfx_id)
	var stream: AudioStream = _streams.get(sfx_id, null) as AudioStream
	if stream == null:
		_note_missing(sfx_id)
		return
	var player: AudioStreamPlayer = _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.play()


## Switch the looping track. Re-requesting the current track does nothing, so a
## scene reload does not restart the music.
func music(music_id: String) -> void:
	if music_id == _current_music:
		return
	_current_music = music_id
	music_changed.emit(music_id)
	var stream: AudioStream = _streams.get(music_id, null) as AudioStream
	if stream == null:
		_note_missing(music_id)
		_music.stop()
		return
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_current_music = ""
	_music.stop()


func current_music() -> String:
	return _current_music


func has(sound_id: String) -> bool:
	return _streams.has(sound_id)


## Ids named in `asset_spec.json → audio.required` that have no file yet.
func missing_required() -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	var spec: JsonLoader.Result = JsonLoader.load_object("res://data/asset_spec.json")
	if not spec.ok:
		return missing
	var audio: Dictionary = (spec.value as Dictionary).get("audio", {}) as Dictionary
	for sound_id: Variant in audio.get("required", []) as Array:
		if not _streams.has(str(sound_id)):
			missing.append(str(sound_id))
	return missing


func _apply_volumes() -> void:
	var settings: Dictionary = SaveManager.settings()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"),
		linear_to_db(maxf(float(settings.get("volume_master", 1.0)), 0.0001)))


func _index_directory(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var extension: String = entry.get_extension().to_lower()
		if not dir.current_is_dir() and SUPPORTED_EXTENSIONS.has(extension):
			var full: String = path.path_join(entry)
			var stream: AudioStream = load(full) as AudioStream
			if stream != null:
				# Looping is a property of the stream, and `save_to_wav` does not
				# write a `smpl` chunk, so set it here rather than relying on the
				# importer to have guessed.
				if path == MUSIC_DIR:
					if stream is AudioStreamOggVorbis:
						(stream as AudioStreamOggVorbis).loop = true
					elif stream is AudioStreamWAV:
						var wav: AudioStreamWAV = stream as AudioStreamWAV
						wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
						wav.loop_begin = 0
						wav.loop_end = wav.data.size() / 2
				_streams[entry.get_basename()] = stream
		entry = dir.get_next()
	dir.list_dir_end()


func _note_missing(sound_id: String) -> void:
	if missing_ids.has(sound_id):
		return
	missing_ids[sound_id] = true
	push_warning("Audio: no file for '%s' yet (ASSET_SPEC §6 — the recorded set lands in M6)."
		% sound_id)
