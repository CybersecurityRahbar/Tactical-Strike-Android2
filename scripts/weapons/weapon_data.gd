extends RefCounted

# Weapon + ammunition authoring data.
#
# Everything that used to be hard-coded in the controller now lives here:
# the cartridge, the three service loads, recoil, dispersion, the ADS zoom,
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

static func all_weapons() -> Array[Dictionary]:
	return [
		{
			"id": "ak74m",
			"name": "AK-74M",
			"caliber": "5.45×39 mm",
			"caliber_id": "5.45x39",
			"model_key": "ak74m",
			"audio_profile": "ak",
			"muzzle_velocity": 900.0,
			"gravity_scale": 1.0,
			"damage": 38.0,
			"penetration": 0.34,
			"max_range": 900.0,
			# Sights regulated for the map's main engagement distance. Gravity
			# drop at 300 m is compensated by the launch angle, so the round
			# crosses the crosshair there; closer and farther shots deviate
			# physically instead of always hitting low.
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
			# The imported rig is authored with the rifle's barrel along +Z in
			# scene space (stock toward -Z), so it must be yawed 180 degrees to
			# point down the camera's -Z forward axis. The previous +90 yaw
			# presented the rifle sideways/backwards across the screen.
			"view_rotation_degrees": Vector3(0.0, 180.0, 0.0),
			"view_scale": 0.46,
			"view_hip_position": Vector3(0.31, -0.34, -0.58),
			# The bore centreline sits at model x = -0.10; after the 180-degree mount
			# it lands at +0.10, so ADS shifts the rig left to put the sights on the
			# camera axis.
			"view_ads_position": Vector3(-0.10, -0.175, -0.44),
			"tracer_ignition_distance": 22.0
		}
	]

static func ammo_names(weapon: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for entry in weapon.get("ammo_types", ["FMJ", "TRACER", "AP"]):
		result.append(str(entry))
	if result.is_empty():
		result = ["FMJ"]
	return result

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
