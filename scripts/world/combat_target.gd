extends CharacterBody3D

# A fighting soldier: hittable body with hit zones, a procedural rig, and an
# AI loop that actually plays the objective.
#
# Behaviour is deliberately Squad-like rather than arcade: soldiers acquire
# targets by line of sight, hold at a fighting distance, fire short bursts with
# dispersion that grows with range and movement, take a knee when suppressed,
# and push the next capture point when nothing is in sight. They do not track
# the player through walls, and they cannot see further than the map's haze.

signal damaged(distance_m: float, killed: bool)
signal died(faction: String)

const IMPACT_FX = preload("res://scripts/effects/impact_fx.gd")
const IMPACT_AUDIO = preload("res://scripts/effects/impact_audio.gd")
const BALLISTICS = preload("res://scripts/weapons/ballistics.gd")
const SOLDIER = preload("res://scripts/world/soldier_visuals.gd")

@export var faction := "militia"
@export var max_health := 120.0
@export var respawn_seconds := 26.0
@export var sight_range := 330.0
@export var preferred_range := 110.0
@export var marksmanship := 1.0
@export var move_speed := 3.4

var health := 120.0
var alive := true
var home_position := Vector3.ZERO
var rig: Dictionary = {}
var flash := 0.0
var flinch := 0.0
var spawn_time := 0.0

var _target: Node3D = null
var _retarget_timer := 0.0
var _los_timer := 0.0
var _has_los := false
var _fire_timer := 0.0
var _burst_left := 0
var _strafe := 0.0
var _strafe_timer := 0.0
var _walk_cycle := 0.0
var _suppression := 0.0
var _goal := Vector3.ZERO
var _goal_timer := 0.0
var _muzzle_flash_timer := 0.0
var _stuck_time := 0.0
var _detour_timer := 0.0
var _detour_side := 1.0
var _rig_scale := 1.0
var _weapon_stats := {}

func _ready() -> void:
	add_to_group("combat_target")
	add_to_group("soldier")
	set_meta("surface", "flesh")
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.7
	floor_max_angle = deg_to_rad(52.0)
	health = max_health
	home_position = global_position
	spawn_time = Time.get_ticks_msec() * 0.001
	_weapon_stats = {
		"damage": 15.0,
		"caliber_id": "5.45x39",
		"caliber": "5.45x39",
		"max_range": sight_range + 60.0,
	}
	_build_visuals()
	_build_collision()

func _build_visuals() -> void:
	var seed_value := int(absf(home_position.x * 91.7 + home_position.z * 37.3)) + 11
	rig = SOLDIER.build(self, faction, seed_value)
	var variation := 0.94 + fmod(absf(home_position.x), 7.0) * 0.016
	_rig_scale = variation
	(rig["root"] as Node3D).scale = Vector3.ONE * variation

func _build_collision() -> void:
	var body_shape := CollisionShape3D.new()
	body_shape.name = "BodyHitZone"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.29
	capsule.height = 1.52
	body_shape.shape = capsule
	body_shape.position.y = 0.84
	add_child(body_shape)

	var head_shape := CollisionShape3D.new()
	head_shape.name = "HeadHitZone"
	var head_sphere := SphereShape3D.new()
	head_sphere.radius = 0.17
	head_shape.shape = head_sphere
	head_shape.position.y = 1.62
	add_child(head_shape)

# --- Damage -----------------------------------------------------------------

func apply_ballistic_damage_at(damage: float, penetration: float, _caliber: String, point: Vector3, _normal: Vector3, shape_index: int) -> void:
	if not alive:
		return
	var dealt := damage * clampf(0.55 + penetration * 1.4, 0.55, 1.15)
	if shape_index == 1:
		dealt *= 2.8
	health -= dealt
	flash = 1.0
	flinch = clampf(flinch + 0.10, 0.0, 0.34)
	_suppression = clampf(_suppression + 0.55, 0.0, 1.0)
	var player := get_tree().get_first_node_in_group("player")
	var distance := 0.0
	if player != null:
		distance = player.global_position.distance_to(point)
	var killed := health <= 0.0
	damaged.emit(distance, killed)
	if killed:
		_die()
	else:
		_spawn_hit_mist(point)
		# Getting hit breaks the burst and makes the soldier seek cover.
		_burst_left = 0
		_has_los = false
		_los_timer = 0.0

func apply_ballistic_damage(damage: float, penetration: float, caliber: String) -> void:
	apply_ballistic_damage_at(damage, penetration, caliber, global_position + Vector3.UP * 1.2, Vector3.UP, 0)

func _spawn_hit_mist(point: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene != null:
		IMPACT_FX.spawn_impact(scene, point, Vector3.UP, "flesh", 900.0, {"penetration": 0.4}, false)

func _die() -> void:
	alive = false
	health = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_target = null
	if rig.has("root"):
		var visual := rig["root"] as Node3D
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "rotation_degrees:x", -86.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "position:y", -0.18, 0.5)
	died.emit(faction)
	var timer := get_tree().create_timer(respawn_seconds)
	timer.timeout.connect(_respawn)

func _respawn() -> void:
	if not is_inside_tree():
		return
	alive = true
	health = max_health
	_suppression = 0.0
	flash = 0.0
	flinch = 0.0
	collision_layer = 1
	collision_mask = 1
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		# Respawn at the rally point of its own side, never on top of the player.
		var rally := home_position
		if rally.distance_to(player.global_position) < 30.0:
			rally += Vector3(0.0, 0.0, 24.0 if faction == "military" else -24.0)
		global_position = rally
	if rig.has("root"):
		var visual := rig["root"] as Node3D
		visual.rotation_degrees = Vector3.ZERO
		visual.position = Vector3.ZERO

# --- AI ---------------------------------------------------------------------

func chest_position() -> Vector3:
	return global_position + Vector3.UP * 1.30

func eye_position() -> Vector3:
	return global_position + Vector3.UP * 1.60

func is_alive_soldier() -> bool:
	return alive

func _physics_process(delta: float) -> void:
	flash = move_toward(flash, 0.0, delta * 6.0)
	flinch = move_toward(flinch, 0.0, delta * 1.8)
	_suppression = move_toward(_suppression, 0.0, delta * 0.45)
	_animate(delta)

	if not alive:
		return

	if not is_on_floor():
		velocity.y -= 19.6 * delta
	else:
		velocity.y = -0.9

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.45 + randf() * 0.25
		_acquire_target()

	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.30 + randf() * 0.15
		_has_los = _target != null and _check_line_of_sight(_target)

	_update_fire(delta)
	_move(delta)
	var before := global_position
	move_and_slide()
	_unstick(delta, before)

func _acquire_target() -> void:
	if _target != null and (not is_instance_valid(_target) or not _target.call("is_alive_soldier")):
		_target = null
	var best: Node3D = null
	var best_distance := sight_range
	for node in get_tree().get_nodes_in_group("combat_target"):
		if node == self or not is_instance_valid(node):
			continue
		var soldier := node as Node3D
		if soldier == null or str(soldier.get("faction")) == faction:
			continue
		if not bool(soldier.call("is_alive_soldier")):
			continue
		var distance := global_position.distance_to(soldier.global_position)
		if distance < best_distance:
			best_distance = distance
			best = soldier
	if faction != "military":
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player != null and bool(player.call("is_alive_player")):
			var player_distance := global_position.distance_to(player.global_position)
			if player_distance < best_distance:
				best_distance = player_distance
				best = player
	_target = best

func _check_line_of_sight(who: Node3D) -> bool:
	if who == null:
		return false
	if global_position.distance_to(who.global_position) > sight_range:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye_position(), who.global_position + Vector3.UP * 1.25)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == who

func _update_fire(delta: float) -> void:
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_muzzle_flash_timer = maxf(0.0, _muzzle_flash_timer - delta)
	if rig.has("muzzle_flash"):
		(rig["muzzle_flash"] as Node3D).visible = _muzzle_flash_timer > 0.0
	if _target == null or not _has_los:
		_burst_left = 0
		return
	if _fire_timer > 0.0:
		return
	if _target.global_position.distance_to(global_position) > sight_range:
		return
	if _burst_left <= 0:
		_burst_left = 2 + randi() % 4
	_fire_timer = 0.14 + randf() * 0.10
	_burst_left -= 1
	_fire_round()

func _fire_round() -> void:
	if rig.is_empty():
		return
	var muzzle_node := rig.get("muzzle") as Node3D
	var origin: Vector3 = muzzle_node.global_position if muzzle_node != null else eye_position()
	var aim_at: Vector3 = _target.global_position + Vector3.UP * 1.25
	var distance := origin.distance_to(aim_at)
	var lead := distance * 0.0045
	var drop := (distance * distance) * 9.81 / (2.0 * 880.0 * 880.0)
	aim_at += Vector3(0.0, drop + lead * 0.15, 0.0)

	# Dispersion: a marksman at 60 m is deadly, a conscript at 250 m is not.
	var spread_deg := (0.16 + distance * 0.0032) * marksmanship
	spread_deg *= 1.0 + _suppression * 1.4
	if velocity.length() > 0.6:
		spread_deg *= 1.35
	var direction := (aim_at - origin).normalized()
	direction = direction.rotated(Vector3.UP, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	var side := direction.cross(Vector3.UP).normalized()
	direction = direction.rotated(side, deg_to_rad(randf_range(-spread_deg, spread_deg)))

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * sight_range)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	var end: Vector3 = origin + direction * sight_range
	var collider: Object = null
	if not hit.is_empty():
		end = hit.get("position")
		collider = hit.get("collider")
	_spawn_tracer(origin, end)
	_muzzle_flash_timer = 0.05
	if collider != null:
		var surface := "dirt"
		if collider.has_meta("surface"):
			surface = str(collider.get_meta("surface"))
		if collider.has_method("apply_ballistic_damage_at"):
			var penetration := BALLISTICS.penetration_at(BALLISTICS.profile("5.45x39"), 880.0)
			collider.call("apply_ballistic_damage_at", float(_weapon_stats["damage"]), penetration, "5.45x39", end, hit.get("normal", Vector3.UP), int(hit.get("shape", 0)))
		elif collider.has_method("apply_ballistic_damage"):
			collider.call("apply_ballistic_damage", float(_weapon_stats["damage"]), 0.5, "5.45x39")
		var scene := get_tree().current_scene
		if scene != null:
			IMPACT_FX.spawn_impact(scene, end, hit.get("normal", Vector3.UP), surface, 1400.0, BALLISTICS.profile("5.45x39"), end.distance_to(_player_position()) < 90.0)
	_suppress_player(origin, end)
	if get_tree().current_scene != null:
		IMPACT_AUDIO.play_crack(get_tree().current_scene, end, BALLISTICS.profile("5.45x39"), 0.8)

func _player_position() -> Vector3:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return Vector3(99999.0, 0.0, 99999.0)
	return (player as Node3D).global_position

func _suppress_player(origin: Vector3, end: Vector3) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("add_suppression"):
		return
	var camera := (player as Node3D).get_node_or_null("Camera3D") as Node3D
	if camera == null:
		return
	var closest := Geometry3D.get_closest_point_to_segment(camera.global_position, origin, end)
	var distance := camera.global_position.distance_to(closest)
	if distance < 9.0:
		player.call("add_suppression", clampf(1.0 - distance / 9.0, 0.0, 1.0) * 0.5)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var length := from.distance_to(to)
	if length < 4.0:
		return
	var tracer := MeshInstance3D.new()
	tracer.name = "BotTracer"
	tracer.add_to_group("bot_tracer")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, length)
	tracer.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.42, 0.16, 0.55 if faction == "militia" else 0.45)
	tracer.material_override = material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(tracer)
	tracer.global_position = (from + to) * 0.5
	if from.distance_to(to) > 0.1:
		tracer.look_at(to, Vector3.UP)
	var tween := tracer.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.14)
	tween.tween_callback(tracer.queue_free)

func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	var engaged: bool = _target != null and _has_los
	if engaged and _target != null:
		var to_target := _target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		var forward := to_target.normalized()
		if distance > preferred_range + 35.0:
			desired = forward * move_speed
		elif distance < preferred_range - 35.0:
			desired = -forward * move_speed * 0.5
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = 1.1 + randf() * 1.6
			_strafe = -1.0 if randf() < 0.5 else 1.0
			if _suppression > 0.35:
				_strafe *= 1.6
		if distance < preferred_range + 55.0:
			desired += forward.cross(Vector3.UP) * _strafe * move_speed * 0.75
			if _suppression > 0.45:
				desired *= 1.25
		# Face the target while firing.
		_face_direction(forward, delta, 7.0)
	else:
		_goal_timer -= delta
		if _goal_timer <= 0.0 or _goal.distance_to(global_position) < 7.0:
			_goal_timer = 5.0 + randf() * 4.0
			_goal = _request_objective()
		var to_goal := _goal - global_position
		to_goal.y = 0.0
		if to_goal.length() > 4.0:
			desired = to_goal.normalized() * move_speed
			_face_direction(to_goal.normalized(), delta, 4.0)

	# Walking into a courtyard wall: sidestep along it instead of grinding.
	if _detour_timer > 0.0:
		_detour_timer -= delta
		var side_step := Vector3(-desired.z, 0.0, desired.x).normalized()
		desired = (side_step * _detour_side + desired.normalized() * 0.3).normalized() * move_speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_velocity := Vector3(desired.x, 0.0, desired.z)
	horizontal = horizontal.move_toward(target_velocity, 14.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if _suppression > 0.6 and not engaged:
		# Pinned: go to ground instead of walking into fire.
		velocity.x *= 0.2
		velocity.z *= 0.2

func _unstick(delta: float, before: Vector3) -> void:
	var wanted := Vector3(velocity.x, 0.0, velocity.z).length() * delta
	var travelled := global_position.distance_to(before)
	if wanted > 0.02 and travelled < wanted * 0.35:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta)
	if _stuck_time > 0.85:
		_stuck_time = 0.0
		_detour_timer = 1.0 + randf() * 0.9
		_detour_side = -1.0 if randf() < 0.5 else 1.0

func _face_direction(direction: Vector3, delta: float, speed: float) -> void:
	if direction.length() < 0.01:
		return
	var target_yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * speed, 0.0, 1.0))

func _request_objective() -> Vector3:
	var director := get_tree().get_first_node_in_group("battle_director")
	if director != null and director.has_method("next_objective"):
		return director.call("next_objective", faction, global_position) as Vector3
	return home_position

func _animate(delta: float) -> void:
	if rig.is_empty():
		return
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var stride := 0.0
	if speed > 0.4:
		_walk_cycle += delta * (7.5 if speed < 4.0 else 9.5)
		stride = sin(_walk_cycle) * clampf(speed / 4.0, 0.0, 1.0) * 0.55
	var leg_left := rig.get("leg_left") as Node3D
	var leg_right := rig.get("leg_right") as Node3D
	if leg_left != null:
		leg_left.rotation.x = stride
	if leg_right != null:
		leg_right.rotation.x = -stride
	var hips := rig.get("hips") as Node3D
	if hips != null:
		hips.position.y = 0.92 + absf(sin(_walk_cycle * 2.0)) * 0.022 * clampf(speed / 4.0, 0.0, 1.0)
	var torso := rig.get("torso") as Node3D
	if torso != null:
		torso.rotation.x = -flinch * 0.8 + (0.06 if _target != null and _has_los else 0.0)
	var head := rig.get("head") as Node3D
	if head != null:
		head.rotation.y = sin(Time.get_ticks_msec() * 0.0006 + spawn_time) * 0.22 * (0.0 if _has_los else 1.0)
	for material in rig.get("materials", []) as Array:
		var standard := material as StandardMaterial3D
		if standard == null:
			continue
		standard.emission_enabled = flash > 0.01
		standard.emission = Color(0.55, 0.08, 0.05)
		standard.emission_energy_multiplier = flash * 1.5
