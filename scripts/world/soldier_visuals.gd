extends RefCounted

# Procedural soldier rigs for the two sides of the fight.
#
# The project ships without imported character art, so every soldier is
# assembled from primitives at runtime. Instead of stacking exposed boxes, the
# rig now uses:
#   - a generated triplanar camouflage texture on every cloth part,
#   - rounded limbs (cylinders capped with spheres) instead of cuboids,
#   - a shouldered rifle with both arms actually holding it,
#   - layered gear: plate carrier with MOLLE rows, pouches, belt, backpack,
#     helmet cover with scrim and a night-vision mount, or a wrapped shemagh,
#     chest rig and loose tracksuit for the militia.
#
# The return value is the rig the AI animates: leg pivots for the walk cycle,
# a torso pivot for aiming and a muzzle marker to spawn rounds from.

const MILITARY := "military"
const MILITIA := "militia"

const SKIN := Color(0.55, 0.41, 0.31)
const SKIN_DARK := Color(0.42, 0.30, 0.22)
const GLOVE := Color(0.115, 0.11, 0.10)
const BOOT := Color(0.085, 0.078, 0.070)
const STEEL := Color(0.105, 0.108, 0.115)
const STEEL_LIGHT := Color(0.19, 0.195, 0.20)
const WOOD := Color(0.315, 0.185, 0.098)

static var _camo_cache: Dictionary = {}

# --- Materials -------------------------------------------------------------

static func _material(color: Color, roughness := 0.92, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

# Generates a cloth camouflage texture (base + two blotch tones) once per key
# and maps it triplanar so every primitive gets continuous cloth, not stripes.
static func _camo_texture(key: String, base: Color, tone_a: Color, tone_b: Color, blobs: int) -> ImageTexture:
	var cached := _camo_cache.get(key) as ImageTexture
	if cached != null:
		return cached
	var size := 96
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	image.fill(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for i in range(blobs):
		var centre := Vector2(rng.randf() * size, rng.randf() * size)
		var radius := rng.randf_range(size * 0.06, size * 0.20)
		var color := tone_a if i % 2 == 0 else tone_b
		for y in range(size):
			for x in range(size):
				# Toroidal distance keeps the texture tileable.
				var dx := absf(float(x) - centre.x)
				var dy := absf(float(y) - centre.y)
				dx = minf(dx, size - dx)
				dy = minf(dy, size - dy)
				var d := sqrt(dx * dx + dy * dy)
				if d < radius:
					var edge := 1.0 - smoothstep(radius * 0.72, radius, d)
					image.set_pixel(x, y, image.get_pixel(x, y).lerp(color, edge * 0.92))
	var texture := ImageTexture.create_from_image(image)
	_camo_cache[key] = texture
	return texture

static func _cloth_material(key: String, base: Color, tone_a: Color, tone_b: Color, blobs: int, scale := 1.6, roughness := 0.95) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _camo_texture(key, base, tone_a, tone_b, blobs)
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(scale, scale, scale)
	material.albedo_color = Color(1.0, 1.0, 1.0)
	material.roughness = roughness
	material.metallic = 0.0
	return material

# --- Primitives ------------------------------------------------------------

static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.rotation_degrees = rot
	instance.material_override = material
	parent.add_child(instance)
	return instance

static func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, material: Material, rot := Vector3.ZERO, top_radius := -1.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	instance.mesh = mesh
	instance.position = at
	instance.rotation_degrees = rot
	instance.material_override = material
	parent.add_child(instance)
	return instance

static func _sphere(parent: Node3D, radius: float, at: Vector3, material: Material, squash := 1.0, scale_xyz := Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash
	mesh.radial_segments = 12
	mesh.rings = 7
	instance.mesh = mesh
	instance.position = at
	instance.scale = scale_xyz
	instance.material_override = material
	parent.add_child(instance)
	return instance

# A limb is a cylinder stretched between two points plus a joint sphere, which
# reads as an arm or a leg instead of a floating box.
static func _limb(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		return
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.92
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 9
	mesh.rings = 1
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	instance.global_transform = Transform3D(Basis.looking_at(delta.normalized(), Vector3.UP), (from + to) * 0.5)
	# Cylinders are Y-up; rotate so the local axis follows the limb.
	instance.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_sphere(parent, radius * 0.98, from, material)
	_sphere(parent, radius * 0.88, to, material)

# --- Rifle -----------------------------------------------------------------

static func _build_rifle(parent: Node3D, military: bool, rng: RandomNumberGenerator) -> Dictionary:
	var rifle := Node3D.new()
	rifle.name = "Rifle"
	parent.add_child(rifle)
	var steel := _material(STEEL, 0.42, 0.55)
	var steel_light := _material(STEEL_LIGHT, 0.35, 0.65)
	var furniture := _material(WOOD, 0.72) if not military else _material(Color(0.135, 0.13, 0.125), 0.85)
	var accent := _material(Color(0.30, 0.29, 0.26), 0.65, 0.2)

	# Receiver, with a dust cover and a charging handle.
	_box(rifle, Vector3(0.058, 0.095, 0.30), Vector3(0.0, 0.0, 0.0), steel)
	_box(rifle, Vector3(0.062, 0.024, 0.17), Vector3(0.0, 0.052, 0.01), steel_light)
	_box(rifle, Vector3(0.022, 0.020, 0.075), Vector3(0.038, 0.030, 0.045), steel_light)
	# Handguard / wooden fore-end.
	_box(rifle, Vector3(0.052, 0.072, 0.28), Vector3(0.0, 0.004, -0.29), furniture)
	if not military:
		# AK gas tube above the barrel and the slanted muzzle brake.
		_cylinder(rifle, 0.011, 0.26, Vector3(0.0, 0.050, -0.30), steel_light, Vector3(90.0, 0.0, 0.0))
		_box(rifle, Vector3(0.030, 0.026, 0.045), Vector3(0.0, 0.004, -0.665), accent)
	else:
		# M4 quad rail and a collapsing stock.
		_box(rifle, Vector3(0.060, 0.020, 0.24), Vector3(0.0, 0.045, -0.29), accent)
		_box(rifle, Vector3(0.020, 0.055, 0.24), Vector3(-0.032, 0.010, -0.29), accent)
		_box(rifle, Vector3(0.020, 0.055, 0.24), Vector3(0.032, 0.010, -0.29), accent)
	# Barrel + muzzle device.
	_cylinder(rifle, 0.0085, 0.30, Vector3(0.0, 0.004, -0.52), steel_light, Vector3(90.0, 0.0, 0.0))
	_cylinder(rifle, 0.0145, 0.070, Vector3(0.0, 0.004, -0.685), steel, Vector3(90.0, 0.0, 0.0))
	# Curved magazine: two angled blocks read as the banana curve.
	_box(rifle, Vector3(0.048, 0.15, 0.075), Vector3(0.0, -0.115, -0.025), accent, Vector3(-16.0, 0.0, 0.0))
	_box(rifle, Vector3(0.044, 0.11, 0.068), Vector3(0.0, -0.215, -0.075), accent, Vector3(-28.0, 0.0, 0.0))
	# Pistol grip and trigger guard.
	_box(rifle, Vector3(0.036, 0.115, 0.052), Vector3(0.0, -0.095, 0.115), furniture, Vector3(14.0, 0.0, 0.0))
	_box(rifle, Vector3(0.030, 0.012, 0.070), Vector3(0.0, -0.062, 0.030), steel)
	# Stock.
	_box(rifle, Vector3(0.042, 0.090, 0.20), Vector3(0.0, -0.005, 0.255), furniture)
	_box(rifle, Vector3(0.048, 0.115, 0.028), Vector3(0.0, -0.008, 0.360), furniture)
	# Sights: optic for the military, notch-and-post for the militia.
	if military:
		_box(rifle, Vector3(0.034, 0.030, 0.10), Vector3(0.0, 0.070, -0.045), accent)
		_cylinder(rifle, 0.026, 0.16, Vector3(0.0, 0.098, -0.055), steel, Vector3(90.0, 0.0, 0.0))
		_cylinder(rifle, 0.030, 0.012, Vector3(0.0, 0.098, -0.135), steel_light, Vector3(90.0, 0.0, 0.0))
		# Laser / illuminator box on the rail.
		_box(rifle, Vector3(0.032, 0.030, 0.055), Vector3(0.030, 0.062, -0.24), accent)
	else:
		_box(rifle, Vector3(0.012, 0.032, 0.020), Vector3(0.0, 0.082, -0.10), steel)
		_box(rifle, Vector3(0.010, 0.038, 0.014), Vector3(0.0, 0.085, -0.60), steel)
	# Sling, so the rifle is carried rather than floating.
	_box(rifle, Vector3(0.014, 0.024, 0.42), Vector3(-0.030, -0.040, 0.06), _material(Color(0.21, 0.20, 0.17), 0.95), Vector3(6.0, 0.0, 0.0))
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.004, -0.735)
	rifle.add_child(muzzle)

	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.075
	flash_mesh.height = 0.20
	flash_mesh.radial_segments = 6
	flash_mesh.rings = 3
	flash.mesh = flash_mesh
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.80, 0.42, 0.95)
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.62, 0.22)
	flash_material.emission_energy_multiplier = 5.0
	flash.material_override = flash_material
	flash.visible = false
	muzzle.add_child(flash)

	return {"rifle": rifle, "muzzle": muzzle, "muzzle_flash": flash, "steel": steel}

# --- Build -----------------------------------------------------------------

static func build(parent: Node3D, faction: String, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var military := faction == MILITARY

	# Military: drab green MultiCam-alike. Militia: dark tracksuit with a faded
	# olive tint, the way the irregular factions read in Squad.
	var uniform: StandardMaterial3D
	var pants: StandardMaterial3D
	if military:
		var tint := rng.randf_range(-0.03, 0.03)
		uniform = _cloth_material("mil_uniform",
			Color(0.365 + tint, 0.385 + tint, 0.295 + tint),
			Color(0.245, 0.265, 0.195), Color(0.505, 0.470, 0.360), 46, 1.7)
		pants = _cloth_material("mil_pants",
			Color(0.325 + tint, 0.345 + tint, 0.265 + tint),
			Color(0.230, 0.250, 0.190), Color(0.455, 0.425, 0.330), 40, 1.9)
	else:
		var tint := rng.randf_range(-0.025, 0.025)
		uniform = _cloth_material("mil_jacket",
			Color(0.205 + tint, 0.192 + tint, 0.170 + tint),
			Color(0.145, 0.138, 0.125), Color(0.280, 0.262, 0.225), 34, 2.1)
		pants = _cloth_material("mil_tracks",
			Color(0.165 + tint, 0.158 + tint, 0.148 + tint),
			Color(0.115, 0.112, 0.108), Color(0.235, 0.225, 0.205), 28, 2.3)

	var gear := _material(Color(0.205, 0.225, 0.185) if military else Color(0.235, 0.215, 0.175), 0.9)
	var gear_dark := _material(Color(0.145, 0.155, 0.130) if military else Color(0.165, 0.150, 0.125), 0.92)
	var skin := _material(SKIN if rng.randf() > 0.35 else SKIN_DARK, 0.75)
	var boots := _material(BOOT, 0.72)
	var gloves := _material(GLOVE, 0.85)

	var root := Node3D.new()
	root.name = "SoldierRig"
	parent.add_child(root)

	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position.y = 0.92
	root.add_child(hips)

	# ---- Legs (pivots at the hip so the walk cycle can swing them) ----------
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegLeft" if side > 0.0 else "LegRight"
		leg.position.x = 0.105 * side
		hips.add_child(leg)
		# Thigh, tapered shin, boot with a raised toe.
		_cylinder(leg, 0.082, 0.44, Vector3(0.0, -0.22, 0.0), pants, Vector3.ZERO, 0.076)
		_cylinder(leg, 0.068, 0.40, Vector3(0.0, -0.63, 0.005), pants, Vector3.ZERO, 0.058)
		_box(leg, Vector3(0.115, 0.10, 0.26), Vector3(0.0, -0.855, -0.035), boots)
		_box(leg, Vector3(0.105, 0.055, 0.09), Vector3(0.0, -0.885, -0.165), boots)
		if military:
			# Knee pad strapped over the shin.
			_box(leg, Vector3(0.115, 0.13, 0.075), Vector3(0.0, -0.44, -0.062), gear_dark)
			_box(leg, Vector3(0.06, 0.055, 0.02), Vector3(0.0, -0.44, -0.10), gear)
		else:
			# Baggy trouser cuff bunched over the boot.
			_cylinder(leg, 0.080, 0.09, Vector3(0.0, -0.80, 0.0), pants, Vector3.ZERO, 0.070)

	# ---- Torso -------------------------------------------------------------
	var torso := Node3D.new()
	torso.name = "Torso"
	hips.add_child(torso)
	# Chest / abdomen volume rather than one slab.
	_box(torso, Vector3(0.345, 0.26, 0.215), Vector3(0.0, 0.13, 0.0), uniform)
	_box(torso, Vector3(0.385, 0.24, 0.235), Vector3(0.0, 0.34, 0.0), uniform)
	_sphere(torso, 0.105, Vector3(0.0, 0.455, 0.0), uniform, 0.8)
	# Shoulders.
	_sphere(torso, 0.088, Vector3(-0.215, 0.415, 0.0), uniform, 0.95)
	_sphere(torso, 0.088, Vector3(0.215, 0.415, 0.0), uniform, 0.95)

	if military:
		# Plate carrier: front and back plates joined by a cummerbund.
		_box(torso, Vector3(0.385, 0.335, 0.265), Vector3(0.0, 0.315, 0.0), gear)
		_box(torso, Vector3(0.330, 0.090, 0.275), Vector3(0.0, 0.170, 0.0), gear_dark)
		for row in range(2):
			for col in range(3):
				_box(torso, Vector3(0.090, 0.020, 0.020), Vector3(-0.105 + float(col) * 0.105, 0.20 + float(row) * 0.055, -0.135), gear_dark)
		# Magazine pouches.
		for i in range(3):
			_box(torso, Vector3(0.096, 0.125, 0.080), Vector3(-0.115 + float(i) * 0.115, 0.255, -0.165), gear_dark)
			_box(torso, Vector3(0.092, 0.018, 0.086), Vector3(-0.115 + float(i) * 0.115, 0.196, -0.166), gear)
		# Shoulder straps and a side pouch.
		_box(torso, Vector3(0.070, 0.200, 0.030), Vector3(-0.130, 0.455, -0.120), gear_dark, Vector3(12.0, 0.0, 0.0))
		_box(torso, Vector3(0.070, 0.200, 0.030), Vector3(0.130, 0.455, -0.120), gear_dark, Vector3(12.0, 0.0, 0.0))
		_box(torso, Vector3(0.100, 0.130, 0.110), Vector3(0.215, 0.250, -0.020), gear_dark)
		# Backpack with a radio whip antenna.
		_box(torso, Vector3(0.300, 0.300, 0.155), Vector3(0.0, 0.320, 0.185), gear)
		_box(torso, Vector3(0.260, 0.070, 0.040), Vector3(0.0, 0.435, 0.265), gear_dark)
		_cylinder(torso, 0.006, 0.42, Vector3(-0.115, 0.560, 0.230), _material(Color(0.08, 0.08, 0.08), 0.6))
		# Helmet band / goggles on the helmet are added with the head.
		_box(torso, Vector3(0.330, 0.050, 0.240), Vector3(0.0, 0.055, 0.0), gear_dark)
	else:
		# Loose jacket plus a simple three-cell chest rig and a waist belt.
		_box(torso, Vector3(0.390, 0.300, 0.235), Vector3(0.0, 0.320, 0.0), uniform)
		_box(torso, Vector3(0.300, 0.115, 0.255), Vector3(0.0, 0.330, 0.0), gear_dark)
		for i in range(3):
			_box(torso, Vector3(0.086, 0.130, 0.070), Vector3(-0.098 + float(i) * 0.098, 0.290, -0.145), gear)
		_box(torso, Vector3(0.340, 0.045, 0.245), Vector3(0.0, 0.085, 0.0), gear_dark)
		_box(torso, Vector3(0.075, 0.090, 0.070), Vector3(0.185, 0.090, -0.075), gear)
		# Rolled blanket across the lower back, a militia signature.
		_cylinder(torso, 0.062, 0.330, Vector3(0.0, 0.195, 0.150), _material(Color(0.36, 0.32, 0.24), 0.95), Vector3(0.0, 0.0, 90.0))

	# ---- Head --------------------------------------------------------------
	var head_pivot := Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0.0, 0.505, 0.0)
	torso.add_child(head_pivot)
	_cylinder(head_pivot, 0.055, 0.09, Vector3(0.0, 0.045, 0.0), skin)
	_sphere(head_pivot, 0.108, Vector3(0.0, 0.155, 0.0), skin, 1.18, Vector3(0.92, 1.0, 0.98))
	_box(head_pivot, Vector3(0.055, 0.045, 0.035), Vector3(0.0, 0.135, -0.098), skin, Vector3(-8.0, 0.0, 0.0))
	# Eyes / goggles band.
	_box(head_pivot, Vector3(0.150, 0.030, 0.020), Vector3(0.0, 0.175, -0.098), _material(Color(0.10, 0.10, 0.10), 0.4))

	if military:
		# Helmet shell with a cover, a scrim band and a night-vision shroud.
		var helmet_mat := _cloth_material("mil_helmet", Color(0.335, 0.350, 0.275), Color(0.245, 0.265, 0.200), Color(0.430, 0.400, 0.320), 18, 3.0, 0.9)
		_sphere(head_pivot, 0.135, Vector3(0.0, 0.185, 0.008), helmet_mat, 0.82)
		_box(head_pivot, Vector3(0.270, 0.028, 0.270), Vector3(0.0, 0.128, 0.005), gear_dark)
		_box(head_pivot, Vector3(0.060, 0.045, 0.055), Vector3(0.0, 0.250, -0.105), gear_dark)
		_box(head_pivot, Vector3(0.038, 0.028, 0.030), Vector3(0.0, 0.268, -0.130), _material(Color(0.09, 0.10, 0.09), 0.5, 0.4))
		# Chin strap.
		_box(head_pivot, Vector3(0.020, 0.120, 0.016), Vector3(-0.085, 0.115, -0.045), gear_dark, Vector3(0.0, 0.0, 6.0))
		_box(head_pivot, Vector3(0.020, 0.120, 0.016), Vector3(0.085, 0.115, -0.045), gear_dark, Vector3(0.0, 0.0, -6.0))
	else:
		# Shemagh: a wrapped head cloth with a tail over the shoulder.
		var cloth_color := Color(0.60, 0.55, 0.44) if rng.randf() > 0.5 else Color(0.29, 0.26, 0.21)
		var cloth := _cloth_material("mil_shemagh_%s" % str(cloth_color), cloth_color,
			Color(0.44, 0.39, 0.30), Color(0.20, 0.18, 0.15), 22, 3.4)
		_sphere(head_pivot, 0.135, Vector3(0.0, 0.175, 0.005), cloth, 0.94)
		_box(head_pivot, Vector3(0.250, 0.150, 0.220), Vector3(0.0, 0.070, 0.040), cloth)
		_box(head_pivot, Vector3(0.115, 0.280, 0.170), Vector3(0.100, -0.070, 0.055), cloth, Vector3(4.0, 0.0, 3.0))
		_box(head_pivot, Vector3(0.105, 0.055, 0.230), Vector3(0.0, 0.010, 0.010), cloth)
		# Short beard shadow.
		_box(head_pivot, Vector3(0.115, 0.060, 0.045), Vector3(0.0, 0.075, -0.085), _material(Color(0.16, 0.13, 0.10), 0.95))

	# ---- Arms and rifle ----------------------------------------------------
	# The rifle is shouldered: butt in the right pocket, muzzle downrange.
	var arms := Node3D.new()
	arms.name = "Arms"
	torso.add_child(arms)
	var rifle_parts := _build_rifle(arms, military, rng)
	var rifle := rifle_parts["rifle"] as Node3D
	rifle.position = Vector3(0.115, 0.330, -0.140)
	rifle.rotation_degrees = Vector3(0.0, -6.0, 0.0)

	# Grip and handguard positions expressed in torso space so the hands land
	# on the rifle instead of floating next to it.
	var grip := rifle.position + Vector3(0.0, -0.115, 0.115)
	var handguard := rifle.position + Vector3(-0.015, 0.010, -0.310)
	var right_shoulder := Vector3(0.215, 0.415, -0.010)
	var left_shoulder := Vector3(-0.215, 0.415, -0.010)
	var right_elbow := Vector3(0.245, 0.245, -0.070)
	var left_elbow := Vector3(-0.135, 0.215, -0.230)
	_limb(arms, right_shoulder, right_elbow, 0.055, uniform)
	_limb(arms, right_elbow, grip + Vector3(0.0, 0.020, 0.020), 0.048, uniform)
	_limb(arms, left_shoulder, left_elbow, 0.055, uniform)
	_limb(arms, left_elbow, handguard + Vector3(0.0, 0.035, 0.010), 0.048, uniform)
	# Hands and gloves.
	_sphere(arms, 0.052, grip + Vector3(0.0, 0.020, 0.020), gloves, 0.85)
	_sphere(arms, 0.052, handguard + Vector3(0.0, 0.035, 0.010), gloves, 0.85)
	if military:
		# Wrist cuffs read as gloves rather than bare skin.
		_cylinder(arms, 0.046, 0.070, grip + Vector3(0.0, 0.075, 0.045), gear_dark, Vector3(32.0, 0.0, 0.0))
		_cylinder(arms, 0.046, 0.070, handguard + Vector3(0.0, 0.080, 0.045), gear_dark, Vector3(30.0, 0.0, 0.0))

	var muzzle := rifle_parts["muzzle"] as Node3D
	var flash := rifle_parts["muzzle_flash"] as MeshInstance3D

	var emitters: Array[StandardMaterial3D] = []
	for material in [uniform, pants]:
		emitters.append(material as StandardMaterial3D)

	return {
		"root": root,
		"hips": hips,
		"torso": torso,
		"head": head_pivot,
		"leg_left": hips.get_node("LegLeft") as Node3D,
		"leg_right": hips.get_node("LegRight") as Node3D,
		"arms": arms,
		"rifle": rifle,
		"muzzle": muzzle,
		"muzzle_flash": flash,
		"materials": emitters,
	}
