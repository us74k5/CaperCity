extends Node3D
## The car dealer's lot: painted stalls of cars with price tags on the windscreens, the glass
## showroom at the back, bunting strung between light poles, a chain-link fence and a waving tube
## man by the street. Cars for sale stand in the front row; the dealer's best cars, which you can
## only steal, stand in the back row. While you're picking one to steal the camera walks in among
## them and the salesman turns his back.
## Cars are from Kenney's Car Kit (CC0), one model per car in Balance.CARS.

const CARS := "res://assets/models/cars/"
const MODELS := "res://assets/models/"
const PERSON := 1.5
const CAR_LEN := 3.1
const STALL_W := 3.6
const FRONT_Z := -1.0
const BACK_Z := -7.6
# Balance.CARS index -> [model, tint, length stretch]
const LOOKS := {
	1: ["hatchback-sports", Color.WHITE, 1.0],
	2: ["sedan", Color.WHITE, 1.0],
	3: ["sedan-sports", Color.WHITE, 1.0],
	4: ["van", Color.WHITE, 1.0],
	5: ["suv", Color.WHITE, 1.0],
	6: ["suv-luxury", Color.WHITE, 1.0],
	7: ["sedan", Color(0.32, 0.32, 0.36), 1.45],
	8: ["sedan-sports", Color(0.45, 0.47, 0.55), 1.0],
	9: ["race-future", Color.WHITE, 1.0],
	10: ["race", Color.WHITE, 1.0],
}
const C_ASPHALT := Color("#3A3D42")
const C_LINE := Color("#E9E6DC")
const C_PENNANTS := [Color("#E0322A"), Color("#F2C230"), Color("#2F6BD8"), Color("#F4F4F4")]

var mode := "lot"                     # "lot", or "steal" while picking a car to steal
var _cam := Transform3D()
var _cam_ready := false
var _tube: Array = []                 # the tube man's segments, bottom up
var _salesman: Node3D
var _tags: Array = []                 # {label, steal} price tags
var _me: Node3D
var _t := 0.0


func build(b: Dictionary, p: Dictionary) -> void:
	_ground()
	_showroom(b)
	_bunting()
	_tube_man(Vector3(-11.5, 0, 2.6))
	var stock: Array = b.get("stock", [])
	var lot: Array = b.get("lot", [])
	_row(stock, FRONT_Z, false)
	_row(lot, BACK_Z, true)
	for c in [Vector3(-9.0, 0, FRONT_Z + 1.2), Vector3(9.0, 0, BACK_Z + 1.2), Vector3(-9.0, 0, BACK_Z + 1.2)]:
		_prop("cone", c, 0.7)
	_salesman = _extra("character-male-b", Vector3(-2.2, 0, -11.0), 0.0)
	_me = _extra(UiTheme.look_of(p), Vector3(-3.0, 0, 2.4), 0.5)
	update(p)


## Follows the menu: in among the cars while picking one to steal.
func update(p: Dictionary) -> void:
	mode = "steal" if p.get("menu_path", []).has("steal_car") else "lot"
	if _salesman:
		_salesman.rotation.y = PI if mode == "steal" else 0.0   # busy on the phone inside
	for tag in _tags:
		tag.label.visible = mode == "lot" or tag.steal
	if _me:
		# Strolling down the back row, hands in pockets.
		_me.position = Vector3(-1.8, 0, BACK_Z + 1.4) if mode == "steal" else Vector3(-3.0, 0, 2.4)
		_me.rotation.y = -PI * 0.6 if mode == "steal" else 0.5


func camera_pose(aspect: float) -> Transform3D:
	# Aimed right of the middle: the menu covers the right of the screen.
	var eye := Vector3(2.6, 8.5, 15.5)
	var look := Vector3(2.6, 0.0, -4.5)
	if mode == "steal":
		# In the aisle between the rows, looking at the back row.
		eye = Vector3(2.6, 4.4, BACK_Z + 8.8)
		look = Vector3(2.6, 0.4, BACK_Z - 1.0)
	if aspect < 1.2:
		eye = Vector3(0, 12.0, 19.0) if mode == "lot" else Vector3(0, 4.0, BACK_Z + 8.0)
		look = Vector3(0, 0.0, -4.5) if mode == "lot" else Vector3(0, 0.4, BACK_Z - 1.0)
	var target := Transform3D(Basis.looking_at(look - eye, Vector3.UP), global_position + eye)
	if not _cam_ready:
		_cam = target
		_cam_ready = true
	_cam = _cam.interpolate_with(target, 0.08)
	return _cam


func _process(delta: float) -> void:
	_t += delta
	# The tube man flops about, each segment a little behind the one below.
	for i in _tube.size():
		var seg: Node3D = _tube[i]
		seg.rotation.z = (0.18 + 0.07 * i) * sin(_t * 3.2 - i * 0.7)
		seg.rotation.x = 0.08 * sin(_t * 2.3 - i * 0.5)


# ------------------------------------------------------------------ the lot

func _ground() -> void:
	_box(Vector3(30, 0.04, 18), Vector3(0, 0.0, -5.0), C_ASPHALT)
	# Pavement and the street in front.
	_box(Vector3(40, 0.16, 2.0), Vector3(0, 0.06, 5.0), Color("#B5B2AA"))
	_box(Vector3(40, 0.04, 6.0), Vector3(0, 0.0, 9.0), Color("#2C2E33"))
	for i in 10:
		_box(Vector3(1.8, 0.05, 0.16), Vector3(-18.0 + i * 4.0, 0.01, 9.0), Color("#E8C547"))
	# Stall lines: two rows of five, plus the lane between them.
	for row_z in [FRONT_Z, BACK_Z]:
		for i in 6:
			var x := (i - 2.5) * STALL_W
			_box(Vector3(0.12, 0.05, 4.4), Vector3(x, 0.02, row_z), C_LINE)
		_box(Vector3(STALL_W * 5, 0.05, 0.12), Vector3(0, 0.02, row_z - 2.2), C_LINE)
	# Chain-link fence down the sides.
	for side in [-1, 1]:
		var x: float = side * 14.5
		for k in 7:
			_box(Vector3(0.1, 2.0, 0.1), Vector3(x, 1.0, 3.2 - k * 2.4), Color("#9AA0A8"))
		var mesh := _box(Vector3(0.04, 1.9, 14.4), Vector3(x, 1.0, -4.0), Color(0.7, 0.74, 0.78, 0.35))
		(mesh.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_box(Vector3(0.08, 0.08, 14.4), Vector3(x, 2.0, -4.0), Color("#9AA0A8"))
	# Arrows painted in the aisle.
	for x in [-6.0, 6.0]:
		var arrow := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.9, 1.0, 0.04)
		arrow.mesh = prism
		arrow.material_override = _flat(C_LINE)
		arrow.rotation = Vector3(-PI / 2, 0, PI / 2 if x < 0 else -PI / 2)
		arrow.position = Vector3(x, 0.03, (FRONT_Z + BACK_Z) / 2.0)
		add_child(arrow)


## A glass-fronted showroom across the back, with the dealer's name on the roof.
func _showroom(b: Dictionary) -> void:
	var z := -12.5
	_box(Vector3(16, 4.2, 4.0), Vector3(0, 2.1, z - 2.0), Color("#D8D4CA"))
	_box(Vector3(16.4, 0.4, 4.6), Vector3(0, 4.4, z - 2.0), Color("#2F5FA8"))
	for i in 5:
		var pane := _box(Vector3(2.7, 3.2, 0.08), Vector3(-6.0 + i * 3.0, 1.75, z + 0.02), Color(0.62, 0.82, 0.95, 0.45))
		var m: StandardMaterial3D = pane.material_override
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.4
		m.roughness = 0.05
		_box(Vector3(0.14, 3.4, 0.14), Vector3(-7.5 + i * 3.0, 1.75, z + 0.05), Color("#E8E8E8"))
	_box(Vector3(0.14, 3.4, 0.14), Vector3(7.5, 1.75, z + 0.05), Color("#E8E8E8"))
	# A car on show inside.
	_car(3, Vector3(3.0, 0, z - 2.0), PI / 2)
	var name := _text(str(b.name).to_upper(), 150, Color("#FFFFFF"))
	name.position = Vector3(0, 5.3, z)
	name.outline_modulate = Color("#1A3A6E")
	add_child(name)
	var autos := _text("AUTOS · BEST DEALS IN TOWN", 56, Color("#FFD27A"))
	autos.position = Vector3(0, 4.4, z + 0.35)
	add_child(autos)


## A row of stalls: the given cars in the middle stalls, each with its tag.
func _row(cars: Array, z: float, steal: bool) -> void:
	var first := 2 - cars.size() / 2
	for i in cars.size():
		var ci := int(cars[i])
		var x := (first + i - 2) * STALL_W
		_car(ci, Vector3(x, 0, z), 0.0)
		var car: Dictionary = Balance.CARS[ci]
		var text := "%s\n%s" % [car.name, "NOT FOR SALE" if steal else "$%s" % _money(int(car.price))]
		var tag := _text(text, 30, Color("#FFD27A") if steal else Color.WHITE)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(x, 2.0, z + 0.6)
		add_child(tag)
		_tags.append({"label": tag, "steal": steal})


## Car `ci` (see LOOKS) parked at `pos`, nose toward the street at turn 0.
func _car(ci: int, pos: Vector3, turn: float) -> Node3D:
	var look: Array = LOOKS.get(ci, LOOKS[2])
	var node: Node3D = load(CARS + str(look[0]) + ".glb").instantiate()
	var bb := _aabb(node)
	var k: float = CAR_LEN / maxf(bb.size.z, 0.01)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = turn
	add_child(holder)
	node.scale = Vector3(k, k, k * float(look[2]))
	node.position = -Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * Vector3(k, k, k * float(look[2]))
	holder.add_child(node)
	if look[1] != Color.WHITE:
		_tint(node, look[1])
	return holder


func _prop(model: String, pos: Vector3, size: float) -> void:
	var node: Node3D = load(CARS + model + ".glb").instantiate()
	var bb := _aabb(node)
	var k := size / maxf(bb.size.y, 0.01)
	node.scale = Vector3.ONE * k
	node.position = pos - Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * k
	add_child(node)


## Strings of pennants from the light poles across the lot.
func _bunting() -> void:
	var poles := [Vector3(-13, 0, 3.5), Vector3(13, 0, 3.5), Vector3(-13, 0, -11.0), Vector3(13, 0, -11.0)]
	for p in poles:
		_box(Vector3(0.16, 5.6, 0.16), p + Vector3(0, 2.8, 0), Color("#7C838C"))
		var lamp := _box(Vector3(0.9, 0.18, 0.5), p + Vector3(0, 5.6, 0), Color("#FFF4C8"))
		(lamp.material_override as StandardMaterial3D).emission_enabled = true
		(lamp.material_override as StandardMaterial3D).emission = Color("#FFE9A0")
	for pair in [[0, 2], [1, 3], [2, 3]]:   # down the sides and across the back, clear of the view
		var a: Vector3 = poles[pair[0]] + Vector3(0, 5.2, 0)
		var b: Vector3 = poles[pair[1]] + Vector3(0, 5.2, 0)
		var n := int(a.distance_to(b) / 0.7)
		for i in n:
			var f := (i + 0.5) / n
			var at := a.lerp(b, f) - Vector3(0, 0.9 * sin(f * PI), 0)   # sagging in the middle
			var flag := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(0.36, 0.45, 0.02)
			flag.mesh = prism
			flag.material_override = _flat(C_PENNANTS[i % C_PENNANTS.size()])
			flag.position = at - Vector3(0, 0.25, 0)
			flag.rotation.z = PI   # point down
			flag.rotation.y = atan2(b.x - a.x, b.z - a.z) + PI / 2
			add_child(flag)


## The inflatable tube man: a stack of red segments with arms, flopping in _process.
func _tube_man(at: Vector3) -> void:
	_box(Vector3(0.9, 0.4, 0.9), at + Vector3(0, 0.2, 0), Color("#2B2F36"))
	var parent: Node3D = self
	var base := at + Vector3(0, 0.4, 0)
	for i in 6:
		var seg := Node3D.new()
		seg.position = base if i == 0 else Vector3(0, 0.55, 0)
		parent.add_child(seg)
		var cyl := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.26
		mesh.bottom_radius = 0.28
		mesh.height = 0.58
		cyl.mesh = mesh
		cyl.material_override = _flat(Color("#E0322A") if i < 5 else Color("#F2C230"))
		cyl.position.y = 0.28
		seg.add_child(cyl)
		if i == 3:
			for s in [-1, 1]:
				var arm := _part(seg, Vector3(0.9, 0.16, 0.16), Vector3(s * 0.6, 0.4, 0), Color("#E0322A"))
				arm.rotation.z = s * 0.5
		_tube.append(seg)
		parent = seg


# ------------------------------------------------------------------ helpers

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


## Bounds of a model's meshes, in its own space.
func _aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		var xf := Transform3D()
		var n: Node = mi
		while n != node and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var bb: AABB = xf * mi.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


## Darkens a model's paint (and everything else) by `col`: the limo and the Stiletto are black.
func _tint(node: Node3D, col: Color) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var dup: StandardMaterial3D = mat.duplicate()
				dup.albedo_color = dup.albedo_color * col
				dup.metallic = 0.5
				dup.roughness = 0.25
				mi.set_surface_override_material(s, dup)


func _money(n: int) -> String:
	var s := str(n)
	return s if s.length() <= 3 else s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)


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
