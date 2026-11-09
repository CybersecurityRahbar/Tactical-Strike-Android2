extends Node3D

# Realistic bullet simulation with per-cartridge ballistics.
# - Quadratic drag (a = -k*v²) fitted per caliber against published velocity curves.
# - Gravity integrated each sub-step.
# - Sub-stepping at ≤2 m so trajectory stays accurate at 900 m/s on 30 fps.
# - Damage/penetration derived from remaining velocity, not a fixed number.
# - Tracer visual that appears after ignition distance, glows brighter when supersonic,
#   and fades over distance so it never reads as a continuous laser.
# - Supersonic crack when a bullet passes near the listener.
# - Surface-aware impact effects (dust, debris, sparks, smoke) with correct colors.
# - Ricochet physics for stone/concrete/metal/brick surfaces.

const IMPACT_FX = preload("res://scripts/effects/impact_fx.gd")
const IMPACT_AUDIO = preload("res://scripts/effects/impact_audio.gd")
const BALLISTICS = preload("res://scripts/weapons/ballistics.gd")

# --- Bullet state ---

var velocity := Vector3.ZERO
var weapon_stats: Dictionary = {}
var caliber: Dictionary = {}
var shooter: Node3D
var tracer_visual: MeshInstance3D
var tracer_enabled := false
var tracer_ignition_distance := 22.0
var travelled_distance := 0.0
var alive_time := 0.0
var ricochet_used := false
var whiz_played := false

# --- Setup ---

func setup(start_position: Vector3, initial_velocity: Vector3, stats: Dictionary, shooter_node: Node3D, show_tracer: bool) -> void:
	add_to_group("ballistic_projectiles")
	global_position = start_position
	velocity = initial_velocity
	weapon_stats = stats.duplicate(true)

	# Resolve caliber from weapon stats, allowing a load (tracer/AP) to override.
	caliber = BALLISTICS.profile(str(weapon_stats.get("caliber_id", "5.45x39")))
	caliber["muzzle_velocity"] = float(weapon_stats.get("muzzle_velocity", caliber.muzzle_velocity))
	caliber["penetration"] = float(weapon_stats.get("penetration", caliber.penetration))
	caliber["tracer_color"] = weapon_stats.get("tracer_color", caliber.tracer_color)

	shooter = shooter_node
	tracer_enabled = show_tracer
	tracer_ignition_distance = float(weapon_stats.get("tracer_ignition_distance", 22.0))

	if tracer_enabled:
		_create_tracer_visual()

# --- Tracer visual ---

func _create_tracer_visual() -> void:
	tracer_visual = MeshInstance3D.new()
	tracer_visual.name = "TracerStreak"

	# A short, thin segment with a bright core. The earlier multi-metre box
	# read as a continuous red laser; this reads as a moving tracer round.
	var streak := CylinderMesh.new()
	streak.top_radius = 0.007
	streak.bottom_radius = 0.004
	streak.height = 1.0
	streak.radial_segments = 5
	streak.rings = 1
	tracer_visual.mesh = streak

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var tracer_color: Color = caliber.get("tracer_color", Color(1.0, 0.30, 0.10))
	material.albedo_color = Color(tracer_color.r, tracer_color.g, tracer_color.b, 0.85)
	material.emission_enabled = true
	material.emission = tracer_color
	material.emission_energy_multiplier = 2.6
	material.no_depth_test = false

	tracer_visual.material_override = material
	tracer_visual.visible = false
	add_child(tracer_visual)

# --- Physics process ---

func _physics_process(delta: float) -> void:
	alive_time += delta
	if alive_time > 6.5 or travelled_distance >= float(weapon_stats.get("max_range", 900.0)):
		queue_free()
		return

	var drag := float(caliber.get("drag_per_meter", 0.0013))
	var max_step := 2.0
	var substeps := clampi(int(ceil(velocity.length() * delta / max_step)), 1, 8)
	var sub_delta := delta / float(substeps)

	for _i in range(substeps):
		var speed := velocity.length()
		if speed <= 45.0:
			queue_free()
			return

		# Quadratic drag: dv/dt = -k*v² keeps the published velocity curve.
		var dropped := drag * speed * speed * sub_delta
		var new_speed := maxf(speed - dropped, 40.0)

		# Apply gravity (integrated vertically each sub-step).
		velocity = velocity.normalized() * new_speed
		velocity.y -= BALLISTICS.GRAVITY * float(weapon_stats.get("gravity_scale", 1.0)) * sub_delta

		var start := global_position
		var finish := start + velocity * sub_delta

		# Sweep the sub-step with a ray query to hit anything in-between.
		var query := PhysicsRayQueryParameters3D.create(start, finish)
		query.collision_mask = int(weapon_stats.get("collision_mask", 1))
		if is_instance_valid(shooter) and shooter is CollisionObject3D:
			query.exclude = [shooter.get_rid()]

		var hit := get_world_3d().direct_space_state.intersect_ray(query)

		if not hit.is_empty():
			if _try_ricochet(hit):
				return
			_apply_impact(hit)
			return

		global_position = finish
		travelled_distance += start.distance_to(finish)
		if travelled_distance >= float(weapon_stats.get("max_range", 900.0)):
			queue_free()
			return

		_update_tracer(sub_delta, velocity.length())
		_check_bullet_whiz()

# --- Tracer update ---

func _update_tracer(delta: float, speed: float) -> void:
	if tracer_visual == null:
		return

	if not tracer_visual.visible:
		# Tracer only ignites after the designated distance.
		if travelled_distance < tracer_ignition_distance:
			return
		tracer_visual.visible = true

	var direction := velocity.normalized()
	if direction.is_zero_approx():
		return

	# Streak length capped so a fast round never becomes a laser.
	# The length shrinks with distance so it feels like a trailing effect.
	var streak_length := clampf(speed * delta * 0.55, 0.35, 2.1)

	# Make the tracer glow brighter when the round is supersonic.
	var is_supersonic := speed > BALLISTICS.SPEED_OF_SOUND_MPS
	var color_mod := 1.5 if is_supersonic else 1.0
	var tracer_color: Color = caliber.get("tracer_color", Color(1.0, 0.30, 0.10))
	tracer_visual.material_override.emission = tracer_color * color_mod

	tracer_visual.global_transform = Transform3D(
		Basis.looking_at(direction, Vector3.UP),
		global_position - direction * streak_length * 0.5
	)
	tracer_visual.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	tracer_visual.scale = Vector3(1.0, streak_length, 1.0)

# --- Surface detection ---

func _surface_of(collider: Object) -> String:
	if collider == null:
		return "dirt"
	if collider is Node:
		var node := collider as Node
		if node.has_meta("surface"):
			return str(node.get_meta("surface"))
		if node.is_in_group("combat_target"):
			return "flesh"
		if node.is_in_group("terrain"):
			return "dirt"
		if node.is_in_group("destructible_cover") and node.get_parent() != null:
			return "sand"
	return "dirt"

# --- Ricochet ---

func _try_ricochet(hit: Dictionary) -> bool:
	if ricochet_used or velocity.length() < 250.0:
		return false

	var collider: Object = hit.get("collider")
	var surface := _surface_of(collider)

	# Only stone, concrete, metal, or brick can ricochet.
	if surface != "stone" and surface != "concrete" and surface != "metal" and surface != "brick":
		return false

	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var impact_dot := absf(velocity.normalized().dot(normal))

	# Only shallow grazes deflect: ~12.7 degrees from the surface.
	if impact_dot > 0.22:
		return false

	ricochet_used = true
	var point: Vector3 = hit.get("position", global_position)
	velocity = velocity.bounce(normal) * 0.52
	global_position = point + normal * 0.08
	weapon_stats["damage"] = float(weapon_stats.get("damage", 38.0)) * 0.35

	var detail := _near_player(point, 160.0)
	IMPACT_FX.spawn_impact(get_tree().current_scene, point, normal, surface, velocity.length() * 0.5, caliber, detail)
	IMPACT_AUDIO.play_ricochet(get_tree().current_scene, point, caliber)
	return true

# --- Impact ---

func _apply_impact(hit: Dictionary) -> void:
	var point: Vector3 = hit.get("position", global_position)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var collider: Object = hit.get("collider")
	var surface := _surface_of(collider)
	var speed := velocity.length()
	var base_damage := float(weapon_stats.get("damage", 38.0))
	var damage := BALLISTICS.damage_at(caliber, speed, base_damage)
	var penetration := BALLISTICS.penetration_at(caliber, speed)

	var caliber_name := str(weapon_stats.get("caliber", caliber.get("name", "")))

	# Forward damage/penetration callbacks if the target has the method.
	if collider != null and collider.has_method("apply_ballistic_damage_at"):
		collider.call("apply_ballistic_damage_at", damage, penetration, caliber_name, point, normal, int(hit.get("shape", -1)))
	elif collider != null and collider.has_method("apply_ballistic_damage"):
		collider.call("apply_ballistic_damage", damage, penetration, caliber_name)

	var detail := _near_player(point, 170.0)
	IMPACT_FX.spawn_impact(get_tree().current_scene, point, normal, surface, BALLISTICS.energy_j(caliber, speed), caliber, detail)

	# Play supersonic crack if the bullet was moving fast enough and passed near a player.
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and not whiz_played:
		var target_camera := player.get_node_or_null("Camera3D") as Camera3D
		if is_instance_valid(target_camera):
			var to_round := global_position - target_camera.global_position
			if to_round.length() <= 7.0 and speed > BALLISTICS.SPEED_OF_SOUND_MPS:
				whiz_played = true
				IMPACT_AUDIO.play_crack(get_tree().current_scene, global_position, caliber, BALLISTICS.crack_strength(caliber, speed))

	queue_free()

# --- Explosion (for rocket projectiles) ---

func _apply_explosion(center: Vector3) -> void:
	var radius := float(weapon_stats.get("explosion_radius", 7.5))
	var scene := get_tree().current_scene

	for cover in get_tree().get_nodes_in_group("destructible_cover"):
		if is_instance_valid(cover) and cover.global_position.distance_to(center) <= radius:
			if cover.has_method("apply_ballistic_damage"):
				var distance: float = cover.global_position.distance_to(center)
				var factor: float = clampf(1.0 - distance / radius, 0.0, 1.0)
				cover.call("apply_ballistic_damage", float(weapon_stats.damage) * maxf(factor, 0.12), float(weapon_stats.penetration), "Explosion")

	if scene != null:
		IMPACT_FX.spawn_destruction(scene, center, "dirt")

# --- Helpers ---

func _near_player(point: Vector3, radius: float) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	return player.global_position.distance_to(point) <= radius

func _check_bullet_whiz() -> void:
	if whiz_played or not is_instance_valid(shooter) or shooter.is_in_group("player"):
		return

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var target_camera := player.get_node_or_null("Camera3D") as Camera3D
	if target_camera == null:
		return

	var to_round := global_position - target_camera.global_position
	if to_round.length() > 7.0:
		return

	var speed := velocity.length()
	if not BALLISTICS.is_supersonic(speed):
		return

	whiz_played = true
	IMPACT_AUDIO.play_crack(get_tree().current_scene, global_position, caliber, BALLISTICS.crack_strength(caliber, speed))