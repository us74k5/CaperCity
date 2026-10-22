class_name WeaponFx
## One-shot visual effects for the fight arena: muzzle flashes, tracers, ejected shells, blood,
## bullet impacts, melee swing trails, explosions and scorch marks. Everything is built from plain
## meshes and CPU particles so it runs the same in the browser (Compatibility renderer) as on desktop.
## All positions are in the parent's local space. Effects free themselves.

const BLOOD := Color(0.45, 0.02, 0.03)
const DUST := Color(0.55, 0.5, 0.42)

static var _mats := {}


# ------------------------------------------------------------------ guns

## Muzzle flash pointing along `dir` (scaled by `size`: pistol 1, rifle 1.4, machine gun 1.1).
static func muzzle_flash(parent: Node3D, pos: Vector3, dir: Vector3, size := 1.0) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	_face(root, dir)
	var outer := _sphere_mi(0.05 * size, _glow(Color(1.0, 0.55, 0.15)))
	outer.scale = Vector3(1, 1, 3.2)
	outer.position.z = 0.1 * size
	root.add_child(outer)
	var core := _sphere_mi(0.035 * size, _glow(Color(1.0, 0.95, 0.75)))
	core.scale = Vector3(1, 1, 2.0)
	core.position.z = 0.05 * size
	root.add_child(core)
	# side petals, like a real flash hider's star
	for a in [0.0, 90.0]:
		var petal := _sphere_mi(0.022 * size, _glow(Color(1.0, 0.7, 0.3)))
		petal.scale = Vector3(4.0, 0.5, 0.6)
		petal.rotation_degrees.z = a + randf_range(-20, 20)
		petal.position.z = 0.04 * size
		root.add_child(petal)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 3.0 * size
	light.omni_range = 2.2 * size
	light.position.z = 0.15
	root.add_child(light)
	root.rotation.z = randf() * TAU
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3(0.2, 0.2, 0.2), 0.07).from(Vector3.ONE * randf_range(0.85, 1.15))
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.07)
	tw.tween_callback(root.queue_free)
	gun_smoke(parent, pos + dir * 0.12, dir, size)


## A glowing streak that flies from `from` to `to`.
static func tracer(parent: Node3D, from: Vector3, to: Vector3, speed := 45.0) -> float:
	var d := to - from
	var dist := d.length()
	if dist < 0.01:
		return 0.0
	var streak := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.014, 0.014, minf(0.5, dist * 0.5))
	streak.mesh = bm
	streak.material_override = _glow(Color(1.0, 0.85, 0.45))
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(streak)
	streak.position = from
	_face(streak, d)
	var t := dist / speed
	var tw := streak.create_tween()
	tw.tween_property(streak, "position", to, t)
	tw.tween_callback(streak.queue_free)
	return t


## A brass casing kicked out to the right of the gun, bouncing once and left lying on the street.
static func eject_shell(parent: Node3D, pos: Vector3, dir: Vector3, big := false) -> void:
	var shell := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008 if big else 0.006
	cm.bottom_radius = cm.top_radius
	cm.height = 0.04 if big else 0.024
	cm.radial_segments = 6
	cm.rings = 1
	shell.mesh = cm
	shell.material_override = WeaponModels.mat("brass")
	parent.add_child(shell)
	shell.position = pos
	var right := dir.cross(Vector3.UP).normalized() * -1.0
	var land := pos + right * randf_range(0.25, 0.45) - dir * randf_range(0.0, 0.15)
	land.y = 0.03
	var peak := pos.lerp(land, 0.5) + Vector3(0, 0.25, 0)
	var spin := Vector3(randf_range(8, 16), randf_range(4, 10), 0)
	var tw := shell.create_tween()
	tw.tween_method(func(k: float):
		shell.position = _bezier(pos, peak, land, k)
		shell.rotation = spin * k, 0.0, 1.0, 0.32)
	tw.tween_property(shell, "position", land + right * 0.06 + Vector3(0, 0.03, 0), 0.08)
	tw.tween_property(shell, "position", land + right * 0.1, 0.08)
	tw.tween_property(shell, "rotation", Vector3(PI / 2, randf() * TAU, 0), 0.1)
	tw.tween_interval(6.0)
	tw.tween_property(shell, "scale", Vector3.ZERO, 0.4)
	tw.tween_callback(shell.queue_free)


static func gun_smoke(parent: Node3D, pos: Vector3, dir: Vector3, size := 1.0) -> void:
	var p := _particles(parent, pos, 6, 0.9, Color(0.75, 0.75, 0.75, 0.35), 0.05 * size, 0.11 * size)
	p.direction = dir + Vector3(0, 0.6, 0)
	p.spread = 25.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 0.6
	p.damping_max = 1.0
	_fire(p, 1.2)


# ------------------------------------------------------------------ impacts

## Blood spray at a hit, thrown in the direction the shot/blow travelled, plus a stain on the street.
static func blood(parent: Node3D, pos: Vector3, dir: Vector3, amount := 1.0) -> void:
	var p := _particles(parent, pos, int(14 * amount), 0.55, BLOOD, 0.018, 0.04)
	p.direction = dir.normalized() + Vector3(0, 0.35, 0)
	p.spread = 38.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0 * amount
	p.gravity = Vector3(0, -6.0, 0)
	_fire(p, 0.8)
	splat(parent, Vector3(pos.x, 0.0, pos.z) + dir.normalized() * 0.2, Color(BLOOD, 0.85), 0.08 + 0.06 * amount, 20.0)


## A flat stain on the street (blood, scorch).
static func splat(parent: Node3D, pos: Vector3, col: Color, radius: float, life: float) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = Vector3(pos.x, 0.026 + randf() * 0.004, pos.z)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 4:
		var blob := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r := radius * (1.0 if i == 0 else randf_range(0.25, 0.5))
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.002
		cm.radial_segments = 14
		cm.rings = 1
		blob.mesh = cm
		blob.material_override = m
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blob.scale = Vector3(randf_range(0.8, 1.3), 1, randf_range(0.7, 1.1))
		if i > 0:
			var a := randf() * TAU
			blob.position = Vector3(cos(a), 0, sin(a)) * radius * randf_range(0.8, 1.5)
		holder.add_child(blob)
	holder.scale = Vector3(0.3, 1, 0.3)
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_interval(life)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.5)
	tw.tween_callback(holder.queue_free)


## A bullet that missed: a puff of grit and a couple of sparks off the street.
static func ricochet(parent: Node3D, pos: Vector3, dir: Vector3) -> void:
	var g := _particles(parent, pos, 10, 0.5, DUST, 0.02, 0.05)
	g.direction = -dir.normalized() + Vector3(0, 1.2, 0)
	g.spread = 40.0
	g.initial_velocity_min = 0.6
	g.initial_velocity_max = 1.4
	g.gravity = Vector3(0, -5, 0)
	_fire(g, 0.7)
	var s := _particles(parent, pos, 5, 0.18, Color(1.0, 0.8, 0.4), 0.008, 0.012, true)
	s.direction = Vector3(dir.x, 0.6, dir.z)
	s.spread = 50.0
	s.initial_velocity_min = 2.0
	s.initial_velocity_max = 4.0
	s.gravity = Vector3(0, -8, 0)
	_fire(s, 0.4)
	splat(parent, pos, Color(0.12, 0.12, 0.13, 0.7), 0.035, 6.0)


## A melee blow landing: a small burst of dust/sweat (blood on top if it drew blood).
static func impact(parent: Node3D, pos: Vector3, dir: Vector3) -> void:
	var p := _particles(parent, pos, 8, 0.3, Color(0.9, 0.9, 0.85, 0.7), 0.015, 0.03)
	p.direction = dir.normalized()
	p.spread = 60.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3.ZERO
	p.damping_min = 3.0
	p.damping_max = 5.0
	_fire(p, 0.5)


## A white arc where a melee weapon swings: `pos` is the fighter's chest, facing `dir`.
static func swing_trail(parent: Node3D, pos: Vector3, dir: Vector3, reach := 0.45, col := Color(1, 1, 1, 0.55)) -> void:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var steps := 14
	for i in steps + 1:
		var k := float(i) / steps
		var a := lerpf(-1.2, 1.0, k)    # right-to-left sweep across the front
		var out := Vector3(sin(a), 0, cos(a))
		var c := col
		c.a = col.a * k * k
		im.surface_set_color(c)
		im.surface_add_vertex(out * reach * 0.55 + Vector3(0, 0.06 * (1.0 - k), 0))
		im.surface_set_color(c)
		im.surface_add_vertex(out * reach + Vector3(0, -0.04 * k, 0))
	im.surface_end()
	parent.add_child(mi)
	mi.position = pos
	mi.rotation.y = atan2(dir.x, dir.z)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.22).from(1.0)
	tw.tween_callback(mi.queue_free)


# ------------------------------------------------------------------ explosions

## A grenade going off: flash, fireball, debris, rolling smoke and a scorch mark. Returns nothing;
## the caller shakes the camera and plays the sound.
static func explosion(parent: Node3D, pos: Vector3, size := 1.0) -> void:
	var base := Vector3(pos.x, 0.05, pos.z)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 8.0
	light.omni_range = 5.0 * size
	parent.add_child(light)
	light.position = base + Vector3(0, 0.6, 0)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	lt.tween_callback(light.queue_free)
	# fireball: hot core inside an orange shell, both swelling and fading
	for layer in [[Color(1.0, 0.95, 0.7), 0.35, 0.18], [Color(1.0, 0.5, 0.12), 0.6, 0.3], [Color(0.85, 0.22, 0.05), 0.75, 0.42]]:
		var ball := _sphere_mi(1.0, _glow(layer[0]))
		parent.add_child(ball)
		ball.position = base + Vector3(0, 0.15, 0)
		ball.scale = Vector3.ONE * 0.05
		var r: float = layer[1] * size
		var t: float = layer[2]
		var mat: StandardMaterial3D = ball.material_override
		var tw := ball.create_tween()
		tw.tween_property(ball, "scale", Vector3(r, r * 0.8, r), t).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tw.parallel().tween_property(ball, "position:y", 0.15 + r * 0.4, t)
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, t).set_delay(t * 0.4)
		tw.tween_callback(ball.queue_free)
	# shock ring along the ground
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	ring.mesh = tm
	var rm := _glow(Color(1.0, 0.85, 0.6, 0.6))
	ring.material_override = rm
	parent.add_child(ring)
	ring.position = base
	var rt := ring.create_tween()
	rt.tween_property(ring, "scale", Vector3(1.6, 0.3, 1.6) * size, 0.3).from(Vector3(0.1, 0.3, 0.1))
	rt.parallel().tween_property(rm, "albedo_color:a", 0.0, 0.3)
	rt.tween_callback(ring.queue_free)
	# debris
	var d := _particles(parent, base + Vector3(0, 0.1, 0), 26, 0.9, Color(0.12, 0.11, 0.1), 0.02, 0.05)
	d.direction = Vector3.UP
	d.spread = 70.0
	d.initial_velocity_min = 2.0
	d.initial_velocity_max = 4.5
	d.gravity = Vector3(0, -9, 0)
	_fire(d, 1.0)
	var sp := _particles(parent, base + Vector3(0, 0.15, 0), 16, 0.45, Color(1.0, 0.7, 0.3), 0.01, 0.02, true)
	sp.direction = Vector3.UP
	sp.spread = 85.0
	sp.initial_velocity_min = 3.0
	sp.initial_velocity_max = 6.0
	sp.gravity = Vector3(0, -9, 0)
	_fire(sp, 0.5)
	# smoke column
	var s := _particles(parent, base + Vector3(0, 0.3, 0), 18, 2.2, Color(0.2, 0.2, 0.21, 0.55), 0.15, 0.32)
	s.direction = Vector3.UP
	s.spread = 45.0
	s.initial_velocity_min = 0.3
	s.initial_velocity_max = 0.9
	s.gravity = Vector3(0, 0.35, 0)
	s.damping_min = 0.4
	s.damping_max = 0.8
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.35 * size
	_fire(s, 2.6)
	splat(parent, base, Color(0.05, 0.05, 0.05, 0.75), 0.55 * size, 15.0)


# ------------------------------------------------------------------ helpers

static func _particles(parent: Node3D, pos: Vector3, amount: int, life: float, col: Color, size_min: float, size_max: float, glow := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	var m := _glow(col) if glow else StandardMaterial3D.new()
	if not glow:
		m.albedo_color = Color.WHITE
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.8
		if col.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = m
	p.mesh = sm
	p.color = col
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	p.position = pos
	parent.add_child(p)
	return p


static func _fire(p: CPUParticles3D, free_after: float) -> void:
	p.restart()
	p.emitting = true
	p.get_tree().create_timer(free_after + p.lifetime).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())


static func _glow(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	return m


static func _sphere_mi(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Turn `n` so its local +Z points along `dir`.
static func _face(n: Node3D, dir: Vector3) -> void:
	if dir.length() < 0.0001:
		return
	var z := dir.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	n.basis = Basis(x, z.cross(x), z)


static func _bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)
