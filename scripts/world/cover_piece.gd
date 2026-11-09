extends StaticBody3D

const IMPACT_FX = preload("res://scripts/effects/impact_fx.gd")

@export var integrity: float = 600.0
@export var armor_rating: float = 0.25
@export var surface: String = "sand"
@export var max_integrity: float = 600.0

func _ready() -> void:
	add_to_group("destructible_cover")
	set_meta("surface", surface)
	if max_integrity <= 0.0:
		max_integrity = maxf(integrity, 1.0)

func apply_ballistic_damage(damage: float, penetration: float, _caliber: String = "") -> void:
	var effectiveness := clampf(penetration / maxf(armor_rating, 0.08), 0.08, 1.0)
	integrity -= damage * effectiveness
	if integrity <= 0.0:
		_break_apart()

func _break_apart() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		IMPACT_FX.spawn_destruction(scene, global_position, surface)
	queue_free()
