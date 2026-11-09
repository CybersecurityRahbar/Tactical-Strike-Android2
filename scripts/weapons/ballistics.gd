extends RefCounted

# Real cartridge data used by the ballistic solver.
#
# muzzle_velocity  : published service-load velocity in m/s.
# bullet_mass_g    : projectile mass in grams (used for kinetic energy).
# drag_per_meter   : exponential velocity-retention constant, fitted so the
#                    solver reproduces published retained velocities, e.g.
#                    5.45x39 7N6 ~550 m/s at 400 m, 7.62x39 ~486 m/s at 274 m,
#                    7.62x54R ~450 m/s at 500 m, 12.7x108 ~560 m/s at 500 m.
# penetration      : relative penetration index used against cover armour.
# crack_pitch      : perceived supersonic crack pitch (gameplay tuning).
#
# The solver intentionally keeps drag as a velocity-dependent quadratic law
# (a = -k*v^2) instead of a full G1/G7 table: it is stable at any frame rate,
# matches the published velocity curves closely inside 600 m, and costs nothing
# on a phone. Drop is integrated from gravity, so longer flight time at long
# range produces the correct hold-over.

const SPEED_OF_SOUND_MPS := 343.0
const GRAVITY := 9.81

const CALIBERS := {
	"5.45x39": {
		"name": "5.45×39 mm",
		"bullet_mass_g": 3.43,
		"muzzle_velocity": 900.0,
		"drag_per_meter": 0.00130,
		"penetration": 0.34,
		"crack_pitch": 1.0,
		"tracer_color": Color(1.0, 0.30, 0.10),
		"dust_color": Color(0.52, 0.42, 0.29)
	},
	"7.62x39": {
		"name": "7.62×39 mm",
		"bullet_mass_g": 7.90,
		"muzzle_velocity": 715.0,
		"drag_per_meter": 0.00140,
		"penetration": 0.41,
		"crack_pitch": 0.86,
		"tracer_color": Color(0.95, 0.42, 0.12),
		"dust_color": Color(0.50, 0.40, 0.28)
	},
	"5.56x45": {
		"name": "5.56×45 mm",
		"bullet_mass_g": 4.00,
		"muzzle_velocity": 948.0,
		"drag_per_meter": 0.00145,
		"penetration": 0.30,
		"crack_pitch": 1.08,
		"tracer_color": Color(1.0, 0.34, 0.12),
		"dust_color": Color(0.54, 0.44, 0.31)
	},
	"7.62x54R": {
		"name": "7.62×54 mm R",
		"bullet_mass_g": 9.60,
		"muzzle_velocity": 830.0,
		"drag_per_meter": 0.00122,
		"penetration": 0.55,
		"crack_pitch": 0.78,
		"tracer_color": Color(0.85, 1.0, 0.35),
		"dust_color": Color(0.48, 0.38, 0.27)
	},
	"12.7x108": {
		"name": "12.7×108 mm",
		"bullet_mass_g": 48.30,
		"muzzle_velocity": 860.0,
		"drag_per_meter": 0.00086,
		"penetration": 1.35,
		"crack_pitch": 0.62,
		"tracer_color": Color(1.0, 0.55, 0.16),
		"dust_color": Color(0.45, 0.35, 0.24)
	},
	"9x19": {
		"name": "9×19 mm",
		"bullet_mass_g": 8.00,
		"muzzle_velocity": 380.0,
		"drag_per_meter": 0.00236,
		"penetration": 0.12,
		"crack_pitch": 1.4,
		"tracer_color": Color(1.0, 0.40, 0.14),
		"dust_color": Color(0.53, 0.43, 0.30)
	}
}

static func profile(caliber_id: String) -> Dictionary:
	var source: Dictionary = CALIBERS.get(caliber_id, CALIBERS["5.45x39"])
	var copy := source.duplicate(true)
	copy["id"] = caliber_id
	return copy

static func has_caliber(caliber_id: String) -> bool:
	return CALIBERS.has(caliber_id)

# Exponential velocity retention inside 600 m (validated against published
# tables); clamped so a round never stops dead in the air.
static func speed_at(cal: Dictionary, distance_m: float) -> float:
	var k := float(cal.get("drag_per_meter", 0.0013))
	var v0 := float(cal.get("muzzle_velocity", 900.0))
	return v0 * exp(-k * maxf(distance_m, 0.0))

static func energy_j(cal: Dictionary, speed: float) -> float:
	var mass_kg := float(cal.get("bullet_mass_g", 3.43)) / 1000.0
	return 0.5 * mass_kg * speed * speed

static func muzzle_energy_j(cal: Dictionary) -> float:
	return energy_j(cal, float(cal.get("muzzle_velocity", 900.0)))

static func time_of_flight(cal: Dictionary, distance_m: float) -> float:
	var k := float(cal.get("drag_per_meter", 0.0013))
	var v0 := float(cal.get("muzzle_velocity", 900.0))
	distance_m = maxf(distance_m, 0.0)
	return (exp(k * distance_m) - 1.0) / maxf(k * v0, 0.0001)

# Gravity drop in metres (no sight-line compensation).
static func drop_at(cal: Dictionary, distance_m: float) -> float:
	var t := time_of_flight(cal, distance_m)
	return 0.5 * GRAVITY * t * t

# Gameplay damage curve: a round keeps most of its lethality far downrange,
# but energy loss is still visible at 500 m+.
static func damage_at(cal: Dictionary, speed: float, base_damage: float) -> float:
	var e0 := maxf(muzzle_energy_j(cal), 1.0)
	var ratio := clampf(energy_j(cal, speed) / e0, 0.04, 1.0)
	return base_damage * pow(ratio, 0.55)

static func penetration_at(cal: Dictionary, speed: float) -> float:
	var base := float(cal.get("penetration", 0.34))
	var ratio := clampf(speed / maxf(float(cal.get("muzzle_velocity", 900.0)), 1.0), 0.15, 1.2)
	return base * pow(ratio, 0.45)

static func is_supersonic(speed: float) -> bool:
	return speed > SPEED_OF_SOUND_MPS

# How loud a projectile crack is perceived near its flight path, 0..1.
static func crack_strength(cal: Dictionary, speed: float) -> float:
	var mach := speed / SPEED_OF_SOUND_MPS
	if mach <= 1.0:
		return 0.0
	return clampf((mach - 1.0) / 1.6, 0.05, 1.0)

# Utility used by tests and the HUD to describe a shot in plain language.
static func describe_shot(cal: Dictionary, distance_m: float) -> String:
	var speed := speed_at(cal, distance_m)
	return "%s  %.0f m  %.0f m/s  %.0f J" % [
		str(cal.get("name", "caliber")),
		distance_m,
		speed,
		energy_j(cal, speed)
	]
