extends Node3D

const IMPACT_FX = preload("res://scripts/effects/impact_fx.gd")

var velocity := Vector3.ZERO
var weapon_stats: Dictionary = {}
var shooter: Node3D
var tracer_visual: MeshInstance3D
var tracer_enabled := false
var travelled_distance := 0.0
var alive_time := 0.0
var ricochet_used := false
var whiz_played := false

func setup(start_position: Vector3, initial_velocity: Vector3, stats: Dictionary, shooter_node: Node3D, show_tracer: bool) -> void:
	add_to_group("ballistic_projectiles")
	global_position = start_position
	velocity = initial_velocity
	weapon_stats = stats.duplicate(true)
	shooter = shooter_node
	tracer_enabled = show_tracer
	if tracer_enabled:
		_create_tracer_visual()

func _create_tracer_visual() -> void:
	tracer_visual = MeshInstance3D.new()
	# A compact luminous projectile core reads as a moving round. The former
	# multi-metre box rendered as a continuous red laser line on mobile screens.
	var core := SphereMesh.new()
	var caliber_factor := 1.0
	if str(weapon_stats.get("caliber", "")).contains("12.7") or str(weapon_stats.get("caliber", "")).contains(".50"):
		caliber_factor = 1.55
	elif str(weapon_stats.get("caliber", "")).contains("7.62"):
		caliber_factor = 1.2
	core.radius = 0.035 * caliber_factor
	core.height = 0.085 * caliber_factor
	core.radial_segments = 8
	core.rings = 4
	tracer_visual.mesh = core
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tracer_color: Color = weapon_stats.get("tracer_color", Color(1.0, 0.36, 0.10))
	material.albedo_color = Color(1.0, 0.72, 0.32)
	material.emission_enabled = true
	material.emission = tracer_color
	material.emission_energy_multiplier = 1.8
	tracer_visual.material_override = material
	add_child(tracer_visual)

func _physics_process(delta: float) -> void:
	alive_time += delta
	if alive_time > 7.0 or travelled_distance >= float(weapon_stats.get("max_range", 600.0)):
		queue_free()
		return

	var start := global_position
	var speed := velocity.length()
	velocity -= velocity.normalized() * speed * speed * float(weapon_stats.get("drag_coefficient", 0.000006)) * delta
	velocity.y -= 9.81 * float(weapon_stats.get("gravity_scale", 1.0)) * delta
	var finish := start + velocity * delta

	var query := PhysicsRayQueryParameters3D.create(start, finish)
	query.collision_mask = 1
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
	if tracer_visual != null and velocity.length() > 0.1:
		tracer_visual.look_at(global_position + velocity.normalized(), Vector3.UP)
	_check_bullet_whiz()

func _try_ricochet(hit: Dictionary) -> bool:
	if ricochet_used or velocity.length() < 190.0:
		return false
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var impact_angle := absf(velocity.normalized().dot(normal))
	if impact_angle > 0.18:
		return false
	ricochet_used = true
	var point: Vector3 = hit.get("position", global_position)
	velocity = velocity.bounce(normal) * 0.54
	weapon_stats.damage = float(weapon_stats.damage) * 0.28
	global_position = point + normal * 0.12
	IMPACT_FX.spawn_dust(get_tree().current_scene, point, normal, false)
	return true

func _apply_impact(hit: Dictionary) -> void:
	var point: Vector3 = hit.get("position", global_position)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var collider: Object = hit.get("collider")
	var heavy := float(weapon_stats.get("damage", 30.0)) >= 75.0
	if collider != null and collider.has_method("apply_ballistic_damage"):
		collider.call(
			"apply_ballistic_damage",
			float(weapon_stats.get("damage", 30.0)),
			float(weapon_stats.get("penetration", 0.3)),
			str(weapon_stats.get("caliber", ""))
		)
	if str(weapon_stats.get("projectile_kind", "bullet")) == "rocket":
		_apply_explosion(point)
	heavy = heavy or str(weapon_stats.get("projectile_kind", "")) == "rocket"
	IMPACT_FX.spawn_dust(get_tree().current_scene, point, normal, heavy)
	queue_free()

func _apply_explosion(center: Vector3) -> void:
	var radius := float(weapon_stats.get("explosion_radius", 7.5))
	for cover in get_tree().get_nodes_in_group("destructible_cover"):
		if is_instance_valid(cover) and cover.global_position.distance_to(center) <= radius:
			if cover.has_method("apply_ballistic_damage"):
				var cover_distance: float = cover.global_position.distance_to(center)
				var distance_factor: float = clampf(1.0 - cover_distance / radius, 0.0, 1.0)
				cover.call("apply_ballistic_damage", float(weapon_stats.damage) * maxf(distance_factor, 0.12), float(weapon_stats.penetration), "Rocket")

func _check_bullet_whiz() -> void:
	if whiz_played or (is_instance_valid(shooter) and shooter.is_in_group("player")):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var target_camera := player.get_node_or_null("Camera3D") as Camera3D
	if target_camera != null and target_camera.global_position.distance_to(global_position) < 4.8:
		whiz_played = true
