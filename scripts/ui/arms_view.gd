extends Node3D
## Inside the arms dealer, which is two rooms: the gun store out front (pegboard walls of rifles
## and pistols, a lit glass counter, ammo shelves, the clerk) and the gym in the back (lockers with
## your crew's names on them, a bench press, a heavy bag, mirrors), where the camera goes while
## you're in "Train your crew". The HUD shows the crew's stats beside it.

const MODELS := "res://assets/models/"
const PERSON := 1.5
const GYM := Vector3(24, 0, 0)       # the back room, beside the store
const C_FLOOR := Color("#8E9096")
const C_WALL := Color("#C9C2B0")
const C_PEG := Color("#B08A5A")
const C_STEEL := Color("#2E3238")
const C_WOOD := Color("#6B4A2E")
const C_RED := Color("#E0322A")
const C_LOCKER := Color("#4F6E8C")
const C_RUBBER := Color("#26282C")

var mode := "shop"                   # "shop" or "gym"
var _cam := Transform3D()
var _cam_ready := false
var _bag: Node3D
var _crew_key := ""
var _crew_nodes: Array = []
var _t := 0.0


func build(b: Dictionary, p: Dictionary, crew_looks: Array) -> void:
	_store(b)
	_gym()
	update(p, crew_looks)


## Follows the menu: the gym while training, the store otherwise; the gym shows the crew as it is.
func update(p: Dictionary, crew_looks: Array) -> void:
	var training := false
	for step in p.get("menu_path", []):
		if str(step).begins_with("train"):
			training = true
	mode = "gym" if training else "shop"
	var key := "%s:%d" % [UiTheme.look_of(p), p.crew.size()]
	if key != _crew_key:
		_crew_key = key
		for n in _crew_nodes:
			n.queue_free()
		_crew_nodes.clear()
		_place_crew(p, crew_looks)


func camera_pose(aspect: float) -> Transform3D:
	var base := GYM if mode == "gym" else Vector3.ZERO
	# Aimed a little right of the room's middle: the menu covers the right of the screen (and in the
	# gym the crew's stats cover the left).
	var shift := 1.2 if mode == "gym" else 1.6
	var eye := base + Vector3(shift, 4.6, 12.5)
	var look := base + Vector3(shift, 2.2, -3.0)
	if aspect < 1.2:
		eye = base + Vector3(0, 7.5, 15.0)
		look = base + Vector3(0, 1.4, -2.6)
	var target := Transform3D(Basis.looking_at(look - eye, Vector3.UP), global_position + eye)
	if not _cam_ready:
		_cam = target
		_cam_ready = true
	_cam = _cam.interpolate_with(target, 0.08)
	return _cam


func _process(delta: float) -> void:
	_t += delta
	if _bag:
		_bag.rotation.z = 0.06 * sin(_t * 2.1)
		_bag.rotation.x = 0.03 * sin(_t * 1.3)


# ------------------------------------------------------------------ the store

func _store(b: Dictionary) -> void:
	_floor(Vector3.ZERO, Vector2(18, 14), C_FLOOR, Color("#7E8086"))
	# Walls: back and sides, the back one hung with pegboard.
	_box(Vector3(18, 5, 0.3), Vector3(0, 2.5, -7), C_WALL)
	_box(Vector3(0.3, 5, 14), Vector3(-9, 2.5, 0), C_WALL)
	_box(Vector3(0.3, 5, 14), Vector3(9, 2.5, 0), C_WALL)
	var peg := _box(Vector3(14, 3.0, 0.08), Vector3(0, 2.3, -6.8), C_PEG)
	peg.material_override = _pegboard()
	# Rifles racked across the pegboard, three rows.
	for row in 3:
		for i in 6:
			var x := -5.6 + i * 2.25
			_rifle(Vector3(x, 1.35 + row * 0.85, -6.68), row * 6 + i)
	# Neon store name over it all, red like the sign outside.
	var sign := _text(str(b.name).to_upper(), 120, C_RED)
	sign.position = Vector3(0, 4.3, -6.8)
	sign.outline_modulate = Color("#4A0B08")
	add_child(sign)
	var stripe := _box(Vector3(18, 0.14, 0.1), Vector3(0, 3.82, -6.82), C_RED)
	_glow(stripe, C_RED)

	# The glass counter, lit from inside, with handguns on red felt.
	_box(Vector3(9.0, 0.5, 1.4), Vector3(0.5, 0.25, -3.6), C_WOOD)
	_box(Vector3(9.0, 0.04, 1.3), Vector3(0.5, 0.52, -3.6), Color("#7A1414"))
	for i in 7:
		_pistol(Vector3(-3.0 + i * 1.15, 0.57, -3.6), i)
	var glass := _box(Vector3(9.0, 0.32, 1.4), Vector3(0.5, 0.7, -3.6), Color(0.75, 0.9, 1.0, 0.18))
	var gm: StandardMaterial3D = glass.material_override
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.metallic = 0.3
	gm.roughness = 0.05
	var strip := _box(Vector3(8.8, 0.04, 0.06), Vector3(0.5, 0.88, -3.0), Color("#FFF6D8"))
	_glow(strip, Color("#FFF6D8"))
	_box(Vector3(0.6, 0.3, 0.4), Vector3(4.4, 1.0, -3.6), Color("#1B1D21"))   # the till
	# The clerk, behind the counter.
	_extra("character-male-a", Vector3(1.2, 0, -4.7), 0.0)

	# Ammo shelves down the left wall, targets and the range door on the right.
	for shelf in 4:
		var y := 0.5 + shelf * 0.8
		_box(Vector3(0.6, 0.06, 5.0), Vector3(-8.5, y, -2.0), C_STEEL)
		for k in 9:
			var col: Color = [Color("#C8423B"), Color("#3E8A5C"), Color("#D9A23A"), Color("#2F5FA8")][(k + shelf) % 4]
			_box(Vector3(0.4, 0.32, 0.4), Vector3(-8.5, y + 0.19, -4.2 + k * 0.55), col)
	var ammo := _text("AMMO", 64, Color("#FFD27A"))
	ammo.position = Vector3(-8.7, 3.9, -2.0)
	ammo.rotation.y = PI / 2
	add_child(ammo)
	for i in 3:
		var target := _box(Vector3(0.06, 1.3, 0.9), Vector3(8.8, 2.4, -4.6 + i * 1.3), Color.WHITE)
		target.material_override = _target_mat()
	_box(Vector3(0.12, 2.6, 1.6), Vector3(8.82, 1.3, 1.6), Color("#3A3F49"))
	var range_ := _text("RANGE", 48, C_RED)
	range_.position = Vector3(8.7, 2.95, 1.6)
	range_.rotation.y = -PI / 2
	add_child(range_)
	# Strip lights overhead.
	for x in [-4.5, 0.0, 4.5]:
		var tube := _box(Vector3(2.6, 0.08, 0.3), Vector3(x, 4.9, -2.0), Color("#F4F8FF"))
		_glow(tube, Color("#F4F8FF"))
		var l := OmniLight3D.new()
		l.light_color = Color("#F1F4FF")
		l.light_energy = 1.3
		l.omni_range = 9.0
		l.position = Vector3(x, 4.4, -2.0)
		add_child(l)


## A rifle on the wall: stock, receiver, barrel and magazine, with a few looks.
func _rifle(at: Vector3, n: int) -> void:
	var r := Node3D.new()
	r.position = at
	add_child(r)
	var dark := Color("#1E2024")
	var stock: Color = [C_WOOD, dark, Color("#4A4F3A")][n % 3]
	var long_ := 1.0 + 0.25 * (n % 2)
	_part(r, Vector3(0.5, 0.16, 0.06), Vector3(-0.7, 0, 0), stock)
	_part(r, Vector3(0.75, 0.13, 0.07), Vector3(-0.08, 0.02, 0), dark)
	_part(r, Vector3(long_ * 0.55, 0.04, 0.04), Vector3(0.3 + long_ * 0.27, 0.04, 0), dark)
	_part(r, Vector3(0.09, 0.22, 0.05), Vector3(0.0, -0.13, 0), dark)
	if n % 3 == 1:
		_part(r, Vector3(0.32, 0.07, 0.07), Vector3(-0.05, 0.13, 0), Color("#111214"))   # a scope
	# The hooks it hangs on.
	_part(r, Vector3(0.04, 0.04, 0.12), Vector3(-0.35, 0.1, -0.05), Color("#8A8F99"))
	_part(r, Vector3(0.04, 0.04, 0.12), Vector3(0.35, 0.1, -0.05), Color("#8A8F99"))


func _pistol(at: Vector3, n: int) -> void:
	var g := Node3D.new()
	g.position = at
	g.rotation.y = 0.3 * ((n % 3) - 1)
	add_child(g)
	var col: Color = [Color("#1E2024"), Color("#8A8F99"), Color("#3A2A1E")][n % 3]
	_part(g, Vector3(0.36, 0.04, 0.09), Vector3(0, 0.02, 0), col)
	_part(g, Vector3(0.1, 0.04, 0.16), Vector3(-0.13, 0.02, 0.1), Color("#1E2024"))


# ------------------------------------------------------------------ the gym

func _gym() -> void:
	var o := GYM
	_floor(o, Vector2(18, 14), C_RUBBER, Color("#2E3036"))
	_box(Vector3(18, 5, 0.3), o + Vector3(0, 2.5, -7), Color("#3C4452"))
	_box(Vector3(0.3, 5, 14), o + Vector3(-9, 2.5, 0), Color("#3C4452"))
	_box(Vector3(0.3, 5, 14), o + Vector3(9, 2.5, 0), Color("#3C4452"))
	var sign := _text("TRAINING", 96, Color("#35D0BA"))
	sign.position = o + Vector3(0, 4.3, -6.8)
	add_child(sign)
	# Lockers along the back wall.
	for i in 8:
		var x := -3.5 + i * 1.0
		_box(Vector3(0.92, 2.6, 0.7), o + Vector3(x, 1.3, -6.45), C_LOCKER)
		for v in 3:
			_box(Vector3(0.5, 0.03, 0.02), o + Vector3(x, 2.3 + v * 0.08, -6.09), Color("#2B3E52"))
		_box(Vector3(0.05, 0.22, 0.04), o + Vector3(x + 0.32, 1.35, -6.08), Color("#C9CED6"))
	_box(Vector3(7.2, 0.4, 0.5), o + Vector3(0.0, 0.2, -5.3), C_WOOD)   # the bench in front of them
	# Mirrors either side of them.
	for mx in [-6.6, 6.6]:
		var mirror := _box(Vector3(4.0, 2.6, 0.05), o + Vector3(mx, 2.0, -6.8), Color("#BFD8E6"))
		var mm: StandardMaterial3D = mirror.material_override
		mm.metallic = 0.9
		mm.roughness = 0.08
	# Bench press.
	var bp := o + Vector3(5.0, 0, -2.6)
	_box(Vector3(0.5, 0.45, 1.8), bp + Vector3(0, 0.38, 0), Color("#1B1D21"))
	_box(Vector3(0.45, 0.08, 1.7), bp + Vector3(0, 0.62, 0), C_RED)
	for side in [-0.75, 0.75]:
		_box(Vector3(0.08, 1.3, 0.08), bp + Vector3(side, 0.65, -0.7), C_STEEL)
	_bar(bp + Vector3(0, 1.25, -0.7), 2.2)
	# The heavy bag on its chain.
	_bag = Node3D.new()
	_bag.position = o + Vector3(7.0, 4.6, 0.6)
	add_child(_bag)
	_part(_bag, Vector3(0.05, 1.0, 0.05), Vector3(0, -0.5, 0), Color("#8A8F99"))
	var bag := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.38
	cyl.bottom_radius = 0.38
	cyl.height = 1.6
	bag.mesh = cyl
	bag.material_override = _flat(Color("#8E1B17"))
	bag.position.y = -1.85
	_bag.add_child(bag)
	# A rack of dumbbells.
	_box(Vector3(2.4, 0.7, 0.6), o + Vector3(-5.2, 0.35, -2.4), C_STEEL)
	for i in 5:
		_bar(o + Vector3(-6.1 + i * 0.45, 0.78, -2.4), 0.32, 0.09)
	# Lights.
	for x in [-4.0, 4.0]:
		var tube := _box(Vector3(3.0, 0.08, 0.3), o + Vector3(x, 4.9, -2.0), Color("#F4F8FF"))
		_glow(tube, Color("#F4F8FF"))
		var l := OmniLight3D.new()
		l.light_energy = 1.4
		l.omni_range = 10.0
		l.position = o + Vector3(x, 4.4, -1.5)
		add_child(l)


## Your crew in the gym, each by their own locker with their name on it.
func _place_crew(p: Dictionary, crew_looks: Array) -> void:
	for i in mini(p.crew.size(), 6):
		var look: String = UiTheme.look_of(p) if i == 0 else crew_looks[(int(p.id) + i) % crew_looks.size()]
		var x := -3.5 + i * 1.0
		var n := _extra(look, GYM + Vector3(x, 0, -4.6), 0.0)
		_crew_nodes.append(n)
		var tag := _text(str(p.crew[i].name).get_slice(" ", 0), 30, Color.WHITE)
		tag.position = GYM + Vector3(x, 2.75, -6.05)
		tag.outline_size = 8
		add_child(tag)
		_crew_nodes.append(tag)
	# And you at the store counter.
	_crew_nodes.append(_extra(UiTheme.look_of(p), Vector3(-0.6, 0, -1.9), PI))


func _bar(at: Vector3, length: float, plate := 0.32) -> void:
	var bar := Node3D.new()
	bar.position = at
	add_child(bar)
	var rod := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.025
	c.bottom_radius = 0.025
	c.height = length
	rod.mesh = c
	rod.material_override = _flat(Color("#C9CED6"))
	rod.rotation.z = PI / 2
	bar.add_child(rod)
	for side in [-1, 1]:
		var pl := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = plate
		pc.bottom_radius = plate
		pc.height = 0.08
		pl.mesh = pc
		pl.material_override = _flat(Color("#1B1D21"))
		pl.rotation.z = PI / 2
		pl.position.x = side * (length / 2.0 - 0.15)
		bar.add_child(pl)


# ------------------------------------------------------------------ helpers

func _floor(at: Vector3, size: Vector2, a: Color, b: Color) -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, a if (x / 8 + y / 8) % 2 == 0 else b)
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	m.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_scale = Vector3(size.x / 2.0, size.y / 2.0, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 0.9
	m.material_override = mat
	m.position = at
	add_child(m)


func _pegboard() -> StandardMaterial3D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(C_PEG)
	for y in [3, 11]:
		for x in [3, 11]:
			img.set_pixel(x, y, Color("#5A4128"))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_scale = Vector3(28, 6, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return mat


func _target_mat() -> StandardMaterial3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 13.5).length()
			if int(d) % 5 < 2 and d < 13:
				img.set_pixel(x, y, Color("#1B1D21"))
			if d < 2.5:
				img.set_pixel(x, y, C_RED)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat


func _extra(model: String, pos: Vector3, turn: float) -> Node3D:
	var n: Node3D = load(MODELS + "characters/" + model + ".glb").instantiate()
	n.position = pos
	n.rotation.y = turn
	n.scale = Vector3.ONE * PERSON
	add_child(n)
	var aps := n.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var ap: AnimationPlayer = aps[0]
		ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")
		ap.seek(randf() * ap.current_animation_length)
	return n


func _text(text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_size = 18
	l.outline_modulate = Color(0.05, 0.05, 0.07, 0.9)
	l.shaded = false
	return l


func _glow(m: MeshInstance3D, col: Color) -> void:
	var mat: StandardMaterial3D = m.material_override
	mat.emission_enabled = true
	mat.emission = col


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	return _part(self, size, pos, col)


func _part(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _flat(col)
	m.position = pos
	parent.add_child(m)
	return m


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m
