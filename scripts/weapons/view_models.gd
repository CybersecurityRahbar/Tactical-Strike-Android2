extends RefCounted

# Detailed first-person weapon models for the weapons that have no imported
# rig. The imported AK-74M already ships with a modelled receiver, magazine,
# optic rail and gloved arms; these builders give the other six the same level
# of silhouette detail instead of a barrel and three boxes.
#
# Authoring space: +Z points down the bore, +Y is up, the origin sits at the
# rear of the receiver. The caller rotates the whole rig 180 degrees so +Z
# faces the camera's forward axis and scales it to the loadout's view_scale.

const STEEL_DARK := Color(0.082, 0.084, 0.090)
const STEEL := Color(0.135, 0.138, 0.146)
const STEEL_WORN := Color(0.235, 0.235, 0.240)
const POLYMER := Color(0.068, 0.068, 0.072)
const WOOD := Color(0.315, 0.178, 0.088)
const WOOD_DARK := Color(0.235, 0.132, 0.068)
const FDE := Color(0.400, 0.340, 0.235)
const BRASS := Color(0.520, 0.400, 0.150)
const GLASS := Color(0.035, 0.090, 0.110)
const SLEEVE := Color(0.245, 0.260, 0.200)
const GLOVE := Color(0.105, 0.100, 0.092)
const GLOVE_PAD := Color(0.150, 0.145, 0.132)
const SKIN := Color(0.505, 0.375, 0.275)

static var _materials: Dictionary = {}

static func _mat(key: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var cached := _materials.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.metallic_specular = 0.5
	_materials[key] = material
	return material

static func _materials_for(id: String) -> Dictionary:
	var worn := _mat("steel_worn", STEEL_WORN, 0.72, 0.38)
	return {
		"steel": _mat("steel", STEEL, 0.68, 0.45),
		"dark": _mat("steel_dark", STEEL_DARK, 0.75, 0.40),
		"worn": worn,
		"polymer": _mat("polymer", POLYMER, 0.10, 0.72),
		"wood": _mat("wood", WOOD, 0.05, 0.58),
		"wood_dark": _mat("wood_dark", WOOD_DARK, 0.05, 0.62),
		"fde": _mat("fde", FDE, 0.15, 0.68),
		"brass": _mat("brass", BRASS, 0.85, 0.30),
		"glass": _mat("glass", GLASS, 0.30, 0.06),
		"sleeve": _mat("sleeve", SLEEVE, 0.0, 0.95),
		"glove": _mat("glove", GLOVE, 0.0, 0.82),
		"glove_pad": _mat("glove_pad", GLOVE_PAD, 0.0, 0.85),
		"skin": _mat("skin", SKIN, 0.0, 0.78),
		"id": id,
	}

# --- primitives ------------------------------------------------------------

static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.rotation_degrees = rot
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _cyl_z(parent: Node3D, radius: float, length: float, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 1
	instance.mesh = mesh
	instance.position = at
	instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _cyl_y(parent: Node3D, radius: float, length: float, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _cone(parent: Node3D, top_radius: float, bottom_radius: float, height: float, at: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	instance.mesh = mesh
	instance.position = at
	instance.rotation_degrees = rot
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _sphere(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _rail(parent: Node3D, from_z: float, to_z: float, y: float, material: Material) -> void:
	_box(parent, Vector3(0.030, 0.010, to_z - from_z), Vector3(0.0, y, (from_z + to_z) * 0.5), material)
	var z := from_z + 0.008
	while z < to_z:
		_box(parent, Vector3(0.036, 0.008, 0.010), Vector3(0.0, y + 0.006, z), material)
		z += 0.022

# --- arms and hands --------------------------------------------------------

static func _hand(parent: Node3D, at: Vector3, material: Material, pad: Material, pointing := false) -> void:
	# Palm plus four curled fingers and a thumb, so the grip reads as a hand.
	_box(parent, Vector3(0.062, 0.085, 0.075), at, material, Vector3(10.0, 0.0, 0.0))
	for i in range(3):
		_box(parent, Vector3(0.058, 0.020, 0.070), at + Vector3(0.0, 0.035 - float(i) * 0.026, -0.052), pad, Vector3(-16.0, 0.0, 0.0))
	if pointing:
		_box(parent, Vector3(0.022, 0.022, 0.075), at + Vector3(-0.028, 0.030, -0.075), pad, Vector3(-8.0, 0.0, 0.0))
	_box(parent, Vector3(0.024, 0.055, 0.028), at + Vector3(0.038, 0.020, -0.020), material, Vector3(0.0, 0.0, -18.0))

static func _forearm(parent: Node3D, from: Vector3, to: Vector3, material: Material, cuff: Material) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		return
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.040
	mesh.bottom_radius = 0.052
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	instance.global_transform = Transform3D(Basis.looking_at(delta.normalized(), Vector3.UP), (from + to) * 0.5)
	instance.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# Cuff band at the wrist end.
	_box(parent, Vector3(0.088, 0.030, 0.088), to, cuff)

static func _fp_arms(scene: Node3D, m: Dictionary, grip: Vector3, handguard: Vector3) -> void:
	# Both arms come from below and behind the camera, as in a shouldered pose.
	_forearm(scene, grip + Vector3(0.115, -0.180, -0.075), grip + Vector3(0.020, -0.028, 0.010), m["sleeve"], m["glove_pad"])
	_forearm(scene, handguard + Vector3(-0.150, -0.215, 0.055), handguard + Vector3(-0.020, -0.020, -0.010), m["sleeve"], m["glove_pad"])
	_hand(scene, grip + Vector3(0.0, -0.020, 0.0), m["glove"], m["glove_pad"])
	_hand(scene, handguard + Vector3(0.0, -0.026, 0.0), m["glove"], m["glove_pad"], true)

# --- AK-74M (used only if the imported rig is missing) ---------------------

static func _ak74m(scene: Node3D, m: Dictionary) -> float:
	_box(scene, Vector3(0.060, 0.100, 0.330), Vector3(0.0, 0.0, 0.190), m["steel"])
	_box(scene, Vector3(0.064, 0.026, 0.190), Vector3(0.0, 0.058, 0.205), m["worn"])
	_box(scene, Vector3(0.022, 0.020, 0.080), Vector3(0.040, 0.034, 0.270), m["worn"])
	_rail(scene, 0.130, 0.220, 0.075, m["dark"])
	# Wooden handguard and gas tube.
	_box(scene, Vector3(0.056, 0.070, 0.240), Vector3(0.0, -0.004, 0.470), m["wood"])
	_cyl_z(scene, 0.011, 0.230, Vector3(0.0, 0.048, 0.480), m["worn"])
	_box(scene, Vector3(0.050, 0.030, 0.060), Vector3(0.0, 0.020, 0.615), m["dark"])
	_cyl_z(scene, 0.0115, 0.190, Vector3(0.0, 0.004, 0.680), m["dark"])
	_cyl_z(scene, 0.017, 0.070, Vector3(0.0, 0.004, 0.800), m["steel"])
	# Front sight post with its protective ears.
	_box(scene, Vector3(0.050, 0.075, 0.030), Vector3(0.0, 0.045, 0.735), m["dark"])
	_box(scene, Vector3(0.010, 0.040, 0.010), Vector3(0.0, 0.078, 0.735), m["worn"])
	# Curved magazine.
	_box(scene, Vector3(0.050, 0.150, 0.078), Vector3(0.0, -0.115, 0.235), m["polymer"], Vector3(-14.0, 0.0, 0.0))
	_box(scene, Vector3(0.046, 0.120, 0.070), Vector3(0.0, -0.225, 0.290), m["polymer"], Vector3(-30.0, 0.0, 0.0))
	_box(scene, Vector3(0.040, 0.115, 0.050), Vector3(0.0, -0.100, 0.090), m["wood_dark"], Vector3(16.0, 0.0, 0.0))
	_box(scene, Vector3(0.034, 0.014, 0.080), Vector3(0.0, -0.058, 0.135), m["worn"])
	_box(scene, Vector3(0.048, 0.100, 0.230), Vector3(0.0, -0.010, -0.090), m["wood"])
	_box(scene, Vector3(0.052, 0.122, 0.030), Vector3(0.0, -0.012, -0.215), m["wood_dark"])
	# Rear sight block and selector.
	_box(scene, Vector3(0.040, 0.030, 0.055), Vector3(0.0, 0.075, 0.330), m["dark"])
	_box(scene, Vector3(0.010, 0.045, 0.080), Vector3(0.042, 0.028, 0.175), m["worn"])
	return 0.835

# --- M4A1 ------------------------------------------------------------------

static func _m4a1(scene: Node3D, m: Dictionary) -> float:
	# Lower + upper receiver with a flat-top rail and forward assist.
	_box(scene, Vector3(0.058, 0.088, 0.245), Vector3(0.0, -0.006, 0.155), m["dark"])
	_box(scene, Vector3(0.052, 0.062, 0.300), Vector3(0.0, 0.052, 0.175), m["steel"])
	_rail(scene, 0.040, 0.310, 0.086, m["dark"])
	_box(scene, Vector3(0.026, 0.026, 0.034), Vector3(0.030, 0.052, 0.100), m["worn"])
	# Free-float handguard: octagonal tube built from four flats + top rail.
	_box(scene, Vector3(0.062, 0.026, 0.300), Vector3(0.0, 0.036, 0.480), m["dark"])
	_box(scene, Vector3(0.062, 0.026, 0.300), Vector3(0.0, -0.032, 0.480), m["dark"])
	_box(scene, Vector3(0.026, 0.062, 0.300), Vector3(0.030, 0.002, 0.480), m["dark"])
	_box(scene, Vector3(0.026, 0.062, 0.300), Vector3(-0.030, 0.002, 0.480), m["dark"])
	_rail(scene, 0.335, 0.620, 0.052, m["dark"])
	# Barrel, gas block and A2 birdcage.
	_cyl_z(scene, 0.0115, 0.150, Vector3(0.0, 0.002, 0.690), m["worn"])
	_box(scene, Vector3(0.030, 0.050, 0.040), Vector3(0.0, 0.030, 0.655), m["dark"])
	_cyl_z(scene, 0.0145, 0.075, Vector3(0.0, 0.002, 0.795), m["steel"])
	for i in range(4):
		_box(scene, Vector3(0.031, 0.006, 0.011), Vector3(0.0, 0.002, 0.770 + float(i) * 0.014), m["dark"])
	# Buffer tube and collapsible stock.
	_cyl_z(scene, 0.019, 0.190, Vector3(0.0, 0.012, -0.140), m["dark"])
	_box(scene, Vector3(0.048, 0.088, 0.150), Vector3(0.0, 0.005, -0.185), m["polymer"])
	_box(scene, Vector3(0.052, 0.115, 0.022), Vector3(0.0, 0.000, -0.268), m["polymer"])
	_box(scene, Vector3(0.040, 0.030, 0.080), Vector3(0.0, 0.060, -0.170), m["dark"])
	# Pistol grip, trigger guard, magazine.
	_box(scene, Vector3(0.040, 0.115, 0.055), Vector3(0.0, -0.100, 0.100), m["polymer"], Vector3(18.0, 0.0, 0.0))
	_box(scene, Vector3(0.034, 0.012, 0.075), Vector3(0.0, -0.066, 0.165), m["dark"])
	_box(scene, Vector3(0.050, 0.140, 0.080), Vector3(0.0, -0.110, 0.235), m["fde"], Vector3(-8.0, 0.0, 0.0))
	_box(scene, Vector3(0.046, 0.115, 0.072), Vector3(0.0, -0.215, 0.270), m["fde"], Vector3(-18.0, 0.0, 0.0))
	# Red dot on a riser, with a lens that catches the light.
	_box(scene, Vector3(0.040, 0.022, 0.080), Vector3(0.0, 0.100, 0.190), m["dark"])
	_cyl_z(scene, 0.026, 0.120, Vector3(0.0, 0.128, 0.190), m["dark"])
	_cyl_z(scene, 0.023, 0.006, Vector3(0.0, 0.128, 0.252), m["glass"])
	_cylinder_ring(scene, 0.028, 0.014, Vector3(0.0, 0.128, 0.254), m["steel"])
	# Charging handle, mag release, selector.
	_box(scene, Vector3(0.048, 0.016, 0.030), Vector3(0.0, 0.062, -0.010), m["worn"])
	_box(scene, Vector3(0.014, 0.020, 0.030), Vector3(0.033, -0.020, 0.210), m["worn"])
	_cyl_y(scene, 0.012, 0.030, Vector3(-0.036, -0.010, 0.130), m["worn"])
	return 0.845

static func _cylinder_ring(parent: Node3D, radius: float, width: float, at: Vector3, material: Material) -> void:
	# A thin disc used as a rim around lenses and muzzle devices.
	_cyl_z(parent, radius, width, at, material)

# --- PKM -------------------------------------------------------------------

static func _pkm(scene: Node3D, m: Dictionary) -> float:
	# Stamped receiver with a hinged top cover and a feed tray.
	_box(scene, Vector3(0.085, 0.115, 0.420), Vector3(0.0, 0.0, 0.230), m["steel"])
	_box(scene, Vector3(0.090, 0.030, 0.380), Vector3(0.0, 0.072, 0.240), m["dark"])
	_box(scene, Vector3(0.070, 0.026, 0.070), Vector3(0.0, 0.096, 0.150), m["worn"], Vector3(-12.0, 0.0, 0.0))
	# Belt box hanging under the receiver, with visible brass links.
	_box(scene, Vector3(0.130, 0.150, 0.180), Vector3(0.115, -0.105, 0.215), m["fde"], Vector3(0.0, 0.0, -6.0))
	for i in range(4):
		_box(scene, Vector3(0.014, 0.014, 0.030), Vector3(0.060 + float(i) * 0.014, -0.030, 0.190), m["brass"])
	# Long barrel with a slotted flash hider and a folded bipod.
	_cyl_z(scene, 0.014, 0.520, Vector3(0.0, 0.012, 0.700), m["steel"])
	_cyl_z(scene, 0.021, 0.090, Vector3(0.0, 0.012, 0.985), m["dark"])
	_box(scene, Vector3(0.050, 0.075, 0.035), Vector3(0.0, 0.055, 0.780), m["dark"])
	_cyl_z(scene, 0.008, 0.230, Vector3(0.030, -0.035, 0.620), m["worn"])
	_cyl_z(scene, 0.008, 0.230, Vector3(-0.030, -0.035, 0.620), m["worn"])
	# Carry handle.
	_box(scene, Vector3(0.020, 0.055, 0.120), Vector3(0.0, 0.130, 0.600), m["dark"])
	_box(scene, Vector3(0.020, 0.055, 0.120), Vector3(0.0, 0.130, 0.360), m["dark"])
	_box(scene, Vector3(0.024, 0.024, 0.260), Vector3(0.0, 0.158, 0.480), m["dark"])
	# Wooden stock, pistol grip, trigger group.
	_box(scene, Vector3(0.055, 0.105, 0.260), Vector3(0.0, -0.012, -0.060), m["wood"])
	_box(scene, Vector3(0.058, 0.125, 0.030), Vector3(0.0, -0.020, -0.195), m["wood_dark"])
	_box(scene, Vector3(0.042, 0.110, 0.055), Vector3(0.0, -0.110, 0.090), m["wood_dark"], Vector3(16.0, 0.0, 0.0))
	_box(scene, Vector3(0.040, 0.014, 0.090), Vector3(0.0, -0.070, 0.160), m["worn"])
	# Rear sight and top rail stub.
	_box(scene, Vector3(0.045, 0.035, 0.060), Vector3(0.0, 0.105, 0.330), m["dark"])
	_box(scene, Vector3(0.012, 0.030, 0.012), Vector3(0.0, 0.130, 0.330), m["worn"])
	return 1.030

# --- SVD Dragunov ----------------------------------------------------------

static func _svd(scene: Node3D, m: Dictionary) -> float:
	# Slim receiver and a long, thin barrel.
	_box(scene, Vector3(0.058, 0.098, 0.360), Vector3(0.0, 0.0, 0.220), m["steel"])
	_box(scene, Vector3(0.062, 0.024, 0.300), Vector3(0.0, 0.060, 0.230), m["worn"])
	_cyl_z(scene, 0.012, 0.520, Vector3(0.0, 0.010, 0.700), m["steel"])
	_cyl_z(scene, 0.019, 0.095, Vector3(0.0, 0.010, 0.980), m["dark"])
	# Wooden handguard with vent cuts, and the front sight block.
	_box(scene, Vector3(0.058, 0.070, 0.250), Vector3(0.0, -0.004, 0.490), m["wood"])
	for i in range(3):
		_box(scene, Vector3(0.020, 0.012, 0.056), Vector3(0.030, 0.014, 0.430 + float(i) * 0.070), m["wood_dark"])
	_box(scene, Vector3(0.048, 0.070, 0.030), Vector3(0.0, 0.048, 0.700), m["dark"])
	_box(scene, Vector3(0.010, 0.040, 0.010), Vector3(0.0, 0.082, 0.700), m["worn"])
	# Thumbhole stock: two rails leaving the hole, plus a cheek riser.
	_box(scene, Vector3(0.050, 0.070, 0.280), Vector3(0.0, 0.038, -0.090), m["wood"])
	_box(scene, Vector3(0.050, 0.060, 0.280), Vector3(0.0, -0.052, -0.095), m["wood"])
	_box(scene, Vector3(0.056, 0.075, 0.030), Vector3(0.0, 0.010, -0.235), m["wood_dark"])
	_box(scene, Vector3(0.050, 0.030, 0.090), Vector3(0.0, 0.080, -0.090), m["wood_dark"])
	_box(scene, Vector3(0.040, 0.110, 0.055), Vector3(0.0, -0.100, 0.110), m["wood_dark"], Vector3(14.0, 0.0, 0.0))
	# Ten-round magazine.
	_box(scene, Vector3(0.044, 0.130, 0.070), Vector3(0.0, -0.105, 0.255), m["dark"], Vector3(-10.0, 0.0, 0.0))
	# PSO-1: mount, body, objective bell, eyepiece, turrets, lit glass.
	_box(scene, Vector3(0.048, 0.030, 0.180), Vector3(0.0, 0.088, 0.230), m["dark"])
	_cyl_z(scene, 0.026, 0.230, Vector3(0.0, 0.118, 0.225), m["steel"])
	_cyl_z(scene, 0.036, 0.080, Vector3(0.0, 0.118, 0.355), m["steel"])
	_cyl_z(scene, 0.030, 0.050, Vector3(0.0, 0.118, 0.100), m["steel"])
	_cyl_z(scene, 0.034, 0.008, Vector3(0.0, 0.118, 0.398), m["glass"])
	_cyl_z(scene, 0.030, 0.008, Vector3(0.0, 0.118, 0.076), m["glass"])
	_cyl_y(scene, 0.018, 0.045, Vector3(0.0, 0.160, 0.250), m["steel"])
	_cyl_y(scene, 0.018, 0.040, Vector3(0.035, 0.118, 0.250), m["steel"])
	_box(scene, Vector3(0.042, 0.016, 0.030), Vector3(0.0, 0.062, -0.020), m["worn"])
	return 1.035

# --- Heavy machine guns (.50 cal / Dushka) ---------------------------------

static func _hmg(scene: Node3D, m: Dictionary, short_barrel: bool) -> float:
	# Massive boxy receiver with a ribbed top cover.
	_box(scene, Vector3(0.115, 0.150, 0.420), Vector3(0.0, 0.0, 0.230), m["steel"])
	_box(scene, Vector3(0.120, 0.030, 0.400), Vector3(0.0, 0.090, 0.230), m["dark"])
	for i in range(5):
		_box(scene, Vector3(0.126, 0.026, 0.014), Vector3(0.0, 0.090, 0.090 + float(i) * 0.058), m["worn"])
	# Carry handle and top-mounted rear sight.
	_box(scene, Vector3(0.024, 0.030, 0.300), Vector3(0.0, 0.140, 0.230), m["dark"])
	_box(scene, Vector3(0.060, 0.040, 0.060), Vector3(0.0, 0.150, 0.130), m["dark"])
	# Heavy barrel with cooling fins and a slotted muzzle brake.
	var barrel_len := 0.470 if short_barrel else 0.560
	var barrel_start := 0.440
	_cyl_z(scene, 0.024, barrel_len, Vector3(0.0, 0.010, barrel_start + barrel_len * 0.5), m["steel"])
	for i in range(6):
		_cyl_z(scene, 0.034, 0.016, Vector3(0.0, 0.010, barrel_start + 0.045 + float(i) * 0.048), m["dark"])
	_box(scene, Vector3(0.060, 0.070, 0.090), Vector3(0.0, 0.010, barrel_start + barrel_len + 0.020), m["dark"])
	_box(scene, Vector3(0.064, 0.014, 0.020), Vector3(0.0, 0.010, barrel_start + barrel_len + 0.055), m["worn"])
	# Ammo can and belt feed on the left.
	_box(scene, Vector3(0.140, 0.170, 0.220), Vector3(-0.135, -0.100, 0.240), m["fde"])
	_box(scene, Vector3(0.060, 0.040, 0.140), Vector3(-0.080, -0.030, 0.260), m["dark"])
	for i in range(5):
		_box(scene, Vector3(0.016, 0.012, 0.030), Vector3(-0.070 + float(i) * 0.014, -0.010, 0.240), m["brass"])
	# Spade grips at the rear.
	_box(scene, Vector3(0.030, 0.120, 0.060), Vector3(0.075, -0.080, 0.020), m["polymer"], Vector3(12.0, 0.0, 0.0))
	_box(scene, Vector3(0.030, 0.120, 0.060), Vector3(-0.075, -0.080, 0.020), m["polymer"], Vector3(12.0, 0.0, 0.0))
	_box(scene, Vector3(0.040, 0.014, 0.090), Vector3(0.0, -0.060, 0.070), m["worn"])
	_box(scene, Vector3(0.140, 0.040, 0.070), Vector3(0.0, -0.140, 0.020), m["dark"])
	return barrel_start + barrel_len + 0.090

# --- RPG-7 ----------------------------------------------------------------

static func _rpg(scene: Node3D, m: Dictionary) -> float:
	# Launch tube, wooden heat guard, and the flared rear venturi.
	_cyl_z(scene, 0.036, 1.020, Vector3(0.0, 0.0, 0.400), m["steel"])
	_box(scene, Vector3(0.070, 0.075, 0.260), Vector3(0.0, 0.0, 0.430), m["wood"])
	_cone(scene, 0.040, 0.062, 0.140, Vector3(0.0, 0.0, -0.130), m["dark"], Vector3(90.0, 0.0, 0.0))
	# Warhead: long cone on a short neck, plus the booster.
	_cyl_z(scene, 0.045, 0.120, Vector3(0.0, 0.0, 0.930), m["dark"])
	_cone(scene, 0.010, 0.072, 0.260, Vector3(0.0, 0.0, 1.115), m["fde"], Vector3(-90.0, 0.0, 0.0))
	_cyl_z(scene, 0.018, 0.060, Vector3(0.0, 0.0, 1.270), m["steel"])
	# Pistol grip and trigger group.
	_box(scene, Vector3(0.038, 0.115, 0.055), Vector3(0.0, -0.085, 0.190), m["wood_dark"], Vector3(14.0, 0.0, 0.0))
	_box(scene, Vector3(0.030, 0.030, 0.090), Vector3(0.0, -0.050, 0.270), m["steel"])
	# Flip-up iron sights.
	_box(scene, Vector3(0.014, 0.070, 0.014), Vector3(0.0, 0.075, 0.640), m["dark"])
	_box(scene, Vector3(0.040, 0.014, 0.014), Vector3(0.0, 0.110, 0.640), m["dark"])
	_box(scene, Vector3(0.014, 0.060, 0.014), Vector3(0.0, 0.065, 0.130), m["dark"])
	_cyl_z(scene, 0.010, 0.030, Vector3(0.0, 0.045, 0.900), m["worn"])
	return 1.300

# --- entry point -----------------------------------------------------------

static func build(spec: Dictionary, scene: Node3D) -> Dictionary:
	var id := str(spec.get("id", ""))
	var m := _materials_for(id)
	var muzzle_z := 0.85
	match id:
		"m4a1":
			muzzle_z = _m4a1(scene, m)
		"pkm":
			muzzle_z = _pkm(scene, m)
		"dragunov":
			muzzle_z = _svd(scene, m)
		"50cal":
			muzzle_z = _hmg(scene, m, false)
		"dushka":
			muzzle_z = _hmg(scene, m, true)
		"rpg7":
			muzzle_z = _rpg(scene, m)
		_:
			muzzle_z = _ak74m(scene, m)

	# Grip and support-hand positions follow the receiver, so the arms line up
	# with the weapon instead of hovering next to it.
	var grip := Vector3(0.0, -0.070, 0.115)
	var handguard := Vector3(0.0, -0.020, muzzle_z * 0.52)
	if id == "rpg7":
		grip = Vector3(0.0, -0.070, 0.190)
		handguard = Vector3(0.0, -0.030, 0.470)
	elif id == "50cal" or id == "dushka":
		grip = Vector3(0.075, -0.080, 0.010)
		handguard = Vector3(-0.060, -0.060, 0.330)
	_fp_arms(scene, m, grip, handguard)

	return {"muzzle_z": muzzle_z}
