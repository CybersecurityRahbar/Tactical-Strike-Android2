extends RefCounted

# Surface-aware ballistic impact effects.
#
# A bullet strike is four things at once, and each one is what sells it:
#   1. a permanent hole with a chipped, cracked rim on the struck surface,
#   2. material thrown back out of the hole along the normal,
#   3. a puff of dust that lingers and drifts,
#   4. sparks and a brief flash for stone, brick and steel.
# The energy of the round scales every layer, so a 12.7 mm hit tears a crater
# while a 5.45 mm hit chips the plaster.

const IMPACT_AUDIO = preload("res://scripts/effects/impact_audio.gd")

const MAX_HOLES := 150
const HOLE_GROUP := "bullet_holes"

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

const HOLE_COLORS := {
	"dirt": Color(0.205, 0.165, 0.115),
	"sand": Color(0.30, 0.245, 0.170),
	"gravel": Color(0.22, 0.20, 0.17),
	"stone": Color(0.30, 0.29, 0.27),
	"concrete": Color(0.33, 0.32, 0.295),
	"brick": Color(0.245, 0.145, 0.115),
	"wood": Color(0.185, 0.125, 0.075),
	"metal": Color(0.145, 0.145, 0.155)
}

static var _hole_textures: Dictionary = {}

static func _color_for(surface: String) -> Color:
	return SURFACE_COLORS.get(surface, SURFACE_COLORS["dirt"])

static func _hole_texture(surface: String) -> ImageTexture:
	var cached := _hole_textures.get(surface) as ImageTexture
	if cached != null:
		return cached
	var base: Color = HOLE_COLORS.get(surface, HOLE_COLORS["dirt"])
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(surface)
	var centre := Vector2(size, size) * 0.5
	var cracks: Array[Vector2] = []
	for _i in range(7):
		var angle := rng.randf() * TAU
		cracks.append(Vector2(cos(angle), sin(angle)) * rng.randf_range(0.22, 0.42))
	for y in range(size):
		for x in range(size):
			var p := Vector2(x + 0.5, y + 0.5) - centre
			var d := p.length() / (float(size) * 0.5)
			var a := 0.0
			var shade := 0.0
			# Solid hole in the middle.
			if d < 0.20:
				a = 0.95
				shade = 0.35
			# Chipped rim.
			elif d < 0.34:
				var rim := (d - 0.20) / 0.14
				a = (1.0 - rim) * 0.75
				shade = rim * 0.85
			# Radial cracks out to the edge.
			for crack in cracks:
				var dir := p.normalized()
				var along := p.dot(crack.normalized())
				if along > 0.0 and along < crack.length() * float(size) * 0.5:
					var across := absf(p.cross(crack.normalized()))
					if across < 1.15 and d < 0.95:
						a = maxf(a, 0.42 * (1.0 - d))
			var color: Color
			if shade > 0.4:
				color = Color(0.80, 0.76, 0.70, a * 0.55)
			else:
				color = Color(base.r * (0.7 + shade * 0.6), base.g * (0.7 + shade * 0.6), base.b * (0.7 + shade * 0.6), a)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_hole_textures[surface] = texture
	return texture

static func _trim_holes(scene: Node) -> void:
	var holes := scene.get_tree().get_nodes_in_group(HOLE_GROUP)
	if holes.size() < MAX_HOLES:
		return
	var excess := holes.size() - MAX_HOLES + 1
	for i in range(mini(excess, holes.size())):
		var node := holes[i]
		if is_instance_valid(node):
			node.queue_free()

static func _spawn_hole(parent: Node, position: Vector3, normal: Vector3, surface: String, power: float) -> void:
	if surface == "flesh" or surface == "metal":
		return
	_trim_holes(parent)
	var hole := MeshInstance3D.new()
	hole.name = "BulletHole"
	hole.add_to_group(HOLE_GROUP)
	var quad := QuadMesh.new()
	var size := (0.075 + 0.055 * power) * randf_range(0.85, 1.2)
	quad.size = Vector2(size, size)
	hole.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _hole_texture(surface)
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.96)
	# Polygon offset keeps the decal from z-fighting with the wall it sits on.
	material.no_depth_test = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	hole.material_override = material
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(hole)

	var n := normal.normalized()
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(-n, up)
	basis = basis.rotated(n, randf() * TAU)
	hole.global_transform = Transform3D(basis, position + n * 0.012)

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

static func _finish(particles: CPUParticles3D, position: Vector3, normal: Vector3, vmin: float, vmax: float, spread: float, gravity := -9.8) -> void:
	particles.global_position = position + normal.normalized() * 0.05
	particles.direction = normal.normalized()
	particles.spread = spread
	particles.gravity = Vector3(0.0, gravity, 0.0)
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

# A very short light bloom at the strike point sells the energy of the hit
# without the cost of keeping a light alive.
static func _impact_flash(parent: Node, position: Vector3, surface: String, power: float) -> void:
	var light := OmniLight3D.new()
	light.name = "ImpactFlash"
	light.light_color = Color(1.0, 0.72, 0.40) if surface != "stone" and surface != "concrete" else Color(1.0, 0.85, 0.62)
	light.light_energy = clampf(1.1 + power * 1.6, 1.0, 4.0)
	light.omni_range = 1.6 + power * 1.8
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = position
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.075)
	tween.tween_callback(light.queue_free)

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
	# Distant impacts only need the dust plume; the hole, debris, sparks and
	# the positional report are skipped to keep long-range fire cheap.
	var dust_amount := int(10.0 + 16.0 * power) if detail else int(5.0 + 7.0 * power)
	var plume := _particles(parent, "BallisticImpactDust", dust_amount, 0.55 + 0.28 * power, dust, color, false)
	_finish(plume, position, normal, 1.6 + power, 5.5 + power * 3.2, 62.0)

	if surface == "flesh":
		var mist := SphereMesh.new()
		mist.radius = 0.075
		mist.height = 0.15
		mist.radial_segments = 6
		mist.rings = 3
		var spray := _particles(parent, "BallisticImpactMist", int(7 + 5 * power), 0.5, mist, color, false)
		_finish(spray, position, normal, 1.2, 3.6, 34.0)
		if detail:
			IMPACT_AUDIO.play_impact(parent, position, surface, energy_j, caliber)
		return

	if not detail:
		return

	# A permanent hole, tinted to the material that was struck.
	_spawn_hole(parent, position, normal, surface, power)

	if surface == "wood":
		var splinter_mesh := BoxMesh.new()
		splinter_mesh.size = Vector3(0.035, 0.035, 0.16)
		var splinters := _particles(parent, "BallisticImpactDebris", int(5 + 5 * power), 0.9, splinter_mesh, Color(0.42, 0.29, 0.16, 0.95), false)
		_finish(splinters, position, normal, 2.6, 7.0, 42.0)
		# Pale splintered core, visible against dark timber.
		var pale := _particles(parent, "BallisticImpactDebris", int(3 + 2 * power), 0.5, splinter_mesh, Color(0.72, 0.62, 0.45, 0.85), false)
		_finish(pale, position, normal, 1.6, 4.0, 30.0)
	elif surface == "stone" or surface == "concrete" or surface == "metal" or surface == "brick" or surface == "gravel":
		var chip_mesh := BoxMesh.new()
		chip_mesh.size = Vector3(0.028, 0.028, 0.028) * (0.8 + power * 0.5)
		var chip_color: Color = color.darkened(0.25)
		var chips := _particles(parent, "BallisticImpactDebris", int(5 + 6 * power), 1.05, chip_mesh, chip_color, false)
		_finish(chips, position, normal, 3.0, 9.0 + power * 2.0, 46.0)
		# Chipped paint / plaster dust blooming off the wall.
		var bloom_mesh := SphereMesh.new()
		bloom_mesh.radius = 0.055
		bloom_mesh.height = 0.11
		bloom_mesh.radial_segments = 5
		bloom_mesh.rings = 2
		var bloom := _particles(parent, "BallisticImpactDust", int(8 + 10 * power), 0.95, bloom_mesh, color.lerp(Color(0.82, 0.80, 0.76), 0.5), false)
		_finish(bloom, position, normal, 0.9, 3.2, 78.0, -1.2)
	else:
		# Dirt geyser: a fast vertical column with heavy clods falling back.
		var geyser_mesh := SphereMesh.new()
		geyser_mesh.radius = 0.05 + power * 0.02
		geyser_mesh.height = geyser_mesh.radius * 2.4
		geyser_mesh.radial_segments = 5
		geyser_mesh.rings = 2
		var geyser := _particles(parent, "BallisticImpactDust", int(9 + 13 * power), 0.75 + 0.25 * power, geyser_mesh, color.lerp(Color(0.36, 0.30, 0.22), 0.3), false)
		_finish(geyser, position, normal, 3.2 + power, 8.5 + power * 2.0, 24.0)
		var clod_mesh := SphereMesh.new()
		clod_mesh.radius = 0.032
		clod_mesh.height = 0.064
		clod_mesh.radial_segments = 4
		clod_mesh.rings = 2
		var clods := _particles(parent, "BallisticImpactDebris", int(4 + 4 * power), 0.7, clod_mesh, Color(0.29, 0.22, 0.15, 0.95), false)
		_finish(clods, position, normal, 2.4, 7.0, 40.0)

	if surface == "stone" or surface == "concrete" or surface == "metal" or surface == "brick":
		var spark_mesh := SphereMesh.new()
		spark_mesh.radius = 0.012
		spark_mesh.height = 0.052
		spark_mesh.radial_segments = 4
		spark_mesh.rings = 2
		var spark_scale := 1.0 if surface != "metal" else 1.8
		var sparks := _particles(parent, "BallisticImpactSparks", int((6 + 9 * power) * spark_scale), 0.30, spark_mesh, Color(1.0, 0.66, 0.24, 1.0), true)
		_finish(sparks, position, normal, 5.0, 14.0 + power * 3.0, 38.0)
		# A real light is only worth its cost on nearby strikes; distant hits get
		# the additive sparks and dust alone.
		var viewport := parent.get_viewport()
		var view_camera := viewport.get_camera_3d() if viewport != null else null
		if view_camera != null and view_camera.global_position.distance_to(position) < 30.0:
			_impact_flash(parent, position, surface, power)

	if power > 0.35:
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
