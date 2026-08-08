extends Node

## Autoload `MusicDirector` — a level's soundtrack.
##
## Up to five tracks per level, chosen in the editor and copied into
## `user://music/<level id>/`. They play in the order they were arranged, one
## crossfading into the next, or shuffled if the level asks for it.
##
## The files live beside the save rather than in the repository on purpose: they
## are the player's music, they are large, and an exported build has no writable
## `res://`. A level file references them by name only, so a level stays a small
## portable text file whether or not the audio came with it.
##
## Missing or unreadable audio is never fatal. A level whose soundtrack has been
## deleted plays silent and says so once — losing a song must not cost you the
## level.

signal track_started(level_id: String, track: String)
signal playlist_finished(level_id: String)

const MUSIC_ROOT: String = "user://music"
## What a soundtrack may contain. Ogg and MP3 cover what people actually have;
## WAV is here because the placeholder set is WAV and refusing it would make the
## shipped music unusable through this path.
const SUPPORTED: Array[String] = ["ogg", "mp3", "wav"]
const MAX_TRACKS: int = LevelData.MAX_TRACKS
## Two players, so one can fade out while the next fades in.
const FADE_STEPS_PER_SECOND: float = 30.0
## Below this the fading-out player is stopped; -60 dB is inaudible.
const SILENT_DB: float = -60.0

var current_level_id: String = ""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _playlist: PackedStringArray = PackedStringArray()
var _order: PackedInt32Array = PackedInt32Array()
var _position: int = -1
var _crossfade: float = 1.5
var _shuffle: bool = false
var _warned: Dictionary = {}
var _fade: Tween = null


func _ready() -> void:
	for index: int in range(2):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Track%d" % index
		player.bus = "Master"
		player.volume_db = SILENT_DB
		add_child(player)
		player.finished.connect(_on_track_finished)
		_players.append(player)


## Where a level's soundtrack lives. Public because the editor writes here.
static func directory_for(level_id: String) -> String:
	return MUSIC_ROOT.path_join(level_id)


static func is_supported(path: String) -> bool:
	return SUPPORTED.has(path.get_extension().to_lower())


## Track file names present for a level, sorted. The editor lists these.
static func available_tracks(level_id: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(directory_for(level_id))
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		if is_supported(file_name):
			found.append(file_name)
	found.sort()
	return found


## Copy a chosen file into a level's soundtrack folder. Returns the stored name,
## or "" with the reason in `out_error`.
static func import_track(level_id: String, source_path: String,
		out_error: PackedStringArray) -> String:
	if not is_supported(source_path):
		out_error.append("'%s' is not a supported audio format (%s)"
			% [source_path.get_file(), ", ".join(SUPPORTED)])
		return ""
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		out_error.append("cannot read '%s'" % source_path)
		return ""

	var folder: String = directory_for(level_id)
	DirAccess.make_dir_recursive_absolute(folder)
	var stored: String = source_path.get_file()
	var destination: String = folder.path_join(stored)
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		out_error.append("cannot write '%s' (error %d)"
			% [destination, FileAccess.get_open_error()])
		return ""
	file.store_buffer(bytes)
	file.close()
	return stored


## Load one track file into a stream, or null. Runtime loading, not importing:
## these files arrive after the game was built, so the importer never sees them.
static func load_track(level_id: String, track: String) -> AudioStream:
	var path: String = directory_for(level_id).path_join(track)
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


# --- playback ------------------------------------------------------------------

## Start (or keep) the soundtrack for a level. Re-requesting the level already
## playing does nothing, so re-entering a level does not restart its music.
func play_for(level: LevelData) -> void:
	if level == null:
		stop()
		return
	if level.id == current_level_id:
		return

	current_level_id = level.id
	_crossfade = maxf(level.music.crossfade_seconds, 0.0)
	_shuffle = level.music.shuffle
	_playlist = _resolve(level)
	if _playlist.is_empty():
		stop()
		return

	_reorder()
	_position = -1
	_advance()


## The tracks a level actually has, in the order it asked for, capped at five and
## skipping anything that is no longer on disk.
func _resolve(level: LevelData) -> PackedStringArray:
	var resolved: PackedStringArray = PackedStringArray()
	for track: String in level.music.tracks:
		if resolved.size() >= MAX_TRACKS:
			_warn("%s lists more than %d tracks; the rest are ignored"
				% [level.id, MAX_TRACKS])
			break
		if load_track(level.id, track) == null:
			_warn("%s: soundtrack '%s' is missing or unreadable — skipping"
				% [level.id, track])
			continue
		resolved.append(track)
	return resolved


func _reorder() -> void:
	_order = PackedInt32Array()
	for index: int in range(_playlist.size()):
		_order.append(index)
	if not _shuffle or _order.size() < 2:
		return
	# Fisher-Yates. Shuffling a *cycle* rather than picking at random is what
	# stops a two-track soundtrack playing the same song four times running.
	for index: int in range(_order.size() - 1, 0, -1):
		var swap: int = randi_range(0, index)
		var held: int = _order[index]
		_order[index] = _order[swap]
		_order[swap] = held


func stop() -> void:
	current_level_id = ""
	_playlist = PackedStringArray()
	_position = -1
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream = null
		player.volume_db = SILENT_DB


func is_playing() -> bool:
	return _players[_active].playing


func current_track() -> String:
	if _position < 0 or _position >= _order.size():
		return ""
	return _playlist[_order[_position]]


## The order the tracks will actually play in, for the editor's preview.
func playing_order() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for index: int in _order:
		names.append(_playlist[index])
	return names


func _advance() -> void:
	if _playlist.is_empty():
		return
	_position += 1
	if _position >= _order.size():
		playlist_finished.emit(current_level_id)
		# A soundtrack loops as a whole; shuffled levels get a fresh order each
		# time round, so the cycle does not repeat itself exactly.
		if _shuffle:
			_reorder()
		_position = 0

	var track: String = _playlist[_order[_position]]
	var stream: AudioStream = load_track(current_level_id, track)
	if stream == null:
		_warn("%s: '%s' vanished mid-playlist" % [current_level_id, track])
		return

	var next: int = 1 - _active
	_players[next].stream = stream
	_players[next].volume_db = SILENT_DB
	_players[next].play()
	_crossfade_to(next)
	track_started.emit(current_level_id, track)


func _crossfade_to(next: int) -> void:
	var previous: int = _active
	_active = next
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if _crossfade <= 0.0:
		_players[previous].stop()
		_players[next].volume_db = 0.0
		return

	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(_players[next], "volume_db", 0.0, _crossfade)
	_fade.tween_property(_players[previous], "volume_db", SILENT_DB, _crossfade)
	_fade.chain().tween_callback(_players[previous].stop)


func _on_track_finished() -> void:
	# A track ending on its own is the cue for the next one. A crossfade started
	# early would need the stream's length up front, which MP3 does not always
	# give honestly, so the handover happens at the seam.
	if not _playlist.is_empty():
		_advance()


func _warn(message: String) -> void:
	if _warned.has(message):
		return
	_warned[message] = true
	push_warning("MusicDirector: %s" % message)


## Warnings raised so far, so a test or the editor can show them.
func warnings() -> PackedStringArray:
	return PackedStringArray(_warned.keys())
