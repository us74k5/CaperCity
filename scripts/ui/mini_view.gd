extends Node3D
## The grid minigames on screen (Net.state.mini; see Mini), seen from above:
##   escape / catch: back alleys with thin brick walls; cops with flashing caps, or the runaway with the case
##   sneak:          an office floor at night; guards with torches, the squares they can see lit up
##   loot:           a shop at night; boxes to push onto the marked squares by the back door
##   containers:     the container yard at the docks
##   train:          the rail yard; containers to push onto the track, then the mail train
## Positions arrive at the server's tick rate and are eased between squares here.
## Grid square (x, y) is at local (x + 0.5, 0, y + 0.5).

const MODELS := "res://assets/models/"
const COP := "character-male-c"
const GUARD := "character-male-d"
const RUNNER := "character-female-a"
const C_SIGHT := Color(1.0, 0.88, 0.3, 0.55)
const C_TARGET := Color("#E8B923")
const C_EXIT := Color("#35D0BA")
const CRATE_COLORS := [Color("#B4553D"), Color("#2F5FA8"), Color("#3E8A5C"), Color("#C9A13A")]
# Per game: floor, wall side, wall top, wall height, thin walls?
const LOOK := {
	"escape": [Color("#2E3238"), Color("#8C5240"), Color("#B9B2A6"), 0.5, true],
	"catch": [Color("#2E3238"), Color("#8C5240"), Color("#B9B2A6"), 0.5, true],
	"sneak": [Color("#4A505B"), Color("#6B4E37"), Color("#9C7A57"), 0.6, false],
	"loot": [Color("#2B3142"), Color("#5E6676"), Color("#8E97A8"), 0.8, false],
	"containers": [Color("#55595F"), Color("#3D5C70"), Color("#6E8DA0"), 0.9, false],
	"train": [Color("#5A5650"), Color("#7A4A3A"), Color("#A5978A"), 0.6, false],
}

var crew_looks: Array = []      # set by city_view
var _id := -1
var _game := ""
var _set: Node3D
var _me: Dictionary = {}        # {node, anim}
var _foes: Array = []           # [{node, anim, lights?, alert?}]
var _items: Array = []          # nodes, by item index
var _train: Node3D
var _sight: MultiMeshInstance3D
var _clock := 0.0               # the server tick we're showing, eased between updates
var _last_tick := -1
var _t := 0.0


func showing() -> bool:
	return _id >= 0


func center() -> Vector3:
	return global_position + Vector3(Mini.W / 2.0, 0, Mini.H / 2.0)


## Builds the scene when a new game starts; positions follow in _process.
func show_mini(m: Dictionary, look: String, col: Color) -> void:
	if int(m.get("id", -1)) == _id:
		return
	clear()
	_id = int(m.id)
	_game = m.game
	_set = Node3D.new()
	add_child(_set)
	_build_floor(m.rows)
	_me = _actor(look, 1.3)
	_disc(_me.node, col, 0.45)
	match _game:
		"escape":
			for f in m.foes:
				var cop := _actor(COP, 1.3)
				cop.lights = _cap_lights(cop.node)
				_disc(cop.node, Color("#2F5FBF"), 0.45)
				_foes.append(cop)
		"catch":
			var r := _actor(RUNNER, 1.0)
			_disc(r.node, UiTheme.YELLOW, 0.45)
			_part(r.node, Vector3(0.28, 0.2, 0.08), Vector3(0.28, 0.32, 0.05), Color("#3A2A1E"))
			_foes.append(r)
		"sneak":
			for g in m.guards:
				var gd := _actor(GUARD, 1.3)
				_disc(gd.node, Color("#C8423B"), 0.45)
				var torch := _part(gd.node, Vector3(0.1, 0.1, 0.3), Vector3(0.25, 0.4, 0.25), Color("#FFE27A"))
				(torch.material_override as StandardMaterial3D).emission_enabled = true
				(torch.material_override as StandardMaterial3D).emission = Color("#FFD24A")
				var alert := Label3D.new()
				alert.text = "!"
				alert.font_size = 160
				alert.modulate = Color("#FF5D4F")
				alert.outline_size = 12
				alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				alert.position.y = 1.4
				alert.visible = false
				gd.node.add_child(alert)
				gd.alert = alert
				_foes.append(gd)
			_sight = MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			var quad := PlaneMesh.new()
			quad.size = Vector2(0.96, 0.96)
			mm.mesh = quad
			mm.instance_count = 0
			_sight.multimesh = mm
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.albedo_color = C_SIGHT
			_sight.material_override = sm
			_sight.position.y = 0.02
			_set.add_child(_sight)
		"loot", "containers", "train":
			for i in m.items.size():
				_items.append(_crate(i))
			if _game == "train":
				_build_track()
	_clock = float(m.tick)
	_last_tick = int(m.tick)
	_place_all(m)


func clear() -> void:
	_id = -1
	_game = ""
	if _set:
		_set.queue_free()
		_set = null
	_me = {}
	_foes.clear()
	_items.clear()
	_train = null
	_sight = null


func _process(delta: float) -> void:
	_t += delta
	if _id < 0:
		return
	var m: Dictionary = Net.state.get("mini", {})
	if m.is_empty() or int(m.get("id", -1)) != _id:
		return
	# Run our clock at the server's pace, and catch up (never run ahead) when an update lands.
	if int(m.tick) != _last_tick:
		_last_tick = int(m.tick)
		_clock = maxf(_clock, float(m.tick) - 1.0)
	_clock = minf(_clock + delta / Mini.TICK, float(m.tick))
	if m.over:
		_clock = float(m.tick)
	_place_all(m)


func _place_all(m: Dictionary) -> void:
	_place(_me, m.me, m)
	var foes: Array = m.get("foes", m.get("guards", []))
	for i in mini(_foes.size(), foes.size()):
		_place(_foes[i], foes[i], m)
	var red := int(_t * 6.0) % 2 == 0
	for f in _foes:
		if f.has("lights"):
			for i in 2:
				var mat: StandardMaterial3D = f.lights[i]
				var on: bool = (i == 0) == red
				var col := Color("#FF3B3B") if i == 0 else Color("#3B7BFF")
				mat.emission = col if on else Color.BLACK
				mat.albedo_color = col if on else col.darkened(0.7)
	if _game == "sneak":
		_show_sight(m)
		for i in _foes.size():
			_foes[i].alert.visible = m.over and int(m.get("spotted", -1)) == i
	if m.has("items"):
		var step_ticks := 1.0 / maxf(0.01, float(m.me.speed))
		for i in mini(_items.size(), m.items.size()):
			var it: Dictionary = m.items[i]
			var node: Node3D = _items[i]
			var k := clampf((_clock - float(it.mt)) / step_ticks, 0.0, 1.0)
			var to := Vector3(int(it.x) + 0.5, 0, int(it.y) + 0.5)
			node.position = Vector3(int(it.px) + 0.5, 0, int(it.py) + 0.5).lerp(to, k)
			if it.get("hit", false):
				# Knocked off the track: tumble away and vanish.
				var f := clampf((_clock - float(it.mt)) / 14.0, 0.0, 1.0)
				node.position = to + Vector3(0.5 * f, 2.2 * sin(f * PI), -2.5 * f)
				node.rotation = Vector3(f * 5.0, f * 3.0, 0)
				node.visible = f < 1.0
	if _train and m.has("train"):
		_train.position.x = lerpf(_train.position.x, float(m.train.x), 0.5)
		_train.visible = m.get("phase", "") == "train"


## Eases an actor from its previous square to its current one over the time a step takes.
func _place(a: Dictionary, s: Dictionary, m: Dictionary) -> void:
	var step_ticks := 1.0 / maxf(0.01, float(s.speed))
	var k := clampf((_clock - float(s.mt)) / step_ticks, 0.0, 1.0)
	var from := Vector3(int(s.px) + 0.5, 0, int(s.py) + 0.5)
	var to := Vector3(int(s.x) + 0.5, 0, int(s.y) + 0.5)
	a.node.position = from.lerp(to, k)
	if from != to:
		a.node.rotation.y = atan2(to.x - from.x, to.z - from.z)
	elif str(s.get("dir", "")) != "":
		var d: Vector2i = Mini.DIRS[s.dir]
		a.node.rotation.y = atan2(d.x, d.y)
	var moving := k < 1.0 or _clock - float(s.mt) < step_ticks + 2.0
	var run := "sprint" if _game in ["escape", "catch"] else "walk"
	var anim := run if moving and not m.over and int(m.ready) <= 0 else "idle"
	if m.over and a == _me:
		anim = "emote-yes" if m.won else "emote-no"
	if a.anim.current_animation != anim:
		a.anim.play(anim, 0.1)


func _show_sight(m: Dictionary) -> void:
	var cells: Array = []
	for g in m.guards:
		for c in Sneak.sight(m.rows, g):
			cells.append(c)
	var mm := _sight.multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(cells[i].x + 0.5, 0, cells[i].y + 0.5)))


# ------------------------------------------------------------------ building

func _build_floor(rows: Array) -> void:
	var look: Array = LOOK[_game]
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(Mini.W + 30, Mini.H + 12)
	ground.mesh = plane
	ground.material_override = _flat(look[0])
	ground.position = Vector3(Mini.W / 2.0, 0.0, Mini.H / 2.0)
	_set.add_child(ground)
	var thin: bool = look[4]
	var wall_t := 0.36 if thin else 1.0
	var is_wall := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < Mini.W and y < Mini.H and (rows[y] as String)[x] == "#"
	var pieces: Array = []   # [center, size on x/z]
	for y in Mini.H:
		for x in Mini.W:
			var mk := (rows[y] as String)[x]
			var c := Vector3(x + 0.5, 0, y + 0.5)
			if mk == "o":
				_tile(c, C_TARGET, 0.84)
			elif mk == "E" or mk == "D":
				_tile(c, C_EXIT, 0.96)
				var arrow := Label3D.new()
				arrow.text = "EXIT" if mk == "E" else "DOOR"
				arrow.font_size = 64
				arrow.modulate = C_EXIT
				arrow.outline_size = 10
				arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				arrow.position = c + Vector3(0, 1.1, 0)
				_set.add_child(arrow)
			if not is_wall.call(x, y):
				continue
			pieces.append([c, Vector2(wall_t, wall_t)])
			if thin and is_wall.call(x + 1, y):
				pieces.append([c + Vector3(0.5, 0, 0), Vector2(1.0, wall_t)])
			if thin and is_wall.call(x, y + 1):
				pieces.append([c + Vector3(0, 0, 0.5), Vector2(wall_t, 1.0)])
	var h: float = look[3]
	var unit := BoxMesh.new()
	for part in [[look[1], h / 2.0, h, 0.0], [look[2], h + 0.03, 0.06, 0.06 if thin else 0.0]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = unit
		mm.instance_count = pieces.size()
		for i in pieces.size():
			var sz: Vector2 = pieces[i][1]
			var grow: float = part[3]
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sz.x + grow, part[2], sz.y + grow)),
				pieces[i][0] + Vector3(0, part[1], 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _flat(part[0])
		_set.add_child(mmi)


## Rails along row 1, running well off both sides of the yard, and the train (hidden until it comes).
func _build_track() -> void:
	var rail := _flat(Color("#9AA0A8"))
	rail.metallic = 0.6
	for z in [1.25, 1.75]:
		var r := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(Mini.W + 40, 0.06, 0.06)
		r.mesh = b
		r.material_override = rail
		r.position = Vector3(Mini.W / 2.0, 0.05, z)
		_set.add_child(r)
	for i in Mini.W + 40:
		var sl := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.18, 0.04, 0.9)
		sl.mesh = sb
		sl.material_override = _flat(Color("#4A3A2E"))
		sl.position = Vector3(i - 20 + 0.5, 0.02, 1.5)
		_set.add_child(sl)
	_train = Node3D.new()
	var loco := Color("#C8423B")
	_part(_train, Vector3(2.6, 1.0, 0.86), Vector3(-1.3, 0.6, 1.5), loco)
	_part(_train, Vector3(0.9, 0.5, 0.8), Vector3(-1.9, 1.35, 1.5), Color("#2B2F36"))
	var lamp := _part(_train, Vector3(0.06, 0.2, 0.3), Vector3(0.02, 0.7, 1.5), Color("#FFF4C8"))
	(lamp.material_override as StandardMaterial3D).emission_enabled = true
	(lamp.material_override as StandardMaterial3D).emission = Color("#FFE9A0")
	for w in 3:
		_part(_train, Vector3(1.9, 0.95, 0.84), Vector3(-3.7 - w * 2.1, 0.6, 1.5), Color("#2F4A8C"))
		_part(_train, Vector3(1.9, 0.12, 0.86), Vector3(-3.7 - w * 2.1, 1.1, 1.5), Color("#E8E3D6"))
	_train.visible = false
	_train.position.x = -20.0
	_set.add_child(_train)


func _crate(i: int) -> Node3D:
	var n := Node3D.new()
	if _game == "loot":
		_part(n, Vector3(0.72, 0.6, 0.72), Vector3(0, 0.3, 0), Color("#B98A57"))
		_part(n, Vector3(0.74, 0.04, 0.16), Vector3(0, 0.61, 0), Color("#E2D3B0"))
		var tv := _part(n, Vector3(0.4, 0.02, 0.28), Vector3(0, 0.62, 0.15), Color("#2B2F36"))
		tv.position.z = 0.18
	else:
		var col: Color = CRATE_COLORS[i % CRATE_COLORS.size()]
		_part(n, Vector3(0.9, 0.8, 0.82), Vector3(0, 0.4, 0), col)
		for k in 3:
			_part(n, Vector3(0.92, 0.7, 0.04), Vector3(0, 0.4, -0.3 + 0.3 * k), col.darkened(0.25))
	_set.add_child(n)
	return n


func _tile(c: Vector3, col: Color, size: float) -> void:
	var t := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	t.mesh = p
	var mat := _flat(col)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.25
	t.material_override = mat
	t.position = c + Vector3(0, 0.012, 0)
	_set.add_child(t)


func _actor(model: String, k: float) -> Dictionary:
	var node: Node3D = load(MODELS + "characters/" + model + ".glb").instantiate()
	node.scale = Vector3.ONE * k
	_set.add_child(node)
	var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["idle", "sprint", "walk"]:
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	ap.play("idle")
	return {"node": node, "anim": ap}


## A little red/blue light on a cop's cap, so cops read at a glance from above.
func _cap_lights(parent: Node3D) -> Array:
	var mats: Array = []
	for i in 2:
		var m := _part(parent, Vector3(0.22, 0.12, 0.22), Vector3(-0.12 + 0.24 * i, 0.74, 0), Color.BLACK)
		var mat: StandardMaterial3D = m.material_override
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 2.5
		mats.append(mat)
	return mats


## A flat colored disc under a figure, so everyone reads at a glance from above.
func _disc(parent: Node3D, col: Color, r: float) -> void:
	var d := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r / parent.scale.x
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 0.02
	d.mesh = cyl
	d.material_override = _flat(col)
	d.position.y = 0.02
	parent.add_child(d)


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
	m.roughness = 0.9
	return m
