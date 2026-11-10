extends Node3D

const WEAPON_DATA = preload("res://scripts/weapons/weapon_data.gd")
const PROJECTILE = preload("res://scripts/weapons/projectile.gd")
const WEAPON_AUDIO = preload("res://scripts/effects/weapon_audio.gd")
const BALLISTICS = preload("res://scripts/weapons/ballistics.gd")

const IDLE_ANIM := "Rig|AK_Idle"
const DRAW_ANIM := "Rig|AK_Draw"
const WALK_ANIM := "Rig|AK_Walk"
const RUN_ANIM := "Rig|AK_Run"
const FIRE_ANIM := "Rig|AK_Shot"
const RELOAD_ANIM := "Rig|AK_Reload_full"

const AMMO_RESERVE_START := 150

var camera: Camera3D
var shooter: Node3D
var hud: CanvasLayer
var weapons: Array[Dictionary] = []
var model_paths: Dictionary = {}
var current_index := 0
var magazine_ammo := 30
var reserve_ammo := AMMO_RESERVE_START
var ammo_type_index := 0
var ammo_names: Array[String] = ["FMJ", "TRACER", "AP"]
var fire_cooldown := 0.0
var reload_remaining := 0.0
var total_shots := 0
var last_shot_used_tracer := false
var aim_enabled := false
var is_reloading := false
var view_model: Node3D
var weapon_scene: Node3D
var weapon_magazines: Array[int] = []
var weapon_reserves: Array[int] = []
var muzzle_marker: Marker3D
var muzzle_flash: Node3D
var muzzle_flash_timer: Timer
var animation_player: AnimationPlayer
var action_animation_active := false
var recoil_amount := 0.0
var recoil_side := 0.0
var aim_blend := 0.0
var view_model_base := Vector3(0.31, -0.34, -0.58)
var view_model_ads := Vector3(0.0, -0.175, -0.44)
var sway_time := 0.0
var movement_state := "idle"
var last_locomotion_animation := ""
var burst_shots := 0
var last_shot_time := -10.0
var look_delta := Vector2.ZERO

func initialize(camera_ref: Camera3D, shooter_ref: Node3D) -> void:
	camera = camera_ref
	shooter = shooter_ref
	_read_model_manifest()
	# Every authored weapon joins the loadout. A weapon whose imported rig is
	# missing gets a procedural stand-in so the whole arsenal stays playable
	# even when the external asset download did not run.
	weapons = WEAPON_DATA.all_weapons()
	if weapons.is_empty():
		push_error("Weapon data is empty; nothing to equip.")
		return
	_ready_weapon_ammo()
	magazine_ammo = weapon_magazines[0]
	reserve_ammo = weapon_reserves[0]
	_apply_weapon_defaults()
	_build_weapon_view_model()
	_update_hud()

func _ready_weapon_ammo() -> void:
	weapon_magazines.clear()
	weapon_reserves.clear()
	for spec in weapons:
		var capacity := int(spec.get("magazine", 30))
		weapon_magazines.append(capacity)
		weapon_reserves.append(int(spec.get("reserve_ammo", AMMO_RESERVE_START)))

func _apply_weapon_defaults() -> void:
	var spec: Dictionary = weapons[current_index]
	ammo_names = WEAPON_DATA.ammo_names(spec)
	ammo_type_index = clampi(ammo_type_index, 0, ammo_names.size() - 1)
	view_model_base = spec.get("view_hip_position", Vector3(0.31, -0.34, -0.58))
	view_model_ads = spec.get("view_ads_position", Vector3(0.0, -0.175, -0.44))

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

func notify_look(delta: Vector2) -> void:
	look_delta += delta

func _ammo_name() -> String:
	if ammo_names.is_empty():
		return "FMJ"
	return ammo_names[clampi(ammo_type_index, 0, ammo_names.size() - 1)]

func cycle_ammo_type() -> void:
	if weapons.is_empty():
		return
	ammo_type_index = (ammo_type_index + 1) % ammo_names.size()
	_update_hud()
	if hud != null:
		hud.set_message("AMMUNITION: " + _ammo_name())

func _process(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	recoil_amount = move_toward(recoil_amount, 0.0, delta * 2.7)
	recoil_side = move_toward(recoil_side, 0.0, delta * 1.9)
	aim_blend = move_toward(aim_blend, 1.0 if aim_enabled else 0.0, delta * 6.5)
	sway_time += delta
	if camera != null and not weapons.is_empty():
		var spec: Dictionary = weapons[current_index]
		var hip_fov := float(spec.get("hip_fov", 78.0))
		var ads_fov := float(spec.get("ads_fov", 34.0))
		camera.fov = lerpf(camera.fov, lerpf(hip_fov, ads_fov, aim_blend), clampf(delta * 10.0, 0.0, 1.0))
	if view_model != null:
		var breathe := Vector3(sin(sway_time * 1.8) * 0.0022, cos(sway_time * 3.6) * 0.0018, 0.0)
		var bob := Vector3(sin(sway_time * 5.2) * 0.004, absf(sin(sway_time * 5.2)) * 0.004, 0.0)
		if movement_state == "idle":
			bob = Vector3.ZERO
		var look_sway := Vector3(clampf(-look_delta.x * 0.00035, -0.02, 0.02), clampf(look_delta.y * 0.0003, -0.02, 0.02), 0.0)
		var target_position := view_model_base.lerp(view_model_ads, aim_blend)
		# Sprinting drops the rifle to the chest, like Squad's run pose.
		if movement_state == "run":
			target_position += Vector3(0.02, -0.13, -0.05)
		view_model.position = target_position + breathe + bob + look_sway + Vector3(recoil_side * 0.35, recoil_amount * 0.12, recoil_amount)
		view_model.rotation.x = -recoil_amount * 0.36
		view_model.rotation.y = recoil_side * 0.10
		look_delta = look_delta.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
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
	if index == current_index:
		return
	if not weapon_magazines.is_empty():
		weapon_magazines[current_index] = magazine_ammo
		weapon_reserves[current_index] = reserve_ammo
	current_index = index
	magazine_ammo = weapon_magazines[index]
	reserve_ammo = weapon_reserves[index]
	_apply_weapon_defaults()
	# Switching a rifle does not magically refill its magazine; the crate
	# reload is an explicit action.
	if magazine_ammo <= 0:
		reload_weapon()
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

func _muzzle_world_position() -> Vector3:
	if muzzle_marker != null and is_instance_valid(muzzle_marker):
		return muzzle_marker.global_position
	var basis := camera.global_transform.basis.orthonormalized()
	return camera.global_position + basis * Vector3(0.22, -0.16, -0.48)

func _try_fire() -> void:
	if movement_state == "run":
		return
	if weapons.is_empty() or is_reloading or fire_cooldown > 0.0:
		return
	if magazine_ammo <= 0:
		if hud != null:
			hud.set_message("EMPTY MAGAZINE — RELOAD")
		return

	var weapon: Dictionary = weapons[current_index]
	fire_cooldown = float(weapon.fire_interval)
	magazine_ammo -= 1
	total_shots += 1

	var now := Time.get_ticks_msec() * 0.001
	if now - last_shot_time > 0.30:
		burst_shots = 0
	last_shot_time = now
	burst_shots += 1
	var burst_factor := 1.0 + minf(float(burst_shots - 1) * 0.16, 1.0)

	var shot_spec := WEAPON_DATA.build_shot_spec(weapon, _ammo_name())
	last_shot_used_tracer = bool(shot_spec.get("tracer", false))
	shot_spec["tracer_ignition_distance"] = float(weapon.get("tracer_ignition_distance", 22.0))
	shot_spec["collision_mask"] = 1

	var recoil_scale := 0.78 if aim_enabled else 1.0
	var pitch_kick := float(weapon.get("recoil_pitch", 0.019)) * recoil_scale * burst_factor
	var yaw_kick := float(weapon.get("recoil_yaw", 0.0055)) * randf_range(-1.0, 1.0) * recoil_scale * burst_factor
	recoil_amount = 0.085 * recoil_scale
	recoil_side = randf_range(-1.0, 1.0) * 0.5
	if is_instance_valid(shooter) and shooter.has_method("add_weapon_recoil"):
		shooter.call("add_weapon_recoil", pitch_kick, yaw_kick)

	var camera_basis := camera.global_transform.basis.orthonormalized()
	var camera_origin := camera.global_position
	var forward := -camera_basis.z
	# Dispersion is an angular cone around the camera axis; it tightens when
	# aiming down the sights and opens up during a long burst.
	var spread_deg := lerpf(float(weapon.get("spread_hip_deg", 0.55)), float(weapon.get("spread_ads_deg", 0.12)), aim_blend) * burst_factor
	# Being under fire opens the cone: suppression is a real mechanic, not a filter.
	if is_instance_valid(shooter):
		var suppression: float = float(shooter.get("suppression"))
		if suppression > 0.0:
			spread_deg *= 1.0 + suppression * 1.3
	var angle := deg_to_rad(spread_deg) * sqrt(randf())
	var roll := randf() * TAU
	var shot_direction := (forward
		+ camera_basis.x * cos(roll) * tan(angle)
		+ camera_basis.y * sin(roll) * tan(angle)).normalized()

	var aim_query := PhysicsRayQueryParameters3D.create(camera_origin, camera_origin + shot_direction * float(weapon.get("max_range", 900.0)))
	aim_query.collision_mask = 1
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		aim_query.exclude = [shooter.get_rid()]
	var aim_hit := camera.get_world_3d().direct_space_state.intersect_ray(aim_query)
	var aim_point: Vector3 = aim_hit.get("position", camera_origin + shot_direction * float(weapon.get("max_range", 900.0)))
	var muzzle := _muzzle_world_position()
	var direction := (aim_point - muzzle).normalized()
	if direction.is_zero_approx():
		direction = shot_direction
	# Sights are regulated for `zero_distance`: lift the bore line by the drop
	# it would accumulate over that distance, mirroring how a rifle is zeroed.
	var zero_distance := float(weapon.get("zero_distance", 300.0))
	var ballistic_profile := BALLISTICS.profile(str(shot_spec.caliber_id))
	ballistic_profile["muzzle_velocity"] = float(shot_spec.muzzle_velocity)
	if zero_distance > 1.0:
		var zero_lift := BALLISTICS.drop_at(ballistic_profile, zero_distance) / zero_distance
		direction = (direction + camera_basis.y * zero_lift).normalized()
	var projectile := PROJECTILE.new()
	get_tree().current_scene.add_child(projectile)
	projectile.setup(muzzle, direction * float(shot_spec.muzzle_velocity), shot_spec, shooter, last_shot_used_tracer)

	WEAPON_AUDIO.play_fire(get_tree().current_scene, muzzle, str(weapon.audio_profile), -0.8 if not aim_enabled else -2.2)
	if animation_player != null:
		if animation_player.current_animation == FIRE_ANIM:
			# Retrigger the shot pose so rapid fire stays in sync with the muzzle.
			animation_player.seek(0.0, true)
		else:
			_play_action_animation(FIRE_ANIM)
	_show_muzzle_flash(muzzle, direction)
	_update_hud()

func _build_weapon_view_model() -> void:
	if camera == null or weapons.is_empty():
		return
	if is_instance_valid(view_model):
		view_model.queue_free()
	if is_instance_valid(muzzle_flash):
		muzzle_flash.queue_free()
	if is_instance_valid(muzzle_flash_timer):
		muzzle_flash_timer.queue_free()
	view_model = Node3D.new()
	view_model.name = "WeaponViewModel"
	view_model.position = view_model_base
	camera.add_child(view_model)
	animation_player = null
	last_locomotion_animation = ""
	action_animation_active = false

	var spec: Dictionary = weapons[current_index]
	var key := str(spec.model_key)
	var resource_path := str(model_paths.get(key, ""))
	var packed: PackedScene = null
	if resource_path != "" and ResourceLoader.exists(resource_path):
		packed = load(resource_path) as PackedScene
	if packed == null:
		# No imported rig for this weapon: build a stand-in silhouette so the
		# weapon is still visible, aimable and fully playable.
		_build_procedural_view_model(spec)
		return
	weapon_scene = packed.instantiate() as Node3D
	if weapon_scene == null:
		push_error("The imported first-person weapon scene root is not Node3D.")
		return
	weapon_scene.name = "AK74M_ArmsAndWeapon"
	# The rig is authored with the barrel along +Z, so it is rotated 180 degrees
	# to face the camera's -Z forward axis. Mount values are authored in
	# weapon_data.gd so framing changes never require touching this code.
	weapon_scene.rotation_degrees = spec.get("view_rotation_degrees", Vector3(0.0, 180.0, 0.0))
	weapon_scene.scale = Vector3.ONE * float(spec.get("view_scale", 0.46))
	view_model.add_child(weapon_scene)
	_create_muzzle_marker()
	_create_muzzle_flash()

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

# Silhouette dimensions for weapons that have no imported rig. Values are in
# the rig's own space where +Z points down the bore (the mount transform then
# turns that towards the camera's -Z forward axis).
const PROC_GEOMETRY := {
	"ak74m": {"barrel": 1.00, "radius": 0.020, "optic": 0.0, "tube": 0.0, "wood": true},
	"m4a1": {"barrel": 0.90, "radius": 0.018, "optic": 0.0, "tube": 0.0, "wood": false},
	"pkm": {"barrel": 1.12, "radius": 0.024, "optic": 0.0, "tube": 0.0, "wood": true},
	"rpg7": {"barrel": 1.25, "radius": 0.042, "optic": 0.12, "tube": 0.075, "wood": true},
	"dragunov": {"barrel": 1.22, "radius": 0.020, "optic": 0.20, "tube": 0.0, "wood": true},
	"50cal": {"barrel": 1.40, "radius": 0.032, "optic": 0.22, "tube": 0.0, "wood": false},
	"dushka": {"barrel": 1.32, "radius": 0.034, "optic": 0.16, "tube": 0.0, "wood": false},
}

func _build_procedural_view_model(spec: Dictionary) -> void:
	if view_model == null:
		return
	var wid := str(spec.get("id", ""))
	var geometry: Dictionary = PROC_GEOMETRY.get(wid, {"barrel": 1.0, "radius": 0.020, "optic": 0.0, "tube": 0.0, "wood": false})
	weapon_scene = Node3D.new()
	weapon_scene.name = wid + "_Procedural"
	weapon_scene.rotation_degrees = spec.get("view_rotation_degrees", Vector3(0.0, 180.0, 0.0))
	weapon_scene.scale = Vector3.ONE * float(spec.get("view_scale", 0.46))
	view_model.add_child(weapon_scene)

	var metal := _proc_material(Color(0.14, 0.145, 0.155), 0.70, 0.38)
	var furniture := _proc_material(Color(0.33, 0.22, 0.12) if bool(geometry.get("wood", false)) else Color(0.10, 0.10, 0.11), 0.15, 0.72)

	var barrel_len := float(geometry.get("barrel", 1.0))
	var radius := float(geometry.get("radius", 0.020))
	var tube_radius := float(geometry.get("tube", 0.0))

	if tube_radius > 0.0:
		# Launcher: one fat tube with a cone warhead at the muzzle end.
		_add_proc_cylinder(weapon_scene, tube_radius, barrel_len * 1.05, Vector3(0.0, 0.0, barrel_len * 0.45), metal)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = tube_radius * 1.25
		cone.height = 0.24
		var cone_instance := MeshInstance3D.new()
		cone_instance.mesh = cone
		cone_instance.material_override = _proc_material(Color(0.30, 0.28, 0.20), 0.4, 0.5)
		cone_instance.position = Vector3(0.0, 0.0, barrel_len * 1.02)
		cone_instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		cone_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		weapon_scene.add_child(cone_instance)
		_add_proc_box(weapon_scene, Vector3(0.05, 0.14, 0.06), Vector3(0.0, -0.10, 0.06), furniture)
	else:
		_add_proc_cylinder(weapon_scene, radius, barrel_len * 0.9, Vector3(0.0, 0.03, barrel_len * 0.45), metal)
		_add_proc_box(weapon_scene, Vector3(0.086, 0.118, 0.56), Vector3(0.0, 0.0, 0.02), furniture)
		_add_proc_box(weapon_scene, Vector3(0.055, 0.095, 0.30), Vector3(0.0, -0.004, -0.40), furniture)
		_add_proc_box(weapon_scene, Vector3(0.052, 0.215, 0.10), Vector3(0.0, -0.145, 0.06), metal)
		_add_proc_box(weapon_scene, Vector3(0.045, 0.14, 0.06), Vector3(0.0, -0.125, -0.12), furniture)
		_add_proc_box(weapon_scene, Vector3(0.048, 0.032, 0.22), Vector3(0.0, 0.072, 0.30), furniture)

	var optic_height := float(geometry.get("optic", 0.0))
	if optic_height > 0.0:
		_add_proc_cylinder(weapon_scene, 0.034, 0.30, Vector3(0.0, 0.085 + optic_height * 0.4, 0.08), metal)
		_add_proc_box(weapon_scene, Vector3(0.048, optic_height * 0.55, 0.16), Vector3(0.0, 0.07 + optic_height * 0.22, 0.08), metal)

	_create_muzzle_marker(Vector3(0.0, 0.03, barrel_len * (1.06 if tube_radius > 0.0 else 0.9)))
	_create_muzzle_flash()
	_update_hud()

func _proc_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

func _add_proc_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _add_proc_cylinder(parent: Node3D, cylinder_radius: float, length: float, at: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = cylinder_radius
	mesh.bottom_radius = cylinder_radius
	mesh.height = length
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _create_muzzle_marker(local_offset := Vector3(-0.10, 0.03, 1.978)) -> void:
	muzzle_marker = Marker3D.new()
	muzzle_marker.name = "MuzzlePoint"
	# Barrel tip in the rig's own space, computed from the skinned pose of the
	# imported glTF (not from the unskinned bind AABB): the rifle mesh spans
	# z = -0.779 .. +1.978 and the magazine sits at the negative-Z grip end, so
	# +Z is the muzzle. Mounting the model 180 degrees maps that to camera -Z.
	muzzle_marker.position = local_offset
	weapon_scene.add_child(muzzle_marker)

func _create_muzzle_flash() -> void:
	muzzle_flash = Node3D.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.visible = false
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.albedo_color = Color(1.0, 0.72, 0.34, 0.95)
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.55, 0.18)
	flash_material.emission_energy_multiplier = 3.2
	for i in range(3):
		var petal := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var scale_factor := 1.0 - float(i) * 0.22
		quad.size = Vector2(0.34 * scale_factor, 0.15 * scale_factor)
		petal.mesh = quad
		petal.material_override = flash_material
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		petal.rotation.z = float(i) * (TAU / 3.0)
		petal.position.z = -0.02 * float(i)
		muzzle_flash.add_child(petal)
	# No dynamic muzzle light: toggling an OmniLight at 600 rpm forces a light
	# list update every shot and can hitch on mobile. The additive petals plus
	# the environment glow carry the flash instead.
	camera.add_child(muzzle_flash)
	muzzle_flash_timer = Timer.new()
	muzzle_flash_timer.one_shot = true
	muzzle_flash_timer.wait_time = 0.055
	muzzle_flash_timer.timeout.connect(_hide_muzzle_flash)
	add_child(muzzle_flash_timer)

func _show_muzzle_flash(_world_position: Vector3, direction: Vector3) -> void:
	if muzzle_flash == null or muzzle_marker == null:
		return
	muzzle_flash.global_position = muzzle_marker.global_position
	var up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.98:
		up = Vector3.RIGHT
	muzzle_flash.look_at(muzzle_marker.global_position + direction, up)
	muzzle_flash.visible = true
	if muzzle_flash_timer != null:
		muzzle_flash_timer.start()

func _hide_muzzle_flash() -> void:
	if muzzle_flash != null:
		muzzle_flash.visible = false

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
		_ammo_name(),
		"ADS" if aim_enabled else "AUTO"
	)

# Used by the HUD and the acceptance test: true when the barrel points down
# the camera forward axis rather than across the screen.
func muzzle_direction() -> Vector3:
	if muzzle_marker == null:
		return Vector3.ZERO
	# The marker inherits the 180-degree mount, so its +Z axis already points
	# down the camera's forward (-Z world) direction.
	return muzzle_marker.global_transform.basis.z.normalized()

func ballistic_report(distance_m: float) -> Dictionary:
	if weapons.is_empty():
		return {}
	var spec := WEAPON_DATA.build_shot_spec(weapons[current_index], _ammo_name())
	var caliber := BALLISTICS.profile(str(spec.caliber_id))
	caliber["muzzle_velocity"] = float(spec.muzzle_velocity)
	var speed := BALLISTICS.speed_at(caliber, distance_m)
	return {
		"distance": distance_m,
		"speed": speed,
		"energy": BALLISTICS.energy_j(caliber, speed),
		"time_of_flight": BALLISTICS.time_of_flight(caliber, distance_m),
		"drop": BALLISTICS.drop_at(caliber, distance_m),
		"damage": BALLISTICS.damage_at(caliber, speed, float(spec.damage))
	}
