extends Node3D
## The fight arena: a stretch of street off to the side of the city where Net.state.fight is played out.
## Replays the fight's events in order (steps, shots, blows, men going down) so everyone sees the
## same fight, then shows the acting player where they can step (teal) and what they can hit (red).
## Arena square (x, y) is at local (x + 0.5, 0, y + 0.5).

signal square_tapped(cell: Vector2i)

const MODELS := "res://assets/models/"
const STEP_TIME := 0.22
const SHOT_TIME := 0.5
# Fighters' looks by role. Crew looks match their city tokens (see city_view.gd CREW_LOOKS).
const ROLE_LOOKS := {"cop": "character-male-c", "guard": "character-male-d", "thug": "character-male-a",
	"civilian": "character-female-d"}
const C_MOVE := Color(0.21, 0.82, 0.73, 0.55)
const C_HIT := Color("#FF5D4F")
const C_CUR := Color("#F2EEE6")

var crew_looks: Array = []      # set by city_view
var _fight_id := -1
var _seen := 0                  # last event number already played
var _queue: Array = []          # events waiting to be played
var _timer := 0.0
var _behind_since := -1         # msec since the shown fight has lagged the server's
var _units := {}                # unit id -> {node, anim, label, pos: Vector2i, hp: int, max: int, name, side}
var _marks: Node3D
var _shot: MeshInstance3D
var _shot_from := Vector3.ZERO
var _shot_to := Vector3.ZERO
var _shot_t := -1.0


func _ready() -> void:
	_build_street()
	_marks = Node3D.new()
	add_child(_marks)
	_shot = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.06
	sph.height = 0.12
	_shot.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#FFE27A")
	mat.emission_enabled = true
	mat.emission = Color("#FFC94A")
	_shot.material_override = mat
	_shot.visible = false
	add_child(_shot)


## True while moves are still being replayed; the HUD holds input until they finish.
func busy() -> bool:
	if not _queue.is_empty() or _timer > 0.0:
		return true
	# Moves the server has sent that haven't been queued yet (the HUD can hear about them first).
	var f: Dictionary = Net.state.get("fight", {})
	var behind: bool = not f.is_empty() and (int(f.get("id", -1)) != _fight_id or int(f.seq) > _seen)
	if not behind:
		_behind_since = -1
	elif _behind_since < 0:
		_behind_since = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - _behind_since > 1000:
		# The city view should have passed this state on by now; catch up rather than hold the
		# player's buttons (and the fight's result card) forever.
		_behind_since = -1
		show_fight(f)
		return not _queue.is_empty() or _timer > 0.0
	return behind


## The energy a fighter shows right now (lags the true state while moves replay).
func shown_hp(id: int, fallback: int) -> int:
	var u: Dictionary = _units.get(id, {})
	return fallback if u.is_empty() else int(u.hp)


func showing() -> bool:
	return _fight_id >= 0


func center() -> Vector3:
	return global_position + Vector3(Fight.W / 2.0, 0, Fight.H / 2.0)


func cell_at_world(p: Vector3) -> Vector2i:
	var local := p - global_position
	return Vector2i(floori(local.x), floori(local.z))


func show_fight(f: Dictionary) -> void:
	if int(f.get("id", -1)) != _fight_id:
		_start(f)
	for ev in f.events:
		if int(ev.n) > _seen:
			_queue.append(ev)
			_seen = int(ev.n)
	if not busy():
		_sync(f)
	_mark(f)


func clear() -> void:
	_fight_id = -1
	for u in _units.values():
		u.node.queue_free()
	_units.clear()
	_queue.clear()
	_clear_marks()


func _process(delta: float) -> void:
	if _shot_t >= 0.0:
		_shot_t += delta / SHOT_TIME * 1.6
		_shot.position = _shot_from.lerp(_shot_to, minf(1.0, _shot_t))
		if _shot_t >= 1.0:
			_shot_t = -1.0
			_shot.visible = false
	for u in _units.values():
		var target := _world(u.pos)
		u.node.position = u.node.position.lerp(target, minf(1.0, delta * 14.0))
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0 and _queue.is_empty():
			# Everything replayed: snap to the true state and show the next choices.
			var f: Dictionary = Net.state.get("fight", {})
			if _fight_id >= 0 and int(f.get("id", -1)) == _fight_id:
				_sync(f)
				_mark(f)
		return
	if not _queue.is_empty():
		_play_event(_queue.pop_front())
		_timer = maxf(_timer, 0.01)


# ------------------------------------------------------------------ fighters

func _start(f: Dictionary) -> void:
	clear()
	_fight_id = int(f.get("id", -1))
	_seen = 0
	for ev in f.events:
		_seen = maxi(_seen, int(ev.n))
	for u in f.units:
		var look := _look(u)
		var node: Node3D = load(MODELS + "characters/" + look + ".glb").instantiate()
		node.scale = Vector3.ONE * 0.9
		node.rotation.y = PI / 2 if int(u.side) == 0 else -PI / 2
		add_child(node)
		var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
		for a in ["idle", "holding-right", "holding-both"]:
			ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		var lab := Label3D.new()
		lab.font_size = 34
		lab.outline_size = 10
		lab.pixel_size = 0.004
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.outline_modulate = Color(0.08, 0.09, 0.11, 0.9)
		lab.position.y = 1.05
		node.add_child(lab)
		var pos := Vector2i(int(u.x), int(u.y))
		node.position = _world(pos)
		_units[int(u.id)] = {"node": node, "anim": ap, "label": lab, "pos": pos, "hp": int(u.hp), "max": int(u.max),
			"name": str(u.name), "side": int(u.side), "gear": int(u.gear)}
		_stance(_units[int(u.id)])
		_relabel(_units[int(u.id)], false)


func _look(u: Dictionary) -> String:
	if str(u.look) == "crew" and int(u.ci) == 0 and Net.state.get("players", {}).has(int(u.owner)):
		return UiTheme.look_of(Net.state.players[int(u.owner)])   # the boss is the character they picked
	if str(u.look) == "crew" and crew_looks.size() > 0:
		return crew_looks[(int(u.owner) + int(u.ci)) % crew_looks.size()]
	return ROLE_LOOKS.get(str(u.look), "character-male-b")


func _stance(u: Dictionary) -> void:
	if int(u.hp) <= 0 or not is_instance_valid(u.node):
		return
	var ranged: bool = int(Balance.GEAR[int(u.gear)].reach) > 1
	_play(u.anim, "holding-right" if ranged else "idle")


func _relabel(u: Dictionary, current: bool) -> void:
	var lab: Label3D = u.label
	lab.visible = int(u.hp) > 0
	lab.text = "%s  %d" % [u.name, u.hp]
	var col: Color = Color("#7FE6D6") if int(u.side) == 0 else Color("#FF9C90")
	if current:
		col = Color("#F2C230")
	lab.modulate = col


func _sync(f: Dictionary) -> void:
	for su in f.units:
		var u: Dictionary = _units.get(int(su.id), {})
		if u.is_empty():
			continue
		u.pos = Vector2i(int(su.x), int(su.y))
		var was_up: bool = int(u.hp) > 0
		u.hp = int(su.hp)
		if was_up and int(u.hp) <= 0:
			_play(u.anim, "die")
		_relabel(u, int(su.id) == int(f.cur) and int(f.side) == 0 and not f.over)


# ------------------------------------------------------------------ replaying events

func _play_event(ev: Dictionary) -> void:
	var u: Dictionary = _units.get(int(ev.get("a", -1)), {})
	match str(ev.k):
		"move":
			if u.is_empty():
				return
			var to := Vector2i(int(ev.to[0]), int(ev.to[1]))
			var d: Vector2i = to - u.pos
			u.node.rotation.y = atan2(d.x, d.y)
			u.pos = to
			_play(u.anim, "walk")
			_timer = STEP_TIME
			get_tree().create_timer(STEP_TIME).timeout.connect(func(): _stance(u))
		"attack":
			if u.is_empty():
				return
			var to2 := Vector2i(int(ev.to[0]), int(ev.to[1]))
			var d2: Vector2i = to2 - u.pos
			u.node.rotation.y = atan2(d2.x, d2.y)
			var melee: bool = ev.get("melee", false)
			_play(u.anim, "attack-melee-right" if melee else "holding-right-shoot", true)
			if not melee:
				_shot_from = _world(u.pos) + Vector3(0, 0.45, 0)
				_shot_to = _world(to2) + Vector3(0, 0.45, 0)
				_shot_t = 0.0
				_shot.visible = true
			_timer = SHOT_TIME
			var t: Dictionary = _units.get(int(ev.get("t", -1)), {})
			var dmg := int(ev.get("dmg", 0))
			get_tree().create_timer(SHOT_TIME * 0.6).timeout.connect(func():
				if not is_instance_valid(u.node):
					return
				if t.is_empty():
					_float_text(_world(to2), "miss", Color("#B5B9C2"))
					return
				if dmg > 0:
					t.hp = maxi(0, int(t.hp) - dmg)
					_float_text(t.node.position, "-%d" % dmg, C_HIT)
					if bool(ev.get("down", false)):
						_play(t.anim, "die", true)
						_float_text(t.node.position + Vector3(0, 0.3, 0), "DOWN", Color("#F2C230"))
					_relabel(t, false)
				else:
					_float_text(t.node.position, "miss", Color("#B5B9C2")))
			get_tree().create_timer(SHOT_TIME).timeout.connect(func(): _stance(u))
		"wait":
			_timer = 0.12
		"backup":
			_float_text(center() - global_position, "BACKUP ARRIVES", Color("#FF9C90"))
			_timer = 0.8


func _float_text(at: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.outline_size = 12
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_modulate = Color(0.08, 0.09, 0.11, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = at + Vector3(0, 1.2, 0)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y + 0.6, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ choice markers

func _clear_marks() -> void:
	for c in _marks.get_children():
		c.queue_free()


func _mark(f: Dictionary) -> void:
	_clear_marks()
	if busy() or f.over or int(f.side) != 0 or int(f.cur) < 0:
		return
	var cur: Dictionary = _units.get(int(f.cur), {})
	if not cur.is_empty():
		_ring_at(cur.pos, C_CUR, 0.36, 0.44)
		_relabel(cur, true)
	if not Net.is_my_turn():
		return
	var opts := Fight.options(f)
	for c in opts.move:
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.86, 0.02, 0.86)
		plate.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = C_MOVE
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		plate.material_override = mat
		plate.position = _world(c) + Vector3(0, 0.03, 0)
		_marks.add_child(plate)
	for c2 in opts.attack:
		_ring_at(c2, C_HIT, 0.32, 0.42)


func _ring_at(c: Vector2i, col: Color, inner: float, outer: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position = _world(c) + Vector3(0, 0.04, 0)
	_marks.add_child(ring)


# ------------------------------------------------------------------ the street

func _build_street() -> void:
	# Pavement on the outer rows, asphalt in the middle, a faint grid so the squares read, shopfronts behind.
	for y in Fight.H:
		if y < 2 or y > Fight.H - 3:
			for x in Fight.W:
				var tile: Node3D = load(MODELS + "roads/tile-low.glb").instantiate()
				tile.position = _world(Vector2i(x, y))
				add_child(tile)
	var asphalt := MeshInstance3D.new()
	var abox := BoxMesh.new()
	abox.size = Vector3(Fight.W, 0.02, Fight.H - 4)
	asphalt.mesh = abox
	asphalt.material_override = _mat(Color("#5D6170"))
	asphalt.position = Vector3(Fight.W / 2.0, 0.0, Fight.H / 2.0)
	add_child(asphalt)
	var line_mat := _mat(Color(0.1, 0.11, 0.14, 0.35))
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for x in Fight.W + 1:
		_grid_line(Vector3(x, 0.025, Fight.H / 2.0), Vector3(0.025, 0.002, Fight.H), line_mat)
	for y in Fight.H + 1:
		_grid_line(Vector3(Fight.W / 2.0, 0.025, y), Vector3(Fight.W, 0.002, 0.025), line_mat)
	var fronts := ["commercial/building-a", "commercial/building-c", "commercial/building-f", "commercial/building-d",
		"commercial/building-g", "commercial/building-b"]
	for i in fronts.size():
		var b: Node3D = load(MODELS + fronts[i] + ".glb").instantiate()
		b.scale = Vector3.ONE * 2.0
		b.position = Vector3(1.0 + i * 2.0, 0, -1.1)
		add_child(b)
	var bin: Node3D = load(MODELS + "roads/dumpster.glb").instantiate()
	bin.scale = Vector3.ONE * 1.6
	bin.position = Vector3(Fight.W + 0.6, 0, 1.0)
	add_child(bin)


func _grid_line(at: Vector3, size: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	m.position = at
	add_child(m)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _world(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0, c.y + 0.5)


func _play(ap: AnimationPlayer, anim: String, restart := false) -> void:
	if restart or ap.current_animation != anim:
		ap.play(anim, 0.1)
		if restart:
			ap.seek(0.0, true)
