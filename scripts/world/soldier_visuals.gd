extends RefCounted

# Procedural soldier rigs for the two sides of the fight.
#
# The project ships without imported character art, so every soldier is
# assembled from primitives at runtime. The two factions read differently at
# the distances this map fights at (40-320 m):
#
#   military - helmet with a brim, plate carrier with magazine pouches,
#              knee pads, uniform in drab green, rifle with an optic.
#   militia  - bare head wrapped in a shemagh, loose tracksuit jacket and
#              trousers, webbing with three rifle-magazine pouches, wooden AK.
#
# The return value is the rig the AI animates: leg pivots for the walk cycle,
# a torso pivot for aiming and a muzzle marker to spawn rounds from.

const MILITARY := "military"
const MILITIA := "militia"

const SKIN := Color(0.56, 0.42, 0.32)
const MILITARY_UNIFORM := Color(0.38, 0.41, 0.32)
const MILITARY_GEAR := Color(0.205, 0.225, 0.185)
const MILITIA_JACKET := Color(0.215, 0.20, 0.175)
const MILITIA_PANTS := Color(0.16, 0.155, 0.145)
const WEAPON_STEEL := Color(0.115, 0.115, 0.115)
const WEAPON_WOOD := Color(0.34, 0.20, 0.11)

static func _material(color: Color, roughness := 0.92) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material

static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance

static func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	instance.mesh = mesh
	instance.position = at
	instance.rotation_degrees = rot
	instance.material_override = material
	parent.add_child(instance)
	return instance

static func _sphere(parent: Node3D, radius: float, at: Vector3, material: Material, squash := 1.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash
	mesh.radial_segments = 10
	mesh.rings = 6
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance

static func build(parent: Node3D, faction: String, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var military := faction == MILITARY

	var uniform_color := MILITARY_UNIFORM if military else MILITIA_JACKET
	var uniform_variation := rng.randf_range(-0.028, 0.028)
	uniform_color = Color(
		clampf(uniform_color.r + uniform_variation, 0.0, 1.0),
		clampf(uniform_color.g + uniform_variation, 0.0, 1.0),
		clampf(uniform_color.b + uniform_variation, 0.0, 1.0)
	)
	var uniform := _material(uniform_color)
	var pants := _material(Color(0.24, 0.26, 0.21) if military else MILITIA_PANTS)
	var gear := _material(MILITARY_GEAR if military else Color(0.26, 0.24, 0.20))
	var skin := _material(SKIN)
	var boots := _material(Color(0.10, 0.09, 0.08))

	var root := Node3D.new()
	root.name = "SoldierRig"
	parent.add_child(root)

	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position.y = 0.92
	root.add_child(hips)

	# ---- Legs (pivots at the hip so the walk cycle can swing them) ----------
	var leg_left := Node3D.new()
	leg_left.name = "LegLeft"
	leg_left.position.x = 0.11
	hips.add_child(leg_left)
	_box(leg_left, Vector3(0.17, 0.88, 0.20), Vector3(0.0, -0.44, 0.0), pants)
	_box(leg_left, Vector3(0.18, 0.12, 0.30), Vector3(0.0, -0.85, -0.04), boots)
	if military:
		_box(leg_left, Vector3(0.19, 0.16, 0.20), Vector3(0.0, -0.30, -0.02), gear)

	var leg_right := Node3D.new()
	leg_right.name = "LegRight"
	leg_right.position.x = -0.11
	hips.add_child(leg_right)
	_box(leg_right, Vector3(0.17, 0.88, 0.20), Vector3(0.0, -0.44, 0.0), pants)
	_box(leg_right, Vector3(0.18, 0.12, 0.30), Vector3(0.0, -0.85, -0.04), boots)
	if military:
		_box(leg_right, Vector3(0.19, 0.16, 0.20), Vector3(0.0, -0.30, -0.02), gear)

	# ---- Torso -------------------------------------------------------------
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position.y = 0.92
	hips.add_child(torso)
	_box(torso, Vector3(0.40, 0.60, 0.25), Vector3(0.0, 0.30, 0.0), uniform)

	if military:
		# Plate carrier with a cummerbund and three magazine pouches.
		_box(torso, Vector3(0.45, 0.38, 0.29), Vector3(0.0, 0.36, -0.01), gear)
		for i in range(3):
			_box(torso, Vector3(0.10, 0.13, 0.07), Vector3(-0.12 + float(i) * 0.12, 0.28, -0.18), gear)
		_box(torso, Vector3(0.13, 0.13, 0.10), Vector3(0.20, 0.30, -0.13), gear)
	else:
		# Loose jacket over a simple three-pouch chest rig.
		_box(torso, Vector3(0.44, 0.34, 0.24), Vector3(0.0, 0.30, 0.0), uniform)
		_box(torso, Vector3(0.34, 0.10, 0.26), Vector3(0.0, 0.34, 0.0), gear)
		for i in range(3):
			_box(torso, Vector3(0.09, 0.14, 0.08), Vector3(-0.10 + float(i) * 0.10, 0.26, -0.16), gear)

	# ---- Head --------------------------------------------------------------
	var head_pivot := Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0.0, 0.60, 0.0)
	torso.add_child(head_pivot)
	_box(head_pivot, Vector3(0.13, 0.10, 0.13), Vector3(0.0, 0.02, 0.0), skin)
	_sphere(head_pivot, 0.125, Vector3(0.0, 0.15, 0.0), skin)

	var emitters: Array[StandardMaterial3D] = []
	if military:
		# Combat helmet with a slight brim and a night-vision shroud.
		var helmet := _material(Color(0.30, 0.32, 0.26))
		_sphere(head_pivot, 0.158, Vector3(0.0, 0.185, 0.012), helmet, 0.78)
		_box(head_pivot, Vector3(0.30, 0.035, 0.30), Vector3(0.0, 0.135, 0.0), helmet)
		_box(head_pivot, Vector3(0.07, 0.05, 0.08), Vector3(0.0, 0.225, -0.13), gear)
	else:
		# Shemagh: wrapped head cloth plus a hanging tail on the shoulder.
		var cloth_color := Color(0.66, 0.60, 0.48) if rng.randf() > 0.45 else Color(0.30, 0.26, 0.22)
		var cloth := _material(cloth_color)
		_sphere(head_pivot, 0.152, Vector3(0.0, 0.155, 0.0), cloth, 0.92)
		_box(head_pivot, Vector3(0.26, 0.16, 0.24), Vector3(0.0, 0.055, 0.03), cloth)
		_box(head_pivot, Vector3(0.10, 0.30, 0.20), Vector3(0.10, -0.10, 0.02), cloth)
		_box(head_pivot, Vector3(0.24, 0.06, 0.10), Vector3(0.0, 0.11, -0.10), gear)

	# ---- Arms and rifle ----------------------------------------------------
	var arms := Node3D.new()
	arms.name = "Arms"
	arms.position = Vector3(0.0, 0.44, -0.02)
	torso.add_child(arms)
	# Right hand on the pistol grip, left hand supporting the handguard.
	_box(arms, Vector3(0.11, 0.30, 0.11), Vector3(-0.16, -0.06, -0.10), uniform)
	_box(arms, Vector3(0.11, 0.11, 0.26), Vector3(-0.16, -0.18, -0.22), uniform)
	_box(arms, Vector3(0.11, 0.30, 0.11), Vector3(0.18, -0.02, -0.22), uniform)
	_box(arms, Vector3(0.11, 0.11, 0.24), Vector3(0.12, -0.15, -0.36), uniform)
	_sphere(arms, 0.055, Vector3(-0.16, -0.22, -0.30), skin)
	_sphere(arms, 0.055, Vector3(0.05, -0.16, -0.46), skin)

	var rifle := Node3D.new()
	rifle.name = "Rifle"
	rifle.position = Vector3(-0.10, -0.08, -0.30)
	arms.add_child(rifle)
	var steel := _material(WEAPON_STEEL, 0.45)
	var wood := _material(WEAPON_WOOD, 0.8)
	var body_material := steel if military else wood
	# Receiver, handguard, barrel, magazine, stock.
	_box(rifle, Vector3(0.075, 0.11, 0.40), Vector3(0.0, 0.06, -0.06), steel)
	_box(rifle, Vector3(0.070, 0.09, 0.30), Vector3(0.0, 0.05, -0.38), body_material)
	_cylinder(rifle, 0.017, 0.52, Vector3(0.0, 0.075, -0.70), steel, Vector3(90.0, 0.0, 0.0))
	_box(rifle, Vector3(0.065, 0.16, 0.09), Vector3(0.0, -0.06, -0.10), steel)
	_box(rifle, Vector3(0.065, 0.08, 0.09), Vector3(0.0, -0.04, -0.05), steel)
	_box(rifle, Vector3(0.06, 0.10, 0.28), Vector3(0.0, 0.03, 0.26), body_material)
	_box(rifle, Vector3(0.05, 0.07, 0.16), Vector3(0.0, -0.02, 0.48), body_material)
	if military:
		# Optic on a riser, plus a laser box on the handguard.
		_box(rifle, Vector3(0.05, 0.07, 0.16), Vector3(0.0, 0.15, -0.10), steel)
		_sphere(rifle, 0.028, Vector3(0.0, 0.15, -0.20), _material(Color(0.05, 0.07, 0.09), 0.2))
		_box(rifle, Vector3(0.05, 0.05, 0.09), Vector3(-0.06, 0.06, -0.44), gear)

	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.075, -0.98)
	rifle.add_child(muzzle)

	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.09
	flash_mesh.height = 0.18
	flash_mesh.radial_segments = 6
	flash_mesh.rings = 3
	flash.mesh = flash_mesh
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.78, 0.35, 0.85)
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash.material_override = flash_material
	flash.visible = false
	muzzle.add_child(flash)

	emitters.append(uniform)
	emitters.append(pants)

	return {
		"root": root,
		"hips": hips,
		"torso": torso,
		"head": head_pivot,
		"leg_left": leg_left,
		"leg_right": leg_right,
		"rifle": rifle,
		"muzzle": muzzle,
		"muzzle_flash": flash,
		"materials": emitters,
	}
