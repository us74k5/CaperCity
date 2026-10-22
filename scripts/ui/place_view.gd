extends Node3D
## The scene you see while inside a building, like the original's full-screen picture of each place:
## the building from across the street (or the playground, the docks, a villa's garden), its
## neighbours, the street out front and a little life. Built when a player walks in; city_view
## points its camera here while they stay inside. The building's front faces +Z at local z = 0;
## the pavement runs z 0..2.5 and the road z 2.5..5.

const MODELS := "res://assets/models/"
const K := 2.5                  # kit models are scaled up this much (a road tile is 2.5 units wide)
const PERSON := 1.5             # character scale
const MAIN_H := 5.5             # the main building is scaled to about this height (or MAIN_W wide)...
const MAIN_W := 7.0
const MIN_W := 3.5              # ...but never narrower than this
const MAX_H := 9.0              # nor taller than this
const PAVE_Z := 1.25            # middle of the front pavement
const CURB_Z := 3.15            # where parked cars stand
const LANE_Z := 4.3             # where passing cars drive
const NEIGHBOURS := ["commercial/building-a", "commercial/building-b", "commercial/building-d", "commercial/building-f",
	"commercial/building-g", "commercial/building-c", "commercial/building-e", "industrial/building-d"]
const HOUSES := ["suburban/building-type-a", "suburban/building-type-c", "suburban/building-type-e",
	"suburban/building-type-h", "suburban/building-type-k", "suburban/building-type-o"]
# The main building per type; a building picks one by its id. Types missing here are built by hand.
const LOOKS := {
	"car_dealer": ["industrial/building-h", "industrial/building-i"],
	"arms": ["commercial/building-b", "commercial/building-d"],
	"pub": ["commercial/building-a", "commercial/building-f", "commercial/building-g"],
	"hotel": ["commercial/building-j", "commercial/building-m"],
	"bank": ["commercial/building-h", "commercial/building-skyscraper-a"],
	"print_shop": ["industrial/building-p", "industrial/building-t"],
	"police": ["commercial/building-l"],
	"station": ["industrial/building-s", "industrial/building-k"],
	"casino": ["commercial/building-n"],
	"supermarket": ["commercial/building-c", "commercial/building-e"],
	"loan_shark": ["commercial/building-i"],
	"dept_store": ["commercial/building-k"],
	"villa": ["suburban/building-type-n", "suburban/building-type-p", "suburban/building-type-b", "suburban/building-type-q"],
	"city_hall": ["commercial/building-skyscraper-e"],
	"airport": ["industrial/building-q"],
	"harbor": ["industrial/building-c"],
	"subway": ["commercial/building-skyscraper-b", "commercial/building-skyscraper-c"],
}
# Who hangs around out front: [model, x, turn, animation].
const LOCALS := {
	"arms": [["character-male-a", 2.6, -0.5, "idle"]],
	"pub": [["character-female-b", 2.4, -0.3, "idle"], ["character-male-e", 3.1, -2.2, "idle"]],
	"hotel": [["character-male-b", 1.9, 0.0, "idle"]],
	"bank": [["character-male-d", 2.2, 0.0, "idle"]],
	"dept_store": [["character-male-d", 2.4, 0.0, "idle"]],
	"police": [["character-male-c", 2.3, -0.4, "idle"], ["character-male-c", 3.2, -1.8, "idle"]],
	"casino": [["character-male-d", 2.0, 0.0, "idle"]],
	"loan_shark": [["character-male-a", 2.2, -0.4, "idle"]],
	"station": [["character-female-c", 2.8, 0.3, "idle"]],
	"city_hall": [["character-male-b", 2.4, -0.3, "idle"]],
}
# Places set back from the pavement, with a forecourt or garden in front.
const SETBACK := {"car_dealer": 3.0, "villa": 3.5, "playground": 0.0}
const C_GRASS := Color("#6DA35F")
const C_WATER := Color("#3F86A6")
const C_SIGN := Color("#FFD27A")
const CAR_COLORS := [Color("#C8423B"), Color("#2F5FA8"), Color("#E8E3D6"), Color("#2B2F36"), Color("#3E8A5C"), Color("#D9A23A")]

var crew_looks: Array = []      # set by city_view, so the player looks the same as their city token
var _key := ""                  # "building id:player id" of the scene on show
var _set: Node3D                # everything built for the current scene
var _movers: Array = []         # {node, from, to, speed, wait, anim?} things that cross the scene on a loop
var _lights: Array = []         # police light materials, flashed in _process
var _bobbers: Array = []        # boats on the water
var _t := 0.0
var _focus_x := 0.0
var casino: Node3D = null       # the casino's interior, when that's the place on show
var arms: Node3D = null         # the arms dealer's store and gym, likewise
var _aabbs := {}


func showing() -> bool:
	return _key != ""


## Builds the scene for player `p` inside building `b`, unless it's already up.
func show_place(b: Dictionary, p: Dictionary) -> void:
	var key := "%d:%d:%d" % [int(b.id), int(p.id), int(p.car)]
	if key == _key:
		if arms:
			arms.update(p, crew_looks)
		return
	clear()
	_key = key
	_build(b, p)


func clear() -> void:
	_key = ""
	if _set:
		_set.queue_free()
		_set = null
	_movers.clear()
	_lights.clear()
	_bobbers.clear()
	casino = null
	arms = null


## Where the camera stands: across the street, eye a little above head height, with the building
## left of center so the menu on the right doesn't hide it.
func camera_pose(aspect: float) -> Transform3D:
	if casino:
		return casino.camera_pose(aspect)
	if arms:
		return arms.camera_pose(aspect)
	var shift := 3.0 if aspect > 1.2 else 0.0
	var eye := global_position + Vector3(_focus_x + shift, 2.3, 15.0)
	var look := global_position + Vector3(_focus_x + shift, 3.0, 0.0)
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


func _process(delta: float) -> void:
	if _set == null:
		return
	_t += delta
	for m in _movers:
		if m.wait > 0.0:
			m.wait -= delta
			m.node.visible = false
			continue
		m.node.visible = true
		var dir: Vector3 = (m.to - m.from).normalized()
		m.node.position += dir * m.speed * delta
		if (m.node.position - m.from).length() >= (m.to - m.from).length():
			m.node.position = m.from
			m.wait = m.pause
	var red := int(_t * 6.0) % 2 == 0
	for i in _lights.size():
		var on: bool = (i % 2 == 0) == red
		var mat: StandardMaterial3D = _lights[i]
		var col := Color("#FF3B3B") if i % 2 == 0 else Color("#3B7BFF")
		mat.albedo_color = col if on else col.darkened(0.7)
		mat.emission = col if on else Color.BLACK
	for i in _bobbers.size():
		var n: Node3D = _bobbers[i]
		n.position.y = 0.05 * sin(_t * 1.6 + i)
		n.rotation.z = 0.03 * sin(_t * 1.1 + i)


# ------------------------------------------------------------------ building the scene

func _build(b: Dictionary, p: Dictionary) -> void:
	_set = Node3D.new()
	add_child(_set)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.id) * 977 + 13
	var t: String = b.type
	var green: bool = t in ["villa", "playground"]
	_focus_x = 0.0
	if t == "casino":
		# The casino is the one place you walk into: its own room with the tables.
		casino = preload("res://scripts/ui/casino_view.gd").new()
		_set.add_child(casino)
		casino.build(b, UiTheme.look_of(p))
		return
	if t == "arms":
		# So is the arms dealer: the gun store, and the gym out back for training.
		arms = preload("res://scripts/ui/arms_view.gd").new()
		_set.add_child(arms)
		arms.build(b, p, crew_looks)
		return

	_backdrop(rng, green)
	if t == "harbor":
		_harbor_front()
	else:
		_street()

	var setback: float = SETBACK.get(t, 0.0)
	var half := 2.5
	var top := 4.0
	if t == "playground":
		_playground(b, rng)
		half = 6.0
	else:
		var looks: Array = LOOKS[t]
		var size := _main(looks[int(b.id) % looks.size()], Vector3(0, 0, -setback))
		half = size.x / 2.0
		top = size.y
		_dress(t, b, half, top, setback)
	if t == "villa":
		_neighbours(half, rng, HOUSES, 1.6)
	elif t != "playground":
		_neighbours(half, rng, NEIGHBOURS, K)
	var info: Dictionary = Balance.BUILDINGS[t]
	if info.sign != "":
		if top > 6.0:
			_roof_sign(info.sign, 2.6, 0.9)   # tall buildings get theirs over the door, to stay on screen
		else:
			_roof_sign(info.sign, top, -setback)

	for l in LOCALS.get(t, []):
		_person(l[0], Vector3(l[1], 0, 0.7), l[2], l[3])
	# You, on the pavement by the door.
	var me := Vector3(-1.4, 0, 1.0) if t != "playground" else Vector3(-1.2, 0, 2.0)
	_person(UiTheme.look_of(p), me, 0.35, "idle")
	if int(p.car) > 0 and t != "harbor":
		_car(Color(p.color), Vector3(-8.5, 0, CURB_Z), PI / 2)
	if t != "harbor":
		_traffic(rng)
	_walker(rng)


## Sky, a far skyline, and a wide ground plane under it all.
func _backdrop(rng: RandomNumberGenerator, green: bool) -> void:
	var sky := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(260, 70)
	sky.mesh = quad
	var grad := Gradient.new()
	grad.set_color(0, Color("#4E9CCB"))
	grad.set_color(1, Color("#CBE5EE"))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 0.55)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = tex
	sky.material_override = sm
	sky.position = Vector3(0, 24, -70)
	_set.add_child(sky)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(260, 140)
	ground.mesh = plane
	ground.material_override = _flat(C_GRASS if green else Color("#8C8F93"))
	ground.position = Vector3(0, -0.02, -40)
	_set.add_child(ground)

	# Far skyline: flat silhouettes in two hazy layers, like the backdrops in the original.
	for layer in 2:
		var col := Color("#A7CAD8") if layer == 0 else Color("#83AFC3")
		var z := -75.0 + layer * 22.0
		var x := -90.0 + rng.randf() * 6.0
		while x < 90.0:
			var w := rng.randf_range(4.0, 10.0)
			var h := rng.randf_range(8.0, 24.0) * (1.25 if layer == 0 else 1.0)
			var m := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(w, h, 1.0)
			m.mesh = box
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = col
			m.material_override = mat
			m.position = Vector3(x + w / 2.0, h / 2.0, z)
			_set.add_child(m)
			x += w + rng.randf_range(-1.5, 2.5)


## Pavement on both sides of a two-lane road, with street lights.
func _street() -> void:
	for i in 25:
		var x := (i - 12) * K
		_model("roads/road-straight", Vector3(x, 0, 3.75 + K / 2.0), 9.0, 0.0, K)
		_model("roads/tile-low", Vector3(x, 0.005, PAVE_Z + K / 2.0), 9.0, 0.0, K)
		_model("roads/tile-low", Vector3(x, 0.005, 6.25 + K / 2.0), 9.0, 0.0, K)
		_model("roads/tile-low", Vector3(x, 0.004, -1.25 + K / 2.0), 9.0, 0.0, K)
	for x in [-10.0, 10.0]:
		_model("roads/light-square", Vector3(x, 0, 2.3), 9.0, PI, K * 1.3)


## The docks: a quay along the front with the harbour water where the road would be.
func _harbor_front() -> void:
	for i in 25:
		var x := (i - 12) * K
		_model("roads/tile-low", Vector3(x, 0.005, PAVE_Z + K / 2.0), 9.0, 0.0, K)
		_model("roads/tile-low", Vector3(x, 0.004, -1.25 + K / 2.0), 9.0, 0.0, K)
	var water := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(120, 0.4, 40)
	water.mesh = box
	var mat := _flat(C_WATER)
	mat.roughness = 0.1
	mat.metallic_specular = 0.8
	water.material_override = mat
	water.position = Vector3(0, -0.18, 2.5 + 20.0)
	_set.add_child(water)
	# Quay edge.
	var edge := MeshInstance3D.new()
	var eb := BoxMesh.new()
	eb.size = Vector3(120, 0.5, 0.25)
	edge.mesh = eb
	edge.material_override = _flat(Color("#6E6A62"))
	edge.position = Vector3(0, -0.2, 2.6)
	_set.add_child(edge)


## The playground: a fenced park with a sandpit, a slide, swings, benches and kids.
func _playground(b: Dictionary, rng: RandomNumberGenerator) -> void:
	_street()
	for i in 12:
		_model("suburban/fence", Vector3(-12 + i * 2.1, 0, -9.0), 3.0, 0.0, K)
	for x in [-14.0, -7.0, 6.0, 12.5, -2.0, 2.5]:
		_model("suburban/tree-large", Vector3(x + rng.randf_range(-1, 1), 0, -7.5 + rng.randf_range(-1, 1)), 9.0, rng.randf() * TAU, K * 2.2)
	for x in [-8.5, 9.0]:
		_model("suburban/tree-large", Vector3(x, 0, -1.5), 9.0, rng.randf() * TAU, K * 2.4)
	# Sandpit
	_box(Vector3(3.2, 0.25, 2.4), Vector3(-4.5, 0.12, -3.0), Color("#8A5A3A"))
	_box(Vector3(2.8, 0.26, 2.0), Vector3(-4.5, 0.13, -3.0), Color("#E6CF8F"))
	# Slide: a ladder tower, a platform and a red chute.
	var wood := Color("#9A6B42")
	for dx in [0.0, 1.0]:
		for dz in [0.0, 1.0]:
			_box(Vector3(0.12, 2.0, 0.12), Vector3(3.0 + dx, 1.0, -4.5 + dz), wood)
	_box(Vector3(1.25, 0.12, 1.25), Vector3(3.5, 2.0, -4.0), wood)
	_box(Vector3(1.3, 0.9, 1.3), Vector3(3.5, 2.6, -4.0), Color("#C8423B"), PI / 4.0, Vector3.UP).scale = Vector3(1, 0.3, 1)
	var chute := _box(Vector3(0.7, 0.08, 3.0), Vector3(5.0, 1.05, -4.0), Color("#D7473F"))
	chute.rotation = Vector3(0, PI / 2, deg_to_rad(36))
	# Swings
	for dx in [-0.9, 0.9]:
		var leg := _box(Vector3(0.12, 2.3, 0.12), Vector3(8.0 + dx * 1.2, 1.1, -3.5), Color("#3E5C7A"))
		leg.rotation.z = dx * 0.2
	_box(Vector3(2.8, 0.12, 0.12), Vector3(8.0, 2.2, -3.5), Color("#3E5C7A"))
	for dx in [-0.5, 0.5]:
		_box(Vector3(0.03, 1.5, 0.03), Vector3(8.0 + dx, 1.45, -3.5), Color("#2B2F36"))
		_box(Vector3(0.5, 0.06, 0.25), Vector3(8.0 + dx, 0.7, -3.5), Color("#D9A23A"))
	_bench(Vector3(-0.5, 0, -1.0))
	_bench(Vector3(-9.0, 0, -4.0))
	# Kids
	var kids := ["character-female-a", "character-male-f", "character-female-e"]
	_person(kids[0], Vector3(-4.0, 0.25, -3.0), 0.6, "idle", 1.1)
	_person(kids[1], Vector3(-5.2, 0.25, -2.8), -0.8, "idle", 1.1)
	_person(kids[2], Vector3(8.5, 0, -2.6), 0.0, "idle", 1.1)
	_park_sign(b.name, Vector3(1.6, 0, 0.3))


## Props in front of the main building, by type.
func _dress(t: String, b: Dictionary, half: float, top: float, setback: float) -> void:
	match t:
		"car_dealer":
			_pave_lot(half + 2.0, setback)
			for i in 3:
				_car(CAR_COLORS[(int(b.id) + i * 2) % CAR_COLORS.size()], Vector3(-3.4 + i * 3.4, 0, -1.3), 0.35)
			for x in [-half - 1.0, half + 1.0]:
				_flag_pole(Vector3(x, 0, -0.4))
		"pub":
			for x in [2.6, 4.4]:
				_model("commercial/detail-parasol-a", Vector3(x, 0, 0.6), 9.0, 0.0, K * 1.5)
		"bank", "dept_store", "hotel", "loan_shark", "city_hall":
			for x in [-half + 0.5, half - 0.5]:
				_model("suburban/planter", Vector3(x, 0, 0.6), 9.0, 0.0, K * 1.6)
			if t in ["loan_shark", "city_hall", "hotel"]:
				_car(Color("#1E2026"), Vector3(4.2, 0, CURB_Z), PI / 2, true)
		"arms":
			_model("roads/dumpster", Vector3(half + 0.9, 0, -0.2), 9.0, 0.3, K * 1.4)
		"print_shop":
			_van(Color("#E8E3D6"), Vector3(3.6, 0, CURB_Z))
		"police":
			for i in 2:
				_police_car(Vector3(-4.0 + i * 8.6, 0, CURB_Z))
		"casino":
			_car(Color("#1E2026"), Vector3(3.8, 0, CURB_Z), PI / 2, true)
			_bulbs(half, minf(top, 3.0))
		"supermarket":
			_car(CAR_COLORS[int(b.id) % CAR_COLORS.size()], Vector3(4.0, 0, CURB_Z), PI / 2)
			for x in [-half - 0.6, half + 0.6]:
				_model("suburban/planter", Vector3(x, 0, 0.8), 9.0, 0.0, K * 1.6)
		"station":
			_bench(Vector3(-4.2, 0, 0.5))
			_bench(Vector3(4.6, 0, 0.5))
		"subway":
			_subway_entrance(Vector3(1.8, 0, 1.2))
		"airport":
			_car(Color("#E8B923"), Vector3(3.6, 0, CURB_Z), PI / 2)
			_plane()
		"harbor":
			var cols := ["a", "b", "c"]
			for i in 6:
				var x := -8.5 - (i % 3) * 1.1 if i < 3 else 6.5 + (i % 3) * 1.1
				_model("industrial/shipping-container-" + cols[(i + int(b.id)) % 3], Vector3(x, 0, 0.0), 9.0, 0.0, K)
			_model("industrial/shipping-container-a", Vector3(-9.6, 0.87, 0.0), 9.0, 0.0, K)
			_model("industrial/shipping-container-c", Vector3(7.6, 0.87, 0.0), 9.0, 0.0, K)
			_boat(Vector3(-3.0, 0, 6.0))
			_person("character-male-e", Vector3(4.0, 0, 1.6), -0.5, "idle")
		"villa":
			for i in 10:
				_model("suburban/fence-low", Vector3(-10.5 + i * 2.33, 0, 0.1), 9.0, 0.0, K)
			_model("suburban/path-long", Vector3(0.0, 0.01, -1.4), 9.0, 0.0, K * 1.4)
			var pool := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(3.2, 0.05, 1.7)
			pool.mesh = pb
			var pm := _flat(Color("#54B8D6"))
			pm.roughness = 0.1
			pool.material_override = pm
			pool.position = Vector3(half + 2.8, 0.02, -1.6)
			_set.add_child(pool)
			_box(Vector3(3.5, 0.04, 2.0), Vector3(half + 2.8, 0.01, -1.6), Color("#E6E1D6"))
			_model("suburban/tree-large", Vector3(-half - 2.0, 0, -1.5), 9.0, 0.0, K * 2.2)
			_car(Color("#2B2F36"), Vector3(-half - 1.2, 0, -1.4), 0.0, true)


## The blocks either side of the main building.
func _neighbours(half: float, rng: RandomNumberGenerator, pool: Array, k: float) -> void:
	for side in [-1.0, 1.0]:
		var edge := half + rng.randf_range(0.3, 0.8)
		for i in 5:
			var path: String = pool[rng.randi() % pool.size()]
			var bb := _aabb_of(path)
			var w := bb.size.x * k
			_model(path, Vector3(side * (edge + w / 2.0), 0, -rng.randf_range(0.0, 0.6)), 4.5, 0.0, k)
			edge += w + rng.randf_range(0.2, 0.6)


func _pave_lot(half_w: float, depth: float) -> void:
	_box(Vector3(half_w * 2.0, 0.02, depth), Vector3(0, 0.012, -depth / 2.0), Color("#A9ABAE"))


# ------------------------------------------------------------------ props

## The place itself, scaled up to stand out from its neighbours.
func _main(path: String, pos: Vector3) -> Vector3:
	var bb := _aabb_of(path)
	var k := maxf(minf(MAIN_W / bb.size.x, MAIN_H / bb.size.y), MIN_W / bb.size.x)
	return _model(path, pos, MAX_H, 0.0, minf(k, MAX_H / bb.size.y))


## A model scaled by k (but no taller than max_h), centered on pos.x with its front face at pos.z.
## Returns its scaled size.
func _model(path: String, pos: Vector3, max_h: float, turn: float, k: float) -> Vector3:
	var node: Node3D = load(MODELS + path + ".glb").instantiate()
	var bb := _aabb_of(path)
	k = minf(k, max_h / bb.size.y)
	var basis := Basis(Vector3.UP, turn)
	var front := Vector3(bb.get_center().x, 0, bb.end.z) * k
	node.basis = basis.scaled(Vector3.ONE * k)
	node.position = pos - basis * front
	_set.add_child(node)
	return bb.size * k


func _person(model: String, pos: Vector3, turn: float, anim: String, k := PERSON) -> Node3D:
	var node: Node3D = load(MODELS + "characters/" + model + ".glb").instantiate()
	node.position = pos
	node.rotation.y = turn
	node.scale = Vector3.ONE * k
	_set.add_child(node)
	var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["idle", "walk"]:
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	ap.play(anim)
	ap.seek(randf() * ap.current_animation_length)
	return node


## A boxy car: body, cabin with dark windows, wheels. Faces +Z at turn 0.
func _car(col: Color, pos: Vector3, turn: float, limo := false) -> Node3D:
	var car := Node3D.new()
	var length := 3.2 if limo else 2.3
	var body := _flat(col)
	body.roughness = 0.35
	body.metallic = 0.3
	_part(car, Vector3(1.05, 0.42, length), Vector3(0, 0.42, 0), body)
	_part(car, Vector3(0.95, 0.36, length * (0.62 if limo else 0.5)), Vector3(0, 0.8, -0.05), _flat(Color("#1E2430")))
	_part(car, Vector3(0.9, 0.06, length * (0.6 if limo else 0.48)), Vector3(0, 1.0, -0.05), body)
	for sx in [-0.5, 0.5]:
		for sz in [-length * 0.32, length * 0.32]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.22
			cyl.bottom_radius = 0.22
			cyl.height = 0.16
			wheel.mesh = cyl
			wheel.material_override = _flat(Color("#16181C"))
			wheel.rotation.z = PI / 2
			wheel.position = Vector3(sx, 0.22, sz)
			car.add_child(wheel)
	for sx in [-0.32, 0.32]:
		var lamp := _flat(Color("#FFF4C8"))
		lamp.emission_enabled = true
		lamp.emission = Color("#FFE9A0")
		lamp.emission_energy_multiplier = 0.6
		_part(car, Vector3(0.22, 0.1, 0.04), Vector3(sx, 0.48, length / 2.0), lamp)
	car.position = pos
	car.rotation.y = turn
	_set.add_child(car)
	return car


func _van(col: Color, pos: Vector3) -> void:
	var van := Node3D.new()
	_part(van, Vector3(1.15, 1.25, 2.8), Vector3(0, 0.85, -0.2), _flat(col))
	_part(van, Vector3(1.1, 0.42, 0.5), Vector3(0, 1.0, 1.2), _flat(Color("#1E2430")))
	_part(van, Vector3(1.15, 0.5, 0.6), Vector3(0, 0.5, 1.25), _flat(col))
	for sx in [-0.55, 0.55]:
		for sz in [-1.0, 0.9]:
			var w := _part(van, Vector3(0.16, 0.44, 0.44), Vector3(sx, 0.22, sz), _flat(Color("#16181C")))
			w.mesh = CylinderMesh.new()
			(w.mesh as CylinderMesh).top_radius = 0.22
			(w.mesh as CylinderMesh).bottom_radius = 0.22
			(w.mesh as CylinderMesh).height = 0.16
			w.rotation.z = PI / 2
	van.position = pos
	van.rotation.y = PI / 2
	_set.add_child(van)


func _police_car(pos: Vector3) -> void:
	var car := _car(Color("#E9ECF2"), pos, PI / 2)
	_part(car, Vector3(1.07, 0.18, 1.2), Vector3(0, 0.45, 0.1), _flat(Color("#1F2A44")))
	for i in 2:
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 2.5
		_part(car, Vector3(0.36, 0.12, 0.2), Vector3(-0.2 + 0.4 * i, 1.1, -0.05), mat)
		_lights.append(mat)


func _bench(pos: Vector3) -> void:
	var wood := Color("#9A6B42")
	_box(Vector3(1.6, 0.08, 0.45), pos + Vector3(0, 0.45, 0), wood)
	_box(Vector3(1.6, 0.4, 0.08), pos + Vector3(0, 0.7, -0.22), wood)
	for dx in [-0.65, 0.65]:
		_box(Vector3(0.08, 0.45, 0.4), pos + Vector3(dx, 0.22, 0), Color("#2B2F36"))


func _flag_pole(pos: Vector3) -> void:
	_box(Vector3(0.08, 3.6, 0.08), pos + Vector3(0, 1.8, 0), Color("#C9CCD1"))
	_box(Vector3(0.9, 0.55, 0.03), pos + Vector3(0.48, 3.2, 0), Color("#C8423B"))


## A subway entrance: a stairwell with railings under a canopy, and the METRO sign on a post.
func _subway_entrance(pos: Vector3) -> void:
	_box(Vector3(2.0, 0.03, 2.6), pos + Vector3(0, 0.02, -0.4), Color("#1A1D22"))
	for i in 5:
		_box(Vector3(1.8, 0.03, 0.4), pos + Vector3(0, 0.025, -1.5 + i * 0.42), Color("#3A3E46").lightened(i * 0.08))
	var rail := Color("#2F6E5E")
	for dx in [-1.0, 1.0]:
		_box(Vector3(0.06, 0.9, 2.6), pos + Vector3(dx, 0.45, -0.4), rail)
	_box(Vector3(2.06, 0.9, 0.06), pos + Vector3(0, 0.45, -1.7), rail)
	_box(Vector3(2.5, 0.1, 3.0), pos + Vector3(0, 2.4, -0.4), Color("#3E5C7A"))
	for dx in [-1.15, 1.15]:
		_box(Vector3(0.08, 2.4, 0.08), pos + Vector3(dx, 1.2, 0.95), Color("#2B2F36"))
	_box(Vector3(0.1, 3.0, 0.1), pos + Vector3(1.9, 1.5, 0.9), Color("#2B2F36"))
	var plate := _box(Vector3(0.75, 0.75, 0.1), pos + Vector3(1.9, 3.1, 0.9), Color("#2F5FA8"))
	var m := _sign_text("M", 120, Color.WHITE)
	m.position = Vector3(0, 0, 0.06)
	plate.add_child(m)


func _park_sign(text: String, pos: Vector3) -> void:
	for dx in [-0.9, 0.9]:
		_box(Vector3(0.1, 1.6, 0.1), pos + Vector3(dx, 0.8, 0), Color("#6B4A2E"))
	var board := _box(Vector3(2.4, 0.7, 0.08), pos + Vector3(0, 1.35, 0), Color("#3E7A4C"))
	var l := _sign_text(text, 44, Color("#F2EEE6"))
	l.position = Vector3(0, 0, 0.05)
	l.width = 560
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board.add_child(l)


## The trade sign on the roof edge (HOTEL, PUB, CASINO...).
func _roof_sign(text: String, top: float, front_z: float) -> void:
	var w := 0.62 * text.length() + 0.8
	var board := _box(Vector3(w, 0.95, 0.12), Vector3(0, top + 0.55, front_z - 0.3), Color("#22252B"))
	for dx in [-w / 2.0 + 0.3, w / 2.0 - 0.3]:
		_box(Vector3(0.08, 0.4, 0.08), Vector3(dx, top + 0.05, front_z - 0.3), Color("#22252B"))
	var l := _sign_text(text, 150, C_SIGN)
	l.position = Vector3(0, 0, 0.07)
	board.add_child(l)


## A row of light bulbs along the casino's front.
func _bulbs(half: float, y: float) -> void:
	var mat := _flat(Color("#FFE27A"))
	mat.emission_enabled = true
	mat.emission = Color("#FFC94A")
	mat.emission_energy_multiplier = 1.5
	var n := int(half * 2.0 / 0.35)
	for i in n + 1:
		var bulb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		bulb.mesh = s
		bulb.material_override = mat
		bulb.position = Vector3(-half + i * 0.35, y, 0.12)
		_set.add_child(bulb)


func _boat(pos: Vector3) -> void:
	var boat := Node3D.new()
	_part(boat, Vector3(4.2, 0.7, 1.5), Vector3(0, 0.1, 0), _flat(Color("#2F4A8C")))
	_part(boat, Vector3(4.25, 0.12, 1.55), Vector3(0, 0.5, 0), _flat(Color("#E8E3D6")))
	_part(boat, Vector3(1.5, 0.8, 1.1), Vector3(-0.6, 0.9, 0), _flat(Color("#E8E3D6")))
	_part(boat, Vector3(1.52, 0.25, 1.12), Vector3(-0.6, 1.05, 0), _flat(Color("#1E2430")))
	var root := Node3D.new()
	root.position = pos
	boat.position = Vector3.ZERO
	root.add_child(boat)
	_set.add_child(root)
	_bobbers.append(boat)


## A jet that crosses the sky every so often.
func _plane() -> void:
	var plane := Node3D.new()
	var white := _flat(Color("#F2F2F2"))
	_part(plane, Vector3(4.0, 0.5, 0.5), Vector3.ZERO, white)
	_part(plane, Vector3(1.0, 0.1, 4.6), Vector3(0.2, -0.05, 0), white)
	_part(plane, Vector3(0.7, 1.0, 0.1), Vector3(-1.8, 0.5, 0), _flat(Color("#C8423B")))
	_part(plane, Vector3(0.5, 0.08, 1.6), Vector3(-1.8, 0.1, 0), white)
	plane.rotation.z = 0.08
	_set.add_child(plane)
	_movers.append({"node": plane, "from": Vector3(-40, 10, -14), "to": Vector3(40, 15, -14), "speed": 7.0,
		"wait": 0.5, "pause": 3.0})


## Cars passing along the far lane now and then.
func _traffic(rng: RandomNumberGenerator) -> void:
	var car := _car(CAR_COLORS[rng.randi() % CAR_COLORS.size()], Vector3(30, 0, LANE_Z + 0.6), -PI / 2)
	_movers.append({"node": car, "from": Vector3(30, 0, LANE_Z + 0.6), "to": Vector3(-30, 0, LANE_Z + 0.6),
		"speed": 9.0, "wait": rng.randf_range(1.0, 3.0), "pause": rng.randf_range(4.0, 8.0)})


## Someone walking along the far pavement.
func _walker(rng: RandomNumberGenerator) -> void:
	var looks := ["character-female-c", "character-male-b", "character-female-f", "character-male-e"]
	var n := _person(looks[rng.randi() % looks.size()], Vector3(-22, 0, 6.6), PI / 2, "walk")
	_movers.append({"node": n, "from": Vector3(-22, 0, 6.6), "to": Vector3(22, 0, 6.6), "speed": 1.6,
		"wait": 0.0, "pause": rng.randf_range(2.0, 6.0)})


# ------------------------------------------------------------------ helpers

func _box(size: Vector3, pos: Vector3, col: Color, turn := 0.0, axis := Vector3.UP) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _flat(col)
	m.position = pos
	if turn != 0.0:
		m.rotate(axis, turn)
	_set.add_child(m)
	return m


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


func _sign_text(text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 8
	l.modulate = col
	l.outline_modulate = Color(0.05, 0.05, 0.07, 0.9)
	l.pixel_size = 0.004
	l.shaded = false
	return l


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _aabb_of(path: String) -> AABB:
	if _aabbs.has(path):
		return _aabbs[path]
	var node: Node3D = load(MODELS + path + ".glb").instantiate()
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p != node:
			xf = p.transform * xf
			p = p.get_parent()
		var a: AABB = xf * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	node.free()
	_aabbs[path] = box
	return box
