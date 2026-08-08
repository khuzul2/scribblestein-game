extends SceneTree

## Generates placeholder audio for every id in `asset_spec.json → audio.required`.
##
##     godot --headless -s tools/generate_placeholder_audio.gd
##
## These are *placeholders*, exactly like the placeholder art: they exist so the
## wiring is audible and testable before the real set is recorded. ASSET_SPEC §6
## calls for recorded mouth noises, pencil on paper and paper handling, and a
## single analog-style mono synth for the loops — none of which can be
## synthesised honestly here.
##
## They are, however, made in the right spirit rather than borrowed: a pencil
## scratch really is band-limited noise, a paper tear really is a noise burst
## with crackle, and a mouth pop really is a fast pitch drop. Nothing here comes
## from a stock pack, which ASSET_SPEC §6 forbids outright.
##
## Output is deterministic — every voice is seeded from its own id.

const SAMPLE_RATE: int = 22050
const SFX_DIR: String = "res://assets/audio/sfx"
const MUSIC_DIR: String = "res://assets/audio/music"

var _written: int = 0
var _skipped: int = 0
var _failed: int = 0


func _initialize() -> void:
	for directory: String in [SFX_DIR, MUSIC_DIR]:
		if not DirAccess.dir_exists_absolute(directory):
			DirAccess.make_dir_recursive_absolute(directory)

	# UI: pencil on paper, and a stamp.
	_save("sfx_ui_click_scratch", _scratch(0.09, 2600.0, 0.5))
	_save("sfx_ui_error_scratch", _scratch(0.26, 900.0, 1.0, true))
	_save("sfx_ui_page_turn", _paper(0.42, 0.6))
	_save("sfx_ui_stamp", _mix(_thud(0.16, 150.0), _scratch(0.06, 1800.0, 0.4)))

	# Movement: scribbled footsteps, a mouth pop, landings by weight.
	for index: int in range(1, 5):
		_save("sfx_step_scribble_0%d" % index, _scratch(0.07, 1400.0 + 220.0 * float(index), 0.45))
	_save("sfx_jump_mouthpop", _pop(0.13, 620.0, 180.0))
	_save("sfx_land_thud_light", _thud(0.13, 190.0))
	_save("sfx_land_thud_med", _thud(0.19, 130.0))
	_save("sfx_land_thud_heavy", _thud(0.30, 82.0))
	_save("sfx_glide_flapflap", _flap(0.55))
	_save("sfx_climb_scratch_loop", _scratch(0.5, 1200.0, 0.55, true))
	_save("sfx_roll_swish", _scratch(0.24, 2000.0, 0.6))
	_save("sfx_crack_floor_break", _mix(_paper(0.5, 1.0), _thud(0.28, 95.0)))

	# Combat: an inhale, a chomp, a thwip, a beatbox thud, grunts, a tear.
	_save("sfx_attack_windup_inhale", _breath(0.22, true))
	_save("sfx_bite_chomp", _mix(_pop(0.09, 260.0, 90.0), _scratch(0.06, 3000.0, 0.35)))
	_save("sfx_sting_thwip", _pop(0.10, 1500.0, 420.0))
	_save("sfx_hit_beatbox_thud", _mix(_thud(0.14, 110.0), _pop(0.05, 900.0, 300.0)))
	for index: int in range(1, 4):
		_save("sfx_hurt_grunt_0%d" % index, _grunt(0.20, 150.0 + 34.0 * float(index)))
	_save("sfx_death_paper_tear", _paper(0.85, 1.0))

	# Economy: slurps, a gasp, a squeak, a ka-ching.
	_save("sfx_ink_slurp", _slurp(0.16, 420.0))
	_save("sfx_blob_recover_bigslurp", _slurp(0.52, 220.0))
	_save("sfx_blueprint_found_gasp", _breath(0.34, true))
	_save("sfx_correction_squeak", _pop(0.16, 1900.0, 2600.0))
	_save("sfx_unlock_kaching_mouth", _mix(_pop(0.12, 900.0, 1500.0), _pop(0.22, 1400.0, 2100.0)))

	# Creature voices: one short mouth noise per enemy type.
	_save("sfx_voice_grunt", _grunt(0.28, 120.0))
	_save("sfx_voice_crawler", _grunt(0.22, 260.0))
	_save("sfx_voice_stinger", _pop(0.18, 1100.0, 700.0))

	# Music: minimalist analog-style loops, one slow and sketchy, one heavy.
	_save("mus_lab_loop", _loop(70.0, 8, false), MUSIC_DIR)
	_save("mus_level01_loop", _loop(124.0, 8, true), MUSIC_DIR)

	print("Placeholder audio: %d written, %d already up to date, %d failed."
		% [_written, _skipped, _failed])
	quit(1 if _failed > 0 else 0)


# --- voices --------------------------------------------------------------------

## Graphite on paper: band-limited noise with a fast attack and a rough tail.
func _scratch(seconds: float, brightness: float, level: float, rasp: bool = false) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var rng: RandomNumberGenerator = _rng(int(brightness))
	var previous: float = 0.0
	var coefficient: float = clampf(brightness / float(SAMPLE_RATE), 0.02, 0.95)
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		var noise: float = rng.randf_range(-1.0, 1.0)
		previous += (noise - previous) * coefficient
		var value: float = noise - previous  # high-passed: hiss, not rumble
		if rasp:
			value *= 0.6 + 0.4 * sin(t * TAU * 11.0)
		samples[index] = value * level * _envelope(t, 0.02, 0.9)
	return samples


## Paper handling: a wide noise sweep with crackle on top.
func _paper(seconds: float, level: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var rng: RandomNumberGenerator = _rng(7717)
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		var crackle: float = 1.0 if rng.randf() < 0.16 else 0.25
		samples[index] = rng.randf_range(-1.0, 1.0) * crackle * level \
			* _envelope(t, 0.05, 0.75) * (0.4 + 0.6 * t)
	return samples


## A mouth pop: a fast pitch slide with a very short body.
func _pop(seconds: float, from_hz: float, to_hz: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var phase: float = 0.0
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		phase += TAU * lerpf(from_hz, to_hz, t) / float(SAMPLE_RATE)
		samples[index] = sin(phase) * _envelope(t, 0.008, 0.5)
	return samples


## A body landing: a low sine drop with a little noise in the transient.
func _thud(seconds: float, hz: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var rng: RandomNumberGenerator = _rng(int(hz) + 91)
	var phase: float = 0.0
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		phase += TAU * lerpf(hz, hz * 0.55, t) / float(SAMPLE_RATE)
		var transient: float = rng.randf_range(-1.0, 1.0) * maxf(0.0, 1.0 - t * 14.0) * 0.5
		samples[index] = (sin(phase) * 0.9 + transient) * _envelope(t, 0.004, 0.45)
	return samples


## Breath: filtered noise that swells (inhale) or fades (exhale).
func _breath(seconds: float, inhale: bool) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var rng: RandomNumberGenerator = _rng(inhale if 1 else 2)
	var previous: float = 0.0
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		previous += (rng.randf_range(-1.0, 1.0) - previous) * 0.08
		var shape: float = t if inhale else (1.0 - t)
		samples[index] = previous * 2.2 * shape * shape * _envelope(t, 0.1, 0.9)
	return samples


## A voiced grunt: a buzzy saw with a downward pitch drift.
func _grunt(seconds: float, hz: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var rng: RandomNumberGenerator = _rng(int(hz))
	var phase: float = 0.0
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		phase += lerpf(hz, hz * 0.78, t) / float(SAMPLE_RATE)
		phase = fmod(phase, 1.0)
		var saw: float = phase * 2.0 - 1.0
		samples[index] = (saw * 0.7 + rng.randf_range(-1.0, 1.0) * 0.18) \
			* _envelope(t, 0.03, 0.6)
	return samples


## An ink slurp: a rising warble.
func _slurp(seconds: float, hz: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var phase: float = 0.0
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		var wobble: float = 1.0 + 0.35 * sin(t * TAU * 7.0)
		phase += TAU * hz * (0.6 + t) * wobble / float(SAMPLE_RATE)
		samples[index] = sin(phase) * 0.8 * _envelope(t, 0.05, 0.7)
	return samples


## Wing scraps: two noise flaps.
func _flap(seconds: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var rng: RandomNumberGenerator = _rng(4242)
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		var beat: float = absf(sin(t * TAU * 2.0))
		samples[index] = rng.randf_range(-1.0, 1.0) * beat * beat * 0.7 * _envelope(t, 0.05, 0.8)
	return samples


## A minimal analog-style loop: kick, bass and a sparse blip line.
func _loop(bpm: float, bars: int, heavy: bool) -> PackedFloat32Array:
	var beat: float = 60.0 / bpm
	var seconds: float = beat * 4.0 * float(bars)
	var samples: PackedFloat32Array = _silence(seconds)
	# Packed, not `Array[float]`: a ternary between two array literals is typed
	# plain `Array`, which cannot be assigned to a typed array — and the resulting
	# error left both music loops as empty 44-byte headers for three milestones.
	var bass_notes: PackedFloat32Array = PackedFloat32Array([55.0, 55.0, 73.42, 61.74]) \
		if heavy else PackedFloat32Array([49.0, 55.0, 41.2, 49.0])

	for step: int in range(bars * 16):
		var start: float = float(step) * beat * 0.25
		if step % 4 == 0:
			_place(samples, start, _thud(minf(0.26, beat * 0.9), 62.0 if heavy else 74.0), 0.9)
		if heavy and step % 8 == 4:
			_place(samples, start, _scratch(0.11, 5200.0, 0.5), 0.5)
		if step % 2 == 0:
			var note: float = bass_notes[(step / 8) % bass_notes.size()]
			_place(samples, start, _bass(beat * 0.45, note), 0.55)
		if step % 16 == 12:
			_place(samples, start, _pop(0.14, 880.0, 660.0), 0.28)
	return samples


func _bass(seconds: float, hz: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = _silence(seconds)
	var phase: float = 0.0
	for index: int in range(samples.size()):
		var t: float = float(index) / float(samples.size())
		phase += hz / float(SAMPLE_RATE)
		phase = fmod(phase, 1.0)
		# A square, softened — the cheapest honest "analog" voice there is.
		var square: float = 1.0 if phase < 0.5 else -1.0
		samples[index] = square * 0.35 * _envelope(t, 0.01, 0.35)
	return samples


# --- plumbing ------------------------------------------------------------------

func _silence(seconds: float) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(maxi(1, int(seconds * float(SAMPLE_RATE))))
	samples.fill(0.0)
	return samples


## Attack/decay in normalised time, so every voice ends at silence and loops or
## retriggers without a click.
func _envelope(t: float, attack: float, decay_start: float) -> float:
	if t < attack:
		return t / attack
	if t < decay_start:
		return 1.0
	return maxf(0.0, 1.0 - (t - decay_start) / (1.0 - decay_start))


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = a.duplicate()
	if b.size() > out.size():
		out.resize(b.size())
	for index: int in range(b.size()):
		out[index] = clampf(out[index] + b[index], -1.0, 1.0)
	return out


func _place(target: PackedFloat32Array, at_seconds: float,
		voice: PackedFloat32Array, level: float) -> void:
	var offset: int = int(at_seconds * float(SAMPLE_RATE))
	for index: int in range(voice.size()):
		var position: int = offset + index
		if position >= target.size():
			return
		target[position] = clampf(target[position] + voice[index] * level, -1.0, 1.0)


## Shortest sound worth writing. Anything below this is a voice that failed to
## render, not a sound — writing it produces a header-only WAV that loads as an
## empty stream and fails at playback rather than at generation.
const MIN_SAMPLES: int = 256


func _save(sound_id: String, samples: PackedFloat32Array, directory: String = SFX_DIR) -> void:
	if samples.size() < MIN_SAMPLES:
		printerr("%s rendered %d samples — refusing to write an empty WAV."
			% [sound_id, samples.size()])
		_failed += 1
		return

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false

	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for index: int in range(samples.size()):
		var value: int = int(clampf(samples[index], -1.0, 1.0) * 32000.0)
		data.encode_s16(index * 2, value)
	stream.data = data

	if directory == MUSIC_DIR:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()

	var path: String = directory.path_join("%s.wav" % sound_id)
	# Compare the encoded bytes on disk, not a loaded resource: on a fresh clone
	# the .wav has no importer output yet and load() would fail noisily.
	if FileAccess.file_exists(path):
		var existing: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if existing.size() > 44 and existing.slice(44) == stream.data:
			_skipped += 1
			return

	if stream.save_to_wav(path) != OK:
		printerr("Cannot write %s" % path)
		return
	_written += 1
	print("  wrote %s (%.2f s)" % [path, float(samples.size()) / float(SAMPLE_RATE)])
