extends RefCounted

static func spawn_dust(parent: Node, position: Vector3, normal: Vector3, heavy: bool = false) -> void:
	var particles := CPUParticles3D.new()
	particles.name = "BallisticImpactDust"
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 42 if heavy else 18
	particles.lifetime = 0.85 if heavy else 0.58
	particles.direction = normal.normalized()
	particles.spread = 58.0
	particles.initial_velocity_min = 2.8 if heavy else 1.2
	particles.initial_velocity_max = 8.5 if heavy else 4.2
	particles.gravity = Vector3(0.0, -11.0, 0.0)
	particles.color = Color(0.50, 0.39, 0.27, 0.78)
	var dust_dot := SphereMesh.new()
	dust_dot.radius = 0.055 if heavy else 0.035
	dust_dot.height = dust_dot.radius * 2.0
	particles.mesh = dust_dot
	parent.add_child(particles)
	particles.global_position = position + normal.normalized() * 0.04
	particles.emitting = true
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 1.5
	timer.timeout.connect(particles.queue_free)
	particles.add_child(timer)
	timer.start()
