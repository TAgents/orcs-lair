class_name AtmosphereParticles
extends RefCounted

# Helpers that build common atmospheric GPUParticles3D nodes used to dress
# the lair. Each factory returns a fully-configured emitter ready to be
# `add_child`'d at the desired global position. Skipped at the call site
# in headless via the standard DisplayServer guard.

# Lair-wide dust motes — slow downward drift, faint white specks lit by
# every nearby torch / firepit. Single emitter covering a 22m × 22m box
# is cheap and reads well at the chibi scale.
static func dust_motes(extents: Vector3 = Vector3(11.0, 4.0, 11.0)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 80
	p.lifetime = 8.0
	p.preprocess = 5.0  # already-floating motes when the scene loads
	p.randomness = 0.5
	p.fixed_fps = 30  # particles don't need 60Hz
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = extents
	mat.gravity = Vector3(0, -0.08, 0)
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.10
	mat.angular_velocity_min = -10.0
	mat.angular_velocity_max = 10.0
	mat.scale_min = 0.04
	mat.scale_max = 0.10
	mat.color = Color(1.0, 0.95, 0.85, 0.6)
	p.process_material = mat
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	sphere.radial_segments = 6
	sphere.rings = 3
	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.albedo_color = Color(1.0, 0.95, 0.85, 0.7)
	sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_mat.emission_enabled = true
	sphere_mat.emission = Color(1.0, 0.85, 0.6, 1)
	sphere_mat.emission_energy_multiplier = 0.4
	sphere.material = sphere_mat
	p.draw_pass_1 = sphere
	return p

# Wispy upward smoke for torches / fire pits. Local-space, attached as a
# child of the light node so it follows. Anisotropic upward + slight
# expansion + fade.
static func torch_smoke(scale: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 20
	p.lifetime = 2.4
	p.randomness = 0.7
	p.fixed_fps = 30
	p.position = Vector3(0, 0.4 * scale, 0)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05 * scale
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 0.4 * scale
	mat.initial_velocity_max = 0.7 * scale
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 18.0
	mat.scale_min = 0.10 * scale
	mat.scale_max = 0.22 * scale
	mat.scale_curve = _grow_curve()
	mat.color = Color(0.3, 0.27, 0.25, 0.4)
	mat.alpha_curve = _fade_curve()
	p.process_material = mat
	var sphere := SphereMesh.new()
	sphere.radius = 0.18 * scale
	sphere.height = 0.36 * scale
	sphere.radial_segments = 6
	sphere.rings = 3
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.35, 0.30, 0.28, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = sm
	p.draw_pass_1 = sphere
	return p

# Hot orange sparks shooting upward in short bursts. One-shot per craft
# tick — caller emits manually via `restart()` to time bursts to a
# gameplay event (forge step, hit impact).
static func sparks_burst(count: int = 14, scale: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.randomness = 0.6
	p.fixed_fps = 60
	p.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05 * scale
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 35.0
	mat.gravity = Vector3(0, -3.5, 0)
	mat.initial_velocity_min = 1.6 * scale
	mat.initial_velocity_max = 3.0 * scale
	mat.scale_min = 0.04 * scale
	mat.scale_max = 0.08 * scale
	mat.color = Color(1.0, 0.7, 0.25, 1.0)
	mat.alpha_curve = _fade_curve()
	p.process_material = mat
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.05) * scale
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.8, 0.4, 1)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.6, 0.2, 1)
	bm.emission_energy_multiplier = 3.0
	box.material = bm
	p.draw_pass_1 = box
	return p

# Gentle white kitchen steam — slower than smoke, brighter, wider spread.
static func kitchen_steam(scale: float = 1.0) -> GPUParticles3D:
	var p := torch_smoke(scale)
	var mat := p.process_material as ParticleProcessMaterial
	mat.color = Color(0.95, 0.97, 1.0, 0.5)
	mat.spread = 28.0
	mat.initial_velocity_min = 0.3 * scale
	mat.initial_velocity_max = 0.55 * scale
	(p.draw_pass_1 as SphereMesh).material = _white_steam_mat()
	p.lifetime = 3.2
	p.amount = 28
	return p

static func _white_steam_mat() -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.95, 0.97, 1.0, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return sm

# Curve helpers — Godot doesn't expose simple-value setters for these so
# we bake a Curve resource each call (cheap; callers cache the emitter).
static func _grow_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.4))
	c.add_point(Vector2(0.5, 0.9))
	c.add_point(Vector2(1.0, 1.2))
	var t := CurveTexture.new()
	t.curve = c
	return t

static func _fade_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var t := CurveTexture.new()
	t.curve = c
	return t
