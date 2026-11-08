extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player/player_controller.gd")
const HUD_SCRIPT = preload("res://scripts/ui/hud.gd")
const COVER_SCRIPT = preload("res://scripts/world/cover_piece.gd")

const MAP_SIZE := 700.0
const TERRAIN_DIVISIONS := 256

var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var gully_noise := FastNoiseLite.new()
var terrain_texture_enabled := false
var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var sky_material: ProceduralSkyMaterial
var hud: CanvasLayer
var player: CharacterBody3D
var night_mode := false

var earth_material: StandardMaterial3D
var sandbag_material: StandardMaterial3D
var brick_material: StandardMaterial3D
var stone_material: StandardMaterial3D
var dark_material: StandardMaterial3D
var soldier_material: StandardMaterial3D

func _ready() -> void:
	_setup_noise()
	_create_materials()
	_build_environment()
	_build_terrain()
	_build_cover_layout()
	_build_approach_track()
	_scatter_ground_details()
	_place_distant_defenders()
	_spawn_player()
	_create_hud()

func _setup_noise() -> void:
	terrain_noise.seed = 20261108
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_noise.frequency = 0.0045
	terrain_noise.fractal_octaves = 5
	terrain_noise.fractal_lacunarity = 2.0
	terrain_noise.fractal_gain = 0.48
	terrain_noise.domain_warp_enabled = true
	terrain_noise.domain_warp_amplitude = 72.0
	terrain_noise.domain_warp_frequency = 0.0038
	terrain_noise.domain_warp_fractal_octaves = 3

	detail_noise.seed = 741208
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.027
	detail_noise.fractal_octaves = 4
	detail_noise.fractal_lacunarity = 2.1
	detail_noise.fractal_gain = 0.52

	ridge_noise.seed = 20261109
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge_noise.frequency = 0.006
	ridge_noise.fractal_octaves = 4
	ridge_noise.fractal_lacunarity = 2.0
	ridge_noise.fractal_gain = 0.52

	gully_noise.seed = 20261110
	gully_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	gully_noise.frequency = 0.005
	gully_noise.fractal_octaves = 3
	gully_noise.fractal_lacunarity = 2.0
	gully_noise.fractal_gain = 0.48

func _create_materials() -> void:
	earth_material = _make_material(Color.WHITE)
	earth_material.vertex_color_use_as_albedo = true
	earth_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	earth_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var diffuse_path := "res://assets/runtime/terrain/rocky_gravel_diff_1k.jpg"
	var normal_path := "res://assets/runtime/terrain/rocky_gravel_nor_gl_1k.jpg"
	var roughness_path := "res://assets/runtime/terrain/rocky_gravel_rough_1k.jpg"
	if ResourceLoader.exists(diffuse_path):
		earth_material.albedo_texture = load(diffuse_path) as Texture2D
		terrain_texture_enabled = earth_material.albedo_texture != null
	if ResourceLoader.exists(normal_path):
		earth_material.normal_enabled = true
		earth_material.normal_texture = load(normal_path) as Texture2D
		earth_material.normal_scale = 1.0
	if ResourceLoader.exists(roughness_path):
		earth_material.roughness_texture = load(roughness_path) as Texture2D
	earth_material.roughness = 0.96
	earth_material.metallic = 0.0
	sandbag_material = _make_material(Color(0.47, 0.40, 0.29))
	brick_material = _make_material(Color(0.39, 0.29, 0.23))
	stone_material = _make_material(Color(0.50, 0.46, 0.39))
	dark_material = _make_material(Color(0.20, 0.19, 0.16))
	soldier_material = _make_material(Color(0.18, 0.22, 0.17))

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	return material

func _build_environment() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.34, 0.42, 0.47)
	sky_material.sky_horizon_color = Color(0.72, 0.62, 0.47)
	sky_material.ground_bottom_color = Color(0.16, 0.14, 0.11)
	sky_material.ground_horizon_color = Color(0.45, 0.36, 0.26)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Soft depth haze preserves distant silhouettes while gently reducing contrast.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = 480.0
	environment.fog_depth_end = 1750.0
	environment.fog_depth_curve = 0.9
	environment.fog_density = 0.025
	environment.fog_light_color = Color(0.56, 0.47, 0.35)
	environment.fog_sky_affect = 0.32
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

func _terrain_height(x: float, z: float) -> float:
	var warp_x := x + terrain_noise.get_noise_2d(x * 0.004, z * 0.004) * 46.0
	var warp_z := z + terrain_noise.get_noise_2d(x * 0.004 + 117.0, z * 0.004 - 83.0) * 54.0
	var broad := terrain_noise.get_noise_2d(warp_x, warp_z) * 11.5
	var ridge_sample := ridge_noise.get_noise_2d(warp_x, warp_z)
	var ridges := pow(maxf(0.0, 1.0 - absf(ridge_sample)), 2.1) * 24.0
	var rolling := detail_noise.get_noise_2d(warp_x * 1.65, warp_z * 1.65) * 4.2
	var fine := detail_noise.get_noise_2d(warp_x * 4.2, warp_z * 4.2) * 0.72
	# Four broad, wind-cut ridge chains run across the valley with irregular shoulders.
	var ridge_axis_a := z - (174.0 + sin(x * 0.0065) * 46.0 + ridge_noise.get_noise_2d(x, z + 91.0) * 17.0)
	var ridge_axis_b := z - (72.0 + sin(x * 0.0080) * 34.0 + ridge_noise.get_noise_2d(x + 131.0, z) * 18.0)
	var ridge_axis_c := z - (-52.0 + sin(x * 0.0072) * 38.0 + ridge_noise.get_noise_2d(x - 83.0, z + 47.0) * 16.0)
	var ridge_axis_d := z - (-167.0 + sin(x * 0.0090) * 24.0 + ridge_noise.get_noise_2d(x + 193.0, z - 63.0) * 12.0)
	var ridge_a := 21.0 * exp(-pow(ridge_axis_a / 68.0, 2.0))
	var ridge_b := 24.0 * exp(-pow(ridge_axis_b / 58.0, 2.0))
	var ridge_c := 19.0 * exp(-pow(ridge_axis_c / 55.0, 2.0))
	var ridge_d := 13.0 * exp(-pow(ridge_axis_d / 44.0, 2.0))
	var gully_sample := absf(gully_noise.get_noise_2d(warp_x, warp_z))
	var gully_cut := pow(maxf(0.0, 0.22 - gully_sample), 2.0) * 105.0
	var lateral_shelf := 6.0 * exp(-pow((x - (118.0 + sin(z * 0.009) * 29.0)) / 48.0, 2.0))
	var valley := -5.5 * exp(-pow((z - 12.0) / 39.0, 2.0))
	var height := broad + rolling + fine + ridge_a + ridge_b + ridge_c + ridge_d + lateral_shelf - gully_cut + valley
	var attacker_trench: float = absf(z - (205.0 + sin(x * 0.055) * 2.2))
	var defender_trench: float = absf(z - (-205.0 + sin(x * 0.045) * 2.4))
	if attacker_trench < 3.0:
		height -= (1.0 - attacker_trench / 3.0) * 1.65
	if defender_trench < 3.0:
		height -= (1.0 - defender_trench / 3.0) * 1.75
	return height

func _soil_color(x: float, z: float, ground_height: float) -> Color:
	var broad_variation := terrain_noise.get_noise_2d(x * 0.31, z * 0.31)
	var fine_variation := detail_noise.get_noise_2d(x * 0.85, z * 0.85)
	var shade := broad_variation * 0.045 + fine_variation * 0.035
	var ridge_light := clampf((ground_height + 13.0) / 45.0, 0.0, 1.0) * 0.025
	if terrain_texture_enabled:
		# Near-white vertex tint lets the photographed reddish gravel PBR diffuse remain visible.
		return Color(
			clampf(0.94 + shade * 0.22 + ridge_light, 0.82, 1.0),
			clampf(0.91 + shade * 0.18 + ridge_light * 0.7, 0.80, 0.99),
			clampf(0.86 + shade * 0.12 + ridge_light * 0.4, 0.74, 0.96),
			1.0
		)
	return Color(
		clampf(0.39 + shade, 0.25, 0.48),
		clampf(0.295 + shade * 0.78, 0.18, 0.38),
		clampf(0.205 + shade * 0.58, 0.12, 0.29),
		1.0
	)

func _build_terrain() -> void:
	var half := MAP_SIZE * 0.5
	var step := MAP_SIZE / float(TERRAIN_DIVISIONS)
	var uv_scale := 0.18
	var grid_side := TERRAIN_DIVISIONS + 1
	var terrain_heights := PackedFloat32Array()
	var terrain_colors := PackedColorArray()
	terrain_heights.resize(grid_side * grid_side)
	terrain_colors.resize(grid_side * grid_side)
	for iz in range(grid_side):
		var z := -half + float(iz) * step
		for ix in range(grid_side):
			var x := -half + float(ix) * step
			var sample_index := iz * grid_side + ix
			var sample_height := _terrain_height(x, z)
			terrain_heights[sample_index] = sample_height
			terrain_colors[sample_index] = _soil_color(x, z, sample_height)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(earth_material)
	for ix in range(TERRAIN_DIVISIONS):
		for iz in range(TERRAIN_DIVISIONS):
			var x0 := -half + float(ix) * step
			var x1 := x0 + step
			var z0 := -half + float(iz) * step
			var z1 := z0 + step
			var i00 := iz * grid_side + ix
			var i10 := i00 + 1
			var i01 := i00 + grid_side
			var i11 := i01 + 1
			var p00 := Vector3(x0, terrain_heights[i00], z0)
			var p10 := Vector3(x1, terrain_heights[i10], z0)
			var p01 := Vector3(x0, terrain_heights[i01], z1)
			var p11 := Vector3(x1, terrain_heights[i11], z1)
			# Godot triangle fronts are clockwise. Keep the collision triangles front-facing
			# from above while flipping the generated normals back toward +Y.
			tool.set_color(terrain_colors[i00])
			tool.set_uv(Vector2(x0 * uv_scale, z0 * uv_scale))
			tool.add_vertex(p00)
			tool.set_color(terrain_colors[i10])
			tool.set_uv(Vector2(x1 * uv_scale, z0 * uv_scale))
			tool.add_vertex(p10)
			tool.set_color(terrain_colors[i01])
			tool.set_uv(Vector2(x0 * uv_scale, z1 * uv_scale))
			tool.add_vertex(p01)
			tool.set_color(terrain_colors[i10])
			tool.set_uv(Vector2(x1 * uv_scale, z0 * uv_scale))
			tool.add_vertex(p10)
			tool.set_color(terrain_colors[i11])
			tool.set_uv(Vector2(x1 * uv_scale, z1 * uv_scale))
			tool.add_vertex(p11)
			tool.set_color(terrain_colors[i01])
			tool.set_uv(Vector2(x0 * uv_scale, z1 * uv_scale))
			tool.add_vertex(p01)
	tool.index()
	tool.generate_normals()
	tool.generate_tangents()
	var terrain_mesh := tool.commit()
	var terrain := MeshInstance3D.new()
	terrain.name = "BattlefieldTerrain"
	terrain.mesh = terrain_mesh
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = grid_side
	heightmap.map_depth = grid_side
	var height_samples := terrain_heights.duplicate()
	for i in range(height_samples.size()):
		# HeightMapShape3D samples a unit grid; use one uniform scale on all
		# axes and pre-scale the stored heights back to world units.
		height_samples[i] /= step
	heightmap.map_data = height_samples
	var shape := CollisionShape3D.new()
	shape.name = "HeightmapCollision"
	shape.shape = heightmap
	shape.scale = Vector3(step, step, step)
	body.add_child(shape)
	add_child(body)

func _build_approach_track() -> void:
	var track_material := _make_material(Color(0.255, 0.192, 0.128))
	track_material.roughness = 1.0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(track_material)
	var segments := 132
	for i in range(segments):
		var z0 := 282.0 - float(i) * 4.35
		var z1 := z0 - 4.35
		var center0 := sin(z0 * 0.014) * 11.0
		var center1 := sin(z1 * 0.014) * 11.0
		var width0 := 4.2 + sin(float(i) * 0.19) * 0.55
		var width1 := 4.2 + sin(float(i + 1) * 0.19) * 0.55
		var left0 := Vector3(center0 - width0, _terrain_height(center0 - width0, z0) + 0.075, z0)
		var right0 := Vector3(center0 + width0, _terrain_height(center0 + width0, z0) + 0.075, z0)
		var left1 := Vector3(center1 - width1, _terrain_height(center1 - width1, z1) + 0.075, z1)
		var right1 := Vector3(center1 + width1, _terrain_height(center1 + width1, z1) + 0.075, z1)
		tool.add_vertex(left0)
		tool.add_vertex(right0)
		tool.add_vertex(left1)
		tool.add_vertex(right0)
		tool.add_vertex(right1)
		tool.add_vertex(left1)
	tool.generate_normals()
	var track := MeshInstance3D.new()
	track.name = "DustyApproachTrack"
	track.mesh = tool.commit()
	track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(track)

func _build_cover_layout() -> void:
	# Forward attacker cover, separated from the main defensive line by a long open approach.
	_build_trench_line(205.0, -46.0, 46.0, 27, "AttackerForwardTrench")
	_build_trench_line(-205.0, -64.0, 64.0, 35, "DefenderMainTrench")
	_build_trench_line(-258.0, -38.0, 38.0, 22, "DefenderFallbackTrench")

	# Irregular stone and brick firing positions on the rolling approach.
	for i in range(12):
		var x := -95.0 + float(i) * 17.0
		var z := 45.0 + sin(float(i) * 0.82) * 18.0
		_add_cover("ApproachStoneCover", Vector3(x, _terrain_height(x, z) + 0.65, z), Vector3(2.8, 1.3, 1.0), stone_material, 2200.0, 0.82)

	_add_house(Vector3(-47.0, 0.0, -250.0), Vector2(14.0, 11.0), brick_material, "WestDefenderHouse")
	_add_house(Vector3(53.0, 0.0, -272.0), Vector2(16.0, 12.0), stone_material, "EastDefenderHouse")

	# Short walls and staggered barriers around the two defensive buildings.
	for i in range(8):
		var x := -78.0 + float(i) * 4.0
		_add_cover("BrickDefensiveWall", Vector3(x, _terrain_height(x, -242.0) + 0.7, -242.0), Vector3(3.7, 1.4, 0.55), brick_material, 1500.0, 0.72)
	for i in range(9):
		var x := 32.0 + float(i) * 4.0
		_add_cover("StoneDefensiveWall", Vector3(x, _terrain_height(x, -286.0) + 0.75, -286.0), Vector3(3.5, 1.5, 0.7), stone_material, 2400.0, 0.95)

func _build_trench_line(center_z: float, x_start: float, x_end: float, count: int, prefix: String) -> void:
	for i in range(count):
		var t := float(i) / float(maxi(count - 1, 1))
		var x: float = lerpf(x_start, x_end, t)
		var z := center_z + sin(float(i) * 0.43) * 1.5
		var ground := _terrain_height(x, z)
		for row in range(2):
			var offset_x: float = x + (0.45 if row == 1 else 0.0)
			var offset_z: float = z + (0.12 if row == 1 else 0.0)
			_add_cover(prefix + "_Sandbag", Vector3(offset_x, ground + 0.30 + float(row) * 0.48, offset_z), Vector3(1.9, 0.56, 0.82), sandbag_material, 580.0, 0.22)

func _add_house(center: Vector3, footprint: Vector2, material: StandardMaterial3D, house_name: String) -> void:
	var x := center.x
	var z := center.z
	var ground := _terrain_height(x, z)
	var width := footprint.x
	var depth := footprint.y
	var wall_height := 3.2
	var wall_y := ground + wall_height * 0.5
	_add_cover(house_name + "_NorthWall", Vector3(x, wall_y, z - depth * 0.5), Vector3(width, wall_height, 0.55), material, 3600.0, 1.05)
	_add_cover(house_name + "_SouthWall", Vector3(x, wall_y, z + depth * 0.5), Vector3(width, wall_height, 0.55), material, 3600.0, 1.05)
	_add_cover(house_name + "_WestWall", Vector3(x - width * 0.5, wall_y, z), Vector3(0.55, wall_height, depth), material, 3600.0, 1.05)
	_add_cover(house_name + "_EastWall", Vector3(x + width * 0.5, wall_y, z), Vector3(0.55, wall_height, depth), material, 3600.0, 1.05)
	_add_cover(house_name + "_Roof", Vector3(x, ground + wall_height + 0.22, z), Vector3(width + 0.5, 0.45, depth + 0.5), dark_material, 4200.0, 1.2)

func _add_cover(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, durability: float, armor_rating: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_script(COVER_SCRIPT)
	body.set("integrity", durability)
	body.set("armor_rating", armor_rating)
	body.add_to_group("destructible_cover")

	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = material
	body.add_child(visual)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body

func _scatter_ground_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 741207
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.56
	rock_mesh.height = 0.92
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = rock_mesh
	multi.instance_count = 520
	for i in range(multi.instance_count):
		var x := rng.randf_range(-335.0, 335.0)
		var z := rng.randf_range(-335.0, 335.0)
		var y := _terrain_height(x, z) + 0.08
		var scale := Vector3(rng.randf_range(0.65, 1.8), rng.randf_range(0.28, 0.68), rng.randf_range(0.65, 1.6))
		var basis := Basis().scaled(scale)
		multi.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
	var rocks := MultiMeshInstance3D.new()
	rocks.name = "DryGroundStones"
	rocks.multimesh = multi
	rocks.material_override = stone_material
	rocks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rocks)

func _place_distant_defenders() -> void:
	var positions: Array[Vector2] = [
		Vector2(-54.0, -198.0), Vector2(-39.0, -199.0), Vector2(-17.0, -203.0),
		Vector2(6.0, -200.0), Vector2(27.0, -207.0), Vector2(47.0, -204.0),
		Vector2(62.0, -211.0), Vector2(-62.0, -256.0), Vector2(22.0, -261.0)
	]
	for i in range(positions.size()):
		var point := positions[i]
		var soldier := Node3D.new()
		soldier.name = "DistantDefender_%02d" % i
		soldier.position = Vector3(point.x, _terrain_height(point.x, point.y), point.y)
		var torso := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.22
		capsule.height = 1.12
		torso.mesh = capsule
		torso.position.y = 0.82
		torso.material_override = soldier_material
		soldier.add_child(torso)
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		head.mesh = sphere
		head.position.y = 1.48
		head.material_override = soldier_material
		soldier.add_child(head)
		add_child(soldier)

func _spawn_player() -> void:
	player = PLAYER_SCRIPT.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(0.0, _terrain_height(0.0, 278.0) + 0.12, 278.0)

func _create_hud() -> void:
	hud = HUD_SCRIPT.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_battle_status("PLATEAU SECTOR 01  |  DAY  |  DEFENDERS: DISTANT")
	if player != null and player.has_method("attach_hud"):
		player.attach_hud(hud)
		var weapon_node := player.get_node_or_null("WeaponController")
		if weapon_node != null:
			hud.connect("weapon_selected", Callable(weapon_node, "select_weapon"))
		hud.connect("sensitivity_adjust_requested", Callable(player, "adjust_sensitivity"))
		hud.connect("night_toggle_requested", Callable(self, "_toggle_night_from_hud"))
		if weapon_node != null and weapon_node.has_method("cycle_ammo_type"):
			hud.connect("ammo_type_changed", Callable(weapon_node, "cycle_ammo_type"))

func _toggle_night_from_hud() -> void:
	_set_night_mode(not night_mode)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			_set_night_mode(not night_mode)

func _set_night_mode(enabled: bool) -> void:
	night_mode = enabled
	if sun != null:
		sun.light_energy = 0.14 if night_mode else 1.15
	if world_environment != null:
		world_environment.environment.ambient_light_energy = 0.24 if night_mode else 0.75
		world_environment.environment.fog_light_color = Color(0.035, 0.045, 0.075) if night_mode else Color(0.64, 0.55, 0.43)
		world_environment.environment.fog_density = 0.04 if night_mode else 0.055
	if sky_material != null:
		sky_material.sky_top_color = Color(0.012, 0.018, 0.035) if night_mode else Color(0.27, 0.34, 0.39)
		sky_material.sky_horizon_color = Color(0.055, 0.065, 0.09) if night_mode else Color(0.72, 0.61, 0.45)
	if hud != null:
		hud.set_battle_status("PLATEAU SECTOR 01  |  NIGHT" if night_mode else "PLATEAU SECTOR 01  |  DAY")
