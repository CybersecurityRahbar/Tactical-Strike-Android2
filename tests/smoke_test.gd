extends SceneTree

const REQUIRED_SCRIPTS: Array[String] = [
	"res://scripts/world/main_world.gd",
	"res://scripts/world/cover_piece.gd",
	"res://scripts/player/player_controller.gd",
	"res://scripts/weapons/weapon_data.gd",
	"res://scripts/weapons/weapon_controller.gd",
	"res://scripts/weapons/projectile.gd",
	"res://scripts/effects/impact_fx.gd",
	"res://scripts/effects/weapon_audio.gd",
	"res://scripts/ui/virtual_joystick.gd",
	"res://scripts/ui/hud.gd"
]
const IMPACT_FX = preload("res://scripts/effects/impact_fx.gd")

func _count_mesh_instances(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count

func _initialize() -> void:
	call_deferred("_run_smoke_test")

func _run_smoke_test() -> void:
	for script_path in REQUIRED_SCRIPTS:
		var script_resource := load(script_path) as Script
		if script_resource == null:
			push_error("Smoke test failed: could not load script %s." % script_path)
			quit(1)
			return
		if not script_resource.can_instantiate():
			push_error("Smoke test failed: script cannot instantiate %s." % script_path)
			quit(1)
			return

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("Smoke test failed: main scene could not be loaded.")
		quit(1)
		return

	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame

	if not instance.has_node("BattlefieldTerrain"):
		push_error("Smoke test failed: procedural terrain was not created.")
		quit(1)
		return
	var terrain_mesh_instance := instance.get_node("BattlefieldTerrain") as MeshInstance3D
	var terrain_arrays: Array = terrain_mesh_instance.mesh.surface_get_arrays(0)
	var terrain_tangents: PackedFloat32Array = terrain_arrays[Mesh.ARRAY_TANGENT]
	var terrain_normals: PackedVector3Array = terrain_arrays[Mesh.ARRAY_NORMAL]
	if terrain_normals.is_empty():
		push_error("Smoke test failed: terrain normal array is empty.")
		quit(1)
		return
	var mean_normal_y := 0.0
	var upward_normals := 0
	for normal: Vector3 in terrain_normals:
		mean_normal_y += normal.y
		if normal.y > 0.2:
			upward_normals += 1
	mean_normal_y /= float(terrain_normals.size())
	if mean_normal_y < 0.55 or upward_normals < int(float(terrain_normals.size()) * 0.72):
		push_error("Smoke test failed: terrain normals are not consistently oriented upward (mean Y %.3f, upward %d/%d)." % [mean_normal_y, upward_normals, terrain_normals.size()])
		quit(1)
		return
	var terrain_collision := instance.get_node("TerrainCollision/HeightmapCollision").shape as HeightMapShape3D
	if terrain_collision == null or terrain_collision.map_width != 257 or terrain_collision.map_depth != 257 or terrain_collision.map_data.size() != 257 * 257:
		push_error("Smoke test failed: optimized terrain heightmap collision was not initialized with the expected full map.")
		quit(1)
		return
	if terrain_tangents.is_empty():
		push_error("Smoke test failed: terrain mesh has no generated tangents for its normal map.")
		quit(1)
		return
	var terrain_material := terrain_mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
	if terrain_material == null or terrain_material.albedo_texture == null or terrain_material.normal_texture == null or not terrain_material.normal_enabled:
		push_error("Smoke test failed: Rocky Gravel diffuse and normal textures are not bound to the terrain material.")
		quit(1)
		return
	if terrain_mesh_instance.mesh.get_aabb().size.y < 12.0:
		push_error("Smoke test failed: battlefield topography does not contain enough vertical relief.")
		quit(1)
		return
	var outcrops := instance.get_node_or_null("DryGroundStones") as MultiMeshInstance3D
	if outcrops == null or outcrops.multimesh.instance_count > 700:
		push_error("Smoke test failed: ground outcrops are missing or excessively dense.")
		quit(1)
		return
	if not instance.has_node("Player"):
		push_error("Smoke test failed: player controller was not created.")
		quit(1)
		return
	if not instance.has_node("HUD"):
		push_error("Smoke test failed: HUD was not created.")
		quit(1)
		return
	if not instance.has_node("Player/Camera3D/WeaponViewModel/AK74M_ArmsAndWeapon"):
		push_error("Smoke test failed: animated AK-74M first-person scene was not created.")
		quit(1)
		return
	var weapon_model := instance.get_node("Player/Camera3D/WeaponViewModel/AK74M_ArmsAndWeapon")
	if _count_mesh_instances(weapon_model) == 0:
		push_error("Smoke test failed: imported weapon scene contains no visible mesh.")
		quit(1)
		return
	var animation_players := weapon_model.find_children("*", "AnimationPlayer", true, false)
	if animation_players.is_empty():
		push_error("Smoke test failed: the first-person AK-74M has no AnimationPlayer.")
		quit(1)
		return
	var weapon_animation := animation_players[0] as AnimationPlayer
	for clip: String in ["Rig|AK_Idle", "Rig|AK_Draw", "Rig|AK_Walk", "Rig|AK_Run", "Rig|AK_Shot", "Rig|AK_Reload_full"]:
		if not weapon_animation.has_animation(clip):
			push_error("Smoke test failed: missing authored weapon animation " + clip)
			quit(1)
			return
	var weapon_controller := instance.get_node("Player/WeaponController")
	if weapon_controller.get("magazine_ammo") != 30 or weapon_controller.get("reserve_ammo") < 60:
		push_error("Smoke test failed: magazine/reserve ammunition was not initialized.")
		quit(1)
		return
	if not instance.has_node("HUD/Overlay/MovementJoystick") or not instance.has_node("HUD/Overlay/AimButton") or not instance.has_node("HUD/Overlay/AmmoButton") or not instance.has_node("HUD/Overlay/FireButton") or not instance.has_node("HUD/Overlay/ReloadButton"):
		push_error("Smoke test failed: analog movement joystick or aim control is missing.")
		quit(1)
		return
	var player_node := instance.get_node("Player")
	var hud_node := instance.get_node("HUD")
	var screen_size: Vector2 = instance.get_viewport().get_visible_rect().size
	var start_position: Vector3 = player_node.global_position

	# Drive the actual HUD touch handler: left thumb down, then drag the virtual stick upward.
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
		push_error("Smoke test failed: real left-stick touch drag did not reach the player movement controller.")
		quit(1)
		return
	for frame in range(48):
		await physics_frame
	var touch_release := InputEventScreenTouch.new()
	touch_release.index = 7
	touch_release.position = touch_origin + Vector2(0.0, -72.0)
	touch_release.pressed = false
	hud_node.call("_input", touch_release)
	if player_node.global_position.distance_to(start_position) < 0.45:
		push_error("Smoke test failed: player did not move after the HUD touch joystick drag.")
		quit(1)
		return
	if player_node.global_position.y < start_position.y - 1.15:
		push_error("Smoke test failed: player fell through or below the terrain collision surface.")
		quit(1)
		return
	if not instance.has_node("HUD/Overlay/PauseButton") or not instance.has_node("HUD/Overlay/ArmoryButton") or not instance.has_node("HUD/Overlay/SettingsButton"):
		push_error("Smoke test failed: pause, armory or settings UI is missing.")
		quit(1)
		return

	var joystick_control := instance.get_node("HUD/Overlay/MovementJoystick") as Control
	var fire_control := instance.get_node("HUD/Overlay/FireButton") as Control
	var aim_control := instance.get_node("HUD/Overlay/AimButton") as Control
	var joystick_rect: Rect2 = joystick_control.get_global_rect()
	var fire_rect: Rect2 = fire_control.get_global_rect()
	var aim_rect: Rect2 = aim_control.get_global_rect()
	if joystick_rect.position.x > screen_size.x * 0.30:
		push_error("Smoke test failed: movement joystick is not anchored on the left side.")
		quit(1)
		return
	if fire_rect.position.x < screen_size.x * 0.50:
		push_error("Smoke test failed: fire control is not anchored on the right side.")
		quit(1)
		return
	if fire_rect.intersects(aim_rect):
		push_error("Smoke test failed: fire and aim touch targets overlap.")
		quit(1)
		return
	if instance.get_node("HUD/Overlay").layout_direction != Control.LAYOUT_DIRECTION_LTR:
		push_error("Smoke test failed: Arabic RTL system layout must not mirror shooter controls.")
		quit(1)
		return

	var weapon_audio_paths: Array[String] = [
		"res://assets/runtime/audio/ak_C_27P.ogg",
		"res://assets/runtime/audio/ak_C_28P.ogg",
		"res://assets/runtime/audio/ak_C_29P.ogg",
		"res://assets/runtime/audio/ak_C_31P.ogg",
		"res://assets/runtime/audio/ak_C_34P.ogg",
		"res://assets/runtime/audio/ak_C_36P.ogg"
	]
	for audio_path in weapon_audio_paths:
		if not ResourceLoader.exists(audio_path):
			push_error("Smoke test failed: missing recorded AK field sample " + audio_path)
			quit(1)
			return

	if InputMap.has_action("fire") == false or InputMap.has_action("reload") == false or InputMap.has_action("ammo_cycle") == false:
		push_error("Smoke test failed: fire, reload or ammunition-cycle input action was not registered.")
		quit(1)
		return

	# Drive the real HUD button signals rather than calling the weapon methods directly.
	set_current_scene(instance)
	var ammo_before := int(weapon_controller.get("magazine_ammo"))
	var fire_button := instance.get_node("HUD/Overlay/FireButton") as Button
	fire_button.emit_signal("button_down")
	await process_frame
	await process_frame
	fire_button.emit_signal("button_up")
	await process_frame
	if int(weapon_controller.get("magazine_ammo")) != ammo_before - 1:
		push_error("Smoke test failed: touching FIRE did not consume one magazine round.")
		quit(1)
		return
	if bool(weapon_controller.get("last_shot_used_tracer")):
		push_error("Smoke test failed: standard FMJ ammunition should create a non-tracer projectile.")
		quit(1)
		return

	var aim_button := instance.get_node("HUD/Overlay/AimButton") as Button
	aim_button.emit_signal("pressed")
	if not bool(weapon_controller.get("aim_enabled")):
		push_error("Smoke test failed: AIM button did not engage aim-down-sights.")
		quit(1)
		return
	aim_button.emit_signal("pressed")

	var ammo_button := instance.get_node("HUD/Overlay/AmmoButton") as Button
	ammo_button.emit_signal("pressed")
	if int(weapon_controller.get("ammo_type_index")) != 1:
		push_error("Smoke test failed: touching AMMO did not activate tracer ammunition.")
		quit(1)
		return
	for frame in range(10):
		await physics_frame
	fire_button.emit_signal("button_down")
	await process_frame
	await process_frame
	fire_button.emit_signal("button_up")
	await process_frame
	if not bool(weapon_controller.get("last_shot_used_tracer")):
		push_error("Smoke test failed: selected tracer ammunition did not create a visible tracer projectile.")
		quit(1)
		return

	var reload_button := instance.get_node("HUD/Overlay/ReloadButton") as Button
	reload_button.emit_signal("button_down")
	await process_frame
	await process_frame
	reload_button.emit_signal("button_up")
	await process_frame
	if not bool(weapon_controller.get("is_reloading")):
		push_error("Smoke test failed: touching RELOAD did not start a magazine reload.")
		quit(1)
		return
	if weapon_animation.current_animation != "Rig|AK_Reload_full":
		push_error("Smoke test failed: reload did not start the authored first-person reload animation.")
		quit(1)
		return

	IMPACT_FX.spawn_dust(instance, player_node.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP, false)
	await process_frame
	var dust_particles := instance.get_node_or_null("BallisticImpactDust") as CPUParticles3D
	if dust_particles == null or dust_particles.mesh == null:
		push_error("Smoke test failed: ballistic impact dust has no valid particle mesh.")
		quit(1)
		return

	print("SMOKE TEST PASSED: rocky PBR terrain, AK-74M + rigged arms, idle/walk/run/shot/reload clips, separate touch zones, player motion, recorded samples, firing and ammo modes initialized.")
	quit(0)
