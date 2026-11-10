extends RefCounted

# Per-weapon gunfire synthesis.
#
# The project ships one recorded AK take and nothing else, so every weapon used
# to sound like the same rifle. Instead of shipping a sample pack, each weapon
# profile is synthesised from the same physical layers a real report has:
#
#   1. CRACK      - the supersonic shock front, a hard broadband transient.
#   2. BLAST      - the muzzle pressure wave: a pitch-swept low sine plus roar.
#   3. ROAR       - the mid-band turbulence that gives a report its "body".
#   4. TAIL       - the environment answering back: a decaying, low-passed
#                   rumble, plus a delayed slap from the nearest buildings.
#   5. MECHANISM  - bolt carrier / belt feed clatter, a few ms after the shot.
#
# The profiles differ in bore size, dwell time and muzzle device, which is why
# a 5.45 rifle snaps, a 7.62 PKM thumps, a SVD cracks and a .50 cal hurts.

const MIX_RATE := 22050
const VARIANTS := 2

# Real, recorded gunfire. These are licensed recordings (see
# THIRD_PARTY_ASSETS.md) cut to single reports with an outdoor tail, so a
# Kalashnikov actually sounds like a Kalashnikov and a 5.56 rifle sounds like a
# 5.56 rifle. Synthesis below stays as the fallback for any profile whose
# recordings are missing.
const SAMPLE_DIR := "res://assets/audio/weapons"
const SAMPLE_PREFIX := {
	"ak": "ak", "ak_burst": "ak", "m4": "m4", "pk": "pkm", "svd": "svd",
	"50cal": "50cal", "dushka": "dushka", "rpg": "rpg_launch"
}
const SAMPLE_COUNT := {"ak": 5, "m4": 5, "pkm": 6, "svd": 5, "50cal": 4, "dushka": 3}
static var _samples: Dictionary = {}

# body_hz      - muzzle blast fundamental.
# body_decay   - how fast the blast pressure wave dies (higher = tighter).
# crack        - supersonic transient level.
# roar         - mid-band turbulence level.
# tail_gain    - environment tail level.
# tail_seconds - length of the tail.
# mech         - bolt / belt mechanical clatter level.
# brightness   - low-pass corner for the roar (higher = brighter, snappier).
# loudness     - relative playback gain in dB.
const PROFILES := {
	"ak": {
		"body_hz": 104.0, "body_decay": 30.0, "crack": 0.85, "roar": 0.95,
		"tail_gain": 0.13, "tail_seconds": 0.60, "mech": 0.55, "brightness": 2100.0,
		"loudness": 0.0
	},
	"ak_burst": {
		"body_hz": 104.0, "body_decay": 30.0, "crack": 0.85, "roar": 0.95,
		"tail_gain": 0.13, "tail_seconds": 0.60, "mech": 0.55, "brightness": 2100.0,
		"loudness": 0.0
	},
	"m4": {
		"body_hz": 122.0, "body_decay": 42.0, "crack": 1.00, "roar": 0.85,
		"tail_gain": 0.11, "tail_seconds": 0.52, "mech": 0.62, "brightness": 2600.0,
		"loudness": -0.5
	},
	"pk": {
		"body_hz": 76.0, "body_decay": 20.0, "crack": 0.72, "roar": 1.10,
		"tail_gain": 0.17, "tail_seconds": 0.95, "mech": 0.80, "brightness": 1500.0,
		"loudness": 1.5
	},
	"svd": {
		"body_hz": 88.0, "body_decay": 18.0, "crack": 1.20, "roar": 1.00,
		"tail_gain": 0.20, "tail_seconds": 1.15, "mech": 0.30, "brightness": 2400.0,
		"loudness": 2.0
	},
	"50cal": {
		"body_hz": 58.0, "body_decay": 13.0, "crack": 1.35, "roar": 1.25,
		"tail_gain": 0.24, "tail_seconds": 1.55, "mech": 0.85, "brightness": 1200.0,
		"loudness": 3.0
	},
	"dushka": {
		"body_hz": 66.0, "body_decay": 15.0, "crack": 1.22, "roar": 1.20,
		"tail_gain": 0.22, "tail_seconds": 1.35, "mech": 0.90, "brightness": 1350.0,
		"loudness": 2.5
	},
	"rpg": {
		"body_hz": 48.0, "body_decay": 9.0, "crack": 0.35, "roar": 0.70,
		"tail_gain": 0.26, "tail_seconds": 1.90, "mech": 0.15, "brightness": 900.0,
		"loudness": 2.0
	}
}

static var _cache: Dictionary = {}

static func sample_paths() -> Array[String]:
	# Kept for the asset validation step: proves the recorded AK takes shipped.
	var result: Array[String] = []
	for name in ["ak_C_27P", "ak_C_28P", "ak_C_29P", "ak_C_31P", "ak_C_34P", "ak_C_36P"]:
		var path := "res://assets/runtime/audio/%s.ogg" % name
		if ResourceLoader.exists(path):
			result.append(path)
	return result

static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for value in samples:
		peak = maxf(peak, absf(value))
	var gain := 0.94 / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream

static func _one_pole(cutoff_hz: float) -> float:
	return clampf(1.0 - exp(-TAU * cutoff_hz / float(MIX_RATE)), 0.0001, 1.0)

# Builds one shot. The layers are mixed in the physical order they reach the
# ear: snap, muzzle blast, turbulence, mechanism, then the room answering.
static func _build_shot(profile_key: String, seed_value: int) -> AudioStreamWAV:
	var profile: Dictionary = PROFILES.get(profile_key, PROFILES["ak"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var tail_seconds := float(profile["tail_seconds"])
	var frames := int(MIX_RATE * (tail_seconds + 0.05))
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var body_hz := float(profile["body_hz"]) * rng.randf_range(0.96, 1.04)
	var body_decay := float(profile["body_decay"])
	var bright := float(profile["brightness"])
	var a_roar := _one_pole(bright)
	var a_body := _one_pole(320.0)
	var tail_alpha := _one_pole(420.0)
	var mech_level := float(profile["mech"])
	var mech_time := rng.randf_range(0.020, 0.045)

	var phase := 0.0
	var roar_lp := 0.0
	var body_lp := 0.0
	var tail_lp := 0.0
	var mech_lp := 0.0

	for i in range(frames):
		var t := float(i) / float(MIX_RATE)
		var noise := rng.randf_range(-1.0, 1.0)
		roar_lp += a_roar * (noise - roar_lp)
		body_lp += a_body * (noise - body_lp)
		tail_lp += tail_alpha * (noise - tail_lp)

		# 1. Supersonic crack: 4-6 ms of raw broadband pressure.
		var crack := (noise - body_lp) * exp(-t * 620.0) * float(profile["crack"]) * 1.6

		# 2. Muzzle blast: a fast downward pitch sweep, the chest thump.
		var freq := body_hz * (0.48 + 0.62 * exp(-t * 34.0))
		phase += TAU * freq / float(MIX_RATE)
		var body := sin(phase) * exp(-t * body_decay)
		body += sin(phase * 2.02) * exp(-t * body_decay * 1.7) * 0.32
		body *= 1.05

		# 3. Turbulence / roar, softened by the bore and muzzle device.
		var roar := roar_lp * exp(-t * 11.0) * float(profile["roar"]) * 1.5

		# 4. Environment tail, quiet and long, plus one building slap-back.
		var tail := tail_lp * exp(-t / maxf(tail_seconds, 0.05)) * float(profile["tail_gain"]) * 4.2
		var slap_t := t - 0.085
		if slap_t > 0.0:
			tail += tail_lp * exp(-slap_t * 14.0) * exp(-slap_t / maxf(tail_seconds, 0.05)) * float(profile["tail_gain"]) * 1.5

		# 5. Bolt carrier / belt feed: a dry clatter just after the shot.
		var mech := 0.0
		if mech_level > 0.0 and t > mech_time and t < mech_time + 0.05:
			mech_lp += 0.45 * (noise - mech_lp)
			mech = (noise - mech_lp) * exp(-(t - mech_time) * 260.0) * mech_level * 0.9

		samples[i] = crack + body + roar + tail + mech

	return _to_stream(samples)

# RPG is not a rifle report: a launch hiss, a rocket motor whoosh, then a
# distant boom as the round leaves.
static func _build_rocket(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 2.0)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var lp := 0.0
	var boom_phase := 0.0
	for i in range(frames):
		var t := float(i) / float(MIX_RATE)
		var noise := rng.randf_range(-1.0, 1.0)
		var alpha := _one_pole(1600.0 + 2600.0 * clampf(t / 0.45, 0.0, 1.0))
		lp += alpha * (noise - lp)
		# Launch tube pop, then the motor hiss swelling over ~0.4 s.
		var launch := noise * exp(-t * 70.0) * 0.9
		var hiss := (noise - lp) * clampf(t / 0.06, 0.0, 1.0) * exp(-t * 2.6) * 0.55
		var whoosh := lp * clampf(t / 0.12, 0.0, 1.0) * exp(-t * 3.4) * 0.9
		boom_phase += TAU * (54.0 - t * 8.0) / float(MIX_RATE)
		var boom := sin(boom_phase) * exp(-t * 6.0) * 0.55
		samples[i] = launch + hiss + whoosh + boom
	return _to_stream(samples)

static func _stream_for(profile: String) -> AudioStreamWAV:
	var key := profile
	if not PROFILES.has(key):
		key = "ak"
	var variant := randi() % VARIANTS
	var cache_key := "%s_%d" % [key, variant]
	var cached := _cache.get(cache_key) as AudioStreamWAV
	if cached != null:
		return cached
	var stream: AudioStreamWAV
	if key == "rpg":
		stream = _build_rocket(cache_key.hash())
	else:
		stream = _build_shot(key, cache_key.hash())
	_cache[cache_key] = stream
	return stream

# Recorded reports for a profile, or an empty array when the pack is absent.
static func sample_streams(profile: String) -> Array:
	var prefix := str(SAMPLE_PREFIX.get(profile, ""))
	if prefix.is_empty():
		return []
	if _samples.has(prefix):
		return _samples[prefix]
	var found: Array = []
	var count := int(SAMPLE_COUNT.get(prefix, 0))
	if count > 0:
		for i in range(1, count + 1):
			var stream := load("%s/%s_%02d.ogg" % [SAMPLE_DIR, prefix, i]) as AudioStream
			if stream != null:
				found.append(stream)
	else:
		var single := load("%s/%s.ogg" % [SAMPLE_DIR, prefix]) as AudioStream
		if single != null:
			found.append(single)
	_samples[prefix] = found
	return found

static func play_fire(parent: Node, world_position: Vector3, profile: String, loudness_db := 0.0) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var real := sample_streams(profile)
	var stream: AudioStream = null
	if not real.is_empty():
		stream = real[randi() % real.size()]
	else:
		stream = _stream_for(profile)
	if stream == null:
		return
	var settings: Dictionary = PROFILES.get(profile, PROFILES["ak"])
	var player := AudioStreamPlayer3D.new()
	player.name = "WeaponReport"
	player.stream = stream
	player.volume_db = loudness_db + float(settings.get("loudness", 0.0))
	player.pitch_scale = randf_range(0.975, 1.025)
	player.unit_size = 14.0
	player.max_distance = 2200.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# Distant reports lose their snap and keep the low rumble, like real gunfire
	# heard across a valley.
	player.attenuation_filter_cutoff_hz = 4200.0
	player.attenuation_filter_db = -11.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	parent.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free)
	player.play()

static func load_sand_footsteps() -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for name in ["sand_l", "sand_r", "sand_l2", "sand_r2"]:
		var stream := load("res://assets/runtime/audio/%s.ogg" % name) as AudioStream
		if stream != null:
			result.append(stream)
	return result
