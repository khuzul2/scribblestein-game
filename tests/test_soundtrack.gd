extends TestCase

## M12: up to five songs per level, chosen in the editor, played by
## `MusicDirector`.
##
## The interesting cases are the unhappy ones. A soundtrack lives in
## `user://music/` — outside the game, outside the repository, and entirely at
## the mercy of whoever moves files around. Losing a song must cost you the song
## and nothing else.

const LEVEL_ID: String = "soundtrack_probe"

var _made: PackedStringArray = PackedStringArray()


func before_each() -> void:
	MusicDirector.stop()
	_made = PackedStringArray()


func after_each() -> void:
	MusicDirector.stop()
	for path: String in _made:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var folder: String = MusicDirector.directory_for(LEVEL_ID)
	var dir: DirAccess = DirAccess.open(folder)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)


# --- getting songs in ----------------------------------------------------------

func test_a_song_is_copied_into_the_levels_own_folder() -> void:
	# The level references it by name; the bytes live beside the save file, so a
	# level stays a small portable text file and keeps working if the original
	# is later moved or deleted.
	var source: String = _shipped_track()
	var problems: PackedStringArray = PackedStringArray()
	var stored: String = MusicDirector.import_track(LEVEL_ID, source, problems)

	ne(stored, "", "the track was imported: %s" % [problems])
	is_true(FileAccess.file_exists(
		MusicDirector.directory_for(LEVEL_ID).path_join(stored)),
		"and it is in the level's own folder")
	any_contains(MusicDirector.available_tracks(LEVEL_ID),
		PackedStringArray([stored]), "and the editor can see it")


func test_every_accepted_format_is_accepted_and_others_are_not() -> void:
	for extension: String in MusicDirector.SUPPORTED:
		is_true(MusicDirector.is_supported("song.%s" % extension),
			"'%s' is a soundtrack format" % extension)
	for extension: String in ["flac", "txt", "png", "mid"]:
		is_false(MusicDirector.is_supported("song.%s" % extension),
			"'%s' is not" % extension)


func test_an_unsupported_file_is_refused_with_a_reason() -> void:
	var problems: PackedStringArray = PackedStringArray()
	var stored: String = MusicDirector.import_track(LEVEL_ID,
		"res://data/game_config.json", problems)
	eq(stored, "", "nothing was imported")
	is_false(problems.is_empty(), "and the reason names the formats that work")


func test_a_track_loads_back_as_a_playable_stream() -> void:
	var problems: PackedStringArray = PackedStringArray()
	var stored: String = MusicDirector.import_track(LEVEL_ID, _shipped_track(), problems)
	var stream: AudioStream = MusicDirector.load_track(LEVEL_ID, stored)
	not_null(stream, "the imported track loads at runtime")
	if stream != null:
		is_true(stream.get_length() > 0.0, "and has some length to it")


# --- the playlist --------------------------------------------------------------

func test_five_songs_play_in_the_order_they_were_arranged() -> void:
	var level: LevelData = _level_with(5)
	MusicDirector.play_for(level)
	eq(MusicDirector.playing_order(), level.music.tracks,
		"the playlist is exactly what the level asked for")
	eq(MusicDirector.current_track(), level.music.tracks[0], "starting with the first")
	is_true(MusicDirector.is_playing(), "and it is playing")


func test_shuffle_reorders_without_dropping_or_repeating_a_song() -> void:
	var level: LevelData = _level_with(5)
	level.music.shuffle = true
	MusicDirector.play_for(level)

	var order: PackedStringArray = MusicDirector.playing_order()
	eq(order.size(), level.music.tracks.size(), "every song is still in the cycle")
	var seen: Dictionary = {}
	for track: String in order:
		is_false(seen.has(track), "'%s' appears once per cycle" % track)
		seen[track] = true
	for track: String in level.music.tracks:
		is_true(seen.has(track), "'%s' is still in there" % track)


func test_re_entering_a_level_does_not_restart_its_music() -> void:
	var level: LevelData = _level_with(3)
	MusicDirector.play_for(level)
	var first: String = MusicDirector.current_track()
	MusicDirector.play_for(level)
	eq(MusicDirector.current_track(), first, "the same song is still playing")


func test_moving_to_another_level_changes_the_music() -> void:
	var level: LevelData = _level_with(2)
	MusicDirector.play_for(level)
	is_true(MusicDirector.is_playing(), "playing")
	MusicDirector.stop()
	is_false(MusicDirector.is_playing(), "and stopped when asked")
	eq(MusicDirector.current_track(), "", "with nothing playing")


# --- when the files are not there ----------------------------------------------

func test_a_missing_song_is_skipped_rather_than_fatal() -> void:
	var level: LevelData = _level_with(2)
	level.music.tracks.append("a_song_that_was_deleted.ogg")
	MusicDirector.play_for(level)
	eq(MusicDirector.playing_order().size(), 2,
		"the two that exist still play")
	is_true(MusicDirector.warnings().size() > 0, "and the missing one is named")


func test_a_level_with_no_soundtrack_plays_silent() -> void:
	var level: LevelData = LevelData.new()
	level.id = "silent_probe"
	level.name = "Silent"
	MusicDirector.play_for(level)
	is_false(MusicDirector.is_playing(), "nothing plays")
	eq(MusicDirector.current_track(), "", "and nothing is claimed to be playing")


func test_a_level_whose_songs_have_all_vanished_plays_silent() -> void:
	var level: LevelData = LevelData.new()
	level.id = LEVEL_ID
	level.name = "Gone"
	level.music.tracks = PackedStringArray(["gone_1.ogg", "gone_2.mp3"])
	MusicDirector.play_for(level)
	is_false(MusicDirector.is_playing(), "silence, not a crash")


func test_a_sixth_song_cannot_be_saved_into_a_level() -> void:
	# The cap is in the schema, so it is enforced wherever a level is written —
	# not only in the editor's UI, which is the only place a person sees it.
	var level: LevelData = _level_with(1)
	level.music.tracks = PackedStringArray(
		["1.ogg", "2.ogg", "3.ogg", "4.ogg", "5.ogg", "6.ogg"])
	is_false(LevelData.validate(level.to_dictionary()).is_empty(),
		"six songs is not a level the game will accept")


# --- helpers -------------------------------------------------------------------

## A real audio file from the shipped set, to import as if the player picked it.
func _shipped_track() -> String:
	return ProjectSettings.globalize_path("res://assets/audio/music/mus_lab_loop.wav")


## A level with `count` real, playable tracks in its folder.
func _level_with(count: int) -> LevelData:
	var level: LevelData = LevelData.new()
	level.id = LEVEL_ID
	level.name = "Soundtrack Probe"
	level.music.crossfade_seconds = 0.0  # instant, so tests do not wait on a tween

	var source: String = _shipped_track()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	var folder: String = MusicDirector.directory_for(LEVEL_ID)
	DirAccess.make_dir_recursive_absolute(folder)
	for index: int in range(count):
		var stored: String = "track_%d.wav" % index
		var file: FileAccess = FileAccess.open(folder.path_join(stored), FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		level.music.tracks.append(stored)
		_made.append(folder.path_join(stored))
	return level
