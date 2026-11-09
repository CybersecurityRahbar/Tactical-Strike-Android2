extends StaticBody3D

# A solid, hittable defender silhouette.
#
# This is the minimum needed to make long-range ballistics observable: a
# collision body with a body and a head hit zone, armour, health, a hit
# reaction and a fall-down death. It deliberately has no AI yet; its purpose is
# to receive rounds at 300-500 m and prove the trajectory, damage falloff and
# impact feedback end to end.

signal damaged(distance_m: float, killed: bool)

const IMPACT_FX = preload("res://scripts/effects/impact_fx.gd")

@export var max_health := 120.0
@export var respawn_seconds := 16.0

var health := 120.0
var alive := true
var home_transform: Transform3D
var visual_root: Node3D
var body_mesh: MeshInstance3D
var uniform_material: StandardMaterial3D
var flinch := 0.0
var flash := 0.0
var spawn_time := 0.0

func _ready() -> void:
	add_to_group("combat_target")
	set_meta("surface", "flesh")
	collision_layer = 1
	collision_mask = 1
	health = max_health
	home_transform = global_transform
	spawn_time = Time.get_ticks_msec() * 0.001
	_build_visuals()
	_build_collision()

func _build_visuals() -> void:
	uniform_material = StandardMaterial3D.new()
	uniform_material.albedo_color = Color(0.22, 0.25, 0.19)
	uniform_material.roughness = 0.92
	visual_root = Node3D.new()
	visual_root.name = "DefenderVisual"
	add_child(visual_root)

	body_mesh = MeshInstance3D.new()
	var torso := CapsuleMesh.new()
	torso.radius = 0.24
	torso.height = 1.08
	body_mesh.mesh = torso
	body_mesh.position.y = 0.86
	body_mesh.material_override = uniform_material
	visual_root.add_child(body_mesh)

	var legs := MeshInstance3D.new()
	var legs_mesh := BoxMesh.new()
	legs_mesh.size = Vector3(0.38, 0.72, 0.28)
	legs.mesh = legs_mesh
	legs.position.y = 0.36
	legs.material_override = uniform_material
	visual_root.add_child(legs)

	var head := MeshInstance3D.new()
	var helmet := SphereMesh.new()
	helmet.radius = 0.145
	helmet.height = 0.30
	head.mesh = helmet
	head.position.y = 1.56
	head.material_override = uniform_material
	visual_root.add_child(head)

	var rifle := MeshInstance3D.new()
	var rifle_mesh := BoxMesh.new()
	rifle_mesh.size = Vector3(0.06, 0.08, 0.82)
	rifle.mesh = rifle_mesh
	rifle.position = Vector3(0.20, 1.02, -0.30)
	rifle.rotation_degrees.x = -12.0
	rifle.material_override = StandardMaterial3D.new()
	(rifle.material_override as StandardMaterial3D).albedo_color = Color(0.14, 0.13, 0.12)
	visual_root.add_child(rifle)

func _build_collision() -> void:
	var body_shape := CollisionShape3D.new()
	body_shape.name = "BodyHitZone"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.55
	body_shape.shape = capsule
	body_shape.position.y = 0.84
	add_child(body_shape)

	var head_shape := CollisionShape3D.new()
	head_shape.name = "HeadHitZone"
	var head_sphere := SphereShape3D.new()
	head_sphere.radius = 0.19
	head_shape.shape = head_sphere
	head_shape.position.y = 1.56
	add_child(head_shape)

# Called by the projectile with the exact hit point, surface normal and the
# collision shape index (0 = body, 1 = head).
func apply_ballistic_damage_at(damage: float, penetration: float, _caliber: String, point: Vector3, _normal: Vector3, shape_index: int) -> void:
	if not alive:
		return
	var dealt := damage
	# Body armour blunts weaker rounds; AP ammunition keeps its damage.
	var armour_factor := clampf(0.55 + penetration * 1.4, 0.55, 1.15)
	dealt *= armour_factor
	if shape_index == 1:
		dealt *= 2.8
	health -= dealt
	flash = 1.0
	flinch = clampf(flinch + 0.09, 0.0, 0.32)
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

func _spawn_hit_mist(point: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene != null:
		IMPACT_FX.spawn_impact(scene, point, Vector3.UP, "flesh", 900.0, {"penetration": 0.4}, false)

func _die() -> void:
	alive = false
	health = 0.0
	collision_layer = 0
	collision_mask = 0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual_root, "rotation_degrees:x", -84.0, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual_root, "position:y", -0.28, 0.55)
	var timer := get_tree().create_timer(respawn_seconds)
	timer.timeout.connect(_respawn)

func _respawn() -> void:
	if not is_inside_tree():
		return
	alive = true
	health = max_health
	visual_root.rotation_degrees = Vector3.ZERO
	visual_root.position = Vector3.ZERO
	collision_layer = 1
	collision_mask = 1
	flash = 0.0
	flinch = 0.0
	var tween := create_tween()
	tween.tween_property(visual_root, "position:y", 0.0, 0.35)

func _process(delta: float) -> void:
	flash = move_toward(flash, 0.0, delta * 6.0)
	flinch = move_toward(flinch, 0.0, delta * 1.6)
	if visual_root != null:
		visual_root.rotation.x = -flinch
	if uniform_material != null:
		uniform_material.emission_enabled = flash > 0.01
		uniform_material.emission = Color(0.55, 0.08, 0.05)
		uniform_material.emission_energy_multiplier = flash * 1.6
