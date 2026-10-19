extends Node3D
## Top-down 3D city in the style of 90s overhead crime games: extruded buildings seen from
## straight above with a perspective camera, so walls lean out as you pass them.
## Everything is generated from the city data plus procedural shaders; art packs can
## replace individual meshes/materials later without touching the rules.

signal cell_tapped(cell: Vector2i)

const C := 2.0                     # world units per map cell
const CAM_MIN := 16.0
const CAM_MAX := 60.0

const HEIGHTS := {
	"car_dealer": 2.0, "arms": 2.4, "pub": 2.4, "hotel": 7.0, "bank": 4.6, "print_shop": 2.2,
	"subway": 1.2, "police": 4.0, "station": 3.0, "casino": 3.6, "supermarket": 2.2, "harbor": 2.6,
	"loan_shark": 3.0, "dept_store": 5.2, "city_hall": 4.4, "airport": 2.6,
}

var city: Dictionary = {}
var camera: Camera3D
var _cam_height := 30.0
var _cam_lift := 0.0
var _tokens := {}          # pid -> Node3D
var _display := {}         # pid -> Vector3
var _ring: MeshInstance3D
var _ransom_ring: MeshInstance3D
var _t := 0.0
var _mat_cache := {}


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.near = 0.5
	camera.far = 300.0
	camera.rotation_degrees = Vector3(-90, 0, 0)
	add_child(camera)
	camera.make_current()
	_setup_environment()


func set_city(c: Dictionary) -> void:
	city = c
	for child in get_children():
		if child != camera and not child is WorldEnvironment and not child is DirectionalLight3D:
			child.queue_free()
	_tokens.clear()
	_display.clear()
	_build_city()
	_ring = _make_ring(Color("#35D0BA"), 1.0)
	_ransom_ring = _make_ring(Color("#F2C230"), 3.2)
	_ransom_ring.visible = false


# ------------------------------------------------------------------ environment

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#15171C")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


# ------------------------------------------------------------------ city geometry

func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _std(color: Color, rough: float = 0.85, emit: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), rough, emit]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mat_cache[key] = m
	return m


func _cell_center(x: float, y: float) -> Vector3:
	return Vector3((x + 0.5) * C, 0.0, (y + 0.5) * C)


func _is_road(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < city.w and y < city.h and city.grid[y * city.w + x] == CityGen.ROAD


func _build_city() -> void:
	var w: int = city.w
	var h: int = city.h
	# ground
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2((w + 16) * C, (h + 16) * C)
	ground.mesh = pm
	ground.position = Vector3(w * C / 2.0, -0.02, h * C / 2.0)
	ground.material_override = _shader_mat("res://shaders/ground.gdshader")
	add_child(ground)

	# roads: one mesh, connectivity in vertex colour for the shader
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in h:
		for x in w:
			if not _is_road(x, y):
				continue
			var col := Color(float(_is_road(x, y - 1)), float(_is_road(x + 1, y)), float(_is_road(x, y + 1)), float(_is_road(x - 1, y)))
			_quad(st, Vector3(x * C, 0.0, y * C), C, C, col)
	var roads := MeshInstance3D.new()
	roads.mesh = st.commit()
	roads.material_override = _shader_mat("res://shaders/road.gdshader")
	add_child(roads)

	# sidewalks with raised curbs along every road edge
	var sw := SurfaceTool.new()
	sw.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := 0.42
	var ch := 0.14
	for y in h:
		for x in w:
			if _is_road(x, y):
				continue
			var x0 := x * C
			var z0 := y * C
			if _is_road(x, y - 1):
				_box(sw, Vector3(x0, 0, z0), Vector3(C, ch, k))
			if _is_road(x, y + 1):
				_box(sw, Vector3(x0, 0, z0 + C - k), Vector3(C, ch, k))
			if _is_road(x - 1, y):
				_box(sw, Vector3(x0, 0, z0), Vector3(k, ch, C))
			if _is_road(x + 1, y):
				_box(sw, Vector3(x0 + C - k, 0, z0), Vector3(k, ch, C))
	var walks := MeshInstance3D.new()
	walks.mesh = sw.commit()
	walks.material_override = _shader_mat("res://shaders/concrete.gdshader")
	add_child(walks)

	# trees (one multimesh)
	var tree_spots: Array = []
	for t in city.trees:
		tree_spots.append(Vector3((t[0] + 0.5) * C, 0, (t[1] + 0.5) * C))
	for d in city.decor:
		_build_decor(d, tree_spots)
	for b in city.buildings:
		_build_building(b, tree_spots)
	_build_trees(tree_spots)


func _quad(st: SurfaceTool, origin: Vector3, sx: float, sz: float, col: Color) -> void:
	var p := [origin, origin + Vector3(sx, 0, 0), origin + Vector3(sx, 0, sz), origin + Vector3(0, 0, sz)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_uv(uv[i])
		st.set_normal(Vector3.UP)
		st.add_vertex(p[i])


func _box(st: SurfaceTool, o: Vector3, s: Vector3) -> void:
	# top + four sides (no bottom)
	var v := [o + Vector3(0, s.y, 0), o + Vector3(s.x, s.y, 0), o + Vector3(s.x, s.y, s.z), o + Vector3(0, s.y, s.z),
		o, o + Vector3(s.x, 0, 0), o + Vector3(s.x, 0, s.z), o + Vector3(0, 0, s.z)]
	var faces := [[0, 1, 2, 3, Vector3.UP], [4, 5, 1, 0, Vector3.FORWARD], [6, 7, 3, 2, Vector3.BACK],
		[7, 4, 0, 3, Vector3.LEFT], [5, 6, 2, 1, Vector3.RIGHT]]
	for f in faces:
		var quad := [v[f[0]], v[f[1]], v[f[2]], v[f[3]]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(f[4])
			st.set_uv(Vector2(i % 2, i / 2))
			st.add_vertex(quad[i])


func _mesh_box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	(parent if parent else self).add_child(mi)
	return mi


func _build_building(b: Dictionary, trees: Array) -> void:
	var info: Dictionary = Balance.BUILDINGS[b.type]
	var origin := Vector3(int(b.x) * C, 0, int(b.y) * C)
	var fw: float = int(b.w) * C
	var fd: float = int(b.h) * C
	var center := origin + Vector3(fw / 2.0, 0, fd / 2.0)
	var col := Color(info.color)
	# plaza under every lot
	var plaza := _mesh_box(Vector3(fw - 0.4, 0.06, fd - 0.4), center + Vector3(0, 0.03, 0), _std(Color("#6B6E74"), 0.95))
	plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match b.type:
		"playground":
			_mesh_box(Vector3(fw - 0.6, 0.08, fd - 0.6), center + Vector3(0, 0.06, 0), _std(Color("#4C8A50"), 1.0))
			_mesh_box(Vector3(1.4, 0.1, 1.4), center + Vector3(0.6, 0.12, 0.6), _std(Color("#D8C27A"), 1.0))
			_mesh_box(Vector3(0.3, 0.9, 1.6), center + Vector3(-0.9, 0.45, -0.5), _std(Color("#C9643A"), 0.6))
			_mesh_box(Vector3(1.8, 0.12, 0.12), center + Vector3(0.2, 1.2, -1.0), _std(Color("#3F86A6"), 0.5))
			trees.append(center + Vector3(-1.2, 0, 1.2))
			trees.append(center + Vector3(1.3, 0, -1.3))
		"villa":
			_mesh_box(Vector3(fw - 0.6, 0.08, fd - 0.6), center + Vector3(0, 0.06, 0), _std(Color("#4C8A50"), 1.0))
			var house := _mesh_box(Vector3(2.4, 1.3, 1.8), center + Vector3(-0.3, 0.65, -0.5), _std(Color("#E4DDCC"), 0.8))
			var roof := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(2.6, 0.8, 2.0)
			roof.mesh = prism
			roof.position = Vector3(0, 1.05, 0)
			roof.material_override = _std(Color("#A14B3B"), 0.8)
			house.add_child(roof)
			var pool := _mesh_box(Vector3(1.4, 0.1, 0.9), center + Vector3(0.9, 0.11, 1.0), _std(Color("#4FB3D9"), 0.1, 0.25))
			pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			trees.append(center + Vector3(1.4, 0, -1.3))
		_:
			var hgt: float = HEIGHTS.get(b.type, 2.5)
			var size := Vector3(fw - 0.7, hgt, fd - 0.7)
			var mat := _shader_mat("res://shaders/building.gdshader")
			mat.set_shader_parameter("wall_color", col.darkened(0.15))
			mat.set_shader_parameter("roof_color", col.lerp(Color("#8C8F96"), 0.45))
			mat.set_shader_parameter("size", size)
			mat.set_shader_parameter("seed", float(int(b.id) * 7 % 31))
			mat.set_shader_parameter("lit", 0.3 if b.type != "subway" else 0.0)
			_mesh_box(size, center + Vector3(0, hgt / 2.0, 0), mat)
			var top := hgt
			# rooftop clutter
			_mesh_box(Vector3(0.8, 0.35, 0.55), center + Vector3(-size.x / 2 + 0.7, top + 0.17, -size.z / 2 + 0.6), _std(Color("#A7ADB5"), 0.5))
			_mesh_box(Vector3(0.45, 0.25, 0.45), center + Vector3(size.x / 2 - 0.55, top + 0.12, -size.z / 2 + 0.55), _std(Color("#8C9097"), 0.6))
			if hgt > 3.5:
				var tank := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.38
				cyl.bottom_radius = 0.38
				cyl.height = 0.7
				tank.mesh = cyl
				tank.position = center + Vector3(size.x / 2 - 0.6, top + 0.35, size.z / 2 - 0.6)
				tank.material_override = _std(Color("#7A5C3E"), 0.9)
				add_child(tank)
			if info.sign != "":
				var sign_bg := _mesh_box(Vector3(size.x - 0.5, 0.06, 0.62), center + Vector3(0, top + 0.03, size.z / 2 - 0.55), _std(Color("#1A1C21"), 0.4))
				sign_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_flat_label(info.sign, center + Vector3(0, top + 0.08, size.z / 2 - 0.55), 46, Color("#FFD27A"), true)
	_flat_label(b.name, center + Vector3(0, 0.2, fd / 2.0 - 0.12), 26, Color(1, 1, 1, 0.9), false)


func _flat_label(text: String, pos: Vector3, font_size: int, color: Color, glow: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.012
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = pos
	l.shaded = false
	l.double_sided = false
	if glow:
		l.modulate = color * 1.4
	add_child(l)


func _build_decor(d: Dictionary, trees: Array) -> void:
	var origin := Vector3(int(d.x) * C, 0, int(d.y) * C)
	var center := origin + Vector3(C, 0, C)
	match d.kind:
		"houses":
			var roofs := [Color("#A14B3B"), Color("#7E5A43"), Color("#5E6E7E"), Color("#9C7B4C")]
			for i in 4:
				var off := Vector3(-0.9 + (i % 2) * 1.8, 0, -0.9 + (i / 2) * 1.8)
				var hs := _mesh_box(Vector3(1.4, 0.9, 1.3), center + off + Vector3(0, 0.45, 0), _std(Color("#D9D2C2"), 0.9))
				var roof := MeshInstance3D.new()
				var prism := PrismMesh.new()
				prism.size = Vector3(1.55, 0.6, 1.4)
				roof.mesh = prism
				roof.position = Vector3(0, 0.75, 0)
				roof.rotation_degrees = Vector3(0, 90 * ((int(d.x) + i) % 2), 0)
				roof.material_override = _std(roofs[(int(d.x) + int(d.y) + i) % 4], 0.85)
				hs.add_child(roof)
		"park":
			for i in 5:
				trees.append(center + Vector3(-1.3 + fmod(i * 1.7, 2.6), 0, -1.2 + fmod(i * 1.1, 2.4)))
		"parking":
			var lot := _mesh_box(Vector3(3.4, 0.05, 3.4), center + Vector3(0, 0.03, 0), _std(Color("#2C2F35"), 0.95))
			lot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for i in 5:
				var line := _mesh_box(Vector3(0.06, 0.02, 1.0), center + Vector3(-1.5 + i * 0.75, 0.07, -1.1), _std(Color("#D9DCE1"), 0.6))
				line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var car_cols := [Color("#4F7BC4"), Color("#D7D2C4"), Color("#8C2F2F")]
			for i in 2:
				var car := _make_car(car_cols[(int(d.x) + i) % 3])
				car.position = center + Vector3(-1.1 + i * 1.5, 0, -1.1)
				car.rotation_degrees.y = 90
				add_child(car)
		"pond":
			var water := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 1.4
			cy.bottom_radius = 1.4
			cy.height = 0.06
			water.mesh = cy
			water.position = center + Vector3(0, 0.04, 0)
			water.material_override = _std(Color("#3F86A6"), 0.08)
			add_child(water)
			trees.append(center + Vector3(1.4, 0, 1.3))
		_:
			var mat := _shader_mat("res://shaders/building.gdshader")
			var size := Vector3(3.2, 3.2, 3.2)
			mat.set_shader_parameter("wall_color", Color("#6C7280"))
			mat.set_shader_parameter("roof_color", Color("#80858F"))
			mat.set_shader_parameter("size", size)
			mat.set_shader_parameter("seed", float(int(d.x) * 3 + int(d.y)))
			_mesh_box(size, center + Vector3(0, 1.6, 0), mat)


func _build_trees(spots: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.75
	sphere.height = 1.2
	sphere.radial_segments = 10
	sphere.rings = 6
	mm.mesh = sphere
	mm.instance_count = spots.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in spots.size():
		var s := rng.randf_range(0.75, 1.25)
		var tr := Transform3D(Basis().scaled(Vector3(s, s, s)), spots[i] + Vector3(rng.randf_range(-0.3, 0.3), 0.9 * s, rng.randf_range(-0.3, 0.3)))
		mm.set_instance_transform(i, tr)
		mm.set_instance_color(i, Color(0.18, 0.42, 0.22).lerp(Color(0.32, 0.55, 0.28), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mmi.material_override = mat
	add_child(mmi)


# ------------------------------------------------------------------ tokens

func _make_car(color: Color) -> Node3D:
	var car := Node3D.new()
	_mesh_box(Vector3(1.7, 0.45, 0.9), Vector3(0, 0.38, 0), _std(color, 0.35), car)
	_mesh_box(Vector3(0.85, 0.36, 0.78), Vector3(-0.1, 0.78, 0), _std(color.darkened(0.1), 0.35), car)
	_mesh_box(Vector3(0.08, 0.3, 0.7), Vector3(0.36, 0.76, 0), _std(Color("#1E2430"), 0.1), car)
	_mesh_box(Vector3(0.08, 0.28, 0.7), Vector3(-0.56, 0.76, 0), _std(Color("#1E2430"), 0.1), car)
	for zx in [[0.55, 0.42], [0.55, -0.42], [-0.55, 0.42], [-0.55, -0.42]]:
		_mesh_box(Vector3(0.36, 0.3, 0.14), Vector3(zx[0], 0.16, zx[1]), _std(Color("#111214"), 0.9), car)
	_mesh_box(Vector3(0.05, 0.1, 0.18), Vector3(0.86, 0.42, 0.28), _std(Color("#FFF2B0"), 0.2, 2.0), car)
	_mesh_box(Vector3(0.05, 0.1, 0.18), Vector3(0.86, 0.42, -0.28), _std(Color("#FFF2B0"), 0.2, 2.0), car)
	return car


func _make_person(color: Color) -> Node3D:
	var p := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.0
	body.mesh = cap
	body.position = Vector3(0, 0.5, 0)
	body.material_override = _std(color, 0.7)
	p.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.2
	sp.height = 0.4
	head.mesh = sp
	head.position = Vector3(0.05, 1.12, 0)
	head.material_override = _std(Color("#2A1D17"), 0.9)
	p.add_child(head)
	return p


func _make_ring(color: Color, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.86
	tm.outer_radius = radius
	tm.rings = 32
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _token_target(p: Dictionary) -> Vector3:
	if int(p.inside) >= 0:
		var b: Dictionary = city.buildings[int(p.inside)]
		return Vector3((int(b.x) + 1) * C, 0, (int(b.y) + int(b.h)) * C - 0.3)
	return _cell_center(int(p.pos[0]), int(p.pos[1]))


func _process(delta: float) -> void:
	_t += delta
	if Net.state.is_empty() or city.is_empty():
		return
	var active := Net.active_player()
	var moving := false
	for pid in Net.state.players:
		var p: Dictionary = Net.state.players[pid]
		var key := "%d|%d" % [pid, 1 if int(p.car) > 0 else 0]
		if not _tokens.has(pid) or _tokens[pid].get_meta("key") != key:
			if _tokens.has(pid):
				_tokens[pid].queue_free()
			var tok: Node3D = _make_car(Color(p.color)) if int(p.car) > 0 else _make_person(Color(p.color))
			tok.set_meta("key", key)
			add_child(tok)
			_tokens[pid] = tok
			_display[pid] = _token_target(p)
		var tok2: Node3D = _tokens[pid]
		tok2.visible = int(p.jail) == 0 and int(p.holiday) == 0
		var target := _token_target(p)
		var cur: Vector3 = _display[pid]
		var nxt := cur.lerp(target, minf(1.0, delta * 10.0))
		var mv := nxt - cur
		if mv.length() > 0.01:
			tok2.rotation.y = atan2(-mv.z, mv.x)
			if not active.is_empty() and int(active.id) == int(pid):
				moving = true
		_display[pid] = nxt
		tok2.position = nxt
	if not active.is_empty() and _display.has(active.id):
		var focus: Vector3 = _display[active.id]
		_ring.visible = true
		_ring.position = focus + Vector3(0, 0.18, 0)
		var s := 1.0 + 0.08 * sin(_t * 5.0)
		_ring.scale = Vector3(s, 1, s)
		# GTA-style: the camera lifts a little while the active player is moving
		_cam_lift = lerpf(_cam_lift, 6.0 if moving else 0.0, delta * 2.0)
		var cam_target := Vector3(focus.x, _cam_height + _cam_lift, focus.z)
		camera.position = camera.position.lerp(cam_target, minf(1.0, delta * 5.0))
	var me := Net.my_player()
	if not me.is_empty() and not me.ransom.is_empty():
		var rb: Dictionary = city.buildings[int(me.ransom.building)]
		_ransom_ring.visible = true
		_ransom_ring.position = Vector3((int(rb.x) + 1) * C, 0.25 + 0.15 * sin(_t * 4.0), (int(rb.y) + 1) * C)
	else:
		_ransom_ring.visible = false


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_height = clampf(_cam_height - 3.0, CAM_MIN, CAM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_height = clampf(_cam_height + 3.0, CAM_MIN, CAM_MAX)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var origin := camera.project_ray_origin(event.position)
			var dir := camera.project_ray_normal(event.position)
			if absf(dir.y) < 0.0001:
				return
			var hit := origin + dir * (-origin.y / dir.y)
			cell_tapped.emit(Vector2i(floori(hit.x / C), floori(hit.z / C)))
	elif event is InputEventMagnifyGesture:
		_cam_height = clampf(_cam_height / event.factor, CAM_MIN, CAM_MAX)
