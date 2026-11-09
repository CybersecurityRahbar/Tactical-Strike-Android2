extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player/player_controller.gd")
const HUD_SCRIPT = preload("res://scripts/ui/hud.gd")
const COVER_SCRIPT = preload("res://scripts/world/cover_piece.gd")
const TARGET_SCRIPT = preload("res://scripts/world/combat_target.gd")

const MAP_SIZE := 700.0
const TERRAIN_DIVISIONS := 256
const PLAYER_SPAWN_Z := 302.0
const DEFENDER_LINE_Z := -196.0

var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var gully_noise := FastNoiseLite.new()
var terrain_texture_enabled := false
var sun: DirectionalLight3D
var fill_light: DirectionalLight3D
var world_environment: WorldEnvironment
var sky_material: ProceduralSkyMaterial
var hud: CanvasLayer
var player: CharacterBody3D
var night_mode := false
var target_count := 0

var soil_material: StandardMaterial3D
var rock_material: StandardMaterial3D
var sandbag_material: StandardMaterial3D
var brick_material: StandardMaterial3D
var stone_material: StandardMaterial3D
var dark_material: StandardMaterial3D
var shrub_material: StandardMaterial3D

func _ready() -> void:
	_setup_noise()
	_create_materials()
	_build_environment()
	_build_terrain()
	_build_cover_layout()
	_build_approach_track()
	_scatter_ground_details()
	_place_defenders()
	_spawn_player()
	_create_hud()

func _setup_noise() -> void:
	terrain_noise.seed = 20261109
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_noise.frequency = 0.0038
	terrain_noise.fractal_octaves = 5
	terrain_noise.fractal_lacunarity = 2.0
	terrain_noise.fractal_gain = 0.48
	terrain_noise.domain_warp_enabled = true
	terrain_noise.domain_warp_amplitude = 46.0
	terrain_noise.domain_warp_frequency = 0.0032
	terrain_noise.domain_warp_fractal_octaves = 3

	detail_noise.seed = 741209
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.022
	detail_noise.fractal_octaves = 4
	detail_noise.fractal_lacunarity = 2.1
	detail_noise.fractal_gain = 0.52

	# Ridged multifractal source for rocky massifs around the basin.
	ridge_noise.seed = 20261111
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge_noise.frequency = 0.017
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge_noise.fractal_octaves = 5
	ridge_noise.fractal_lacunarity = 2.15
	ridge_noise.fractal_gain = 0.52

	gully_noise.seed = 20261112
	gully_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	gully_noise.frequency = 0.0055
	gully_noise.fractal_octaves = 3
	gully_noise.fractal_lacunarity = 2.0
	gully_noise.fractal_gain = 0.47

func _ridged(x: float, z: float) -> float:
	# FastNoiseLite returns -1..1; ridged fractal type already folds its output,
	# so remap smoothly into 0..1 for mountain amplitude.
	var n := ridge_noise.get_noise_2d(x, z)
	return clampf(n * 0.5 + 0.5, 0.0, 1.0)

func _create_materials() -> void:
	soil_material = _make_material(Color.WHITE)
	soil_material.vertex_color_use_as_albedo = true
	soil_material.cull_mode = BaseMaterial3D.CULL_BACK
	soil_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var diffuse_path := "res://assets/runtime/terrain/rocky_gravel_diff_1k.jpg"
	var normal_path := "res://assets/runtime/terrain/rocky_gravel_nor_gl_1k.jpg"
	var roughness_path := "res://assets/runtime/terrain/rocky_gravel_rough_1k.jpg"
	if ResourceLoader.exists(diffuse_path):
		soil_material.albedo_texture = load(diffuse_path) as Texture2D
		terrain_texture_enabled = soil_material.albedo_texture != null
	if ResourceLoader.exists(normal_path):
		soil_material.normal_enabled = true
		soil_material.normal_texture = load(normal_path) as Texture2D
		soil_material.normal_scale = 1.15
	if ResourceLoader.exists(roughness_path):
		soil_material.roughness_texture = load(roughness_path) as Texture2D
	soil_material.roughness = 0.96
	soil_material.metallic = 0.0

	# Rock shares the same PBR maps but renders triplanar so cliff faces never
	# stretch, and is tinted cooler through vertex colour.
	rock_material = _make_material(Color.WHITE)
	rock_material.vertex_color_use_as_albedo = true
	rock_material.cull_mode = BaseMaterial3D.CULL_BACK
	rock_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	rock_material.uv1_triplanar = true
	rock_material.uv1_scale = Vector3(0.055, 0.055, 0.055)
	if ResourceLoader.exists(diffuse_path):
		rock_material.albedo_texture = load(diffuse_path) as Texture2D
	if ResourceLoader.exists(normal_path):
		rock_material.normal_enabled = true
		rock_material.normal_texture = load(normal_path) as Texture2D
		rock_material.normal_scale = 1.9
	if ResourceLoader.exists(roughness_path):
		rock_material.roughness_texture = load(roughness_path) as Texture2D
	rock_material.roughness = 0.88

	sandbag_material = _make_material(Color(0.52, 0.45, 0.31))
	sandbag_material.roughness = 1.0
	brick_material = _make_material(Color(0.44, 0.31, 0.24))
	stone_material = _make_material(Color(0.47, 0.45, 0.41))
	dark_material = _make_material(Color(0.16, 0.15, 0.13))
	shrub_material = _make_material(Color(0.24, 0.26, 0.16))
	shrub_material.roughness = 1.0

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
	sky_material.sky_top_color = Color(0.27, 0.40, 0.56)
	sky_material.sky_horizon_color = Color(0.74, 0.68, 0.57)
	sky_material.sky_curve = 0.18
	sky_material.ground_bottom_color = Color(0.20, 0.17, 0.13)
	sky_material.ground_horizon_color = Color(0.52, 0.44, 0.33)
	sky_material.sun_angle_max = 14.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.62
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.02
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 1.04
	# Aerial perspective: distant massifs fade into warm haze instead of
	# ending in a hard fog wall.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = 320.0
	environment.fog_depth_end = 2300.0
	environment.fog_depth_curve = 0.85
	environment.fog_density = 0.014
	environment.fog_light_color = Color(0.66, 0.58, 0.46)
	environment.fog_sky_affect = 0.28
	environment.fog_height = 10.0
	environment.fog_height_density = 0.08
	environment.glow_enabled = true
	environment.glow_intensity = 0.28
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.15
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-36.0, -124.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.32
	sun.shadow_enabled = true
	# Two shadow splits keep the mobile shadow pass affordable while still
	# covering the 300 m engagement area with crisp near shadows.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 200.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.20
	sun.directional_shadow_split_3 = 0.45
	sun.shadow_bias = 0.045
	sun.shadow_normal_bias = 1.2
	add_child(sun)

	# Cool sky bounce from the opposite side keeps shadowed rock readable
	# without flattening the terrain.
	fill_light = DirectionalLight3D.new()
	fill_light.name = "SkyFill"
	fill_light.rotation_degrees = Vector3(-24.0, 52.0, 0.0)
	fill_light.light_color = Color(0.55, 0.66, 0.85)
	fill_light.light_energy = 0.16
	fill_light.shadow_enabled = false
	add_child(fill_light)

func _terrain_height(x: float, z: float) -> float:
	var warp_x := x + terrain_noise.get_noise_2d(x * 0.0035, z * 0.0035) * 42.0
	var warp_z := z + terrain_noise.get_noise_2d(x * 0.0035 + 91.0, z * 0.0035 - 47.0) * 48.0

	# Central plain: broad, gentle, walkable.
	var broad := terrain_noise.get_noise_2d(warp_x, warp_z) * 4.6
	var detail := detail_noise.get_noise_2d(warp_x * 2.2, warp_z * 2.2) * 1.05
	var fine := detail_noise.get_noise_2d(warp_x * 7.0, warp_z * 7.0) * 0.26
	var basin := -1.6 * exp(-pow(z / 220.0, 2.0))

	# Two knee-high rises cross the plain. They give cover and rolling shape
	# without ever blocking the 300-500 m sightline the map is built around.
	var rise_a := 2.3 * exp(-pow((z - 116.0) / 54.0, 2.0))
	var rise_b := 2.6 * exp(-pow((z + 42.0) / 60.0, 2.0))
	var spawn_knoll := 4.8 * exp(-pow((z - 305.0) / 50.0, 2.0)) * exp(-pow(x / 120.0, 2.0))
	var defender_knoll := 9.2 * exp(-pow((z + 236.0) / 62.0, 2.0)) * exp(-pow(x / 150.0, 2.0))

	# Eastern massif: steep, ridged, rock-faced.
	var east := smoothstep(140.0, 330.0, x)
	var east_h := east * (30.0 + 118.0 * pow(_ridged(warp_x * 0.55, warp_z * 0.55), 1.25)
		+ terrain_noise.get_noise_2d(warp_x * 0.35, warp_z * 0.35) * 18.0)

	# Western plateau: a flat table top with a cliff edge, mountains behind.
	var west_edge := smoothstep(-148.0, -214.0, x)
	var west_top := 47.0 + detail_noise.get_noise_2d(x * 0.02, z * 0.02) * 1.7
	var west_h := west_edge * west_top
	var west_back := smoothstep(-238.0, -340.0, x) * (32.0 + 92.0 * _ridged(warp_x * 0.5 + 31.0, warp_z * 0.5))

	# Enclosing ridges close the horizon behind both ends of the valley.
	var north := smoothstep(-300.0, -350.0, z) * (44.0 + 92.0 * _ridged(warp_x * 0.7, warp_z * 0.7 + 12.0))
	var south := smoothstep(322.0, 350.0, z) * (30.0 + 58.0 * _ridged(warp_x * 0.7 + 19.0, warp_z * 0.7))

	# Dry wadis cut the plain into readable cover lanes.
	var basin_mask := (1.0 - east) * (1.0 - west_edge) * (1.0 - north) * (1.0 - south)
	var gully := pow(maxf(0.0, 0.17 - absf(gully_noise.get_noise_2d(warp_x * 1.35, warp_z * 1.35))), 2.0) * 240.0 * basin_mask

	var height := broad + detail + fine + basin + rise_a + rise_b + spawn_knoll + defender_knoll
	height += east_h + west_h + west_back + north + south - gully

	# Trenches carved along the attacker and defender lines.
	var attacker_trench: float = absf(z - (205.0 + sin(x * 0.055) * 2.2))
	var defender_trench: float = absf(z - (DEFENDER_LINE_Z + sin(x * 0.045) * 2.4))
	if attacker_trench < 3.0:
		height -= (1.0 - attacker_trench / 3.0) * 1.6
	if defender_trench < 3.0:
		height -= (1.0 - defender_trench / 3.0) * 1.7
	return height

func _terrain_normal(x: float, z: float) -> Vector3:
	var e := 1.6
	var dx := _terrain_height(x + e, z) - _terrain_height(x - e, z)
	var dz := _terrain_height(x, z + e) - _terrain_height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()

func _soil_color(x: float, z: float, ground_height: float) -> Color:
	var broad_variation := terrain_noise.get_noise_2d(x * 0.31, z * 0.31)
	var fine_variation := detail_noise.get_noise_2d(x * 0.85, z * 0.85)
	var shade := broad_variation * 0.05 + fine_variation * 0.035
	var altitude := clampf((ground_height - 4.0) / 55.0, 0.0, 1.0)
	var dry := Color(0.97, 0.90, 0.79)
	var high := Color(0.74, 0.72, 0.68)
	var tint := dry.lerp(high, altitude)
	if not terrain_texture_enabled:
		tint = Color(0.40, 0.31, 0.22).lerp(Color(0.46, 0.43, 0.39), altitude)
	return Color(
		clampf(tint.r + shade, 0.0, 1.0),
		clampf(tint.g + shade * 0.92, 0.0, 1.0),
		clampf(tint.b + shade * 0.82, 0.0, 1.0),
		1.0
	)

func _rock_color(x: float, z: float, ground_height: float) -> Color:
	var variation := detail_noise.get_noise_2d(x * 0.4, z * 0.4) * 0.06
	var base := Color(0.62, 0.60, 0.57).lerp(Color(0.50, 0.49, 0.47), clampf(ground_height / 140.0, 0.0, 1.0))
	return Color(clampf(base.r + variation, 0.0, 1.0), clampf(base.g + variation, 0.0, 1.0), clampf(base.b + variation, 0.0, 1.0), 1.0)

func _build_terrain() -> void:
	var half := MAP_SIZE * 0.5
	var step := MAP_SIZE / float(TERRAIN_DIVISIONS)
	var uv_scale := 0.085
	var grid_side := TERRAIN_DIVISIONS + 1
	var terrain_heights := PackedFloat32Array()
	var terrain_colors := PackedColorArray()
	var rock_colors := PackedColorArray()
	terrain_heights.resize(grid_side * grid_side)
	terrain_colors.resize(grid_side * grid_side)
	rock_colors.resize(grid_side * grid_side)
	for iz in range(grid_side):
		var z := -half + float(iz) * step
		for ix in range(grid_side):
			var x := -half + float(ix) * step
			var sample_index := iz * grid_side + ix
			var sample_height := _terrain_height(x, z)
			terrain_heights[sample_index] = sample_height
			terrain_colors[sample_index] = _soil_color(x, z, sample_height)
			rock_colors[sample_index] = _rock_color(x, z, sample_height)

	var soil_tool := SurfaceTool.new()
	soil_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	soil_tool.set_material(soil_material)
	var rock_tool := SurfaceTool.new()
	rock_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	rock_tool.set_material(rock_material)
	var soil_triangles := 0
	var rock_triangles := 0
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
			# Two triangles per cell; classify by slope and altitude so cliffs and
			# peaks use the triplanar rock surface while the plain keeps soil.
			var quad_normal := (p10 - p00).cross(p01 - p00).normalized()
			var average_height := (terrain_heights[i00] + terrain_heights[i10] + terrain_heights[i01] + terrain_heights[i11]) * 0.25
			var is_rock := absf(quad_normal.y) < 0.74 or average_height > 42.0
			if is_rock:
				# Triplanar shading ignores these UVs, but tangents (needed by the
				# normal map) can only be generated when a UV channel exists.
				_add_terrain_triangle(rock_tool, p00, p10, p01, rock_colors, i00, i10, i01, 0.06, true)
				_add_terrain_triangle(rock_tool, p10, p11, p01, rock_colors, i10, i11, i01, 0.06, true)
				rock_triangles += 2
			else:
				_add_terrain_triangle(soil_tool, p00, p10, p01, terrain_colors, i00, i10, i01, uv_scale, true)
				_add_terrain_triangle(soil_tool, p10, p11, p01, terrain_colors, i10, i11, i01, uv_scale, true)
				soil_triangles += 2
	soil_tool.index()
	soil_tool.generate_normals()
	soil_tool.generate_tangents()
	var soil_mesh := soil_tool.commit()
	var soil_instance := MeshInstance3D.new()
	soil_instance.name = "BattlefieldTerrain"
	soil_instance.mesh = soil_mesh
	soil_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(soil_instance)

	rock_tool.index()
	rock_tool.generate_normals()
	rock_tool.generate_tangents()
	var rock_mesh := rock_tool.commit()
	var rock_instance := MeshInstance3D.new()
	rock_instance.name = "BattlefieldRock"
	rock_instance.mesh = rock_mesh
	rock_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rock_instance)

	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("terrain")
	body.set_meta("surface", "dirt")
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = grid_side
	heightmap.map_depth = grid_side
	var height_samples := terrain_heights.duplicate()
	for i in range(height_samples.size()):
		height_samples[i] /= step
	heightmap.map_data = height_samples
	var shape := CollisionShape3D.new()
	shape.name = "HeightmapCollision"
	shape.shape = heightmap
	shape.scale = Vector3(step, step, step)
	body.add_child(shape)
	add_child(body)

func _add_terrain_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colors: PackedColorArray, ia: int, ib: int, ic: int, uv_scale: float, with_uv: bool) -> void:
	tool.set_color(colors[ia])
	if with_uv:
		tool.set_uv(Vector2(a.x * uv_scale, a.z * uv_scale))
	tool.add_vertex(a)
	tool.set_color(colors[ib])
	if with_uv:
		tool.set_uv(Vector2(b.x * uv_scale, b.z * uv_scale))
	tool.add_vertex(b)
	tool.set_color(colors[ic])
	if with_uv:
		tool.set_uv(Vector2(c.x * uv_scale, c.z * uv_scale))
	tool.add_vertex(c)

func _build_approach_track() -> void:
	var track_material := _make_material(Color(0.30, 0.235, 0.16))
	track_material.roughness = 1.0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(track_material)
	var segments := 128
	for i in range(segments):
		var z0 := 286.0 - float(i) * 4.6
		var z1 := z0 - 4.6
		var center0 := sin(z0 * 0.014) * 9.0
		var center1 := sin(z1 * 0.014) * 9.0
		var width0 := 4.6 + sin(float(i) * 0.19) * 0.6
		var width1 := 4.6 + sin(float(i + 1) * 0.19) * 0.6
		var left0 := Vector3(center0 - width0, _terrain_height(center0 - width0, z0) + 0.06, z0)
		var right0 := Vector3(center0 + width0, _terrain_height(center0 + width0, z0) + 0.06, z0)
		var left1 := Vector3(center1 - width1, _terrain_height(center1 - width1, z1) + 0.06, z1)
		var right1 := Vector3(center1 + width1, _terrain_height(center1 + width1, z1) + 0.06, z1)
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
	_build_trench_line(205.0, -48.0, 48.0, 27, "AttackerForwardTrench")
	_build_trench_line(DEFENDER_LINE_Z, -64.0, 64.0, 35, "DefenderMainTrench")
	_build_trench_line(-262.0, -40.0, 40.0, 22, "DefenderFallbackTrench")

	# Stone firing positions scattered across the plain.
	for i in range(12):
		var x := -96.0 + float(i) * 17.5
		var z := 62.0 + sin(float(i) * 0.82) * 20.0
		_add_cover("ApproachStoneCover", Vector3(x, _terrain_height(x, z) + 0.65, z), Vector3(2.8, 1.3, 1.0), stone_material, "stone", 2400.0, 0.82)

	_add_house(Vector3(-74.0, 0.0, -248.0), Vector2(14.0, 11.0), brick_material, "brick", "WestDefenderHouse")
	_add_house(Vector3(78.0, 0.0, -266.0), Vector2(16.0, 12.0), stone_material, "stone", "EastDefenderHouse")

	for i in range(8):
		var x := -78.0 + float(i) * 4.0
		_add_cover("BrickDefensiveWall", Vector3(x, _terrain_height(x, -238.0) + 0.7, -238.0), Vector3(3.7, 1.4, 0.55), brick_material, "brick", 1500.0, 0.72)
	for i in range(9):
		var x := 32.0 + float(i) * 4.0
		_add_cover("StoneDefensiveWall", Vector3(x, _terrain_height(x, -284.0) + 0.75, -284.0), Vector3(3.5, 1.5, 0.7), stone_material, "stone", 2400.0, 0.95)

func _build_trench_line(center_z: float, x_start: float, x_end: float, count: int, prefix: String) -> void:
	for i in range(count):
		var t := float(i) / float(maxi(count - 1, 1))
		var x: float = lerpf(x_start, x_end, t)
		var z := center_z + sin(float(i) * 0.43) * 1.5
		var ground := _terrain_height(x, z)
		for row in range(2):
			var offset_x: float = x + (0.45 if row == 1 else 0.0)
			var offset_z: float = z + (0.12 if row == 1 else 0.0)
			_add_cover(prefix + "_Sandbag", Vector3(offset_x, ground + 0.30 + float(row) * 0.48, offset_z), Vector3(1.9, 0.56, 0.82), sandbag_material, "sand", 580.0, 0.22)

func _add_house(center: Vector3, footprint: Vector2, material: StandardMaterial3D, surface: String, house_name: String) -> void:
	var x := center.x
	var z := center.z
	var ground := _terrain_height(x, z)
	var width := footprint.x
	var depth := footprint.y
	var wall_height := 3.2
	var wall_y := ground + wall_height * 0.5
	_add_cover(house_name + "_NorthWall", Vector3(x, wall_y, z - depth * 0.5), Vector3(width, wall_height, 0.55), material, surface, 3600.0, 1.05)
	_add_cover(house_name + "_SouthWall", Vector3(x, wall_y, z + depth * 0.5), Vector3(width, wall_height, 0.55), material, surface, 3600.0, 1.05)
	_add_cover(house_name + "_WestWall", Vector3(x - width * 0.5, wall_y, z), Vector3(0.55, wall_height, depth), material, surface, 3600.0, 1.05)
	_add_cover(house_name + "_EastWall", Vector3(x + width * 0.5, wall_y, z), Vector3(0.55, wall_height, depth), material, surface, 3600.0, 1.05)
	_add_cover(house_name + "_Roof", Vector3(x, ground + wall_height + 0.22, z), Vector3(width + 0.5, 0.45, depth + 0.5), dark_material, surface, 4200.0, 1.2)

func _add_cover(node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D, surface: String, durability: float, armor_rating: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_script(COVER_SCRIPT)
	body.set("integrity", durability)
	body.set("max_integrity", durability)
	body.set("armor_rating", armor_rating)
	body.set("surface", surface)
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

func _make_rock_mesh(radius: float, stretch: Vector3, seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 7
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i in range(vertices.size()):
			indices.append(i)
	for i in range(0, indices.size(), 3):
		for k in range(3):
			var v: Vector3 = vertices[indices[i + k]]
			var noise := detail_noise.get_noise_3d(v.x * 7.0, v.y * 7.0, v.z * 7.0) * 0.22
			var jitter := Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.06, 0.06))
			var deformed := (v * (1.0 + noise)).normalized() * radius * (1.0 + noise)
			deformed = deformed * stretch + jitter
			tool.add_vertex(deformed)
	tool.generate_normals()
	return tool.commit()

func _scatter_ground_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 771213
	_scatter_multimesh("MountainBoulders", _make_rock_mesh(1.0, Vector3(1.0, 0.72, 1.35), 3301), 240, rng, 2.6, 7.5, true)
	_scatter_multimesh("GroundStones", _make_rock_mesh(1.0, Vector3(1.0, 0.5, 1.1), 3302), 620, rng, 0.35, 1.6, false)
	_scatter_multimesh("MountainScree", _make_rock_mesh(1.0, Vector3(1.0, 0.42, 1.2), 3303), 900, rng, 0.14, 0.55, false)
	_scatter_shrubs(rng)

func _scatter_multimesh(node_name: String, mesh: Mesh, count: int, rng: RandomNumberGenerator, min_scale: float, max_scale: float, requires_slope: bool) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 12:
		attempts += 1
		var x := rng.randf_range(-338.0, 338.0)
		var z := rng.randf_range(-338.0, 338.0)
		var normal := _terrain_normal(x, z)
		var height := _terrain_height(x, z)
		if requires_slope:
			if normal.y > 0.86 or height < 16.0:
				continue
		else:
			if normal.y < 0.90 or height > 34.0:
				continue
		var size := rng.randf_range(min_scale, max_scale)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12)))
		basis = basis.scaled(Vector3(size, size * rng.randf_range(0.7, 1.1), size))
		multi.set_instance_transform(placed, Transform3D(basis, Vector3(x, height - size * 0.18, z)))
		placed += 1
	multi.instance_count = placed
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = stone_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _scatter_shrubs(rng: RandomNumberGenerator) -> void:
	var bush := SphereMesh.new()
	bush.radius = 0.42
	bush.height = 0.8
	bush.radial_segments = 5
	bush.rings = 3
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = bush
	multi.instance_count = 460
	var placed := 0
	var attempts := 0
	while placed < 460 and attempts < 6000:
		attempts += 1
		var x := rng.randf_range(-140.0, 145.0)
		var z := rng.randf_range(-290.0, 300.0)
		var height := _terrain_height(x, z)
		if height > 26.0 or _terrain_normal(x, z).y < 0.93:
			continue
		var size := rng.randf_range(0.6, 1.5)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(size, size * 0.55, size))
		multi.set_instance_transform(placed, Transform3D(basis, Vector3(x, height + size * 0.18, z)))
		placed += 1
	multi.instance_count = placed
	var instance := MultiMeshInstance3D.new()
	instance.name = "DryShrubs"
	instance.multimesh = multi
	instance.material_override = shrub_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _place_defenders() -> void:
	var main_line := [
		Vector2(-56.0, -190.0), Vector2(-37.0, -193.0), Vector2(-15.0, -191.0),
		Vector2(8.0, -194.0), Vector2(30.0, -196.0), Vector2(52.0, -199.0),
		Vector2(-66.0, -244.0), Vector2(24.0, -252.0), Vector2(72.0, -236.0)
	]
	# Three exposed forward sentries: the first engagement at ~320 m.
	var sentries := [Vector2(-26.0, -18.0), Vector2(6.0, -24.0), Vector2(33.0, -14.0)]
	var all_positions: Array = []
	all_positions.append_array(sentries)
	all_positions.append_array(main_line)
	for i in range(all_positions.size()):
		var point: Vector2 = all_positions[i]
		var soldier := TARGET_SCRIPT.new()
		soldier.name = "Defender_%02d" % i
		add_child(soldier)
		soldier.global_position = Vector3(point.x, _terrain_height(point.x, point.y) + 0.02, point.y)
		soldier.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		soldier.damaged.connect(_on_target_damaged)
		target_count += 1

func _on_target_damaged(distance_m: float, killed: bool) -> void:
	if hud == null:
		return
	if killed:
		hud.set_message("TARGET DOWN — %.0f m" % distance_m)
	else:
		hud.set_message("HIT — %.0f m" % distance_m)

func _spawn_player() -> void:
	player = PLAYER_SCRIPT.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(0.0, _terrain_height(0.0, PLAYER_SPAWN_Z) + 0.12, PLAYER_SPAWN_Z)

func _create_hud() -> void:
	hud = HUD_SCRIPT.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_battle_status("PLATEAU SECTOR 01  |  DAY  |  TARGETS: %d" % target_count)
	if player != null and player.has_method("attach_hud"):
		player.attach_hud(hud)
		var weapon_node := player.get_node_or_null("WeaponController")
		if weapon_node != null:
			hud.connect("weapon_selected", Callable(weapon_node, "select_weapon"))
			hud.connect("sensitivity_adjust_requested", Callable(player, "adjust_sensitivity"))
			hud.connect("night_toggle_requested", Callable(self, "_toggle_night_from_hud"))
			if weapon_node.has_method("cycle_ammo_type"):
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
		sun.light_energy = 0.10 if night_mode else 1.32
		sun.light_color = Color(0.62, 0.70, 0.95) if night_mode else Color(1.0, 0.94, 0.84)
	if fill_light != null:
		fill_light.light_energy = 0.05 if night_mode else 0.16
	if world_environment != null:
		var environment := world_environment.environment
		environment.ambient_light_energy = 0.10 if night_mode else 0.62
		environment.fog_light_color = Color(0.03, 0.04, 0.07) if night_mode else Color(0.66, 0.58, 0.46)
		environment.fog_density = 0.02 if night_mode else 0.014
	if sky_material != null:
		sky_material.sky_top_color = Color(0.010, 0.016, 0.032) if night_mode else Color(0.27, 0.40, 0.56)
		sky_material.sky_horizon_color = Color(0.045, 0.055, 0.08) if night_mode else Color(0.74, 0.68, 0.57)
		sky_material.ground_horizon_color = Color(0.03, 0.035, 0.05) if night_mode else Color(0.52, 0.44, 0.33)
	if hud != null:
		hud.set_battle_status("PLATEAU SECTOR 01  |  NIGHT  |  TARGETS: %d" % target_count if night_mode else "PLATEAU SECTOR 01  |  DAY  |  TARGETS: %d" % target_count)
