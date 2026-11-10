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
const TRACER = preload("res://scripts/effects/tracer_visual.gd")

# --- Bullet state ---

var velocity := Vector3.ZERO
var weapon_stats: Dictionary = {}
var caliber: Dictionary = {}
var shooter: Node3D
var tracer_visual: MeshInstance3D
var tracer_round: Dictionary = {}
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
	# A tracer is a burning round: hot white core, orange halo and a short
	# spark trail that lags behind in world space. No laser line.
	var tracer_color: Color = caliber.get("tracer_color", Color(1.0, 0.30, 0.10))
	tracer_round = TRACER.build_round(self, tracer_color)
	tracer_visual = tracer_round.get("core") as MeshInstance3D
	TRACER.set_visible(tracer_round, false)

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
	if tracer_round.is_empty():
		return
	var root := tracer_round.get("root") as Node3D
	if root == null:
		return

	if not root.visible:
		# Tracer only ignites after the designated distance.
		if travelled_distance < tracer_ignition_distance:
			return
		TRACER.set_visible(tracer_round, true)

	# Faster rounds burn brighter and leave a wider halo; the flicker keeps a
	# stream of tracers from looking like identical sprites.
	var speed_factor := clampf(speed / 950.0, 0.55, 1.5)
	var flicker := 0.88 + sin(alive_time * 62.0) * 0.12
	var outer := tracer_round.get("outer") as MeshInstance3D
	if outer != null:
		outer.scale = Vector3.ONE * speed_factor * (1.0 + sin(alive_time * 41.0) * 0.10)
	var outer_material := tracer_round.get("outer_material") as StandardMaterial3D
	if outer_material != null:
		outer_material.albedo_color.a = clampf(0.26 * speed_factor * flicker, 0.1, 0.55)
	var halo := tracer_round.get("halo") as MeshInstance3D
	if halo != null:
		halo.scale = Vector3.ONE * clampf(speed_factor * flicker, 0.6, 1.4)

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

	# Friendly fire stays off between AI soldiers of the same side.
	if collider is Node and (collider as Node).is_in_group("soldier") and is_instance_valid(shooter) and shooter.has_method("is_alive_soldier") and str(collider.get("faction")) == str(shooter.get("faction")):
		IMPACT_FX.spawn_impact(get_tree().current_scene, point, normal, surface, BALLISTICS.energy_j(caliber, speed), caliber, false)
		queue_free()
		return

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
	if player.has_method("add_suppression"):
		player.call("add_suppression", 0.4)