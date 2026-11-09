extends CharacterBody3D

const WEAPON_CONTROLLER = preload("res://scripts/weapons/weapon_controller.gd")

@export var walk_speed := 5.1
@export var sprint_speed := 7.2
@export var crouch_speed := 2.55
@export var jump_impulse := 4.4
@export var mouse_sensitivity := 0.00205
@export var mobile_look_multiplier := 1.12
@export var ground_acceleration := 25.0
@export var air_acceleration := 7.0

var camera: Camera3D
var weapon_controller: Node3D
var hud: CanvasLayer
var body_collider: CollisionShape3D
var footstep_player: AudioStreamPlayer3D
var footstep_streams: Array[AudioStream] = []
var touch_move_vector := Vector2.ZERO
var pitch := 0.0
var camera_kick := 0.0
var camera_bob_time := 0.0
var footstep_timer := 0.0
var is_crouched := false
var aim_enabled := false
var on_spawn_floor := false

func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 0.62
	floor_max_angle = deg_to_rad(52.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	safe_margin = 0.035
	max_slides = 6
	_create_input_map()
	_create_body_collider()
	_create_camera()
	_create_weapon_controller()
	_create_footstep_audio()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _is_touch_device() else Input.MOUSE_MODE_CAPTURED

func _is_touch_device() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "iOS"

func _create_body_collider() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.84
	body_collider = CollisionShape3D.new()
	body_collider.name = "BodyCollider"
	body_collider.shape = capsule
	body_collider.position.y = 0.92
	add_child(body_collider)

func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 1.62, 0.0)
	camera.current = true
	camera.fov = 78.0
	camera.near = 0.055
	camera.far = 1800.0
	add_child(camera)

func _create_weapon_controller() -> void:
	weapon_controller = WEAPON_CONTROLLER.new()
	weapon_controller.name = "WeaponController"
	add_child(weapon_controller)
	weapon_controller.initialize(camera, self)

func _create_footstep_audio() -> void:
	footstep_streams = load_sand_footsteps()
	footstep_player = AudioStreamPlayer3D.new()
	footstep_player.name = "FootstepAudio"
	footstep_player.volume_db = -1.5
	footstep_player.unit_size = 3.2
	footstep_player.max_distance = 42.0
	footstep_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(footstep_player)

func load_sand_footsteps() -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for sample in ["sand_l", "sand_r", "sand_l2", "sand_r2"]:
		var path := "res://assets/runtime/audio/%s.ogg" % sample
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				result.append(stream)
	return result

func attach_hud(hud_node: CanvasLayer) -> void:
	hud = hud_node
	if weapon_controller != null:
		weapon_controller.set_hud(hud)
	if hud != null:
		hud.connect("movement_vector_changed", Callable(self, "set_mobile_move_vector"))
		hud.connect("aim_toggle_requested", Callable(self, "set_aim_enabled"))

func set_mobile_move_vector(value: Vector2) -> void:
	touch_move_vector = value.limit_length(1.0)

func adjust_sensitivity(amount: float) -> void:
	mouse_sensitivity = clampf(mouse_sensitivity + amount, 0.00075, 0.0065)
	if hud != null:
		hud.set_message("LOOK SENSITIVITY: %.3f" % (mouse_sensitivity * 1000.0))

func set_aim_enabled(enabled: bool) -> void:
	aim_enabled = enabled
	if weapon_controller != null and weapon_controller.has_method("set_aiming"):
		weapon_controller.call("set_aiming", aim_enabled)

func add_weapon_recoil(pitch_kick: float, yaw_kick: float = 0.0) -> void:
	# Positive X rotation lifts the view, so recoil must add to the kick.
	camera_kick = clampf(camera_kick + pitch_kick, 0.0, 0.24)
	if absf(yaw_kick) > 0.0001:
		rotate_y(yaw_kick)

func _create_input_map() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("jump", KEY_SPACE)
	_bind_key("crouch", KEY_C)
	_bind_key("reload", KEY_R)
	_bind_key("weapon_next", KEY_Q)
	_bind_key("ammo_cycle", KEY_Y)
	for i in range(7):
		_bind_key("weapon_%d" % (i + 1), KEY_1 + i)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mouse_event)

func _bind_key(action: String, key_code: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key_code
	InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not _is_touch_device():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			get_tree().paused = false
		else:
			get_tree().paused = true
	if get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)
	elif event is InputEventScreenDrag and _is_touch_device():
		var viewport_size := get_viewport().get_visible_rect().size
		# Left third belongs to the movement joystick; the bottom-right strip belongs to action buttons.
		var is_look_region: bool = event.position.x > viewport_size.x * 0.38
		var is_clear_vertical_region: bool = event.position.y > 76.0 and event.position.y < viewport_size.y - 204.0
		if is_look_region and is_clear_vertical_region:
			_apply_look(event.relative * mobile_look_multiplier)

func _apply_look(relative: Vector2) -> void:
	# Looking through the sights is slower, which is how magnified aiming feels.
	var sensitivity_scale := 1.0
	if aim_enabled:
		sensitivity_scale = 0.62
	rotate_y(-relative.x * mouse_sensitivity * sensitivity_scale)
	pitch = clampf(pitch - relative.y * mouse_sensitivity * sensitivity_scale, -1.42, 1.42)
	camera.rotation.x = pitch + camera_kick
	if weapon_controller != null and weapon_controller.has_method("notify_look"):
		weapon_controller.call("notify_look", relative * sensitivity_scale)

func _set_crouch(enabled: bool, delta: float) -> void:
	if is_crouched != enabled:
		is_crouched = enabled
		var capsule := body_collider.shape as CapsuleShape3D
		if capsule != null:
			capsule.height = 1.22 if is_crouched else 1.84
			body_collider.position.y = 0.61 if is_crouched else 0.92

func _get_move_input() -> Vector2:
	if touch_move_vector.length() > 0.04:
		return Vector2(touch_move_vector.x, -touch_move_vector.y).limit_length(1.0)
	if _is_touch_device():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")

func _physics_process(delta: float) -> void:
	_set_crouch(Input.is_action_pressed("crouch"), delta)
	var input_vector := _get_move_input()
	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var direction := (global_transform.basis * local_direction).normalized()
	var moving := input_vector.length() > 0.08
	var sprinting := moving and Input.is_action_pressed("sprint") and not is_crouched
	var speed := sprint_speed if sprinting else walk_speed
	if is_crouched:
		speed = crouch_speed
	var target_horizontal := direction * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	horizontal = horizontal.move_toward(target_horizontal, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not is_crouched:
			velocity.y = jump_impulse
		elif velocity.y < 0.0:
			velocity.y = -0.8
	else:
		velocity.y -= 19.6 * delta

	move_and_slide()
	_update_camera_motion(delta, moving, sprinting)
	_update_footsteps(delta, moving, sprinting)
	if weapon_controller != null and weapon_controller.has_method("set_movement_state"):
		weapon_controller.call("set_movement_state", moving, sprinting)

func _process(delta: float) -> void:
	camera_kick = move_toward(camera_kick, 0.0, delta * 2.4)
	if camera != null:
		camera.rotation.x = pitch + camera_kick
		# The weapon controller owns the zoom while a weapon is equipped; this
		# fallback keeps ADS working in a build without imported assets.
		var weapon_list = weapon_controller.get("weapons") if weapon_controller != null else null
		var weapon_ready: bool = weapon_list is Array and not weapon_list.is_empty()
		if not weapon_ready:
			camera.fov = lerpf(camera.fov, 57.0 if aim_enabled else 78.0, clampf(delta * 9.0, 0.0, 1.0))

func _update_camera_motion(delta: float, moving: bool, sprinting: bool) -> void:
	var base_height := 1.08 if is_crouched else 1.62
	var bob := 0.0
	if moving and is_on_floor():
		camera_bob_time += delta * (13.0 if sprinting else 9.2)
		var bob_scale := 0.030 if sprinting else 0.018
		bob = absf(sin(camera_bob_time)) * bob_scale
	else:
		camera_bob_time = lerpf(camera_bob_time, 0.0, delta * 3.0)
	camera.position.y = move_toward(camera.position.y, base_height + bob, delta * 7.5)

func _update_footsteps(delta: float, moving: bool, sprinting: bool) -> void:
	if not moving or not is_on_floor() or footstep_streams.is_empty():
		footstep_timer = 0.0
		return
	footstep_timer += delta
	var interval := 0.34 if sprinting else (0.52 if is_crouched else 0.46)
	if footstep_timer >= interval:
		footstep_timer = 0.0
		footstep_player.stream = footstep_streams[randi_range(0, footstep_streams.size() - 1)]
		footstep_player.pitch_scale = randf_range(0.94, 1.06)
		footstep_player.play()
