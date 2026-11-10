extends RefCounted

# Procedural impact / ricochet / supersonic-crack audio.
#
# Bullet impacts are the single most repeated sound in a firefight and every
# surface has a different signature (dry dirt thud, gravel spray, stone chip,
# brick dust, wood splinter, steel spark). Shipping a sample for every
# surface x caliber combination is not practical on a mobile download, so the
# impulses are synthesised once at load time, cached, and then played through
# positional players. They stay correct even when an external asset pack is
# missing.

const MIX_RATE := 22050

static var _cache: Dictionary = {}

static func _noise(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(-1.0, 1.0)

static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream

# Dirt: soft low thud plus a short spray of grains.
static func _build_dirt(seed_value: int, power: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 0.34)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var low := 0.0
	for i in range(frames):
		var t := float(i) / MIX_RATE
		low = lerpf(low, _noise(rng), 0.10)
		var thud := sin(TAU * (86.0 - t * 40.0) * t) * exp(-t * 26.0)
		var grains := _noise(rng) * exp(-t * 34.0) * 0.35
		samples[i] = (low * exp(-t * 15.0) * 1.5 + thud * 0.7 + grains) * power
	return _to_stream(samples)

# Stone / concrete: a hard crack, a short high spray, a low body.
static func _build_stone(seed_value: int, power: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 0.30)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var band := 0.0
	for i in range(frames):
		var t := float(i) / MIX_RATE
		band = lerpf(band, _noise(rng), 0.62)
		var crack := _noise(rng) * exp(-t * 90.0) * 0.9
		var chip := band * exp(-t * 26.0) * 0.75
		var body := sin(TAU * 132.0 * t) * exp(-t * 30.0) * 0.45
		samples[i] = (crack + chip + body) * power
	return _to_stream(samples)

# Brick / plaster: duller than stone, more mid-range dust.
static func _build_brick(seed_value: int, power: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 0.32)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var low := 0.0
	var band := 0.0
	for i in range(frames):
		var t := float(i) / MIX_RATE
		low = lerpf(low, _noise(rng), 0.22)
		band = lerpf(band, _noise(rng), 0.48)
		var crack := band * exp(-t * 60.0) * 0.8
		var dust := low * exp(-t * 16.0) * 1.2
		var body := sin(TAU * 104.0 * t) * exp(-t * 34.0) * 0.4
		samples[i] = (crack + dust + body) * power
	return _to_stream(samples)

# Wood: hollow knock with a splinter tail.
static func _build_wood(seed_value: int, power: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 0.39)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var band := 0.0
	for i in range(frames):
		var t := float(i) / MIX_RATE
		band = lerpf(band, _noise(rng), 0.30)
		var knock := sin(TAU * 196.0 * t) * exp(-t * 42.0)
		var splinter := band * exp(-t * 20.0) * 0.55
		samples[i] = (knock * 0.85 + splinter) * power
	return _to_stream(samples)

# Steel: bright metallic ping plus sparks.
static func _build_metal(seed_value: int, power: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 0.55)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i in range(frames):
		var t := float(i) / MIX_RATE
		var f1 := 2400.0 - t * 1500.0
		var ping := (sin(TAU * f1 * t) * 0.5 + sin(TAU * f1 * 2.7 * t) * 0.22) * exp(-t * 9.0)
		var spark := _noise(rng) * exp(-t * 55.0) * 0.7
		samples[i] = (ping + spark) * power
	return _to_stream(samples)

# Flesh / uniform: heavy, wet, low impact without graphic content.
static func _build_flesh(seed_value: int, power: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 0.26)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var low := 0.0
	for i in range(frames):
		var t := float(i) / MIX_RATE
		low = lerpf(low, _noise(rng), 0.06)
		var thump := sin(TAU * (72.0 - t * 30.0) * t) * exp(-t * 24.0)
		samples[i] = (thump * 0.9 + low * exp(-t * 18.0) * 1.2) * power
	return _to_stream(samples)

# Ricochet whine: falling, slightly detuned sine with a noise edge.
static func _build_ricochet(seed_value: int, power: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 0.62)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var phase := 0.0
	for i in range(frames):
		var t := float(i) / MIX_RATE
		var freq := lerpf(2450.0, 620.0, clampf(t / 0.62, 0.0, 1.0))
		phase += TAU * freq / MIX_RATE
		var tone := sin(phase) * exp(-t * 5.0) * 0.55
		var edge := _noise(rng) * exp(-t * 30.0) * 0.25
		samples[i] = (tone + edge) * power
	return _to_stream(samples)

# Supersonic crack of a round passing the listener.
static func _build_crack(seed_value: int, pitch: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frames := int(MIX_RATE * 0.075)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var band := 0.0
	for i in range(frames):
		var t := float(i) / MIX_RATE
		band = lerpf(band, _noise(rng), 0.85)
		var snap := _noise(rng) * exp(-t * 220.0)
		var ring := sin(TAU * 3600.0 * pitch * t) * exp(-t * 120.0) * 0.35
		samples[i] = (snap * 0.75 + ring + band * exp(-t * 60.0) * 0.3)
	return _to_stream(samples)

# Recorded impacts for the surfaces we have real takes for (dirt, flesh).
const SAMPLE_DIR := "res://assets/audio/weapons"
static var _sample_cache: Dictionary = {}

static func _recorded(key: String, names: Array) -> Array:
	if _sample_cache.has(key):
		return _sample_cache[key]
	var found: Array = []
	for sample_name in names:
		var stream := load("%s/%s.ogg" % [SAMPLE_DIR, str(sample_name)]) as AudioStream
		if stream != null:
			found.append(stream)
	_sample_cache[key] = found
	return found

static func _play_recorded(parent: Node, world_position: Vector3, key: String, names: Array, volume_db: float, unit_size: float, max_distance: float) -> bool:
	var list := _recorded(key, names)
	if list.is_empty():
		return false
	_play(parent, world_position, list[randi() % list.size()], volume_db, unit_size, max_distance)
	return true

static func _cached(key: String) -> AudioStreamWAV:
	return _cache.get(key) as AudioStreamWAV

static func _variants(key: String, builder: Callable) -> AudioStreamWAV:
	var names: Array[String] = ["a", "b", "c"]
	var pick: String = names[randi() % names.size()]
	var cache_key: String = key + "_" + pick
	var stream := _cached(cache_key)
	if stream != null:
		return stream
	stream = builder.call(cache_key.hash())
	_cache[cache_key] = stream
	return stream

static func _play(parent: Node, world_position: Vector3, stream: AudioStream, volume_db: float, unit_size: float, max_distance: float) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var player := AudioStreamPlayer3D.new()
	player.name = "ImpactAudio"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.97, 1.03)
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.attenuation_filter_cutoff_hz = 7000.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	parent.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free)
	player.play()

static func play_impact(parent: Node, world_position: Vector3, surface: String, energy_j: float, caliber: Dictionary) -> void:
	var power := clampf(energy_j / 1500.0, 0.12, 1.5)
	var volume := linear_to_db(clampf(power * 0.9, 0.08, 1.0)) - 2.0
	var unit := clampf(3.5 + float(caliber.get("penetration", 0.34)) * 5.0, 4.0, 10.0)
	# Real takes first: dirt thud and a body hit are the two the player hears
	# most, and recordings beat any synthesised impulse.
	if surface == "flesh" and _play_recorded(parent, world_position, "flesh", ["impact_flesh"], volume + 2.0, unit, 420.0):
		return
	if (surface == "sand" or surface == "dirt" or surface == "grass") and _play_recorded(parent, world_position, "dirt", ["impact_dirt"], volume, unit, 420.0):
		return
	var stream: AudioStreamWAV
	match surface:
		"stone", "concrete":
			stream = _variants("stone", func(s): return _build_stone(s, power))
		"brick":
			stream = _variants("brick", func(s): return _build_brick(s, power))
		"wood":
			stream = _variants("wood", func(s): return _build_wood(s, power))
		"metal":
			stream = _variants("metal", func(s): return _build_metal(s, power))
		"flesh":
			stream = _variants("flesh", func(s): return _build_flesh(s, power))
		"sand":
			stream = _variants("dirt", func(s): return _build_dirt(s, power * 0.9))
		_:
			stream = _variants("dirt", func(s): return _build_dirt(s, power))
	_play(parent, world_position, stream, volume, unit, 420.0)

static func play_ricochet(parent: Node, world_position: Vector3, caliber: Dictionary) -> void:
	var power := clampf(float(caliber.get("penetration", 0.34)), 0.2, 1.2)
	var stream := _variants("ricochet", func(s): return _build_ricochet(s, power))
	_play(parent, world_position, stream, -7.0, 8.0, 340.0)

static func play_crack(parent: Node, world_position: Vector3, caliber: Dictionary, strength: float) -> void:
	var pitch := float(caliber.get("crack_pitch", 1.0))
	var stream := _variants("crack_%.2f" % pitch, func(s): return _build_crack(s, pitch))
	_play(parent, world_position, stream, linear_to_db(clampf(strength, 0.08, 1.0)) - 3.0, 9.0, 260.0)

# Heavier, longer-lived debris burst used when a cover piece breaks apart.
static func play_destruction(parent: Node, world_position: Vector3, surface: String) -> void:
	var stream: AudioStreamWAV
	if surface == "stone":
		stream = _variants("stone_break", func(s): return _build_stone(s, 1.5))
	elif surface == "wood":
		stream = _variants("wood_break", func(s): return _build_wood(s, 1.5))
	else:
		stream = _variants("dirt_break", func(s): return _build_dirt(s, 1.4))
	_play(parent, world_position, stream, 1.5, 12.0, 500.0)
