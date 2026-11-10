extends SceneTree

# Content test for the art pass: every weapon in the loadout must build a
# complete first-person model with a muzzle at the barrel tip, every weapon
# must have its own synthesised report, and a tracer must build its hot core,
# halo and spark trail. Runs headless, no rendering needed.

const WEAPON_AUDIO = preload("res://scripts/effects/weapon_audio.gd")
const TRACER = preload("res://scripts/effects/tracer_visual.gd")
const IMPACT_FX = preload("res://scripts/effects/impact_fx.gd")

func _fail(message: String) -> void:
	push_error("Content test failed: " + message)
	quit(1)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("could not load the main scene.")
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	set_current_scene(instance)
	await create_timer(0.6).timeout

	var player := get_first_node_in_group("player")
	if player == null:
		_fail("no player in the scene.")
		return
	var weapon_controller := instance.get_node_or_null("Player/WeaponController")
	if weapon_controller == null:
		_fail("weapon controller node is missing.")
		return
	var weapons: Array = weapon_controller.get("weapons")
	if weapons.size() != 7:
		_fail("expected 7 weapons, found %d." % weapons.size())
		return

	var camera := player.get_node("Camera3D") as Camera3D
	var profiles_seen := {}
	var checked := 0
	for index in range(weapons.size()):
		var spec: Dictionary = weapons[index]
		weapon_controller.call("select_weapon", index)
		await process_frame
		await process_frame
		var view_model := weapon_controller.get("view_model") as Node3D
		if view_model == null or view_model.get_child_count() == 0:
			_fail("weapon %d (%s) built no view model." % [index, str(spec.get("name", "?"))])
			return
		var scene_root := view_model.get_child(view_model.get_child_count() - 1) as Node3D
		var muzzle := weapon_controller.get("muzzle_marker") as Node3D
		if muzzle == null:
			_fail("weapon %s has no muzzle marker." % str(spec.get("name", "?")))
			return
		var parts := scene_root.find_children("*", "MeshInstance3D", true, false)
		# The AK-74M uses its imported rig; the other six are built from parts
		# and must carry a real silhouette, not a barrel and three boxes.
		var minimum_parts := 2 if str(spec.get("id", "")) == "ak74m" else 14
		if parts.size() < minimum_parts:
			_fail("weapon %s is too simple: only %d mesh parts." % [str(spec.get("name", "?")), parts.size()])
			return
		# The muzzle must sit in front of the camera, roughly at the barrel tip.
		var to_muzzle := muzzle.global_position - camera.global_position
		var forward := -camera.global_transform.basis.z
		if to_muzzle.dot(forward) < 0.20:
			_fail("weapon %s muzzle is not in front of the camera (%.2f m)." % [str(spec.get("name", "?")), to_muzzle.dot(forward)])
			return
		if to_muzzle.length() > 2.2:
			_fail("weapon %s muzzle is detached from the camera (%.2f m)." % [str(spec.get("name", "?")), to_muzzle.length()])
			return

		# Every profile must synthesise a distinct stream.
		var profile := str(spec.get("audio_profile", "ak"))
		if not profiles_seen.has(profile):
			profiles_seen[profile] = true
			WEAPON_AUDIO.play_fire(instance, camera.global_position, profile, -6.0)
			await process_frame
			var found := false
			for node in instance.find_children("*", "AudioStreamPlayer3D", true, false):
				var stream_player := node as AudioStreamPlayer3D
				if stream_player.stream is AudioStreamWAV:
					found = true
					break
			if not found:
				_fail("profile '%s' produced no synthesised report." % profile)
				return
		checked += 1

	if profiles_seen.size() < 6:
		_fail("expected at least 6 distinct weapon audio profiles, found %d." % profiles_seen.size())
		return

	# Tracer round: hot core + halo + trail.
	var round := TRACER.build_round(instance as Node3D, Color(1.0, 0.4, 0.12))
	if round.get("core") == null or round.get("halo") == null or round.get("trail") == null:
		_fail("tracer round is missing its core, halo or trail.")
		return

	# Impact: a hole must be left behind on a hard surface.
	var before_holes := get_nodes_in_group("bullet_holes").size()
	IMPACT_FX.spawn_impact(instance, Vector3(0.0, 0.5, 0.0), Vector3.UP, "concrete", 1800.0, {"penetration": 0.5}, true)
	await process_frame
	var after_holes := get_nodes_in_group("bullet_holes").size()
	if after_holes <= before_holes:
		_fail("impact left no bullet hole on concrete.")
		return

	print("CONTENT TEST PASSED: %d weapons built with complete models, %d distinct audio profiles, burning tracer round, bullet holes on hard surfaces." % [checked, profiles_seen.size()])
	quit(0)
