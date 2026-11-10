extends RefCounted

# Weapon + ammunition authoring data.
# 
# Everything that used to be hard-coded in the controller now lives here:
# the cartridge, the service loads, recoil, dispersion, the ADS zoom,
# and the first-person mount transform. Adding another rifle later is a data
# entry + an imported model, not a code change.

const BALLISTICS = preload("res://scripts/weapons/ballistics.gd")

const LOADS := {
	"FMJ": {
		"name": "FMJ",
		"description": "7N6 steel-core ball",
		"velocity_scale": 1.0,
		"damage_scale": 1.0,
		"penetration_scale": 1.0,
		"tracer": false
	},
	"TRACER": {
		"name": "TRACER",
		"description": "7T3 tracer, ignites in flight",
		"velocity_scale": 0.933,
		"damage_scale": 0.94,
		"penetration_scale": 0.90,
		"tracer": true
	},
	"AP": {
		"name": "AP",
		"description": "7N22 armour-piercing",
		"velocity_scale": 0.99,
		"damage_scale": 0.90,
		"penetration_scale": 1.85,
		"tracer": false
	}
}

# ── All weapons ──────────────────────────────────────────────────────
static func all_weapons() -> Array[Dictionary]:
	return [
		# ── AK‑74 / AK‑74M ──────────────────────────────────────────
		{
			"id": "ak74m",
			"name": "AK‑74M",
			"caliber": "5.45×39 mm",
			"caliber_id": "5.45x39",
			"model_key": "ak74m",
			"audio_profile": "ak",
			"muzzle_velocity": 900.0,
			"gravity_scale": 1.0,
			"damage": 38.0,
			"penetration": 0.34,
			"max_range": 900.0,
			"zero_distance": 300.0,
			"magazine": 30,
			"fire_interval": 0.10,
			"projectile_kind": "bullet",
			"ammo_types": ["FMJ", "TRACER", "AP"],
			"hip_fov": 78.0,
			"ads_fov": 34.0,
			"recoil_pitch": 0.019,
			"recoil_yaw": 0.0055,
			"recoil_view": 0.085,
			"spread_hip_deg": 0.55,
			"spread_ads_deg": 0.12,
			"view_rotation_degrees": Vector3(0.0, 180.0, 0.0),
			"view_scale": 0.46,
			"view_hip_position": Vector3(0.31, -0.34, -0.58),
			"view_ads_position": Vector3(-0.10, -0.175, -0.44),
			"tracer_ignition_distance": 22.0
		},

		# ── M4A1 ─────────────────────────────────────────────────────
		{
			"id": "m4a1",
			"name": "M4A1",
			"caliber": "5.56×45 mm",
			"caliber_id": "5.56x45",
			"model_key": "m4a1",
			"audio_profile": "m4",
			"muzzle_velocity": 948.0,
			"gravity_scale": 1.0,
			"damage": 36.0,
			"penetration": 0.30,
			"max_range": 800.0,
			"zero_distance": 300.0,
			"magazine": 30,
			"fire_interval": 0.09,
			"projectile_kind": "bullet",
			"ammo_types": ["FMJ", "TRACER", "AP"],
			"hip_fov": 75.0,
			"ads_fov": 30.0,
			"recoil_pitch": 0.021,
			"recoil_yaw": 0.0060,
			"recoil_view": 0.090,
			"spread_hip_deg": 0.50,
			"spread_ads_deg": 0.10,
			"view_rotation_degrees": Vector3(0.0, 180.0, 0.0),
			"view_scale": 0.44,
			"view_hip_position": Vector3(0.28, -0.38, -0.55),
			"view_ads_position": Vector3(-0.05, -0.20, -0.40),
			"tracer_ignition_distance": 22.0
		},

		# ── PK Russian machine gun ───────────────────────────────────
		{
			"id": "pk",
			"name": "PKM",
			"caliber": "7.62×54 mm R",
			"caliber_id": "7.62x54R",
			"model_key": "pkm",
			"audio_profile": "pk",
			"muzzle_velocity": 830.0,
			"gravity_scale": 1.0,
			"damage": 52.0,
			"penetration": 0.55,
			"max_range": 1200.0,
			"zero_distance": 400.0,
			"magazine": 100,
			"fire_interval": 0.075,
			"projectile_kind": "bullet",
			"ammo_types": ["FMJ", "AP"],
			"hip_fov": 80.0,
			"ads_fov": 40.0,
			"recoil_pitch": 0.035,
			"recoil_yaw": 0.0080,
			"recoil_view": 0.120,
			"spread_hip_deg": 0.80,
			"spread_ads_deg": 0.18,
			"view_rotation_degrees": Vector3(0.0, 180.0, 0.0),
			"view_scale": 0.52,
			"view_hip_position": Vector3(0.45, -0.42, -0.70),
			"view_ads_position": Vector3(0.10, -0.25, -0.55),
			"tracer_ignition_distance": 25.0
		},

		# ── RPG-7 Russian rocket ─────────────────────────────────────
		{
			"id": "rpg7",
			"name": "RPG‑7",
			"caliber": "40 mm HE",
			"caliber_id": "rpg7",
			"model_key": "rpg7",
			"audio_profile": "rpg",
			"muzzle_velocity": 294.0,
			"gravity_scale": 1.2,
			"damage": 120.0,
			"penetration": 1.20,
			"max_range": 500.0,
			"zero_distance": 200.0,
			"magazine": 1,
			"fire_interval": 1.80,
			"projectile_kind": "rocket",
			"ammo_types": ["HE"],
			"hip_fov": 85.0,
			"ads_fov": 45.0,
			"recoil_pitch": 0.150,
			"recoil_yaw": 0.020,
			"recoil_view": 0.200,
			"spread_hip_deg": 2.00,
			"spread_ads_deg": 0.50,
			"view_rotation_degrees": Vector3(0.0, 180.0, 0.0),
			"view_scale": 0.58,
			"view_hip_position": Vector3(0.10, -0.10, -0.30),
			"view_ads_position": Vector3(0.05, -0.05, -0.20),
			"tracer_ignition_distance": 0.0
		},

		# ── Sniper Dragunov ──────────────────────────────────────────
		{
			"id": "dragunov",
			"name": "SVD Dragunov",
			"caliber": "7.62×54 mm R",
			"caliber_id": "7.62x54R",
			"model_key": "dragunov",
			"audio_profile": "svd",
			"muzzle_velocity": 830.0,
			"gravity_scale": 1.0,
			"damage": 75.0,
			"penetration": 0.65,
			"max_range": 1000.0,
			"zero_distance": 400.0,
			"magazine": 10,
			"fire_interval": 0.80,
			"projectile_kind": "bullet",
			"ammo_types": ["FMJ", "AP"],
			"hip_fov": 80.0,
			"ads_fov": 12.0,
			"recoil_pitch": 0.045,
			"recoil_yaw": 0.0090,
			"recoil_view": 0.100,
			"spread_hip_deg": 1.50,
			"spread_ads_deg": 0.08,
			"view_rotation_degrees": Vector3(0.0, 180.0, 0.0),
			"view_scale": 0.48,
			"view_hip_position": Vector3(0.35, -0.36, -0.60),
			"view_ads_position": Vector3(0.02, -0.25, -0.48),
			"tracer_ignition_distance": 22.0
		},

		# ── Heavy machine gun .50cal (Ma Deuce) ──────────────────────
		{
			"id": "heavymg",
			"name": ".50 BMG HMG",
			"caliber": ".50 BMG",
			"caliber_id": "50bmg",
			"model_key": "50cal",
			"audio_profile": "50cal",
			"muzzle_velocity": 880.0,
			"gravity_scale": 1.0,
			"damage": 200.0,
			"penetration": 1.50,
			"max_range": 2000.0,
			"zero_distance": 600.0,
			"magazine": 10,
			"fire_interval": 0.060,
			"projectile_kind": "rocket",
			"ammo_types": ["FMJ", "AP"],
			"hip_fov": 90.0,
			"ads_fov": 20.0,
			"recoil_pitch": 0.050,
			"recoil_yaw": 0.015,
			"recoil_view": 0.150,
			"spread_hip_deg": 1.00,
			"spread_ads_deg": 0.12,
			"view_rotation_degrees": Vector3(0.0, 180.0, 0.0),
			"view_scale": 0.55,
			"view_hip_position": Vector3(0.60, -0.50, -0.80),
			"view_ads_position": Vector3(0.20, -0.30, -0.60),
			"tracer_ignition_distance": 0.0
		},

		# ── Dushka 12.7mm heavy machine gun ──────────────────────────
		{
			"id": "dushka",
			"name": "Dushka 12.7mm",
			"caliber": "12.7×108 mm",
			"caliber_id": "12.7x108",
			"model_key": "dushka",
			"audio_profile": "dushka",
			"muzzle_velocity": 860.0,
			"gravity_scale": 1.0,
			"damage": 180.0,
			"penetration": 1.35,
			"max_range": 1800.0,
			"zero_distance": 500.0,
			"magazine": 25,
			"fire_interval": 0.070,
			"projectile_kind": "bullet",
			"ammo_types": ["FMJ", "AP"],
			"hip_fov": 82.0,
			"ads_fov": 38.0,
			"recoil_pitch": 0.040,
			"recoil_yaw": 0.012,
			"recoil_view": 0.110,
			"spread_hip_deg": 0.90,
			"spread_ads_deg": 0.15,
			"view_rotation_degrees": Vector3(0.0, 180.0, 0.0),
			"view_scale": 0.50,
			"view_hip_position": Vector3(0.50, -0.45, -0.75),
			"view_ads_position": Vector3(0.15, -0.30, -0.60),
			"tracer_ignition_distance": 25.0
		}
	]

static func ammo_names(weapon: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for entry in weapon.get("ammo_types", ["FMJ", "TRACER", "AP"]):
		result.append(str(entry))
	if result.is_empty():
		result = ["FMJ"]
	return result

# ── Build shot spec ────────────────────────────────────────────────
# Merge the weapon, the selected load and the published cartridge data into
# one dictionary consumed by the projectile.
static func build_shot_spec(weapon: Dictionary, load_name: String) -> Dictionary:
	var spec := weapon.duplicate(true)
	var load: Dictionary = LOADS.get(load_name, LOADS["FMJ"])
	var caliber := BALLISTICS.profile(str(weapon.get("caliber_id", "5.45x39")))

	spec["caliber_id"] = str(caliber.get("id", "5.45x39"))
	spec["caliber"] = str(caliber.get("name", weapon.get("caliber", "")))
	spec["bullet_mass_g"] = float(caliber.get("bullet_mass_g", 3.43))
	spec["drag_per_meter"] = float(caliber.get("drag_per_meter", 0.0013))
	spec["muzzle_velocity"] = float(weapon.get("muzzle_velocity", caliber.get("muzzle_velocity", 900.0))) * float(load.get("velocity_scale", 1.0))
	spec["damage"] = float(weapon.get("damage", 38.0)) * float(load.get("damage_scale", 1.0))
	spec["penetration"] = float(weapon.get("penetration", 0.34)) * float(load.get("penetration_scale", 1.0))
	spec["tracer_color"] = caliber.get("tracer_color", Color(1.0, 0.30, 0.10))
	spec["ammo_type"] = str(load.get("name", load_name))
	spec["tracer"] = bool(load.get("tracer", false))
	return spec

static func is_valid_load(load_name: String) -> bool:
	return LOADS.has(load_name)