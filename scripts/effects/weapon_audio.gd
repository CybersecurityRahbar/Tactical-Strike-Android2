extends RefCounted

const AK_TAKES: Array[String] = [
	"res://assets/runtime/audio/ak_C_27P.ogg",
	"res://assets/runtime/audio/ak_C_28P.ogg",
	"res://assets/runtime/audio/ak_C_29P.ogg",
	"res://assets/runtime/audio/ak_C_31P.ogg",
	"res://assets/runtime/audio/ak_C_34P.ogg",
	"res://assets/runtime/audio/ak_C_36P.ogg"
]
const AK_BURST_TAKE := "res://assets/runtime/audio/ak_C_36P.ogg"

static func sample_paths() -> Array[String]:
	return AK_TAKES.duplicate()

# One trigger pull must produce exactly one report. The source takes in the
# upstream library are multi-shot field recordings (~10 s), so the asset
# preparation step extracts a single shot from each take before encoding.
static func play_fire(parent: Node, world_position: Vector3, profile: String, loudness_db := 0.0) -> void:
	var candidates: Array[String] = AK_TAKES
	if profile == "ak_burst":
		candidates = [AK_BURST_TAKE]
	var path := candidates[randi_range(0, candidates.size() - 1)]
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Recorded firearm audio is missing: " + path)
		return
	var player := AudioStreamPlayer3D.new()
	player.name = "RecordedFirearmReport"
	player.stream = stream
	player.volume_db = loudness_db
	player.pitch_scale = randf_range(0.985, 1.015)
	player.unit_size = 16.0
	player.max_distance = 1800.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.attenuation_filter_cutoff_hz = 5200.0
	player.attenuation_filter_db = -9.0
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
