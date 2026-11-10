extends RefCounted

# Burning tracer round visuals.
#
# A tracer is not a red line drawn from the muzzle to the target: it is a
# small, extremely bright projectile with a hot white core, an orange halo and
# a short trail of sparks that lags behind it. This module builds that round
# once and lets callers move it along its flight path (player bullets) or
# animate a fast streak to an impact point (AI bursts).

static var _glow_texture: ImageTexture

# Soft radial falloff: white hot centre, orange shoulder, transparent edge.
static func glow_texture() -> ImageTexture:
	if _glow_texture != null:
		return _glow_texture
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre) / (float(size) * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.7)
			var hot := clampf(1.0 - d * 2.2, 0.0, 1.0)
			var color := Color(1.0, 0.55 + hot * 0.42, 0.24 + hot * 0.66, a)
			image.set_pixel(x, y, color)
	_glow_texture = ImageTexture.create_from_image(image)
	return _glow_texture

static func _glow_quad(size: float, color: Color, alpha: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = glow_texture()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 4.0
	material.no_depth_test = false
	material.disable_receive_shadows = true
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

# Builds a complete burning round under `parent`. Returns the pieces the
# caller needs: the node to move, the halo materials and the spark trail.
static func build_round(parent: Node3D, color: Color) -> Dictionary:
	var root := Node3D.new()
	root.name = "TracerRound"
	parent.add_child(root)

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.026
	core_mesh.height = 0.075
	core_mesh.radial_segments = 6
	core_mesh.rings = 3
	core.mesh = core_mesh
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = Color(1.0, 0.97, 0.82)
	core_material.emission_enabled = true
	core_material.emission = Color(1.0, 0.82, 0.44)
	core_material.emission_energy_multiplier = 9.0
	core.material_override = core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)

	# Halo: a bright inner quad and a wide, dimmer outer quad.
	var halo := _glow_quad(0.30, Color(1.0, 0.72, 0.34), 0.95)
	root.add_child(halo)
	var outer := _glow_quad(0.95, Color(1.0, 0.42, 0.12), 0.34)
	root.add_child(outer)

	# Spark trail: particles emitted in world space so they stay behind.
	var trail := CPUParticles3D.new()
	trail.name = "TracerTrail"
	trail.amount = 10
	trail.lifetime = 0.085
	trail.local_coords = false
	trail.emitting = false
	trail.direction = Vector3.ZERO
	trail.spread = 12.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.4
	trail.scale_amount_min = 0.25
	trail.scale_amount_max = 0.6
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.035
	spark_mesh.height = 0.07
	spark_mesh.radial_segments = 4
	spark_mesh.rings = 2
	trail.mesh = spark_mesh
	var trail_material := StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.albedo_color = Color(1.0, 0.58, 0.22)
	trail_material.emission_enabled = true
	trail_material.emission = Color(1.0, 0.55, 0.20)
	trail_material.emission_energy_multiplier = 5.0
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = trail_material
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trail)

	return {
		"root": root,
		"core": core,
		"halo": halo,
		"outer": outer,
		"trail": trail,
		"core_material": core_material,
		"halo_material": halo.material_override,
		"outer_material": outer.material_override,
	}

static func set_visible(round: Dictionary, visible: bool) -> void:
	var root := round.get("root") as Node3D
	if root == null:
		return
	root.visible = visible
	var trail := round.get("trail") as CPUParticles3D
	if trail != null:
		trail.emitting = visible

# A complete fly-out streak for AI fire: the round travels the whole line in
# real time and leaves a spark trail, instead of drawing a static laser line.
static func spawn_streak(scene: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	var distance := from.distance_to(to)
	if distance < 6.0:
		return
	var round := build_round(scene as Node3D, color)
	var root := round.get("root") as Node3D
	root.add_to_group("bot_tracer")
	root.global_position = from
	set_visible(round, true)

	# 850 m/s is close enough that the eye reads it as a tracer, not a laser.
	var flight := clampf(distance / 850.0, 0.03, 0.55)
	var tween := root.create_tween()
	tween.tween_property(root, "global_position", to, flight)
	tween.tween_callback(func():
		set_visible(round, false)
		# Short afterglow so the halo does not pop out of existence.
		var fade := root.create_tween()
		fade.tween_interval(0.10)
		fade.tween_callback(root.queue_free)
	)
