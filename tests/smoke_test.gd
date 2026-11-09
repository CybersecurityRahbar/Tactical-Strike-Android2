extends SceneTree

const REQUIRED_SCRIPTS: Array[String] = [
	"res://scripts/world/main_world.gd",
	"res://scripts/world/cover_piece.gd",
	"res://scripts/world/combat_target.gd",
	"res://scripts/player/player_controller.gd",
	"res://scripts/weapons/ballistics.gd",
	"res://scripts/weapons/weapon_data.gd",
	"res://scripts/weapons/weapon_controller.gd",
	"res://scripts/weapons/projectile.gd",
	"res://scripts/effects/impact_fx.gd",
	"res://scripts/effects/impact_audio.gd",
	"res://scripts/effects/weapon_audio.gd",
	"res://scripts/ui/virtual_joystick.gd",
	"res://scripts/ui/hud.gd"
]
const IMPACT_FX = preload("res://scripts/effects/impact_fx.gd")
const BALLISTICS = preload("res://scripts/weapons/ballistics.gd")

func _count_mesh_instances(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count

func _fail(message: String) -> void:
	push_error("Smoke test failed: " + message)
	quit(1)

func _initialize() -> void:
	call_deferred("_run_smoke_test")

func _run_smoke_test() -> void:
	for script_path in REQUIRED_SCRIPTS:
		var script_resource := load(script_path) as Script
		if script_resource == null:
			_fail("could not load script %s." % script_path)
			return
		if not script_resource.can_instantiate():
			_fail("script cannot instantiate %s." % script_path)
			return

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main scene could not be loaded.")
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame

	# ---- Terrain -----------------------------------------------------------
	if not instance.has_node("BattlefieldTerrain"):
		_fail("procedural soil terrain was not created.")
		return
	if not instance.has_node("BattlefieldRock"):
		_fail("rock cliff surface was not created.")
		return
	var terrain_mesh_instance := instance.get_node("BattlefieldTerrain") as MeshInstance3D
	var terrain_arrays: Array = terrain_mesh_instance.mesh.surface_get_arrays(0)
	var terrain_tangents: PackedFloat32Array = terrain_arrays[Mesh.ARRAY_TANGENT]
	var terrain_normals: PackedVector3Array = terrain_arrays[Mesh.ARRAY_NORMAL]
	if terrain_normals.is_empty():
		_fail("terrain normal array is empty.")
		return
	var mean_normal_y := 0.0
	var upward_normals := 0
	for normal: Vector3 in terrain_normals:
		mean_normal_y += normal.y
		if normal.y > 0.2:
			upward_normals += 1
	mean_normal_y /= float(terrain_normals.size())
	if mean_normal_y < 0.50 or upward_normals < int(float(terrain_normals.size()) * 0.60):
		_fail("terrain normals are not consistently oriented upward (mean Y %.3f, upward %d/%d)." % [mean_normal_y, upward_normals, terrain_normals.size()])
		return
	if not instance.has_node("TerrainCollision/HeightmapCollision"):
		_fail("terrain heightmap collision is missing.")
		return
	var terrain_collision := instance.get_node("TerrainCollision/HeightmapCollision").shape as HeightMapShape3D
	if terrain_collision == null or terrain_collision.map_width != 257 or terrain_collision.map_depth != 257 or terrain_collision.map_data.size() != 257 * 257:
		_fail("optimized terrain heightmap collision was not initialized with the expected full map.")
		return
	if terrain_tangents.is_empty():
		_fail("terrain mesh has no generated tangents for its normal map.")
		return
	var terrain_material := terrain_mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
	if terrain_material == null or terrain_material.albedo_texture == null or terrain_material.normal_texture == null or not terrain_material.normal_enabled:
		_fail("Rocky Gravel diffuse and normal textures are not bound to the soil material.")
		return
	if terrain_mesh_instance.mesh.get_aabb().size.y < 8.0:
		_fail("battlefield topography does not contain enough vertical relief.")
		return
	var rock_material := (instance.get_node("BattlefieldRock") as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
	if rock_material == null or not rock_material.uv1_triplanar:
		_fail("cliff rock surface is not using the triplanar material.")
		return
	var outcrops := instance.get_node_or_null("GroundStones") as MultiMeshInstance3D
	if outcrops == null or outcrops.multimesh == null or outcrops.multimesh.instance_count < 100:
		_fail("ground outcrops are missing.")
		return
	if not instance.has_node("DryShrubs"):
		_fail("dry scrub scatter is missing.")
		return

	# ---- Player / HUD ------------------------------------------------------
	if not instance.has_node("Player"):
		_fail("player controller was not created.")
		return
	if not instance.has_node("HUD"):
		_fail("HUD was not created.")
		return
	if not instance.has_node("Player/Camera3D/WeaponViewModel/AK74M_ArmsAndWeapon"):
		_fail("animated AK-74M first-person scene was not created.")
		return
	var weapon_model := instance.get_node("Player/Camera3D/WeaponViewModel/AK74M_ArmsAndWeapon")
	if _count_mesh_instances(weapon_model) == 0:
		_fail("imported weapon scene contains no visible mesh.")
		return
	var animation_players := weapon_model.find_children("*", "AnimationPlayer", true, false)
	if animation_players.is_empty():
		_fail("the first-person AK-74M has no AnimationPlayer.")
		return
	var weapon_animation := animation_players[0] as AnimationPlayer
	for clip: String in ["Rig|AK_Idle", "Rig|AK_Draw", "Rig|AK_Walk", "Rig|AK_Run", "Rig|AK_Shot", "Rig|AK_Reload_full"]:
		if not weapon_animation.has_animation(clip):
			_fail("missing authored weapon animation " + clip)
			return

	# ---- Muzzle mount ------------------------------------------------------
	if not weapon_model.has_node("MuzzlePoint"):
		_fail("the weapon has no muzzle marker.")
		return
	var weapon_controller := instance.get_node("Player/WeaponController")
	var camera := instance.get_node("Player/Camera3D") as Camera3D
	var muzzle_marker := weapon_model.get_node("MuzzlePoint") as Marker3D
	var forward := -camera.global_transform.basis.z
	var muzzle_offset := muzzle_marker.global_position - camera.global_position
	if muzzle_offset.dot(forward) < 0.25:
		_fail("the muzzle marker is not in front of the camera (offset %s)." % str(muzzle_offset))
		return
	var muzzle_direction: Vector3 = weapon_controller.call("muzzle_direction")
	if muzzle_direction.dot(forward) < 0.85:
		_fail("the weapon barrel does not point down the camera forward axis (dot %.2f); it is mounted sideways/backwards." % muzzle_direction.dot(forward))
		return

	# ---- Hittable defenders ------------------------------------------------
	var targets := instance.get_tree().get_nodes_in_group("combat_target")
	if targets.size() < 10:
		_fail("expected at least 10 hittable defenders, found %d." % targets.size())
		return
	var first_target := targets[0] as Node3D
	var hit_zones := first_target.find_children("*", "CollisionShape3D", true, false)
	if hit_zones.size() < 2:
		_fail("defender has no separate body/head hit zones.")
		return
	if not first_target.has_method("apply_ballistic_damage_at"):
		_fail("defender does not accept ballistic damage.")
		return

	# ---- Ammunition --------------------------------------------------------
	if weapon_controller.get("magazine_ammo") != 30 or weapon_controller.get("reserve_ammo") < 90:
		_fail("magazine/reserve ammunition was not initialized.")
		return
	if not instance.has_node("HUD/Overlay/MovementJoystick") or not instance.has_node("HUD/Overlay/AimButton") or not instance.has_node("HUD/Overlay/AmmoButton") or not instance.has_node("HUD/Overlay/FireButton") or not instance.has_node("HUD/Overlay/ReloadButton"):
		_fail("analog movement joystick or aim control is missing.")
		return

	# ---- Ballistic model ---------------------------------------------------
	var caliber := BALLISTICS.profile("5.45x39")
	if absf(BALLISTICS.speed_at(caliber, 0.0) - 900.0) > 0.5:
		_fail("muzzle velocity does not match the authored cartridge data.")
		return
	var speed_500 := BALLISTICS.speed_at(caliber, 500.0)
	if speed_500 < 380.0 or speed_500 > 560.0:
		_fail("5.45x39 retained velocity at 500 m is not realistic (%.0f m/s)." % speed_500)
		return
	var drop_500 := BALLISTICS.drop_at(caliber, 500.0)
	if drop_500 < 1.5 or drop_500 > 8.0:
		_fail("5.45x39 drop at 500 m is not realistic (%.2f m)." % drop_500)
		return
	var damage_far := BALLISTICS.damage_at(caliber, speed_500, 38.0)
	if damage_far >= 38.0 or damage_far < 6.0:
		_fail("damage does not fall off with distance (%.1f)." % damage_far)
		return
	if BALLISTICS.speed_at(caliber, 300.0) >= BALLISTICS.speed_at(caliber, 100.0):
		_fail("velocity does not decay downrange.")
		return

	# ---- Audio: one report per file ---------------------------------------
	for audio_path in [
		"res://assets/runtime/audio/ak_C_27P.ogg",
		"res://assets/runtime/audio/ak_C_28P.ogg",
		"res://assets/runtime/audio/ak_C_29P.ogg",
		"res://assets/runtime/audio/ak_C_31P.ogg",
		"res://assets/runtime/audio/ak_C_34P.ogg",
		"res://assets/runtime/audio/ak_C_36P.ogg"
	]:
		if not ResourceLoader.exists(audio_path):
			_fail("missing recorded AK field sample " + audio_path)
			return
		var sample := load(audio_path) as AudioStream
		if sample == null or sample.get_length() <= 0.0:
			_fail("recorded AK sample is unreadable: " + audio_path)
			return
		if sample.get_length() > 1.2:
			_fail("recorded AK sample still contains a burst (%.2f s): %s" % [sample.get_length(), audio_path])
			return

	if InputMap.has_action("fire") == false or InputMap.has_action("reload") == false or InputMap.has_action("ammo_cycle") == false:
		_fail("fire, reload or ammunition-cycle input action was not registered.")
		return

	# ---- Touch movement ----------------------------------------------------
	set_current_scene(instance)
	var player_node := instance.get_node("Player")
	var hud_node := instance.get_node("HUD")
	var screen_size: Vector2 = instance.get_viewport().get_visible_rect().size
	var start_position: Vector3 = player_node.global_position

	var touch_origin := Vector2(screen_size.x * 0.16, screen_size.y * 0.72)
	var touch_press := InputEventScreenTouch.new()
	touch_press.index = 7
	touch_press.position = touch_origin
	touch_press.pressed = true
	hud_node.call("_input", touch_press)
	var touch_drag := InputEventScreenDrag.new()
	touch_drag.index = 7
	touch_drag.position = touch_origin + Vector2(0.0, -72.0)
	hud_node.call("_input", touch_drag)
	var touch_vector: Vector2 = Vector2(player_node.get("touch_move_vector"))
	if touch_vector.y < 0.75:
		_fail("real left-stick touch drag did not reach the player movement controller.")
		return
	for frame in range(48):
		await physics_frame
	var touch_release := InputEventScreenTouch.new()
	touch_release.index = 7
	touch_release.position = touch_origin + Vector2(0.0, -72.0)
	touch_release.pressed = false
	hud_node.call("_input", touch_release)
	if player_node.global_position.distance_to(start_position) < 0.45:
		_fail("player did not move after the HUD touch joystick drag.")
		return
	if player_node.global_position.y < start_position.y - 1.15:
		_fail("player fell through or below the terrain collision surface.")
		return
	if not instance.has_node("HUD/Overlay/PauseButton") or not instance.has_node("HUD/Overlay/ArmoryButton") or not instance.has_node("HUD/Overlay/SettingsButton"):
		_fail("pause, armory or settings UI is missing.")
		return

	var joystick_control := instance.get_node("HUD/Overlay/MovementJoystick") as Control
	var fire_control := instance.get_node("HUD/Overlay/FireButton") as Control
	var aim_control := instance.get_node("HUD/Overlay/AimButton") as Control
	var joystick_rect: Rect2 = joystick_control.get_global_rect()
	var fire_rect: Rect2 = fire_control.get_global_rect()
	var aim_rect: Rect2 = aim_control.get_global_rect()
	if joystick_rect.position.x > screen_size.x * 0.30:
		_fail("movement joystick is not anchored on the left side.")
		return
	if fire_rect.position.x < screen_size.x * 0.50:
		_fail("fire control is not anchored on the right side.")
		return
	if fire_rect.intersects(aim_rect):
		_fail("fire and aim touch targets overlap.")
		return
	if instance.get_node("HUD/Overlay").layout_direction != Control.LAYOUT_DIRECTION_LTR:
		_fail("Arabic RTL system layout must not mirror shooter controls.")
		return

	# ---- Fire: one round, one physical projectile --------------------------
	var ammo_before := int(weapon_controller.get("magazine_ammo"))
	var fire_button := instance.get_node("HUD/Overlay/FireButton") as Button
	fire_button.emit_signal("button_down")
	await process_frame
	await process_frame
	fire_button.emit_signal("button_up")
	await process_frame
	if int(weapon_controller.get("magazine_ammo")) != ammo_before - 1:
		_fail("touching FIRE did not consume exactly one magazine round.")
		return
	if bool(weapon_controller.get("last_shot_used_tracer")):
		_fail("standard FMJ ammunition should create a non-tracer projectile.")
		return
	var projectiles := instance.get_tree().get_nodes_in_group("ballistic_projectiles")
	if projectiles.is_empty():
		_fail("firing did not create a physical projectile.")
		return
	var live_projectile = projectiles[projectiles.size() - 1]
	var live_caliber: Dictionary = live_projectile.get("caliber")
	if live_caliber.is_empty() or float(live_caliber.get("drag_per_meter", 0.0)) <= 0.0:
		_fail("projectile is not carrying real cartridge drag data.")
		return
	if live_projectile.get("tracer_visual") != null:
		_fail("FMJ rounds should not render a tracer streak.")
		return

	# ---- ADS ---------------------------------------------------------------
	var aim_button := instance.get_node("HUD/Overlay/AimButton") as Button
	aim_button.emit_signal("pressed")
	if not bool(weapon_controller.get("aim_enabled")):
		_fail("AIM button did not engage aim-down-sights.")
		return
	aim_button.emit_signal("pressed")

	# ---- Tracer ammunition -------------------------------------------------
	var ammo_button := instance.get_node("HUD/Overlay/AmmoButton") as Button
	ammo_button.emit_signal("pressed")
	if int(weapon_controller.get("ammo_type_index")) != 1:
		_fail("touching AMMO did not activate tracer ammunition.")
		return
	for frame in range(10):
		await physics_frame
	fire_button.emit_signal("button_down")
	await process_frame
	await process_frame
	fire_button.emit_signal("button_up")
	await process_frame
	if not bool(weapon_controller.get("last_shot_used_tracer")):
		_fail("selected tracer ammunition did not create a tracer projectile.")
		return
	var tracer_projectiles := instance.get_tree().get_nodes_in_group("ballistic_projectiles")
	var tracer_projectile = tracer_projectiles[tracer_projectiles.size() - 1]
	var tracer_visual = tracer_projectile.get("tracer_visual")
	if tracer_visual == null or not (tracer_visual.mesh is CylinderMesh):
		_fail("tracer projectile has no compact streak mesh.")
		return
	if tracer_visual.scale.y > 2.4:
		_fail("tracer streak is too long and reads as a laser line (%.2f m)." % tracer_visual.scale.y)
		return

	# ---- Reload ------------------------------------------------------------
	var reload_button := instance.get_node("HUD/Overlay/ReloadButton") as Button
	reload_button.emit_signal("button_down")
	await process_frame
	await process_frame
	reload_button.emit_signal("button_up")
	await process_frame
	if not bool(weapon_controller.get("is_reloading")):
		_fail("touching RELOAD did not start a magazine reload.")
		return
	if weapon_animation.current_animation != "Rig|AK_Reload_full":
		_fail("reload did not start the authored first-person reload animation.")
		return

	# ---- Impact effects and audio -----------------------------------------
	IMPACT_FX.spawn_impact(instance, player_node.global_position + Vector3(0.0, 1.0, -2.0), Vector3.UP, "stone", 1600.0, {"penetration": 0.5}, true)
	await process_frame
	var dust_particles := instance.get_node_or_null("BallisticImpactDust") as CPUParticles3D
	if dust_particles == null or dust_particles.mesh == null:
		_fail("ballistic impact dust has no valid particle mesh.")
		return
	if instance.get_node_or_null("BallisticImpactSparks") == null:
		_fail("stone impacts do not emit sparks.")
		return
	if instance.get_node_or_null("ImpactAudio") == null:
		_fail("ballistic impacts do not emit a positional impact sound.")
		return

	# ---- Target damage -----------------------------------------------------
	var target_a := targets[0]
	var health_before := float(target_a.get("health"))
	target_a.call("apply_ballistic_damage_at", 10.0, 0.45, "5.45×39 mm", target_a.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP, 0)
	var body_damage := health_before - float(target_a.get("health"))
	if body_damage <= 0.0:
		_fail("a body hit did not reduce defender health.")
		return
	var target_b := targets[1]
	var health_b := float(target_b.get("health"))
	target_b.call("apply_ballistic_damage_at", 10.0, 0.45, "5.45×39 mm", target_b.global_position + Vector3(0.0, 1.55, 0.0), Vector3.UP, 1)
	var head_damage := health_b - float(target_b.get("health"))
	if head_damage <= body_damage:
		_fail("head hits are not more damaging than body hits.")
		return

	print("SMOKE TEST PASSED: rocky/plain terrain with triplanar cliffs, forward-mounted AK-74M muzzle, hit-zoned defenders, real drag/gravity ballistics, single-shot reports, tracer streaks, surface impacts with sparks and audio, mobile input, firing, ADS and reload.")
	quit(0)
