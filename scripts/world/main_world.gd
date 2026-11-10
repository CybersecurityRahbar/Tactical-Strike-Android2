extends Node3D

# Green village map, built for Squad-style play.
#
# Layout (north is -Z):
#   * South: attacker spawn, a dirt road, open fields split by hedgerows and
#     dry-stone walls, a farm compound (objective A).
#   * Centre: a village of walled courtyards around a crossroads with a
#     fountain, two-storey houses for overwatch (objective B).
#   * North: farm sheds and a walled yard on rising ground (objective C), with
#     Radio Hill in the north-east as the map's dominant feature.
#
# Three capture points sit along that axis. Both sides spawn squads of AI
# soldiers, they fight over the points, and the HUD reports who holds what.

const PLAYER_SCRIPT = preload("res://scripts/player/player_controller.gd")
const HUD_SCRIPT = preload("res://scripts/ui/hud.gd")
const COVER_SCRIPT = preload("res://scripts/world/cover_piece.gd")
const TARGET_SCRIPT = preload("res://scripts/world/combat_target.gd")

const MAP_SIZE := 700.0
const TERRAIN_DIVISIONS := 256
const PLAYER_SPAWN := Vector3(-6.0, 0.0, 224.0)

var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var terrain_texture_enabled := false
var sun: DirectionalLight3D
var fill_light: DirectionalLight3D
var world_environment: WorldEnvironment
var sky_material: ProceduralSkyMaterial
var hud: CanvasLayer
var player: CharacterBody3D
var night_mode := false
var target_count := 0
var capture_points: Array[Dictionary] = []
var soldiers: Array[Node3D] = []
var status_timer := 0.0

var soil_material: StandardMaterial3D
var rock_material: StandardMaterial3D
var sandbag_material: StandardMaterial3D
var brick_material: StandardMaterial3D
var stone_material: StandardMaterial3D
var dark_material: StandardMaterial3D
var shrub_material: StandardMaterial3D
var wood_material: StandardMaterial3D
var metal_material: StandardMaterial3D
var road_material: StandardMaterial3D
var leaf_material: StandardMaterial3D

# Wall / building vocabulary used by the village builder.
const COMPOUNDS := [
	{"c": Vector2(-56.0, -44.0), "s": Vector2(38.0, 34.0), "b": Vector2(15.0, 12.0), "floors": 2, "mat": "brick"},
	{"c": Vector2(62.0, -46.0), "s": Vector2(36.0, 32.0), "b": Vector2(17.0, 13.0), "floors": 2, "mat": "stone"},
	{"c": Vector2(-62.0, 40.0), "s": Vector2(36.0, 32.0), "b": Vector2(14.0, 12.0), "floors": 1, "mat": "stone"},
	{"c": Vector2(66.0, 38.0), "s": Vector2(34.0, 30.0), "b": Vector2(15.0, 11.0), "floors": 2, "mat": "brick"},
	{"c": Vector2(-124.0, -4.0), "s": Vector2(30.0, 42.0), "b": Vector2(12.0, 17.0), "floors": 1, "mat": "stone"},
	{"c": Vector2(126.0, 2.0), "s": Vector2(30.0, 38.0), "b": Vector2(12.0, 15.0), "floors": 2, "mat": "brick"},
	{"c": Vector2(-34.0, -128.0), "s": Vector2(46.0, 38.0), "b": Vector2(20.0, 13.0), "floors": 1, "mat": "stone"},
	{"c": Vector2(36.0, 130.0), "s": Vector2(42.0, 34.0), "b": Vector2(18.0, 12.0), "floors": 1, "mat": "brick"},
]

const HEDGES := [
	[Vector2(-340.0, 96.0), Vector2(-150.0, 88.0)],
	[Vector2(140.0, 92.0), Vector2(340.0, 100.0)],
	[Vector2(-336.0, 190.0), Vector2(-120.0, 176.0)],
	[Vector2(112.0, 186.0), Vector2(336.0, 196.0)],
	[Vector2(-96.0, 120.0), Vector2(-88.0, 250.0)],
	[Vector2(96.0, 122.0), Vector2(104.0, 254.0)],
	[Vector2(-330.0, -96.0), Vector2(-176.0, -108.0)],
	[Vector2(176.0, -100.0), Vector2(332.0, -92.0)],
]

func _ready() -> void:
	add_to_group("battle_director")
	_setup_noise()
	_create_materials()
	_build_environment()
	_build_terrain()
	_build_roads()
	_build_village()
	_build_field_works()
	_scatter_ground_details()
	_place_soldiers()
	_spawn_player()
	_create_hud()

func _setup_noise() -> void:
	terrain_noise.seed = 20260410
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_noise.frequency = 0.0042
	terrain_noise.fractal_octaves = 4
	terrain_noise.fractal_lacunarity = 2.1
	terrain_noise.fractal_gain = 0.42

	detail_noise.seed = 99117
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.023
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_lacunarity = 2.3
	detail_noise.fractal_gain = 0.4

	ridge_noise.seed = 44219
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge_noise.frequency = 0.012
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge_noise.fractal_octaves = 4
	ridge_noise.fractal_lacunarity = 2.2
	ridge_noise.fractal_gain = 0.46

func _ridged(x: float, z: float) -> float:
	return clampf(ridge_noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)

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
		soil_material.normal_scale = 0.9
	if ResourceLoader.exists(roughness_path):
		soil_material.roughness_texture = load(roughness_path) as Texture2D
	soil_material.roughness = 1.0
	soil_material.metallic = 0.0

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
		rock_material.normal_scale = 1.6
	rock_material.roughness = 0.92

	sandbag_material = _make_material(Color(0.50, 0.46, 0.33))
	brick_material = _make_material(Color(0.80, 0.70, 0.62))
	stone_material = _make_material(Color(0.80, 0.78, 0.72))
	dark_material = _make_material(Color(0.13, 0.13, 0.12))
	shrub_material = _make_material(Color(0.20, 0.27, 0.14))
	wood_material = _make_material(Color(0.72, 0.62, 0.52))
	metal_material = _make_material(Color(0.70, 0.68, 0.64), 0.55)
	metal_material.metallic = 0.45
	road_material = _make_material(Color(0.66, 0.60, 0.50))
	leaf_material = _make_material(Color(0.19, 0.27, 0.13))
	# Photographed CC0 material sets give the village real surface detail:
	# brick courses, painted plaster, weathered planks and corrugated steel.
	_apply_pbr(brick_material, "brick", 0.55)
	_apply_pbr(stone_material, "concrete", 0.42)
	_apply_pbr(wood_material, "wood", 0.70)
	_apply_pbr(metal_material, "metal", 0.50)
	_apply_pbr(road_material, "concrete", 0.30)

# Triplanar PBR so box-mapped walls keep a constant texel density.
func _apply_pbr(material: StandardMaterial3D, set_name: String, scale: float) -> void:
	var base := "res://assets/runtime/materials/%s_" % set_name
	var color_path := base + "color.jpg"
	if not ResourceLoader.exists(color_path):
		return
	material.albedo_texture = load(color_path) as Texture2D
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(scale, scale, scale)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var normal_path := base + "normal.jpg"
	if ResourceLoader.exists(normal_path):
		material.normal_enabled = true
		material.normal_texture = load(normal_path) as Texture2D
		material.normal_scale = 0.85
	var roughness_path := base + "roughness.jpg"
	if ResourceLoader.exists(roughness_path):
		material.roughness_texture = load(roughness_path) as Texture2D
		material.roughness = 1.0

func _make_material(color: Color, roughness := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material

func _build_environment() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.34, 0.47, 0.62)
	sky_material.sky_horizon_color = Color(0.72, 0.73, 0.68)
	sky_material.sky_curve = 0.16
	sky_material.ground_bottom_color = Color(0.18, 0.19, 0.13)
	sky_material.ground_horizon_color = Color(0.44, 0.45, 0.36)
	sky_material.sun_angle_max = 16.0
	sky_material.sun_curve = 0.09
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.72
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.0
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = 240.0
	environment.fog_depth_end = 1600.0
	environment.fog_depth_curve = 0.9
	environment.fog_density = 0.012
	environment.fog_light_color = Color(0.62, 0.66, 0.62)
	environment.fog_sky_affect = 0.32
	environment.glow_enabled = true
	environment.glow_intensity = 0.22
	environment.glow_bloom = 0.03
	environment.glow_hdr_threshold = 1.2
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, -138.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.89)
	sun.light_energy = 1.28
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 190.0
	sun.directional_shadow_split_1 = 0.07
	sun.directional_shadow_split_2 = 0.22
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.1
	add_child(sun)

	fill_light = DirectionalLight3D.new()
	fill_light.name = "SkyFill"
	fill_light.rotation_degrees = Vector3(-26.0, 46.0, 0.0)
	fill_light.light_color = Color(0.58, 0.68, 0.82)
	fill_light.light_energy = 0.18
	fill_light.shadow_enabled = false
	add_child(fill_light)

# --- Terrain ---------------------------------------------------------------

func _terrain_height(x: float, z: float) -> float:
	var warp_x := x + terrain_noise.get_noise_2d(x * 0.004, z * 0.004) * 34.0
	var warp_z := z + terrain_noise.get_noise_2d(x * 0.004 + 61.0, z * 0.004 - 39.0) * 36.0

	var rolling := terrain_noise.get_noise_2d(warp_x * 0.85, warp_z * 0.85) * 3.1
	var detail := detail_noise.get_noise_2d(x * 0.85, z * 0.85) * 0.55
	var fine := detail_noise.get_noise_2d(x * 3.6, z * 3.6) * 0.16

	# Radio Hill, north-east: the high ground that dominates objective C.
	var hill_distance := Vector2(x - 186.0, z + 196.0).length()
	var hill := 37.0 * exp(-pow(hill_distance / 138.0, 2.0))

	# Western ridge closes the map and gives a distant backdrop.
	var west := smoothstep(-236.0, -336.0, x) * (44.0 + 42.0 * _ridged(warp_x * 0.6, warp_z * 0.6))
	var north := smoothstep(-302.0, -348.0, z) * (32.0 + 44.0 * _ridged(warp_x * 0.65 + 17.0, warp_z * 0.65))
	var south := smoothstep(300.0, 348.0, z) * (26.0 + 38.0 * _ridged(warp_x * 0.65 + 41.0, warp_z * 0.65))

	# Dry irrigation ditch crossing the southern fields.
	var ditch_center := 186.0 + sin(x * 0.011) * 12.0
	var ditch := -2.3 * exp(-pow((z - ditch_center) / 8.0, 2.0))

	var height := rolling + detail + fine + hill + west + north + south + ditch

	# The village sits on a flat shelf, which is what makes courtyard fighting
	# readable instead of a slope scramble.
	var flat_distance := Vector2(x, z).length()
	var plateau := 1.0 - smoothstep(132.0, 218.0, flat_distance)
	height = lerpf(height, 2.0 + detail * 0.22, plateau * 0.92)

	# The central corridor is a shallow valley: a long, unobstructed grade from
	# the south fields up to the village. Without it the rolling noise blocks
	# every 200 m sightline, which is what makes a Squad map readable.
	var axis_height := lerpf(2.0, -2.6, clampf((z + 140.0) / 440.0, 0.0, 1.0))
	var corridor := 1.0 - smoothstep(65.0, 175.0, absf(x))
	return lerpf(height, axis_height + detail * 0.16, corridor * 0.88)

func _terrain_normal(x: float, z: float) -> Vector3:
	var e := 1.6
	var dx := _terrain_height(x + e, z) - _terrain_height(x - e, z)
	var dz := _terrain_height(x, z + e) - _terrain_height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()

func _road_center(z: float) -> float:
	return sin(z * 0.0105) * 7.0

func _cross_road_center(x: float) -> float:
	return -8.0 + sin(x * 0.0102) * 6.0

func _near_road(x: float, z: float) -> bool:
	if absf(x - _road_center(z)) < 5.2:
		return true
	if absf(z - _cross_road_center(x)) < 4.6:
		return true
	return false

func _soil_color(x: float, z: float, ground_height: float) -> Color:
	var broad := terrain_noise.get_noise_2d(x * 0.20, z * 0.20)
	var fine := detail_noise.get_noise_2d(x * 0.55, z * 0.55)
	var grass := Color(0.33, 0.40, 0.20).lerp(Color(0.47, 0.47, 0.28), clampf(broad * 0.5 + 0.5, 0.0, 1.0))
	grass = grass.lerp(Color(0.55, 0.51, 0.34), clampf(fine * 0.5 + 0.5, 0.0, 1.0) * 0.30)
	var altitude := clampf((ground_height - 30.0) / 60.0, 0.0, 1.0)
	grass = grass.lerp(Color(0.50, 0.47, 0.38), altitude * 0.7)
	if _near_road(x, z):
		grass = Color(0.44, 0.36, 0.25)
	var shade := broad * 0.035 + fine * 0.025
	return Color(
		clampf(grass.r + shade, 0.04, 1.0),
		clampf(grass.g + shade, 0.04, 1.0),
		clampf(grass.b + shade * 0.8, 0.03, 1.0),
		1.0
	)

func _rock_color(x: float, z: float, ground_height: float) -> Color:
	var variation := detail_noise.get_noise_2d(x * 0.35, z * 0.35) * 0.05
	var base := Color(0.56, 0.53, 0.47).lerp(Color(0.40, 0.38, 0.34), clampf(ground_height / 90.0, 0.0, 1.0))
	return Color(
		clampf(base.r + variation, 0.02, 0.95),
		clampf(base.g + variation, 0.02, 0.95),
		clampf(base.b + variation, 0.02, 0.95),
		1.0
	)

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
			var quad_normal := (p10 - p00).cross(p01 - p00).normalized()
			var average_height := (terrain_heights[i00] + terrain_heights[i10] + terrain_heights[i01] + terrain_heights[i11]) * 0.25
			var is_rock := absf(quad_normal.y) < 0.74 or average_height > 34.0
			if is_rock:
				_add_terrain_triangle(rock_tool, p00, p10, p01, rock_colors, i00, i10, i01, 0.06)
				_add_terrain_triangle(rock_tool, p10, p11, p01, rock_colors, i10, i11, i01, 0.06)
			else:
				_add_terrain_triangle(soil_tool, p00, p10, p01, terrain_colors, i00, i10, i01, uv_scale)
				_add_terrain_triangle(soil_tool, p10, p11, p01, terrain_colors, i10, i11, i01, uv_scale)
	soil_tool.index()
	soil_tool.generate_normals()
	soil_tool.generate_tangents()
	var soil_instance := MeshInstance3D.new()
	soil_instance.name = "BattlefieldTerrain"
	soil_instance.mesh = soil_tool.commit()
	soil_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(soil_instance)

	rock_tool.index()
	rock_tool.generate_normals()
	rock_tool.generate_tangents()
	var rock_instance := MeshInstance3D.new()
	rock_instance.name = "BattlefieldRock"
	rock_instance.mesh = rock_tool.commit()
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

func _add_terrain_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colors: PackedColorArray, ia: int, ib: int, ic: int, uv_scale: float) -> void:
	tool.set_color(colors[ia])
	tool.set_uv(Vector2(a.x * uv_scale, a.z * uv_scale))
	tool.add_vertex(a)
	tool.set_color(colors[ib])
	tool.set_uv(Vector2(b.x * uv_scale, b.z * uv_scale))
	tool.add_vertex(b)
	tool.set_color(colors[ic])
	tool.set_uv(Vector2(c.x * uv_scale, c.z * uv_scale))
	tool.add_vertex(c)

# --- Roads -----------------------------------------------------------------

func _build_roads() -> void:
	_build_road_strip("MainRoad", true, -338.0, 338.0, 7.0)
	_build_road_strip("CrossRoad", false, -338.0, 338.0, 6.0)
	# A farm track loops off the main road towards objective A.
	_build_road_strip("FarmTrack", true, 120.0, 300.0, 4.0, 34.0)

func _build_road_strip(node_name: String, along_z: bool, start: float, finish: float, width: float, lateral_offset := 0.0) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(road_material)
	var segments := 96
	var previous_left := Vector3.ZERO
	var previous_right := Vector3.ZERO
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var along: float = lerpf(start, finish, t)
		var center: Vector2
		if along_z:
			center = Vector2(_road_center(along) + lateral_offset, along)
		else:
			center = Vector2(along, _cross_road_center(along) + lateral_offset)
		var perpendicular := Vector2(1.0, 0.0) if along_z else Vector2(0.0, 1.0)
		var half_width := width * 0.5
		var left := center - perpendicular * half_width
		var right := center + perpendicular * half_width
		var left_point := Vector3(left.x, _terrain_height(left.x, left.y) + 0.07, left.y)
		var right_point := Vector3(right.x, _terrain_height(right.x, right.y) + 0.07, right.y)
		if i > 0:
			tool.add_vertex(previous_left)
			tool.add_vertex(previous_right)
			tool.add_vertex(left_point)
			tool.add_vertex(previous_right)
			tool.add_vertex(right_point)
			tool.add_vertex(left_point)
		previous_left = left_point
		previous_right = right_point
	tool.generate_normals()
	var road := MeshInstance3D.new()
	road.name = node_name
	road.mesh = tool.commit()
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)

# --- Village ---------------------------------------------------------------

func _build_village() -> void:
	for index in range(COMPOUNDS.size()):
		var data: Dictionary = COMPOUNDS[index]
		var center: Vector2 = data["c"]
		var size: Vector2 = data["s"]
		var building: Vector2 = data["b"]
		var floors: int = data["floors"]
		var material := brick_material if str(data["mat"]) == "brick" else stone_material
		var surface := str(data["mat"])
		_build_compound("Compound_%02d" % index, center, size, building, floors, material, surface)

	# Central crossroads: fountain, market stalls and jersey barriers.
	_add_cover("FountainBase", Vector3(0.0, _terrain_height(0.0, 0.0) + 0.45, 0.0), Vector3(4.6, 0.9, 4.6), stone_material, "stone", 9000.0, 1.6)
	_add_cylinder_prop("FountainColumn", Vector3(0.0, _terrain_height(0.0, 0.0) + 1.4, 0.0), 0.55, 1.6, stone_material)
	for i in range(5):
		var angle := TAU * float(i) / 5.0
		var x := cos(angle) * 11.0
		var z := sin(angle) * 11.0
		_add_cover("MarketStall_%d" % i, Vector3(x, _terrain_height(x, z) + 0.55, z), Vector3(3.0, 1.1, 1.4), wood_material, "wood", 700.0, 0.35)

	# Roadblocks where the two roads leave the village.
	for i in range(4):
		var offset := -6.0 + float(i) * 4.2
		_add_cover("JerseyBarrier_%d" % i, Vector3(offset + _road_center(46.0), _terrain_height(offset, 46.0) + 0.55, 46.0), Vector3(3.6, 1.05, 0.85), stone_material, "stone", 5200.0, 1.4)
	for i in range(4):
		var offset := -6.0 + float(i) * 4.2
		_add_cover("JerseyBarrierN_%d" % i, Vector3(offset + _road_center(-46.0), _terrain_height(offset, -46.0) + 0.55, -46.0), Vector3(3.6, 1.05, 0.85), stone_material, "stone", 5200.0, 1.4)

	# Landmarks: water tower and a burnt-out truck for orientation.
	_build_water_tower(Vector3(-146.0, 0.0, 62.0))
	_build_truck(Vector3(22.0, 0.0, -22.0), 34.0)
	_build_truck(Vector3(-18.0, 0.0, 96.0), -112.0)

func _build_compound(node_name: String, center: Vector2, size: Vector2, building: Vector2, floors: int, material: StandardMaterial3D, surface: String) -> void:
	var ground := _terrain_height(center.x, center.y)
	var wall_height := 3.0
	var thickness := 0.42
	var half_x := size.x * 0.5
	var half_z := size.y * 0.5

	# Courtyard walls with a gate on the south side and a breach on the east.
	var gate_width := 4.2
	_add_cover(node_name + "_WallS_W", Vector3(center.x - (half_x + gate_width * 0.5) * 0.5 - gate_width * 0.25, ground + wall_height * 0.5, center.y + half_z), Vector3(half_x - gate_width * 0.5, wall_height, thickness), material, surface, 6000.0, 1.2)
	_add_cover(node_name + "_WallS_E", Vector3(center.x + (half_x + gate_width * 0.5) * 0.5 + gate_width * 0.25, ground + wall_height * 0.5, center.y + half_z), Vector3(half_x - gate_width * 0.5, wall_height, thickness), material, surface, 6000.0, 1.2)
	_add_cover(node_name + "_WallN", Vector3(center.x, ground + wall_height * 0.5, center.y - half_z), Vector3(size.x, wall_height, thickness), material, surface, 6000.0, 1.2)
	_add_cover(node_name + "_WallW", Vector3(center.x - half_x, ground + wall_height * 0.5, center.y), Vector3(thickness, wall_height, size.y), material, surface, 6000.0, 1.2)
	_add_cover(node_name + "_WallE", Vector3(center.x + half_x, ground + wall_height * 0.5, center.y - size.y * 0.28), Vector3(thickness, wall_height, size.y * 0.44), material, surface, 6000.0, 1.2)
	_add_cover(node_name + "_WallE2", Vector3(center.x + half_x, ground + wall_height * 0.5, center.y + size.y * 0.28), Vector3(thickness, wall_height, size.y * 0.44), material, surface, 6000.0, 1.2)

	_build_house(node_name + "_House", center, building, floors, material, surface)

	# Courtyard cover: sandbag nest in one corner, a shed in the other.
	var corner := Vector3(center.x - half_x * 0.55, 0.0, center.y + half_z * 0.55)
	_add_cover(node_name + "_Sandbags", Vector3(corner.x, _terrain_height(corner.x, corner.z) + 0.45, corner.z), Vector3(3.4, 0.9, 0.9), sandbag_material, "sand", 900.0, 0.25)
	_add_cover(node_name + "_Sandbags2", Vector3(corner.x + 2.6, _terrain_height(corner.x + 2.6, corner.z) + 0.45, corner.z + 0.4), Vector3(2.6, 0.9, 0.9), sandbag_material, "sand", 900.0, 0.25)

func _build_house(node_name: String, center: Vector2, footprint: Vector2, floors: int, material: StandardMaterial3D, surface: String) -> void:
	var ground := _terrain_height(center.x, center.y)
	var wall_height := 3.1
	var thickness := 0.5
	var width := footprint.x
	var depth := footprint.y
	var door_width := 1.7
	for floor in range(floors):
		var base := ground + wall_height * float(floor)
		var wall_y := base + wall_height * 0.5
		# South wall split around a doorway.
		_add_cover("%s_F%d_S_W" % [node_name, floor], Vector3(center.x - (width * 0.5 + door_width) * 0.5, wall_y, center.y + depth * 0.5), Vector3(width * 0.5 - door_width * 0.5, wall_height, thickness), material, surface, 9000.0, 1.6)
		_add_cover("%s_F%d_S_E" % [node_name, floor], Vector3(center.x + (width * 0.5 + door_width) * 0.5, wall_y, center.y + depth * 0.5), Vector3(width * 0.5 - door_width * 0.5, wall_height, thickness), material, surface, 9000.0, 1.6)
		_add_cover("%s_F%d_N" % [node_name, floor], Vector3(center.x, wall_y, center.y - depth * 0.5), Vector3(width, wall_height, thickness), material, surface, 9000.0, 1.6)
		_add_cover("%s_F%d_W" % [node_name, floor], Vector3(center.x - width * 0.5, wall_y, center.y), Vector3(thickness, wall_height, depth), material, surface, 9000.0, 1.6)
		_add_cover("%s_F%d_E" % [node_name, floor], Vector3(center.x + width * 0.5, wall_y, center.y), Vector3(thickness, wall_height, depth), material, surface, 9000.0, 1.6)
		# Floor slab above every storey except the top one.
		if floor < floors - 1:
			_add_cover("%s_F%d_Slab" % [node_name, floor], Vector3(center.x, base + wall_height + 0.2, center.y), Vector3(width, 0.4, depth), dark_material, surface, 12000.0, 2.0)
	_build_roof(node_name + "_Roof", center, footprint, ground + wall_height * float(floors), material)

func _build_roof(node_name: String, center: Vector2, footprint: Vector2, top_y: float, material: StandardMaterial3D) -> void:
	var roof := MeshInstance3D.new()
	roof.name = node_name
	var mesh := PrismMesh.new()
	mesh.size = Vector3(footprint.x + 0.9, 1.5, footprint.y + 0.9)
	roof.mesh = mesh
	roof.position = Vector3(center.x, top_y + 0.55, center.y)
	roof.material_override = material
	add_child(roof)
	var body := StaticBody3D.new()
	body.position = roof.position
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_script(COVER_SCRIPT)
	body.set("integrity", 12000.0)
	body.set("max_integrity", 12000.0)
	body.set("armor_rating", 2.0)
	body.set("surface", "brick")
	body.add_to_group("destructible_cover")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(footprint.x + 0.9, 1.2, footprint.y + 0.9)
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _build_water_tower(base: Vector3) -> void:
	var ground := _terrain_height(base.x, base.z)
	for i in range(4):
		var angle := TAU * float(i) / 4.0 + 0.4
		var leg := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.18
		mesh.bottom_radius = 0.22
		mesh.height = 11.0
		leg.mesh = mesh
		leg.position = Vector3(base.x + cos(angle) * 2.3, ground + 5.5, base.z + sin(angle) * 2.3)
		leg.material_override = metal_material
		add_child(leg)
	var tank := MeshInstance3D.new()
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 3.2
	tank_mesh.bottom_radius = 3.2
	tank_mesh.height = 4.4
	tank.mesh = tank_mesh
	tank.position = Vector3(base.x, ground + 13.2, base.z)
	tank.material_override = metal_material
	add_child(tank)
	_add_cover("WaterTowerBody", Vector3(base.x, ground + 5.5, base.z), Vector3(2.0, 11.0, 2.0), metal_material, "metal", 40000.0, 3.0)

func _add_cylinder_prop(node_name: String, position: Vector3, radius: float, height: float, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	add_child(instance)

func _build_truck(at: Vector3, yaw: float) -> void:
	var ground := _terrain_height(at.x, at.z)
	var root := Node3D.new()
	root.position = Vector3(at.x, ground, at.z)
	root.rotation_degrees.y = yaw
	add_child(root)
	var cab := MeshInstance3D.new()
	var cab_mesh := BoxMesh.new()
	cab_mesh.size = Vector3(2.2, 1.9, 2.4)
	cab.mesh = cab_mesh
	cab.position = Vector3(0.0, 1.35, -2.4)
	cab.material_override = metal_material
	root.add_child(cab)
	var bed := MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(2.3, 1.1, 5.0)
	bed.mesh = bed_mesh
	bed.position = Vector3(0.0, 0.95, 1.4)
	bed.material_override = metal_material
	root.add_child(bed)
	for side in [-1.0, 1.0]:
		for offset in [-2.2, 2.6]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.55
			wheel_mesh.bottom_radius = 0.55
			wheel_mesh.height = 0.4
			wheel_mesh.radial_segments = 10
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(side * 1.15, 0.55, offset)
			wheel.rotation_degrees.z = 90.0
			wheel.material_override = dark_material
			root.add_child(wheel)
	var body := StaticBody3D.new()
	body.position = Vector3(at.x, ground + 1.1, at.z)
	body.rotation_degrees.y = yaw
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_script(COVER_SCRIPT)
	body.set("integrity", 26000.0)
	body.set("max_integrity", 26000.0)
	body.set("armor_rating", 2.4)
	body.set("surface", "metal")
	body.add_to_group("destructible_cover")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.2, 7.6)
	shape.shape = box
	body.add_child(shape)
	add_child(body)

# --- Fields, hedgerows and tree lines --------------------------------------

func _build_field_works() -> void:
	for hedge in HEDGES:
		var start: Vector2 = hedge[0]
		var finish: Vector2 = hedge[1]
		var length := start.distance_to(finish)
		var count := int(length / 5.0)
		var direction := (finish - start).normalized()
		for i in range(count):
			var point := start + direction * (float(i) * 5.0 + 1.0)
			# Leave gaps so the fields can be crossed without walking into walls.
			if i % 7 == 3:
				continue
			_add_cover("FieldWall_%d" % (i + int(absf(start.y))), Vector3(point.x, _terrain_height(point.x, point.y) + 0.55, point.y), Vector3(5.2, 1.0, 0.55), stone_material, "stone", 3000.0, 0.9)
			if i % 3 == 0:
				_plant_tree(Vector3(point.x + 1.6, 0.0, point.y + 1.6), 1.0)

	# Assault lanes: sandbag emplacements facing the village.
	for i in range(9):
		var x := -96.0 + float(i) * 24.0
		var z := 208.0 + sin(float(i) * 0.8) * 14.0
		_add_cover("AttackSandbags_%d" % i, Vector3(x, _terrain_height(x, z) + 0.45, z), Vector3(4.2, 0.9, 0.9), sandbag_material, "sand", 900.0, 0.25)

	# Defensive works around objective C and along the north hedgerows.
	for i in range(7):
		var x := -70.0 + float(i) * 20.0
		_add_cover("NorthSandbags_%d" % i, Vector3(x, _terrain_height(x, -96.0) + 0.45, -96.0), Vector3(4.0, 0.9, 0.9), sandbag_material, "sand", 900.0, 0.25)

	# Scattered trees inside and around the village for vertical cover.
	var rng := RandomNumberGenerator.new()
	rng.seed = 30217
	for i in range(46):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(96.0, 210.0)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		_plant_tree(Vector3(x, 0.0, z), rng.randf_range(0.85, 1.35))

func _plant_tree(at: Vector3, scale_factor: float) -> void:
	if absf(at.x) > 336.0 or absf(at.z) > 336.0:
		return
	var ground := _terrain_height(at.x, at.z)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16 * scale_factor
	trunk_mesh.bottom_radius = 0.24 * scale_factor
	trunk_mesh.height = 3.4 * scale_factor
	trunk_mesh.radial_segments = 6
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(at.x, ground + 1.7 * scale_factor, at.z)
	trunk.material_override = wood_material
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(trunk)
	var canopy := MeshInstance3D.new()
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 2.1 * scale_factor
	canopy_mesh.height = 3.4 * scale_factor
	canopy_mesh.radial_segments = 8
	canopy_mesh.rings = 5
	canopy.mesh = canopy_mesh
	canopy.position = Vector3(at.x, ground + 4.6 * scale_factor, at.z)
	canopy.material_override = leaf_material
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(canopy)

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

# --- Scatter ---------------------------------------------------------------

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
	rng.seed = 512077
	_scatter_multimesh("MountainBoulders", _make_rock_mesh(1.0, Vector3(1.0, 0.72, 1.35), 3301), 130, rng, 2.2, 6.5, true)
	_scatter_multimesh("GroundStones", _make_rock_mesh(1.0, Vector3(1.0, 0.5, 1.1), 3302), 420, rng, 0.3, 1.3, false)
	_scatter_multimesh("MountainScree", _make_rock_mesh(1.0, Vector3(1.0, 0.42, 1.2), 3303), 700, rng, 0.12, 0.5, false)
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
			if normal.y > 0.86 or height < 14.0:
				continue
		else:
			if normal.y < 0.90 or height > 30.0:
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
	instance.material_override = rock_material
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
	multi.instance_count = 520
	var placed := 0
	var attempts := 0
	while placed < 520 and attempts < 7000:
		attempts += 1
		var x := rng.randf_range(-250.0, 250.0)
		var z := rng.randf_range(-290.0, 300.0)
		var height := _terrain_height(x, z)
		if height > 22.0 or _terrain_normal(x, z).y < 0.93:
			continue
		# Keep the village core and the roads clear of bushes.
		if Vector2(x, z).length() < 150.0 or _near_road(x, z):
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

# --- Battle layer ----------------------------------------------------------

func _place_soldiers() -> void:
	_add_capture_point("A", "SOUTH FARM", Vector3(36.0, 0.0, 130.0), "military")
	_add_capture_point("B", "VILLAGE CROSSROADS", Vector3(0.0, 0.0, 4.0), "military")
	_add_capture_point("C", "NORTH YARD", Vector3(-34.0, 0.0, -122.0), "militia")

	# Militia garrison: holds the north yard and the village.
	# Militia posts sit on the streets, in the courtyard gates and in the open
	# fields, never inside a building, so they always have a firing lane.
	var militia_positions := [
		Vector3(0.0, 0.0, -96.0), Vector3(-18.0, 0.0, -100.0), Vector3(14.0, 0.0, -108.0),
		Vector3(0.0, 0.0, -30.0), Vector3(-22.0, 0.0, -8.0), Vector3(22.0, 0.0, -6.0),
		Vector3(-100.0, 0.0, -6.0), Vector3(100.0, 0.0, -4.0), Vector3(0.0, 0.0, 20.0),
		Vector3(-22.0, 0.0, 28.0), Vector3(24.0, 0.0, 30.0), Vector3(0.0, 0.0, 62.0),
		Vector3(-92.0, 0.0, 64.0), Vector3(92.0, 0.0, 66.0),
		# Forward outpost on objective A, so contact happens at ~110 m.
		Vector3(18.0, 0.0, 100.0), Vector3(46.0, 0.0, 102.0), Vector3(-4.0, 0.0, 112.0),
	]
	for i in range(militia_positions.size()):
		var at: Vector3 = militia_positions[i]
		_spawn_soldier("militia", at, 0.88 + float(i % 5) * 0.05, 155.0 + float(i % 4) * 14.0)

	# Military section: the player's squad, pushing up from the south.
	var military_positions := [
		Vector3(-14.0, 0.0, 214.0), Vector3(4.0, 0.0, 220.0), Vector3(-26.0, 0.0, 226.0),
		Vector3(14.0, 0.0, 232.0), Vector3(-2.0, 0.0, 204.0), Vector3(26.0, 0.0, 210.0),
		Vector3(-38.0, 0.0, 204.0), Vector3(34.0, 0.0, 226.0), Vector3(-20.0, 0.0, 192.0),
		Vector3(18.0, 0.0, 194.0),
	]
	for i in range(military_positions.size()):
		var at: Vector3 = military_positions[i]
		_spawn_soldier("military", at, 1.12, 185.0 + float(i % 3) * 12.0)

func _spawn_soldier(faction: String, at: Vector3, marksmanship: float, health: float) -> void:
	var soldier := TARGET_SCRIPT.new()
	soldier.name = "%s_Soldier_%02d" % [faction.capitalize(), target_count]
	# Position before entering the tree so the rig and rally point are built at
	# the right spot (the world node itself sits at the origin).
	soldier.set("faction", faction)
	soldier.set("marksmanship", marksmanship)
	soldier.set("max_health", health)
	soldier.set("health", health)
	soldier.position = Vector3(at.x, _terrain_height(at.x, at.z) + 0.05, at.z)
	add_child(soldier)
	soldier.rotation_degrees = Vector3(0.0, 0.0 if faction == "military" else 180.0, 0.0)
	soldier.connect("damaged", Callable(self, "_on_target_damaged"))
	soldier.connect("died", Callable(self, "_on_soldier_died"))
	soldiers.append(soldier)
	target_count += 1

func _add_capture_point(id: String, label: String, at: Vector3, owner: String) -> void:
	capture_points.append({
		"id": id,
		"label": label,
		"position": Vector3(at.x, _terrain_height(at.x, at.z), at.z),
		"owner": owner,
		"progress": 0.0,
		"radius": 26.0,
	})
	_add_objective_marker(id, at)

func _add_objective_marker(id: String, at: Vector3) -> void:
	var ground := _terrain_height(at.x, at.z)
	for i in range(4):
		var angle := TAU * float(i) / 4.0
		var pole := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.06
		mesh.bottom_radius = 0.06
		mesh.height = 2.4
		pole.mesh = mesh
		pole.position = Vector3(at.x + cos(angle) * 2.4, ground + 1.2, at.z + sin(angle) * 2.4)
		pole.material_override = metal_material
		add_child(pole)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(1.6, 0.9, 0.08)
	plate.mesh = plate_mesh
	plate.position = Vector3(at.x, ground + 1.9, at.z)
	plate.material_override = _make_material(Color(0.85, 0.78, 0.30))
	add_child(plate)

func next_objective(faction: String, from: Vector3) -> Vector3:
	var best: Vector3 = from
	var best_score := INF
	for point in capture_points:
		var position: Vector3 = point["position"]
		var owned := str(point["owner"]) == faction
		# Attack the nearest point that is not ours; if all are ours, hold.
		var score := from.distance_to(position) - (0.0 if owned else 220.0)
		score += randf() * 45.0
		if score < best_score:
			best_score = score
			best = position
	return best

func _process(delta: float) -> void:
	_update_capture_points(delta)
	status_timer -= delta
	if status_timer <= 0.0:
		status_timer = 0.9
		_update_battle_status()

func _update_capture_points(delta: float) -> void:
	for point in capture_points:
		var position: Vector3 = point["position"]
		var radius: float = point["radius"]
		var military_count := 0
		var militia_count := 0
		for node in soldiers:
			if not is_instance_valid(node) or not bool(node.call("is_alive_soldier")):
				continue
			if node.global_position.distance_to(position) > radius:
				continue
			if str(node.get("faction")) == "military":
				military_count += 1
			else:
				militia_count += 1
		var player_response := _player_presence(position, radius)
		military_count += player_response
		var owner := str(point["owner"])
		var progress := float(point["progress"])
		if military_count > 0 and militia_count == 0:
			progress += delta * (0.16 + float(military_count - 1) * 0.05)
		elif militia_count > 0 and military_count == 0:
			progress -= delta * (0.16 + float(militia_count - 1) * 0.05)
		else:
			progress = move_toward(progress, 0.0, delta * 0.12)
		if progress >= 1.0:
			point["owner"] = "military"
			progress = 1.0
		elif progress <= -1.0:
			point["owner"] = "militia"
			progress = -1.0
		point["progress"] = progress
		if owner != str(point["owner"]) and hud != null:
			hud.set_message("%s CAPTURED BY %s" % [str(point["label"]), str(point["owner"]).to_upper()])

func _player_presence(position: Vector3, radius: float) -> int:
	if player == null:
		return 0
	if not bool(player.call("is_alive_player")):
		return 0
	return 1 if player.global_position.distance_to(position) <= radius else 0

func _update_battle_status() -> void:
	if hud == null:
		return
	var parts: Array[String] = []
	for point in capture_points:
		var owner := str(point["owner"])
		var tag := "MIL" if owner == "military" else "MTA"
		var contested := absf(float(point["progress"])) < 0.99 and absf(float(point["progress"])) > 0.02
		parts.append("%s:%s%s" % [str(point["id"]), ">>" if contested else "", tag])
	var alive_military := 0
	var alive_militia := 0
	for node in soldiers:
		if not is_instance_valid(node) or not bool(node.call("is_alive_soldier")):
			continue
		if str(node.get("faction")) == "military":
			alive_military += 1
		else:
			alive_militia += 1
	var phase := "NIGHT" if night_mode else "DAY"
	hud.set_battle_status("SECTOR 01 | %s | %s | SQUAD %d vs %d" % [phase, " ".join(parts), alive_military + 1, alive_militia])

func _on_target_damaged(distance_m: float, killed: bool) -> void:
	if hud == null:
		return
	if killed:
		hud.set_message("TARGET DOWN — %.0f m" % distance_m)
	else:
		hud.set_message("HIT — %.0f m" % distance_m)

func _on_soldier_died(_faction: String) -> void:
	pass

func _spawn_player() -> void:
	player = PLAYER_SCRIPT.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(PLAYER_SPAWN.x, _terrain_height(PLAYER_SPAWN.x, PLAYER_SPAWN.z) + 0.12, PLAYER_SPAWN.z)

func _create_hud() -> void:
	hud = HUD_SCRIPT.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_battle_status("SECTOR 01 | DAY | DEPLOYING")
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
		sun.light_energy = 0.10 if night_mode else 1.28
		sun.light_color = Color(0.62, 0.70, 0.95) if night_mode else Color(1.0, 0.96, 0.89)
	if fill_light != null:
		fill_light.light_energy = 0.06 if night_mode else 0.18
	if world_environment != null:
		var environment := world_environment.environment
		environment.ambient_light_energy = 0.10 if night_mode else 0.72
		environment.fog_light_color = Color(0.04, 0.05, 0.07) if night_mode else Color(0.62, 0.66, 0.62)
		environment.fog_density = 0.018 if night_mode else 0.012
	if sky_material != null:
		sky_material.sky_top_color = Color(0.010, 0.016, 0.032) if night_mode else Color(0.34, 0.47, 0.62)
		sky_material.sky_horizon_color = Color(0.045, 0.055, 0.08) if night_mode else Color(0.72, 0.73, 0.68)
		sky_material.ground_horizon_color = Color(0.03, 0.035, 0.05) if night_mode else Color(0.44, 0.45, 0.36)
