extends Node3D

const WEAPON_DATA = preload("res://scripts/weapons/weapon_data.gd")
const PROJECTILE = preload("res://scripts/weapons/projectile.gd")
const WEAPON_AUDIO = preload("res://scripts/effects/weapon_audio.gd")

const IDLE_ANIM := "Rig|AK_Idle"
const DRAW_ANIM := "Rig|AK_Draw"
const WALK_ANIM := "Rig|AK_Walk"
const RUN_ANIM := "Rig|AK_Run"
const FIRE_ANIM := "Rig|AK_Shot"
const RELOAD_ANIM := "Rig|AK_Reload_full"

const AMMO_NAMES: Array[String] = ["FMJ", "TRACER", "AP"]
const AMMO_RESERVE_START := 120

var camera: Camera3D
var shooter: Node3D
var hud: CanvasLayer
var weapons: Array[Dictionary] = []
var model_paths: Dictionary = {}
var current_index := 0
var magazine_ammo := 30
var reserve_ammo := AMMO_RESERVE_START
var ammo_type_index := 0
var fire_cooldown := 0.0
var reload_remaining := 0.0
var total_shots := 0
var last_shot_used_tracer := false
var aim_enabled := false
var is_reloading := false
var view_model: Node3D
var weapon_scene: Node3D
var animation_player: AnimationPlayer
var action_animation_active := false
var recoil_amount := 0.0
var aim_blend := 0.0
var view_model_base := Vector3(0.31, -0.34, -0.58)
var view_model_ads := Vector3(0.22, -0.25, -0.66)
var view_model_scale := 0.46
var sway_time := 0.0
var movement_state := "idle"
var last_locomotion_animation := ""

func initialize(camera_ref: Camera3D, shooter_ref: Node3D) -> void:
	camera = camera_ref
	shooter = shooter_ref
	_read_model_manifest()
	var all_weapons: Array[Dictionary] = WEAPON_DATA.all_weapons()
	for spec in all_weapons:
		var model_key := str(spec.get("model_key", ""))
		if model_paths.has(model_key) and ResourceLoader.exists(str(model_paths[model_key])):
			weapons.append(spec)
	if weapons.is_empty():
		push_error("No authentic animated weapon model was prepared for this build.")
		return
	magazine_ammo = int(weapons[0].magazine)
	_build_weapon_view_model()
	_update_hud()

func _read_model_manifest() -> void:
	var path := "res://assets/runtime/weapon_manifest.json"
	if not FileAccess.file_exists(path):
		push_error("Weapon model manifest missing. External asset preparation did not run.")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open weapon model manifest.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Weapon model manifest is invalid JSON.")
		return
	model_paths = parsed

func set_hud(hud_ref: CanvasLayer) -> void:
	hud = hud_ref
	_update_hud()

func set_aiming(enabled: bool) -> void:
	aim_enabled = enabled

func set_movement_state(walking: bool, running: bool) -> void:
	if running:
		movement_state = "run"
	elif walking:
		movement_state = "walk"
	else:
		movement_state = "idle"
	_play_locomotion_if_ready()

func cycle_ammo_type() -> void:
	ammo_type_index = (ammo_type_index + 1) % AMMO_NAMES.size()
	_update_hud()
	if hud != null:
		hud.set_message("AMMUNITION: " + AMMO_NAMES[ammo_type_index])

func _process(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	recoil_amount = move_toward(recoil_amount, 0.0, delta * 2.7)
	aim_blend = move_toward(aim_blend, 1.0 if aim_enabled else 0.0, delta * 6.5)
	sway_time += delta
	if view_model != null:
		var target_position := view_model_base.lerp(view_model_ads, aim_blend)
		var sway := Vector3(sin(sway_time * 1.8) * 0.0025, cos(sway_time * 3.6) * 0.0025, 0.0)
		view_model.position = target_position + sway + Vector3(0.0, recoil_amount * 0.12, recoil_amount)
		view_model.rotation.x = -recoil_amount * 0.34

	if is_reloading:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			_finish_reload()
	if weapons.is_empty():
		return
	if Input.is_action_just_pressed("weapon_next"):
		select_weapon((current_index + 1) % weapons.size())
	if Input.is_action_just_pressed("ammo_cycle"):
		cycle_ammo_type()
	if Input.is_action_just_pressed("reload"):
		reload_weapon()
	if Input.is_action_pressed("fire"):
		_try_fire()

func select_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return
	current_index = index
	magazine_ammo = int(weapons[current_index].magazine)
	_build_weapon_view_model()
	_update_hud()

func reload_weapon() -> void:
	if weapons.is_empty() or is_reloading or reserve_ammo <= 0:
		return
	var capacity := int(weapons[current_index].magazine)
	var required := capacity - magazine_ammo
	if required <= 0:
		if hud != null:
			hud.set_message("MAGAZINE FULL")
		return
	is_reloading = true
	action_animation_active = true
	reload_remaining = 2.15
	if animation_player != null and _has_animation(RELOAD_ANIM):
		var clip := animation_player.get_animation(RELOAD_ANIM)
		reload_remaining = maxf(clip.length, 1.25)
		animation_player.play(RELOAD_ANIM)
	if hud != null:
		hud.set_message("RELOADING")
	_update_hud()

func _finish_reload() -> void:
	if not is_reloading or weapons.is_empty():
		return
	var capacity := int(weapons[current_index].magazine)
	var missing := capacity - magazine_ammo
	var transferred := mini(missing, reserve_ammo)
	magazine_ammo += transferred
	reserve_ammo -= transferred
	is_reloading = false
	action_animation_active = false
	_play_locomotion_if_ready()
	_update_hud()
	if hud != null:
		hud.set_message("RELOAD COMPLETE")

func _try_fire() -> void:
	if weapons.is_empty() or is_reloading or fire_cooldown > 0.0:
		return
	if magazine_ammo <= 0:
		if hud != null:
			hud.set_message("EMPTY MAGAZINE — RELOAD")
		return

	var spec: Dictionary = weapons[current_index]
	fire_cooldown = float(spec.fire_interval)
	magazine_ammo -= 1
	total_shots += 1
	recoil_amount = 0.11 if aim_enabled else 0.085
	if is_instance_valid(shooter) and shooter.has_method("add_weapon_recoil"):
		shooter.call("add_weapon_recoil", 0.022 if aim_enabled else 0.014)

	var shot_spec := spec.duplicate(true)
	var ammo_name := AMMO_NAMES[ammo_type_index]
	if ammo_name == "AP":
		shot_spec.damage = float(shot_spec.damage) * 1.12
		shot_spec.penetration = float(shot_spec.penetration) * 1.42
	# Tracers are an explicit ammunition choice; FMJ/AP must not unexpectedly
	# turn into bright streaks every few rounds.
	var use_tracer := ammo_name == "TRACER"
	last_shot_used_tracer = use_tracer
	shot_spec["ammo_type"] = ammo_name
	shot_spec["tracer_color"] = Color(1.0, 0.16, 0.045)

	var camera_basis := camera.global_transform.basis.orthonormalized()
	var camera_origin := camera.global_position
	var forward := -camera_basis.z
	var aim_query := PhysicsRayQueryParameters3D.create(
		camera_origin,
		camera_origin + forward * float(spec.max_range)
	)
	aim_query.collision_mask = 1
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		aim_query.exclude = [shooter.get_rid()]
	var aim_hit := camera.get_world_3d().direct_space_state.intersect_ray(aim_query)
	var aim_point: Vector3 = aim_hit.get("position", camera_origin + forward * float(spec.max_range))
	# Keep the launch point close to the visible weapon and aim from that point
	# toward the camera's actual center-screen target to reduce near-range parallax.
	var muzzle := camera_origin + camera_basis * Vector3(0.22, -0.16, -0.48)
	var shot_direction := (aim_point - muzzle).normalized()
	if shot_direction.is_zero_approx():
		shot_direction = forward
	var projectile := PROJECTILE.new()
	get_tree().current_scene.add_child(projectile)
	projectile.setup(muzzle, shot_direction * float(spec.muzzle_velocity), shot_spec, shooter, use_tracer)

	# One recorded report per shot. Procedural legacy gunshot/impact tones are disabled.
	WEAPON_AUDIO.play_fire(get_tree().current_scene, muzzle, str(spec.audio_profile), -0.8 if not aim_enabled else -1.8)
	if animation_player != null and animation_player.current_animation != FIRE_ANIM:
		_play_action_animation(FIRE_ANIM)
	_spawn_muzzle_flash(muzzle)
	_update_hud()

func _build_weapon_view_model() -> void:
	if camera == null or weapons.is_empty():
		return
	if is_instance_valid(view_model):
		view_model.queue_free()
	view_model = Node3D.new()
	view_model.name = "WeaponViewModel"
	view_model.position = view_model_base
	camera.add_child(view_model)

	var key := str(weapons[current_index].model_key)
	var resource_path := str(model_paths.get(key, ""))
	var packed := load(resource_path) as PackedScene
	if packed == null:
		push_error("Could not load animated first-person weapon scene: " + resource_path)
		return
	weapon_scene = packed.instantiate() as Node3D
	if weapon_scene == null:
		push_error("The imported first-person weapon scene root is not Node3D.")
		return
	weapon_scene.name = "AK74M_ArmsAndWeapon"
	# The source is authored with its rifle axis across the screen in the current
	# camera mount. Rotate the whole rig into the camera-forward axis and reduce
	# its oversized foreground framing; keep the transform isolated at the root.
	weapon_scene.rotation_degrees.y = 90.0
	weapon_scene.scale = Vector3.ONE * view_model_scale
	view_model.add_child(weapon_scene)

	var players := weapon_scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("AK74M first-person model has no AnimationPlayer.")
		return
	animation_player = players[0] as AnimationPlayer
	for required_clip in [IDLE_ANIM, DRAW_ANIM, WALK_ANIM, RUN_ANIM, FIRE_ANIM, RELOAD_ANIM]:
		if not animation_player.has_animation(required_clip):
			push_error("AK74M animation clip missing: " + required_clip)
			return
	animation_player.animation_finished.connect(_on_animation_finished)
	_set_animation_loop(IDLE_ANIM, true)
	_set_animation_loop(WALK_ANIM, true)
	_set_animation_loop(RUN_ANIM, true)
	_play_action_animation(DRAW_ANIM)
	_update_hud()

func _set_animation_loop(animation_name: String, enabled: bool) -> void:
	if not _has_animation(animation_name):
		return
	var clip := animation_player.get_animation(animation_name)
	clip.loop_mode = Animation.LOOP_LINEAR if enabled else Animation.LOOP_NONE

func _has_animation(animation_name: String) -> bool:
	return animation_player != null and animation_player.has_animation(animation_name)

func _play_action_animation(animation_name: String) -> void:
	if not _has_animation(animation_name):
		push_warning("Requested AK74M animation is missing: " + animation_name)
		return
	action_animation_active = true
	animation_player.play(animation_name)

func _play_locomotion_if_ready() -> void:
	if animation_player == null or is_reloading or action_animation_active:
		return
	var desired := IDLE_ANIM
	if movement_state == "walk":
		desired = WALK_ANIM
	elif movement_state == "run":
		desired = RUN_ANIM
	if not _has_animation(desired) or last_locomotion_animation == desired:
		return
	last_locomotion_animation = desired
	animation_player.play(desired)

func _on_animation_finished(animation_name: StringName) -> void:
	var name := str(animation_name)
	if name == RELOAD_ANIM and is_reloading:
		_finish_reload()
	elif name == FIRE_ANIM or name == DRAW_ANIM:
		action_animation_active = false
		last_locomotion_animation = ""
		_play_locomotion_if_ready()

func _spawn_muzzle_flash(world_position: Vector3) -> void:
	var flash := MeshInstance3D.new()
	flash.name = "BriefMuzzleFlash"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.07)
	flash.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.64, 0.22, 0.82)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.26, 0.055)
	material.emission_energy_multiplier = 1.2
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = material
	get_tree().current_scene.add_child(flash)
	flash.global_position = world_position
	flash.look_at(world_position + -camera.global_transform.basis.z, Vector3.UP)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.045
	timer.timeout.connect(flash.queue_free)
	flash.add_child(timer)
	timer.start()

func _update_hud() -> void:
	if hud == null or weapons.is_empty():
		return
	var spec: Dictionary = weapons[current_index]
	hud.set_weapon_info(
		str(spec.name),
		str(spec.caliber),
		magazine_ammo,
		int(spec.magazine),
		reserve_ammo,
		AMMO_NAMES[ammo_type_index],
		"ADS" if aim_enabled else "AUTO"
	)
