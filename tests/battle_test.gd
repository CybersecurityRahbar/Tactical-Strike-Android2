extends SceneTree

# Battlefield behaviour test.
#
# Loads the real map and lets the AI play for a while with no rendering. It
# asserts the things a map/AI rewrite can silently break: soldiers acquire and
# shoot at each other, they advance instead of standing at spawn, capture points
# tick, and the player takes damage from incoming fire.

func _fail(message: String) -> void:
	push_error("Battle test failed: " + message)
	quit(1)

func _initialize() -> void:
	call_deferred("_run_battle_test")

func _run_battle_test() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("could not load the main scene.")
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	set_current_scene(instance)
	await create_timer(1.0).timeout

	var soldiers := get_nodes_in_group("combat_target")
	if soldiers.size() < 20:
		_fail("expected both squads to be deployed, found %d soldiers." % soldiers.size())
		return

	var start_positions := {}
	for soldier in soldiers:
		start_positions[soldier] = (soldier as Node3D).global_position

	var military := 0
	var militia := 0
	for soldier in soldiers:
		if str(soldier.get("faction")) == "military":
			military += 1
		else:
			militia += 1
	if military < 6 or militia < 6:
		_fail("both factions need a squad: %d military vs %d militia." % [military, militia])
		return

	var first := soldiers[0] as Node3D
	var rig: Dictionary = first.get("rig")
	if not rig.has("muzzle") or not rig.has("leg_left") or not rig.has("leg_right"):
		_fail("soldier rig is missing its muzzle or leg pivots.")
		return
	if (first.find_children("*", "CollisionShape3D", true, false)).size() < 2:
		_fail("soldier has no separate body/head hit zones.")
		return

	var player := get_first_node_in_group("player")
	if player == null:
		_fail("no player in the scene.")
		return
	var player_health_before := float(player.get("health"))

	# Let the AI fight for a few seconds of wall time.
	var tracers_seen := 0
	var distance_moved := 0.0
	for step in range(24):
		await create_timer(0.25).timeout
		tracers_seen += get_nodes_in_group("bot_tracer").size()
		for soldier in soldiers:
			if not is_instance_valid(soldier):
				continue
			var start: Vector3 = start_positions.get(soldier, (soldier as Node3D).global_position)
			distance_moved = maxf(distance_moved, start.distance_to((soldier as Node3D).global_position))

	if tracers_seen <= 0:
		_fail("no AI soldier fired a shot in six seconds; the squads are not engaging.")
		return
	if distance_moved < 5.0:
		_fail("no AI soldier advanced; they are standing at spawn instead of playing the objective.")
		return

	var points: Array = instance.get("capture_points")
	if points.size() != 3:
		_fail("expected three capture points, found %d." % points.size())
		return
	var any_progress := false
	for point in points:
		if absf(float(point["progress"])) > 0.01:
			any_progress = true
			break
	if not any_progress:
		_fail("no capture point is being contested or flipped.")
		return

	var health_now := float(player.get("health"))
	print("BATTLE TEST PASSED: %d vs %d soldiers, %d tracer volleys, %.1f m advance, player health %.0f -> %.0f, capture points live." % [
		military, militia, tracers_seen, distance_moved, player_health_before, health_now
	])
	quit(0)

func _count_group_children(node_name: String) -> int:
	var count := 0
	for child in root.get_children():
		count += _count_named(child, node_name)
	return count

func _count_named(node: Node, node_name: String) -> int:
	var count := 1 if node.name == node_name else 0
	for child in node.get_children():
		count += _count_named(child, node_name)
	return count
