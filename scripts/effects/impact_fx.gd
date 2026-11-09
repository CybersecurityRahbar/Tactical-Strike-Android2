extends RefCounted

# Surface-aware ballistic impact effects.
#
# Each impact is a combination of four cheap, mobile-friendly layers:
#   1. a dust plume tinted by the surface (dirt, sand, brick, stone, wood),
#   2. solid debris chips thrown along the surface normal,
#   3. bright sparks for stone / brick / metal,
#   4. a short-lived smoke puff for nearby impacts.
# The energy of the round scales amount, speed and lifetime, so a 12.7 mm hit
# visibly tears up the ground while a 5.45 mm hit kicks a small puff.

const IMPACT_AUDIO = preload("res://scripts/effects/impact_audio.gd")

const SURFACE_COLORS := {
	"dirt": Color(0.52, 0.42, 0.29, 0.82),
	"sand": Color(0.66, 0.57, 0.40, 0.80),
	"gravel": Color(0.47, 0.42, 0.35, 0.78),
	"stone": Color(0.60, 0.58, 0.53, 0.70),
	"concrete": Color(0.66, 0.64, 0.60, 0.70),
	"brick": Color(0.55, 0.34, 0.26, 0.76),
	"wood": Color(0.44, 0.31, 0.19, 0.72),
	"metal": Color(0.55, 0.55, 0.58, 0.60),
	"flesh": Color(0.35, 0.09, 0.07, 0.55)
}

static func _color_for(surface: String) -> Color:
	return SURFACE_COLORS.get(surface, SURFACE_COLORS["dirt"])

static func _particles(parent: Node, node_name: String, amount: int, lifetime: float, mesh: Mesh, color: Color, glow: bool) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = maxi(amount, 1)
	particles.lifetime = lifetime
	particles.mesh = mesh
	particles.direction = Vector3.UP
	particles.spread = 55.0
	particles.gravity = Vector3(0.0, -9.8, 0.0)
	particles.scale_amount_min = 0.65
	particles.scale_amount_max = 1.35
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 3.4
	particles.material_override = material
	parent.add_child(particles)
	return particles

static func _finish(particles: CPUParticles3D, position: Vector3, normal: Vector3, vmin: float, vmax: float, spread: float) -> void:
	particles.global_position = position + normal.normalized() * 0.05
	particles.direction = normal.normalized()
	particles.spread = spread
	particles.initial_velocity_min = vmin
	particles.initial_velocity_max = vmax
	particles.emitting = true
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = particles.lifetime + 0.65
	timer.timeout.connect(particles.queue_free)
	particles.add_child(timer)
	timer.start()

static func _smoke_puff(parent: Node, position: Vector3, normal: Vector3, color: Color, power: float) -> void:
	var puff := MeshInstance3D.new()
	puff.name = "ImpactSmoke"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	puff.mesh = quad
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.42)
	material.no_depth_test = false
	puff.material_override = material
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(puff)
	puff.global_position = position + normal.normalized() * 0.22
	puff.scale = Vector3.ONE * (0.18 + power * 0.06)
	var final_scale := 0.65 + power * 0.42
	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * final_scale, 0.8)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.8)
	tween.chain().tween_callback(puff.queue_free)

static func spawn_impact(parent: Node, position: Vector3, normal: Vector3, surface: String, energy_j: float, caliber: Dictionary, detail: bool = true) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var power := clampf(energy_j / 1500.0, 0.18, 2.4)
	var color := _color_for(surface)
	var dust := SphereMesh.new()
	dust.radius = 0.045 + power * 0.02
	dust.height = dust.radius * 2.0
	dust.radial_segments = 6
	dust.rings = 3
	# Distant impacts only need the dust plume; debris, sparks, smoke and the
	# positional report are skipped to keep lots of long-range fire cheap.
	var dust_amount := int(10.0 + 16.0 * power) if detail else int(5.0 + 7.0 * power)
	var plume := _particles(parent, "BallisticImpactDust", dust_amount, 0.55 + 0.28 * power, dust, color, false)
	_finish(plume, position, normal, 1.6 + power, 5.5 + power * 3.2, 62.0)

	if surface == "flesh":
		var mist := SphereMesh.new()
		mist.radius = 0.09
		mist.height = 0.18
		var spray := _particles(parent, "BallisticImpactMist", int(6 + 4 * power), 0.5, mist, color, false)
		_finish(spray, position, normal, 0.8, 2.4, 38.0)
		if detail:
			IMPACT_AUDIO.play_impact(parent, position, surface, energy_j, caliber)
		return

	if not detail:
		return

	if surface == "wood":
		var splinter_mesh := BoxMesh.new()
		splinter_mesh.size = Vector3(0.035, 0.035, 0.16)
		var splinters := _particles(parent, "BallisticImpactDebris", int(4 + 4 * power), 0.85, splinter_mesh, Color(0.32, 0.22, 0.13, 0.9), false)
		_finish(splinters, position, normal, 2.4, 6.5, 48.0)
	elif surface == "stone" or surface == "concrete" or surface == "metal" or surface == "brick":
		var chip_mesh := BoxMesh.new()
		chip_mesh.size = Vector3(0.028, 0.028, 0.028) * (0.8 + power * 0.5)
		var chip_color: Color = color.darkened(0.25)
		var chips := _particles(parent, "BallisticImpactDebris", int(4 + 5 * power), 1.0, chip_mesh, chip_color, false)
		_finish(chips, position, normal, 3.0, 9.0 + power * 2.0, 52.0)
	else:
		# Dirt clods: fewer, heavier, shorter lived than stone chips.
		var clod_mesh := SphereMesh.new()
		clod_mesh.radius = 0.032
		clod_mesh.height = 0.064
		clod_mesh.radial_segments = 4
		clod_mesh.rings = 2
		var clods := _particles(parent, "BallisticImpactDebris", int(3 + 3 * power), 0.7, clod_mesh, Color(0.29, 0.22, 0.15, 0.92), false)
		_finish(clods, position, normal, 2.0, 6.0, 55.0)

	if detail and (surface == "stone" or surface == "concrete" or surface == "metal" or surface == "brick"):
		var spark_mesh := SphereMesh.new()
		spark_mesh.radius = 0.012
		spark_mesh.height = 0.045
		spark_mesh.radial_segments = 4
		spark_mesh.rings = 2
		var spark_scale := 1.0 if surface != "metal" else 1.5
		var sparks := _particles(parent, "BallisticImpactSparks", int((5 + 7 * power) * spark_scale), 0.28, spark_mesh, Color(1.0, 0.72, 0.32, 1.0), true)
		_finish(sparks, position, normal, 4.0, 12.0 + power * 3.0, 46.0)

	if detail and power > 0.35:
		_smoke_puff(parent, position, normal, color.lerp(Color(0.35, 0.33, 0.30), 0.45), power)

	IMPACT_AUDIO.play_impact(parent, position, surface, energy_j, caliber)

# Backwards-compatible helper used by older call sites and the smoke test.
static func spawn_dust(parent: Node, position: Vector3, normal: Vector3, heavy: bool = false) -> void:
	spawn_impact(parent, position, normal, "dirt", 2600.0 if heavy else 900.0, {"penetration": 0.5}, true)

# Heavy debris burst when a cover piece is destroyed.
static func spawn_destruction(parent: Node, position: Vector3, surface: String) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var color := _color_for(surface)
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.16, 0.12, 0.16)
	var debris := _particles(parent, "CoverDebris", 26, 1.6, chunk, color.darkened(0.15), false)
	_finish(debris, position + Vector3(0.0, 0.4, 0.0), Vector3.UP, 2.5, 8.0, 75.0)
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.16
	dust_mesh.height = 0.32
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	var cloud := _particles(parent, "CoverDust", 34, 1.9, dust_mesh, color, false)
	_finish(cloud, position + Vector3(0.0, 0.35, 0.0), Vector3.UP, 1.2, 4.5, 80.0)
	_smoke_puff(parent, position + Vector3(0.0, 0.4, 0.0), Vector3.UP, color, 2.2)
	IMPACT_AUDIO.play_destruction(parent, position, surface)
