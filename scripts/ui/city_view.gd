extends Node3D
## Draws the city in 3D from Net.state and animates player tokens.
## Models are Kenney's City Kits (CC0): see assets/models/*/License.txt.
## One grid cell = one world unit; cell (x, y) covers x..x+1 on X and y..y+1 on Z.

signal cell_tapped(cell: Vector2i)
signal fight_square_tapped(cell: Vector2i)
signal table_tapped(game: String)

const MODELS := "res://assets/models/"
const ZOOM_MIN := 6.0
const ZOOM_MAX := 30.0
const PITCH := deg_to_rad(52.0)
const ARENA := Vector3(-30, 0, 4)   # where fights are staged, off the west edge of town
const FIGHT_ZOOM := 11.5
const MINI := Vector3(-150, 0, -40)   # where the grid minigames are staged
const MINI_PITCH := deg_to_rad(72.0)
const PLACE := Vector3(-150, 0, 40)  # where the inside-a-building scene is staged, well away from town
const MAX_HEIGHT := 3.2    # tallest a model may be after scaling to its lot
const TOKEN_CAR_LEN := 0.95  # players' cars and the squad car on the map

# Building looks: model variants (kit/name) per type. A building picks one by its id.
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
}
const OFFICES := ["commercial/building-skyscraper-b", "commercial/building-skyscraper-c", "commercial/building-skyscraper-d",
	"industrial/building-a", "industrial/building-b", "industrial/building-d", "industrial/building-e", "industrial/building-g"]
const HOUSES := ["suburban/building-type-a", "suburban/building-type-c", "suburban/building-type-e", "suburban/building-type-h",
	"suburban/building-type-i", "suburban/building-type-k", "suburban/building-type-l", "suburban/building-type-o",
	"suburban/building-type-r", "suburban/building-type-s", "suburban/building-type-u"]
# Crew characters for players. character-male-c wears a police uniform, so it only appears at Police HQ.
const CREW_LOOKS := ["character-male-a", "character-female-a", "character-male-b", "character-female-b",
	"character-male-d", "character-female-c", "character-male-e", "character-female-d", "character-male-f",
	"character-female-f", "character-female-e"]
const COP := "character-male-c"
# Types that stand on grass rather than paving.
const GREEN_LOTS := ["villa", "playground"]

const C_GRASS := Color("#6DA35F")
const C_WATER := Color("#3F86A6")
const C_ASPHALT := Color("#7C8095")   # matches the Kenney road surface
const C_MEDIAN := Color("#5E9C4E")
const C_KERB := Color("#DDE3F0")
const C_RING := Color("#35D0BA")
const C_SIGN := Color("#FFD27A")

var city: Dictionary = {}
var camera: Camera3D
var zoom := 13.0
var _display_pos := {}     # pid -> Vector3, animated
var _tokens := {}          # pid -> {node, person, anim, car, label}
var _t := 0.0
var _world: Node3D
var _heights := {}         # building id -> height, for tap picking
var _aabbs := {}           # model path -> AABB cache
var _custom_meshes := {}    # "custom:..." batch key -> Mesh made in code (the motorway)
var _ring: MeshInstance3D
var _ransom: Node3D
var _cam_target := Vector3.ZERO
var fight_view: Node3D
var place_view: Node3D
var mini_view: Node3D
var _police: Node3D
var _police_lights: Array = []
var _seen_rev := -1
## Free look: the player dragged the map, so the camera stays put instead of following the active
## crew until follow() (walking, Centre, or a new turn).
var free_look := false
var _press := {}            # the mouse button held down on the map: {button, at, last, dragged}
var _follow_pid := -1
const DRAG_START := 10.0    # pixels the pointer must travel before a press becomes a drag


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.far = 200.0
	add_child(camera)
	camera.make_current()

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#1B2230")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#9AA6C0")
	env.environment.ambient_light_energy = 0.45
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	sun.light_color = Color("#FFF1DC")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.42
	_ring.mesh = torus
	_ring.material_override = _flat(C_RING)
	_ring.visible = false
	add_child(_ring)

	_ransom = Node3D.new()
	var rr := MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = 1.3
	rt.outer_radius = 1.45
	rr.mesh = rt
	rr.material_override = _flat(Color(0.95, 0.76, 0.19))
	_ransom.add_child(rr)
	var rl := _label("RANSOM DROP", 56, Color("#F2C230"))
	rl.position.y = 3.6
	_ransom.add_child(rl)
	_ransom.visible = false
	add_child(_ransom)

	fight_view = preload("res://scripts/ui/fight_view.gd").new()
	fight_view.crew_looks = CREW_LOOKS
	fight_view.position = ARENA
	add_child(fight_view)
	place_view = preload("res://scripts/ui/place_view.gd").new()
	place_view.crew_looks = CREW_LOOKS
	place_view.position = PLACE
	add_child(place_view)
	mini_view = preload("res://scripts/ui/mini_view.gd").new()
	mini_view.crew_looks = CREW_LOOKS
	mini_view.position = MINI
	add_child(mini_view)
	_police = _make_police_stop()
	add_child(_police)


## True while a fight is on screen.
func in_fight() -> bool:
	return not Net.state.get("fight", {}).is_empty() and Net.state.get("phase", "") == "playing"


## The casino follows the menu: which table you're sitting at, and the hand just played.
func _update_casino(active: Dictionary) -> void:
	place_view.casino.sit(casino_table(active))
	var pend: Dictionary = Net.state.pending
	if pend.get("kind", "") == "result" and pend.has("show"):
		place_view.casino.play(pend.show, str(pend.show.get("n", 0)))


## The casino table the active player is sitting at ("" if none): their menu offers its stakes.
static func casino_table(active: Dictionary) -> String:
	for e in active.get("menu", []):
		var id: String = e.id
		if id.begins_with("act:gamble:"):
			return id.split(":")[2]
	return ""


## True while the casino is showing a hand being played out.
func casino_busy() -> bool:
	if not in_place() or place_view.casino == null:
		return false
	var pend: Dictionary = Net.state.pending
	var unplayed: bool = pend.get("kind", "") == "result" and pend.has("show") and place_view.casino.played() != str(pend.show.get("n", 0))
	return unplayed or place_view.casino.busy()


## True while a grid minigame is on screen (it takes over from everything else). The safe isn't one:
## it plays over the bank's scene.
func in_mini() -> bool:
	return Mini.is_grid(Net.state.get("mini", {})) and Net.state.get("phase", "") == "playing" and not in_fight()


## True while the active player is inside a building and its scene is on screen (a fight takes over).
func in_place() -> bool:
	var a := Net.active_player()
	return not a.is_empty() and int(a.inside) >= 0 and Net.state.get("phase", "") == "playing" and not in_fight() and not in_mini()


func set_city(c: Dictionary) -> void:
	if c == city and _world:
		return
	city = c
	if _world:
		_world.queue_free()
	_world = Node3D.new()
	add_child(_world)
	_build_world()


func _process(delta: float) -> void:
	_t += delta
	if Net.state.is_empty() or city.is_empty():
		return
	var active := Net.active_player()
	for pid in Net.state.players:
		var p: Dictionary = Net.state.players[pid]
		var target := _token_target(p)
		var cur: Vector3 = _display_pos.get(pid, target)
		var nxt := cur.lerp(target, minf(1.0, delta * 12.0))
		_display_pos[pid] = nxt
		_update_token(pid, p, nxt, cur)
	_ring.visible = false
	if not active.is_empty() and _display_pos.has(active.id):
		var ap: Vector3 = _display_pos[active.id]
		if int(active.id) != _follow_pid:
			_follow_pid = int(active.id)
			free_look = false   # a new turn: go and watch it
		if not in_fight() and not free_look:
			_cam_target = _cam_target.lerp(ap, minf(1.0, delta * 6.0))
		if int(active.jail) <= 0 and int(active.holiday) <= 0:
			_ring.visible = true
			_ring.position = ap + Vector3(0, 0.03, 0)
			var s := 1.0 + 0.08 * sin(_t * 5.0)
			_ring.scale = Vector3(s, 1, s)
	_update_ransom()
	_update_police(active)
	var dist := zoom
	if in_fight():
		free_look = false
		if int(Net.state.rev) != _seen_rev:
			fight_view.show_fight(Net.state.fight)
		_cam_target = _cam_target.lerp(fight_view.center(), minf(1.0, delta * 8.0))
		dist = FIGHT_ZOOM
	elif fight_view.showing():
		fight_view.clear()
	_seen_rev = int(Net.state.rev)
	# The building you were in stays built underneath, but its sky backdrop reaches across the
	# minigame stage, so it hides until the fight or minigame is over.
	place_view.visible = not in_mini() and not in_fight()
	if in_mini():
		mini_view.show_mini(Net.state.mini, UiTheme.look_of(active), Color(active.color))
		var vs := get_viewport().get_visible_rect().size
		var fit := maxf(Mini.H + 5.5, (Mini.W + 2.0) / maxf(0.5, vs.x / maxf(1.0, vs.y)))
		var d := fit / 2.0 / tan(deg_to_rad(camera.fov / 2.0)) * 0.98
		var look: Vector3 = mini_view.center() + Vector3(0, 0, -1.4)   # the grid sits low, clear of the minigame bar
		# The jailbreak is watched from lower down, so the people (and Big Lou's moment) read.
		var pitch: float = deg_to_rad(52.0) if Net.state.mini.get("game", "") == "jailbreak" else MINI_PITCH
		camera.position = look + Vector3(0, sin(pitch), cos(pitch)) * d
		camera.look_at(look, Vector3.UP)
		return
	elif mini_view.showing():
		mini_view.clear()
	if in_place():
		place_view.show_place(city.buildings[int(active.inside)], active)
		if place_view.casino:
			_update_casino(active)
		var vs := get_viewport().get_visible_rect().size
		camera.global_transform = place_view.camera_pose(vs.x / maxf(1.0, vs.y))
		return
	elif place_view.showing():
		place_view.clear()
	var back := Vector3(0, sin(PITCH), cos(PITCH)) * dist
	camera.position = _cam_target + back
	camera.look_at(_cam_target, Vector3.UP)
	if in_fight():
		camera.position += fight_view.shake_offset()


func _token_target(p: Dictionary) -> Vector3:
	if int(p.inside) >= 0:
		var b: Dictionary = city.buildings[int(p.inside)]
		return Vector3(int(b.x) + 1, 0, int(b.y) + 1)
	return Vector3(int(p.pos[0]) + 0.5, 0, int(p.pos[1]) + 0.5)


## Back to following the active crew.
func follow() -> void:
	free_look = false


## Over the town map (not a fight, minigame or building scene), where dragging pans.
func _on_map() -> bool:
	return not city.is_empty() and not in_place() and not in_mini() and not in_fight()


## The point on the ground under a screen position.
func _ground_at(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return from
	return from + dir * (-from.y / dir.y)


func _unhandled_input(event: InputEvent) -> void:
	# Touch arrives as emulated mouse clicks (Godot default), so one branch handles both.
	# On the map, left or right button (or a finger) drags it around; a left click that didn't drag
	# is a tap, sent on release (walking is the d-pad and keys only; nothing walks on a click).
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and _on_map():
		if event.pressed:
			_press = {"button": event.button_index, "at": event.position, "last": event.position, "dragged": false}
		elif not _press.is_empty() and event.button_index == _press.button:
			var tap: bool = not _press.dragged and _press.button == MOUSE_BUTTON_LEFT
			_press = {}
			if tap:
				cell_tapped.emit(_cell_at(event.position))
		return
	if event is InputEventMouseMotion and not _press.is_empty():
		if not _press.dragged and event.position.distance_to(_press.at) > DRAG_START:
			_press.dragged = true
			free_look = true
		if _press.dragged:
			# Grab the ground: the point under the pointer stays under it.
			var moved: Vector3 = _ground_at(_press.last) - _ground_at(event.position)
			_cam_target = (_cam_target + Vector3(moved.x, 0, moved.z)).clamp(Vector3(0, 0, 0), Vector3(city.w, 0, city.h))
			_press.last = event.position
		return
	if event is InputEventMouseButton and event.pressed:
		if in_place() and place_view.casino and event.button_index == MOUSE_BUTTON_LEFT:
			var g: String = place_view.casino.pick(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
			if g != "":
				table_tapped.emit(g)
		elif in_place() or in_mini():
			pass
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom / 1.1, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_LEFT and in_fight():
			var from := camera.project_ray_origin(event.position)
			var dir := camera.project_ray_normal(event.position)
			if absf(dir.y) > 0.0001:
				var sq: Vector2i = fight_view.cell_at_world(from + dir * (-from.y / dir.y))
				if sq.x >= 0 and sq.y >= 0 and sq.x < Fight.W and sq.y < Fight.H:
					fight_square_tapped.emit(sq)
	elif event is InputEventMouseMotion and in_place() and place_view.casino:
		place_view.casino.hover(place_view.casino.pick(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position)))
	elif event is InputEventMagnifyGesture:
		zoom = clampf(zoom / event.factor, ZOOM_MIN, ZOOM_MAX)


## Screen point -> grid cell. Buildings are tested as boxes first so tapping a roof picks that building.
func _cell_at(screen_pos: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best := INF
	var cell := Vector2i(-1, -1)
	for b in city.buildings:
		var box := AABB(Vector3(int(b.x), 0, int(b.y)), Vector3(int(b.w), _heights.get(int(b.id), 1.0), int(b.h)))
		var hit = box.intersects_ray(from, dir)
		if hit != null and from.distance_to(hit) < best:
			best = from.distance_to(hit)
			cell = Vector2i(int(b.x), int(b.y))
	if cell.x >= 0 or absf(dir.y) < 0.0001:
		return cell
	var ground := from + dir * (-from.y / dir.y)
	return Vector2i(floori(ground.x), floori(ground.z))


# ------------------------------------------------------------------ building the world

func _build_world() -> void:
	var w: int = city.w
	var h: int = city.h
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(w + 80, h + 80)
	ground.mesh = plane
	ground.material_override = _flat(C_GRASS)
	ground.position = Vector3(w / 2.0, -0.01, h / 2.0)
	_world.add_child(ground)

	var batches := {}      # model path -> Array[Transform3D], drawn as one MultiMesh each
	_make_custom_meshes()
	var roads: PackedByteArray = city.roads
	var terrain: PackedByteArray = city.terrain
	for y in h:
		var run := 0   # open water and canals are drawn as one slab per row run
		for x in w + 1:
			var ch := "" if x == w else char(terrain[y * w + x])
			if ch == "w" or ch == "c":
				run += 1
				continue
			if run > 0:
				_add_water(Vector3(x - run / 2.0, 0.005, y + 0.5), Vector2(run, 1.0))
				run = 0
			if x == w:
				break
			match ch:
				"r":
					_add_road(batches, roads[y * w + x], x, y)
				"p":
					_batch(batches, "roads/tile-low", Transform3D(Basis(), Vector3(x + 0.5, 0, y + 0.5)))
				"o":
					_add_water(Vector3(x + 0.5, 0.01, y + 0.5), Vector2(0.8, 0.7), true)

	var rng := RandomNumberGenerator.new()
	rng.seed = w * 7919 + h
	for t in city.trees:
		var tp := Vector3(t[0] + 0.5 + rng.randf_range(-0.2, 0.2), 0, t[1] + 0.5 + rng.randf_range(-0.2, 0.2))
		_batch(batches, "suburban/tree-large" if rng.randf() < 0.6 else "suburban/tree-small",
			Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.1, 1.5)), tp))

	for d in city.decor:
		_add_decor(batches, d, rng)
	for b in city.buildings:
		_add_building(batches, b)
		_add_locals(b, rng)

	for path in batches:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _custom_meshes[path] if _custom_meshes.has(path) else _mesh_of(path)
		var xfs: Array = batches[path]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		_world.add_child(mmi)

	_cam_target = Vector3(w / 2.0, 0, h / 2.0)


## One road cell, drawn as the original piece: its code says which sides it opens to.
## The motorway is drawn as one two-lane road: asphalt edge to edge, a green median between the
## lanes, a kerb on the outside and arrows showing which way each lane runs.
func _add_road(batches: Dictionary, code: int, x: int, y: int) -> void:
	var c := Vector3(x + 0.5, 0, y + 0.5)
	if code >= CityGen.MOTORWAY:
		_batch(batches, "custom:asphalt", Transform3D(Basis(), c + Vector3(0, 0.01, 0)))
		if code == CityGen.JUNCTION:
			return
		var vertical := code >= 14
		var turn := Basis(Vector3.UP, PI / 2) if not vertical else Basis()
		# lanes 12 (upper) and 14 (left) carry the median on their inner side; every lane has its kerb outside
		var inner: Vector3 = {12: Vector3(0, 0, 0.5), 13: Vector3(0, 0, -0.5), 14: Vector3(0.5, 0, 0), 15: Vector3(-0.5, 0, 0)}[code]
		if code == 12 or code == 14:
			_batch(batches, "custom:median", Transform3D(turn, c + inner + Vector3(0, 0.03, 0)))
		_batch(batches, "custom:kerb", Transform3D(turn, c - inner * 0.92 + Vector3(0, 0.015, 0)))
		if (x + y) % 3 == 0:
			var yaw: float = {12: PI / 2, 13: -PI / 2, 14: PI, 15: 0.0}[code]   # west, east, south, north
			_batch(batches, "custom:arrow", Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI / 2), c + Vector3(0, 0.025, 0)))
		return
	var bits: int = CityGen.EXITS[code]
	var n := bits & CityGen.N != 0
	var e := bits & CityGen.E != 0
	var s := bits & CityGen.S != 0
	var wv := bits & CityGen.WEST != 0
	var count := int(n) + int(e) + int(s) + int(wv)
	var model := "roads/road-square"
	var angle := 0.0
	# Kenney tiles at rotation 0 (north = -Z at the top): straight runs E-W; bend joins W and S;
	# intersection (T) is closed on the N side; end is open to the E. +90 degrees turns N to W.
	match count:
		4:
			model = "roads/road-crossroad"
		3:
			model = "roads/road-intersection"
			angle = [0.0, -PI / 2, PI, PI / 2][[n, e, s, wv].find(false)]
		2:
			if e and wv:
				model = "roads/road-straight"
			elif n and s:
				model = "roads/road-straight"
				angle = PI / 2
			else:
				model = "roads/road-bend"
				if wv and s:
					angle = 0.0
				elif s and e:
					angle = PI / 2
				elif e and n:
					angle = PI
				else:
					angle = -PI / 2
		1:
			model = "roads/road-end"
			angle = [-PI / 2, 0.0, PI / 2, PI][[s, e, n, wv].find(true)]
	_batch(batches, model, Transform3D(Basis(Vector3.UP, angle), c))


## Meshes for the motorway pieces, made in code and drawn through the same batches as the models.
func _make_custom_meshes() -> void:
	var asphalt := BoxMesh.new()
	asphalt.size = Vector3(1.0, 0.02, 1.0)
	asphalt.material = _flat(C_ASPHALT)
	var median := BoxMesh.new()
	median.size = Vector3(0.16, 0.06, 1.0)
	median.material = _flat(C_MEDIAN)
	var kerb := BoxMesh.new()
	kerb.size = Vector3(0.08, 0.03, 1.0)
	kerb.material = _flat(C_KERB)
	var arrow := PrismMesh.new()
	arrow.size = Vector3(0.28, 0.38, 0.01)
	arrow.material = _flat(Color(1, 1, 1, 1))
	_custom_meshes = {"custom:asphalt": asphalt, "custom:median": median, "custom:kerb": kerb, "custom:arrow": arrow}


func _add_building(batches: Dictionary, b: Dictionary) -> void:
	var t: String = b.type
	var bx := float(int(b.x))
	var by := float(int(b.y))
	var center := Vector3(bx + 1, 0, by + 1)
	var top := 1.0
	if b.has("cells"):
		# The airport: the terminal on the top row of its lot, the apron paved around the access road.
		center = Vector3(bx + int(b.w) / 2.0, 0, by + 1)
		for c in b.cells:
			_batch(batches, "roads/tile-low", Transform3D(Basis(), Vector3(int(c[0]) + 0.5, 0, int(c[1]) + 0.5)))
	elif not t in GREEN_LOTS:
		_pave(batches, int(b.x), int(b.y))
	match t:
		"subway":
			top = _place("commercial/detail-overhang-wide", center + Vector3(0, 0.02, 0.3), 1.4, 0.0)
			_batch(batches, "suburban/planter", Transform3D(Basis().scaled(Vector3.ONE * 1.6), center + Vector3(-0.6, 0.02, -0.5)))
			_batch(batches, "suburban/planter", Transform3D(Basis().scaled(Vector3.ONE * 1.6), center + Vector3(0.6, 0.02, -0.5)))
			top = maxf(top, 0.9)
		"playground":
			_place("commercial/detail-parasol-a", center + Vector3(-0.4, 0, 0.3), 0.6, 0.0)
			_place("commercial/detail-parasol-b", center + Vector3(0.45, 0, 0.35), 0.6, 0.0)
			_batch(batches, "suburban/planter", Transform3D(Basis().scaled(Vector3.ONE * 1.5), center + Vector3(0.3, 0, -0.5)))
			_batch(batches, "suburban/tree-large", Transform3D(Basis().scaled(Vector3.ONE * 1.4), center + Vector3(-0.6, 0, -0.6)))
			top = 0.8
		"harbor":
			_add_water(Vector3(bx + 1, 0.005, by + 1.55), Vector2(2.0, 0.9))
			var cols := ["a", "b", "c"]
			for i in 4:
				var p := center + Vector3(-0.6 + i * 0.38, 0.02, -0.35)
				_place("industrial/shipping-container-" + cols[(i + int(b.id)) % 3], p, 0.8, 0.0, true)
			_place("industrial/shipping-container-a", center + Vector3(-0.41, 0.36, -0.35), 0.8, 0.0, true)
			top = 1.0
		"villa":
			var looks: Array = LOOKS[t]
			top = _place(looks[int(b.id) % looks.size()], center + Vector3(-0.2, 0, -0.25), 1.35, 0.0)
			_add_water(center + Vector3(0.6, 0.01, 0.6), Vector2(0.7, 0.7), true)
			_batch(batches, "suburban/tree-large", Transform3D(Basis().scaled(Vector3.ONE * 1.3), center + Vector3(-0.75, 0, 0.7)))
		_:
			var looks2: Array = LOOKS[t]
			top = _place(looks2[int(b.id) % looks2.size()], center, 1.85, 0.0)
	_heights[int(b.id)] = top

	var info: Dictionary = Balance.BUILDINGS[t]
	if info.sign != "":
		var sign := _label(info.sign, 64, C_SIGN)
		sign.position = center + Vector3(0, top + 0.35, 0)
		_world.add_child(sign)
	var name_l := _label(b.name, 40, Color(1, 1, 1, 0.92))
	name_l.position = Vector3(bx + 1, 0.25, by + 2.05)
	_world.add_child(name_l)


## Townsfolk by a building's front corner: an officer at Police HQ, and a passer-by at about a third of the rest.
func _add_locals(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var front := Vector3(int(b.x) + 1.75, 0.02, int(b.y) + 1.8)
	if b.type == "police":
		_add_extra(COP, front, 0.0, "idle")
		_add_extra(COP, front - Vector3(1.5, 0, 0), 0.4, "idle")
	elif not b.type in GREEN_LOTS and rng.randf() < 0.35:
		_add_extra(CREW_LOOKS[rng.randi() % CREW_LOOKS.size()], front, rng.randf_range(-0.8, 0.8), "idle")


func _add_decor(batches: Dictionary, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var x := int(d.x)
	var y := int(d.y)
	var center := Vector3(x + 1, 0, y + 1)
	match d.kind:
		"houses":
			for i in 4:
				var p := Vector3(x + 0.5 + (i % 2), 0, y + 0.5 + (i / 2))
				var turn := 0.0 if i / 2 == 1 else PI
				_place(HOUSES[(x * 3 + y + i) % HOUSES.size()], p, 0.95, turn)
		"park":
			for i in 5:
				var tp := center + Vector3(rng.randf_range(-0.75, 0.75), 0, rng.randf_range(-0.75, 0.75))
				_batch(batches, "suburban/tree-large", Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(1.2, 1.7)), tp))
			_batch(batches, "suburban/planter", Transform3D(Basis().scaled(Vector3.ONE * 1.5), center))
		"parking":
			for i in 4:
				_batch(batches, "roads/road-square", Transform3D(Basis(), Vector3(x + 0.5 + (i % 2), 0.002, y + 0.5 + (i / 2))))
			_batch(batches, "roads/dumpster", Transform3D(Basis().scaled(Vector3.ONE * 1.5), center + Vector3(0.7, 0.02, -0.7)))
		"pond":
			_add_water(center + Vector3(0, 0.01, 0), Vector2(1.3, 1.3), true)
			_batch(batches, "suburban/tree-small", Transform3D(Basis().scaled(Vector3.ONE * 1.4), center + Vector3(0.75, 0, -0.7)))
		_:
			_pave(batches, x, y)
			_place(OFFICES[(x * 5 + y) % OFFICES.size()], center, 1.8, 0.0)


func _pave(batches: Dictionary, x: int, y: int) -> void:
	for i in 4:
		_batch(batches, "roads/tile-low", Transform3D(Basis(), Vector3(x + 0.5 + (i % 2), 0, y + 0.5 + (i / 2))))


## Instances a model, scaled so its footprint fits `fit` units and centered on `pos`. Returns its top height.
func _place(path: String, pos: Vector3, fit: float, turn: float, keep_scale := false) -> float:
	var node: Node3D = load(MODELS + path + ".glb").instantiate()
	var bb := _aabb_of(path)
	var k := fit if keep_scale else minf(fit / maxf(bb.size.x, bb.size.z), MAX_HEIGHT / bb.size.y)
	var mid := bb.get_center() * k
	node.basis = Basis(Vector3.UP, turn).scaled(Vector3.ONE * k)
	node.position = pos - Basis(Vector3.UP, turn) * Vector3(mid.x, 0, mid.z)
	_world.add_child(node)
	return bb.end.y * k


## A flat patch of water: a rectangle, or an oval when `round` is set.
func _add_water(pos: Vector3, size: Vector2, round := false) -> void:
	var m := MeshInstance3D.new()
	if round:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.02
		m.mesh = disc
		m.scale = Vector3(size.x, 1, size.y)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(size.x, 0.02, size.y)
		m.mesh = box
	var mat := _flat(C_WATER)
	mat.roughness = 0.15
	m.material_override = mat
	m.position = pos
	_world.add_child(m)


func _batch(batches: Dictionary, path: String, xf: Transform3D) -> void:
	if not batches.has(path):
		batches[path] = []
	batches[path].append(xf)


func _mesh_of(path: String) -> Mesh:
	var node: Node = load(MODELS + path + ".glb").instantiate()
	var mi: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: Mesh = mi.mesh
	node.free()
	return mesh


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


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _label(text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 14
	l.modulate = col
	l.outline_modulate = Color(0.08, 0.09, 0.11, 0.9)
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	return l


# ------------------------------------------------------------------ tokens and markers

func _update_token(pid, p: Dictionary, pos: Vector3, prev: Vector3) -> void:
	if _tokens.has(pid) and _tokens[pid].look != UiTheme.look_of(p):
		_tokens[pid].node.queue_free()   # they picked a different character
		_tokens.erase(pid)
	if not _tokens.has(pid):
		_tokens[pid] = _make_token(UiTheme.look_of(p), Color(p.color), p.name)
	var tk: Dictionary = _tokens[pid]
	var node: Node3D = tk.node
	node.visible = int(p.jail) <= 0 and int(p.holiday) <= 0
	node.position = pos
	# In a wheelchair the car only goes out if someone in the crew can drive it.
	var chair: bool = p.get("chair", false)
	var has_car: bool = int(p.car) > 0 and (not chair or p.crew.size() >= 2)
	var moving := (pos - prev).length() > 0.002
	if chair and not has_car and tk.get("chair") == null:
		var wc: Node3D = load(MODELS + "characters/wheelchair.glb").instantiate()
		wc.scale = Vector3.ONE * 0.9
		node.add_child(wc)
		tk.chair = wc
	if tk.get("chair") != null:
		tk.chair.visible = chair and not has_car
	if has_car and int(tk.car_ci) != int(p.car):
		# The same model as on the dealer's lot, with the boss riding up through the sunroof.
		if tk.car:
			tk.car.queue_free()
		tk.car = CarModels.car(int(p.car), TOKEN_CAR_LEN)
		node.add_child(tk.car)
		tk.car_ci = int(p.car)
		tk.roof = CarModels.aabb(tk.car.get_child(0)).size.y * tk.car.get_child(0).scale.y
	if tk.car:
		tk.car.visible = has_car
	var person: Node3D = tk.person
	person.position.y = float(tk.roof) - 0.3 if has_car else 0.0
	person.scale = Vector3.ONE * (0.6 if has_car else 0.9)
	if has_car:
		_play(tk.anim, "drive")
	elif chair:
		_play(tk.anim, "wheelchair-move-forward" if moving else "wheelchair-sit")
	else:
		_play(tk.anim, "walk" if moving else "idle")
	if moving:
		node.rotation.y = atan2(pos.x - prev.x, pos.z - prev.z)
	tk.label.text = p.name


## A player's token: their character on a disc of the player's color, plus their car once they
## own one.
func _make_token(look: String, col: Color, label: String) -> Dictionary:
	var node := Node3D.new()
	add_child(node)

	var base := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.26
	disc.bottom_radius = 0.26
	disc.height = 0.02
	base.mesh = disc
	base.material_override = _flat(col)
	base.position.y = 0.02
	node.add_child(base)

	var person: Node3D = load(MODELS + "characters/" + look + ".glb").instantiate()
	node.add_child(person)

	var l := _label(label, 44, Color.WHITE)
	l.position.y = 1.0
	node.add_child(l)
	# The car (see CarModels) is added once they own one.
	return {"node": node, "person": person, "anim": _anim_player(person), "car": null, "car_ci": 0, "roof": 0.0,
		"chair": null, "label": l, "look": look}


## Places an extra (non-player) character in the city, looping one animation.
func _add_extra(model: String, pos: Vector3, turn: float, anim: String) -> void:
	var person: Node3D = load(MODELS + "characters/" + model + ".glb").instantiate()
	person.position = pos
	person.rotation.y = turn
	person.scale = Vector3.ONE * 0.9
	_world.add_child(person)
	var ap := _anim_player(person)
	_play(ap, anim)
	ap.seek(randf() * ap.current_animation_length)


func _anim_player(model: Node) -> AnimationPlayer:
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["idle", "walk", "drive", "wheelchair-sit", "wheelchair-move-forward"]:
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	return ap


func _play(ap: AnimationPlayer, anim: String) -> void:
	if ap.current_animation != anim:
		ap.play(anim, 0.15)


## Two officers and a squad car with flashing lights, pulled up next to whoever they've stopped.
func _make_police_stop() -> Node3D:
	var root := Node3D.new()
	root.visible = false
	var car := CarModels.model("police", TOKEN_CAR_LEN)
	var roof: float = CarModels.aabb(car.get_child(0)).size.y * car.get_child(0).scale.y
	for i in 2:
		var light := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		lbox.size = Vector3(0.14, 0.06, 0.08)
		light.mesh = lbox
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		light.material_override = mat
		light.position = Vector3(-0.08 + 0.16 * i, roof + 0.02, -0.04)
		car.add_child(light)
		_police_lights.append(mat)
	car.position = Vector3(0.75, 0, -0.1)
	root.add_child(car)
	for i in 2:
		var cop: Node3D = load(MODELS + "characters/" + COP + ".glb").instantiate()
		cop.scale = Vector3.ONE * 0.9
		cop.position = Vector3(0.45, 0, 0.45 - 0.9 * i)
		cop.rotation.y = -PI / 2
		root.add_child(cop)
		_play(_anim_player(cop), "idle")
	return root


func _update_police(active: Dictionary) -> void:
	var stopped: bool = Net.state.pending.get("kind", "") == "police" and not active.is_empty()
	_police.visible = stopped
	if not stopped:
		return
	_police.position = _display_pos.get(active.id, Vector3.ZERO)
	var red := int(_t * 6.0) % 2 == 0
	for i in _police_lights.size():
		var on: bool = (i == 0) == red
		var mat: StandardMaterial3D = _police_lights[i]
		var col := Color("#FF3B3B") if i == 0 else Color("#3B7BFF")
		mat.albedo_color = col if on else col.darkened(0.7)
		mat.emission = col if on else Color.BLACK
		mat.emission_energy_multiplier = 2.5 if on else 0.0


func _update_ransom() -> void:
	# Your ransom drop point, visible to the kidnapper only.
	var me := Net.my_player()
	if me.is_empty() or me.ransom.is_empty():
		_ransom.visible = false
		return
	var b: Dictionary = city.buildings[int(me.ransom.building)]
	_ransom.visible = true
	_ransom.position = Vector3(int(b.x) + 1, 0.05, int(b.y) + 1)
	var s := 1.0 + 0.06 * sin(_t * 4.0)
	_ransom.get_child(0).scale = Vector3(s, 1, s)
