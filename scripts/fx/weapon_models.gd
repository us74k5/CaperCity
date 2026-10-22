class_name WeaponModels
## Semi-realistic 3D weapons, one per gear level (see Balance.GEAR), built from primitives so they
## need no files. Each model's origin is the grip (where the hand closes) and it points along +Z
## (barrel / blade forward), +Y up, in character-space units (a person is about 0.7 tall, so the
## weapons are scaled up a little to read from the top-down camera).
##
## Drop-in art: put a model at res://assets/models/weapons/<slug>.glb (or .fbx / .gltf) and it is
## used instead. Optional tuning per model in res://assets/models/weapons/weapons.json:
##   {"pistol": {"file": "Pistol_1.fbx", "length": 0.17, "rot": [0, 90, 0], "grip": 0.35}}
## length = how long it should be, rot = degrees to make it point +Z, grip = where along its
## length (0 = back, 1 = front) the hand holds it.

const SLUGS := ["fists", "club", "baton", "switchblade", "throwing_knife", "pistol", "rifle", "machine_gun", "grenade"]
const LENGTH := [0.0, 0.34, 0.27, 0.14, 0.12, 0.17, 0.44, 0.38, 0.07]
const GRIP := [0.0, 0.08, 0.15, 0.3, 0.3, 0.3, 0.38, 0.4, 0.5]
const DIR := "res://assets/models/weapons/"

static var _mats := {}
static var _cfg: Variant = null


## A weapon model for gear index `g`, or null for bare hands.
static func build(g: int) -> Node3D:
	if g <= 0 or g >= SLUGS.size():
		return null
	var custom := _custom(g)
	if custom:
		return custom
	var root := Node3D.new()
	root.name = SLUGS[g]
	match g:
		1: _club(root)
		2: _baton(root)
		3: _switchblade(root)
		4: _throwing_knife(root)
		5: _pistol(root)
		6: _rifle(root)
		7: _machine_gun(root)
		8: _grenade(root)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


## Where the muzzle (or blade tip) is, in the model's own space.
static func muzzle(g: int) -> Vector3:
	if g <= 0 or g >= SLUGS.size():
		return Vector3(0, 0, 0.12)
	return Vector3(0, 0.04 if g in [5, 6, 7] else 0.0, LENGTH[g] * (1.0 - GRIP[g]))


static func is_gun(g: int) -> bool:
	return g in [5, 6, 7]


# ------------------------------------------------------------------ materials

static func mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"gunmetal":
			m.albedo_color = Color(0.16, 0.17, 0.19)
			m.metallic = 0.85
			m.roughness = 0.35
		"blued":
			m.albedo_color = Color(0.12, 0.13, 0.16)
			m.metallic = 0.9
			m.roughness = 0.28
		"polymer":
			m.albedo_color = Color(0.09, 0.09, 0.1)
			m.roughness = 0.7
		"wood":
			m.albedo_color = Color(0.45, 0.27, 0.13)
			m.roughness = 0.6
		"wood_light":
			m.albedo_color = Color(0.72, 0.55, 0.33)
			m.roughness = 0.55
		"steel":
			m.albedo_color = Color(0.82, 0.84, 0.88)
			m.metallic = 0.55
			m.roughness = 0.3
		"brass":
			m.albedo_color = Color(0.8, 0.6, 0.25)
			m.metallic = 1.0
			m.roughness = 0.3
		"olive":
			m.albedo_color = Color(0.26, 0.3, 0.16)
			m.roughness = 0.65
		"rubber":
			m.albedo_color = Color(0.05, 0.05, 0.05)
			m.roughness = 0.95
		"tape":
			m.albedo_color = Color(0.2, 0.2, 0.22)
			m.roughness = 0.9
		"glass":
			m.albedo_color = Color(0.25, 0.45, 0.6)
			m.metallic = 0.5
			m.roughness = 0.05
			m.emission_enabled = true
			m.emission = Color(0.1, 0.25, 0.35)
	_mats[kind] = m
	return m


static func _box(p: Node3D, size: Vector3, pos: Vector3, m: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat(m)
	p.add_child(mi)
	return mi


## A cylinder lying along +Z.
static func _cyl(p: Node3D, r_back: float, r_front: float, length: float, center_z: float, m: String, y := 0.0, x := 0.0, sides := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_back
	cm.top_radius = r_front
	cm.height = length
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.position = Vector3(x, y, center_z)
	mi.material_override = mat(m)
	p.add_child(mi)
	return mi


static func _sphere(p: Node3D, r: float, pos: Vector3, m: String, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 14
	sm.rings = 8
	mi.mesh = sm
	mi.position = pos
	mi.scale = scale
	mi.material_override = mat(m)
	p.add_child(mi)
	return mi


static func _torus(p: Node3D, inner: float, outer: float, pos: Vector3, rot: Vector3, m: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 16
	tm.ring_segments = 8
	mi.mesh = tm
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat(m)
	p.add_child(mi)
	return mi


static func _blade(p: Node3D, length: float, width: float, thick: float, z0: float, m := "steel") -> void:
	# a straight blade with a pointed tip: body box + a tapered tip (prism)
	var body := length * 0.72
	_box(p, Vector3(thick, width, body), Vector3(0, 0, z0 + body / 2.0), m)
	var tip := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(width, length - body, thick)
	pm.left_to_right = 0.0
	tip.mesh = pm
	tip.rotation_degrees = Vector3(90, 0, 90)
	tip.position = Vector3(0, 0, z0 + body + (length - body) / 2.0)
	tip.material_override = mat(m)
	p.add_child(tip)


# ------------------------------------------------------------------ the arsenal

static func _club(r: Node3D) -> void:
	# baseball bat: taped handle, knob, tapering barrel
	_cyl(r, 0.019, 0.019, 0.012, -0.02, "wood")                    # knob
	_cyl(r, 0.012, 0.013, 0.09, 0.025, "tape")                      # grip tape
	_cyl(r, 0.013, 0.026, 0.12, 0.13, "wood")                       # taper
	_cyl(r, 0.026, 0.029, 0.11, 0.245, "wood")                      # barrel
	_sphere(r, 0.029, Vector3(0, 0, 0.3), "wood", Vector3(1, 1, 0.5))


static func _baton(r: Node3D) -> void:
	# police side-handle baton (tonfa)
	_cyl(r, 0.012, 0.012, 0.27, 0.095, "polymer")
	_cyl(r, 0.014, 0.014, 0.05, 0.0, "rubber")                      # grip
	_cyl(r, 0.014, 0.014, 0.012, 0.23, "rubber")                    # end cap
	var side := _cyl(r, 0.01, 0.01, 0.06, 0.0, "polymer", 0.0, 0.03)
	side.rotation_degrees = Vector3(0, 0, 90)
	side.position = Vector3(0.035, 0, 0.05)


static func _switchblade(r: Node3D) -> void:
	_box(r, Vector3(0.016, 0.022, 0.07), Vector3(0, 0, 0.0), "polymer")       # handle
	_box(r, Vector3(0.018, 0.024, 0.008), Vector3(0, 0, -0.035), "steel")     # pommel bolster
	_box(r, Vector3(0.018, 0.024, 0.008), Vector3(0, 0, 0.035), "steel")      # front bolster
	_box(r, Vector3(0.004, 0.006, 0.012), Vector3(0, 0.014, 0.01), "steel")   # button
	_blade(r, 0.075, 0.018, 0.004, 0.039)


static func _throwing_knife(r: Node3D) -> void:
	_torus(r, 0.008, 0.013, Vector3(0, 0, -0.03), Vector3(0, 90, 0), "steel")  # ring
	_box(r, Vector3(0.012, 0.016, 0.045), Vector3(0, 0, -0.0), "tape")       # wrapped handle
	_blade(r, 0.07, 0.022, 0.003, 0.022)


static func _pistol(r: Node3D) -> void:
	# compact semi-auto: slide, frame, angled grip, trigger guard, sights
	_box(r, Vector3(0.026, 0.032, 0.15), Vector3(0, 0.046, 0.045), "gunmetal")       # slide
	for i in 6:   # rear slide serrations
		_box(r, Vector3(0.028, 0.026, 0.003), Vector3(0, 0.048, -0.02 + i * 0.006), "blued")
	_box(r, Vector3(0.024, 0.02, 0.115), Vector3(0, 0.021, 0.04), "polymer")         # frame
	_box(r, Vector3(0.026, 0.085, 0.036), Vector3(0, -0.02, -0.008), "polymer", Vector3(-14, 0, 0))   # grip
	_box(r, Vector3(0.027, 0.006, 0.04), Vector3(0, -0.063, -0.018), "gunmetal", Vector3(-14, 0, 0))  # magazine base
	_torus(r, 0.016, 0.02, Vector3(0, 0.005, 0.035), Vector3(0, 90, 0), "polymer")   # trigger guard
	_box(r, Vector3(0.004, 0.016, 0.004), Vector3(0, 0.005, 0.03), "gunmetal", Vector3(-10, 0, 0))   # trigger
	_cyl(r, 0.006, 0.006, 0.012, 0.124, "blued", 0.05)                               # muzzle
	_box(r, Vector3(0.006, 0.007, 0.006), Vector3(0, 0.065, 0.11), "polymer")         # front sight
	_box(r, Vector3(0.02, 0.007, 0.006), Vector3(0, 0.065, -0.022), "polymer")       # rear sight


static func _rifle(r: Node3D) -> void:
	# bolt-action hunting rifle with a scope
	_box(r, Vector3(0.03, 0.05, 0.13), Vector3(0, 0.005, -0.12), "wood", Vector3(6, 0, 0))   # butt stock
	_box(r, Vector3(0.032, 0.058, 0.016), Vector3(0, 0.0, -0.188), "rubber", Vector3(6, 0, 0))  # recoil pad
	_box(r, Vector3(0.026, 0.05, 0.05), Vector3(0, -0.015, -0.03), "wood", Vector3(-20, 0, 0))   # wrist / grip
	_box(r, Vector3(0.03, 0.034, 0.17), Vector3(0, 0.018, 0.08), "wood")                        # fore-end
	_box(r, Vector3(0.026, 0.026, 0.12), Vector3(0, 0.044, 0.02), "blued")                      # receiver
	_cyl(r, 0.009, 0.007, 0.2, 0.18, "blued", 0.045)                                              # barrel
	_cyl(r, 0.009, 0.009, 0.012, 0.284, "gunmetal", 0.045)                                        # crown
	var bolt := _cyl(r, 0.004, 0.004, 0.03, -0.01, "steel", 0.05, 0.02)                          # bolt handle
	bolt.rotation_degrees = Vector3(0, 0, 90)
	_sphere(r, 0.007, Vector3(0.036, 0.05, -0.01), "steel")                                       # bolt knob
	_torus(r, 0.014, 0.018, Vector3(0, -0.005, 0.0), Vector3(0, 90, 0), "blued")                 # trigger guard
	# scope with rings and lenses
	_cyl(r, 0.012, 0.012, 0.12, 0.03, "polymer", 0.085)
	_cyl(r, 0.017, 0.012, 0.03, 0.105, "polymer", 0.085)
	_cyl(r, 0.014, 0.012, 0.025, -0.04, "polymer", 0.085)
	_cyl(r, 0.0155, 0.0155, 0.002, 0.121, "glass", 0.085)
	for z in [-0.005, 0.06]:
		_box(r, Vector3(0.012, 0.03, 0.01), Vector3(0, 0.066, z), "gunmetal")


static func _machine_gun(r: Node3D) -> void:
	# compact assault rifle: polymer stock, receiver with rail, curved magazine, vented handguard
	_box(r, Vector3(0.026, 0.045, 0.1), Vector3(0, 0.03, -0.13), "polymer")          # stock
	_box(r, Vector3(0.028, 0.055, 0.012), Vector3(0, 0.025, -0.185), "rubber")       # butt pad
	_box(r, Vector3(0.014, 0.014, 0.06), Vector3(0, 0.045, -0.07), "gunmetal")       # buffer tube
	_box(r, Vector3(0.028, 0.04, 0.13), Vector3(0, 0.04, 0.0), "gunmetal")           # receiver
	_box(r, Vector3(0.014, 0.01, 0.18), Vector3(0, 0.065, 0.04), "polymer")          # top rail
	for i in 10:
		_box(r, Vector3(0.018, 0.004, 0.006), Vector3(0, 0.071, -0.04 + i * 0.017), "polymer")
	_box(r, Vector3(0.024, 0.07, 0.03), Vector3(0, -0.02, -0.03), "polymer", Vector3(-16, 0, 0))   # pistol grip
	_box(r, Vector3(0.02, 0.06, 0.032), Vector3(0, -0.02, 0.04), "polymer", Vector3(12, 0, 0))     # magazine
	_box(r, Vector3(0.02, 0.04, 0.03), Vector3(0, -0.06, 0.052), "polymer", Vector3(24, 0, 0))     # (curved)
	_torus(r, 0.013, 0.017, Vector3(0, 0.0, 0.005), Vector3(0, 90, 0), "gunmetal")                # trigger guard
	_box(r, Vector3(0.03, 0.034, 0.1), Vector3(0, 0.04, 0.115), "polymer")                         # handguard
	for i in 4:
		_box(r, Vector3(0.032, 0.006, 0.012), Vector3(0, 0.04, 0.08 + i * 0.022), "gunmetal")      # vents
	_cyl(r, 0.006, 0.006, 0.07, 0.2, "blued", 0.042)                                                 # barrel
	_cyl(r, 0.009, 0.009, 0.022, 0.24, "gunmetal", 0.042, 0.0, 6)                                    # flash hider
	_box(r, Vector3(0.006, 0.02, 0.006), Vector3(0, 0.068, 0.16), "gunmetal")                       # front sight


static func _grenade(r: Node3D) -> void:
	# fragmentation "pineapple" grenade with spoon and pin
	_sphere(r, 0.026, Vector3(0, 0, 0.0), "olive", Vector3(1, 1.25, 1))
	for i in 3:
		_torus(r, 0.0255, 0.0275, Vector3(0, -0.018 + i * 0.018, 0), Vector3.ZERO, "olive")
	_cyl(r, 0.012, 0.012, 0.018, 0.0, "olive", 0.034).rotation_degrees = Vector3.ZERO           # fuse top
	_box(r, Vector3(0.012, 0.05, 0.005), Vector3(0, 0.02, -0.027), "olive", Vector3(-8, 0, 0))   # spoon
	_torus(r, 0.006, 0.009, Vector3(0.016, 0.045, 0), Vector3(0, 0, 90), "steel")               # pin ring


# ------------------------------------------------------------------ drop-in models

static func _custom(g: int) -> Node3D:
	var slug: String = SLUGS[g]
	if _cfg == null:
		_cfg = {}
		if FileAccess.file_exists(DIR + "weapons.json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIR + "weapons.json"))
			if parsed is Dictionary:
				_cfg = parsed
	var c: Dictionary = _cfg.get(slug, {})
	var path := ""
	if c.has("file"):
		path = DIR + str(c.file)
	else:
		for ext in ["glb", "gltf", "fbx"]:
			if ResourceLoader.exists(DIR + slug + "." + ext):
				path = DIR + slug + "." + ext
				break
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var model: Node3D = scene.instantiate()
	var holder := Node3D.new()
	holder.name = slug
	var turn := Node3D.new()
	var rot: Array = c.get("rot", [0, 0, 0])
	turn.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	turn.add_child(model)
	holder.add_child(turn)
	# fit: scale the longest side to the wanted length and put the grip at the origin
	var box := _aabb(turn)
	var longest: float = maxf(box.size.z, maxf(box.size.x, box.size.y))
	if longest <= 0.0:
		return holder
	var s: float = float(c.get("length", LENGTH[g])) / longest
	turn.scale = Vector3.ONE * s
	box = _aabb(turn)
	var grip: float = float(c.get("grip", GRIP[g]))
	turn.position = -Vector3(box.position.x + box.size.x / 2.0, box.position.y + box.size.y * 0.35, box.position.z + box.size.z * grip)
	return holder


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := n.global_transform.affine_inverse() * m.global_transform if n.is_inside_tree() else _rel(n, m)
		var b := xf * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return root.transform * xf if false else xf
