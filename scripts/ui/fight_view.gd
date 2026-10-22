extends Node3D
## The fight arena: a stretch of street off to the side of the city where Net.state.fight is played out.
## Replays the fight's events in order (steps, shots, blows, men going down) so everyone sees the
## same fight, then shows the acting player where they can step (teal) and what they can hit (red).
## Arena square (x, y) is at local (x + 0.5, 0, y + 0.5).

signal square_tapped(cell: Vector2i)

const MODELS := "res://assets/models/"
const STEP_TIME := 0.22
const SHOT_TIME := 0.5
# Gear indexes (Balance.GEAR) that get special handling.
const CLUB := 1
const BATON := 2
const SWITCHBLADE := 3
const THROWING_KNIFE := 4
const GRENADE := 8
# Where the right fist is in the "holding-right" pose, in the character's skeleton space
# (+Z forward). Weapons are attached here and follow the arm bone from then on.
const FIST := Vector3(-0.1, 0.27, 0.21)
# Fighters' looks by role. Crew looks match their city tokens (see city_view.gd CREW_LOOKS).
const ROLE_LOOKS := {"cop": "character-male-c", "guard": "character-male-d", "thug": "character-male-a",
	"civilian": "character-female-d", "eddie": "character-male-f"}
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
var _fx: Node3D               # flashes, shells, blood and scorch marks of the current fight
var _shake := 0.0              # camera shake strength, read by city_view through shake_offset()


func _ready() -> void:
	_build_street()
	_marks = Node3D.new()
	add_child(_marks)
	_fx = Node3D.new()
	add_child(_fx)


## Added to the camera position while a grenade goes off.
func shake_offset() -> Vector3:
	if _shake <= 0.001:
		return Vector3.ZERO
	return Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * _shake


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
	_shake = 0.0
	for c in _fx.get_children():
		c.queue_free()
	_clear_marks()


func _process(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 0.9)
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
			"name": str(u.name), "side": int(u.side), "gear": int(u.gear), "weapon": _arm(node, ap, int(u.gear))}
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
	var g := int(u.gear)
	_play(u.anim, "holding-right" if g > 0 else "idle")   # weapon out where you can see it


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
			_attack(u, ev)
		"wait":
			_timer = 0.12
		"backup":
			_float_text(center() - global_position, "BACKUP ARRIVES", Color("#FF9C90"))
			_timer = 0.8
		"legs":
			_break_legs(_units.get(int(ev.get("victim", -1)), {}))


# ------------------------------------------------------------------ weapons

## Put the fighter's weapon in their right hand. The grip goes where the fist is in the
## "holding-right" pose and then rides the arm bone through every animation.
func _arm(node: Node3D, ap: AnimationPlayer, g: int) -> Node3D:
	var w := WeaponModels.build(g)
	if w == null:
		return null
	var found := node.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		w.queue_free()
		return null
	var sk: Skeleton3D = found[0]
	var bi := sk.find_bone("arm-right")
	if bi < 0:
		w.queue_free()
		return null
	ap.play("holding-right")
	ap.advance(0.0)
	var pose := sk.get_bone_global_pose(bi)
	var ba := BoneAttachment3D.new()
	ba.bone_name = "arm-right"
	sk.add_child(ba)
	ba.add_child(w)
	w.transform = pose.affine_inverse() * Transform3D(Basis(), FIST)
	return w


## Play out one attack with the attacker's weapon: the animation, flash, tracer, shell, thrown
## knife or grenade, the sound, and then the hit (or miss) on the target.
func _attack(u: Dictionary, ev: Dictionary) -> void:
	var to2 := Vector2i(int(ev.to[0]), int(ev.to[1]))
	var d2: Vector2i = to2 - u.pos
	u.node.rotation.y = atan2(d2.x, d2.y)
	var g := int(u.gear)
	var t: Dictionary = _units.get(int(ev.get("t", -1)), {})
	var dmg := int(ev.get("dmg", 0))
	var hit: bool = not t.is_empty() and dmg > 0
	var chest := _world(u.pos) + Vector3(0, 0.38, 0)
	var aim := _world(to2) + Vector3(0, 0.34, 0)
	if not hit:   # a miss goes wide and ends on the street beside the target
		var side := Vector3(-(aim - chest).z, 0, (aim - chest).x).normalized()
		aim = _world(to2) + side * randf_range(0.3, 0.5) * (1.0 if randf() < 0.5 else -1.0) + Vector3(0, 0.02, 0)
	var dir := (aim - chest).normalized()
	var land := 0.28
	var total := SHOT_TIME
	if WeaponModels.is_gun(g):
		_play(u.anim, "holding-right-shoot", true)
		var rounds := 6 if g == 7 else 1
		var gap := 0.085
		var size: float = [1.0, 1.5, 1.15][g - 5]
		Sfx.play(["pistol", "rifle", "machine_gun"][g - 5], 0.0, 0.05, 0.08)
		for i in rounds:
			var spray := Vector3.ZERO if i == 0 else Vector3(randf_range(-0.12, 0.12), randf_range(-0.05, 0.05), randf_range(-0.12, 0.12))
			get_tree().create_timer(0.08 + gap * i).timeout.connect(_fire_round.bind(u, g, aim + spray, size, hit and i < 3 + int(dmg > 6)))
		var fly := chest.distance_to(aim) / 45.0
		land = 0.08 + gap * (rounds - 1) + fly
		total = maxf(SHOT_TIME, land + 0.25)
		if g == 6:
			Sfx.play("gun_cock", -6.0, 0.03, 0.55)   # work the bolt
			total = maxf(total, 0.8)
	elif g == THROWING_KNIFE:
		_play(u.anim, "attack-melee-right", true)
		Sfx.play("knife_throw", 0.0, 0.06, 0.12)
		var flight := clampf(chest.distance_to(aim) / 9.0, 0.12, 0.45)
		get_tree().create_timer(0.16).timeout.connect(_throw_knife.bind(u, aim, flight, hit))
		land = 0.16 + flight
		total = land + 0.25
	elif g == GRENADE:
		Sfx.play("grenade_pin", 0.0, 0.03)
		get_tree().create_timer(0.22).timeout.connect(func(): _play(u.anim, "attack-melee-right", true))
		var ground := Vector3(aim.x, 0.04, aim.z) if hit else Vector3(_world(to2).x, 0.04, _world(to2).z) + (aim - _world(to2)) * 0.4
		get_tree().create_timer(0.38).timeout.connect(_lob_grenade.bind(u, ground))
		land = 0.38 + 0.55 + 0.35
		get_tree().create_timer(land).timeout.connect(func():
			Sfx.play("explosion", 2.0, 0.04)
			WeaponFx.explosion(_fx, ground, 1.0)
			_shake = 0.22)
		total = land + 0.6
	else:
		_play(u.anim, "attack-melee-right", true)
		Sfx.play("swing_heavy" if g in [CLUB, BATON] else "swing_light", -2.0, 0.08, 0.04)
		get_tree().create_timer(0.1).timeout.connect(func():
			if is_instance_valid(u.node):
				WeaponFx.swing_trail(_fx, chest, dir, 0.5 if g in [CLUB, BATON] else 0.38,
					Color(0.85, 0.9, 1.0, 0.5) if g == SWITCHBLADE else Color(1, 1, 1, 0.4)))
		land = 0.26
	_timer = total
	get_tree().create_timer(land).timeout.connect(_land.bind(u, t, ev, to2, dmg, g, dir, aim))
	get_tree().create_timer(total).timeout.connect(func(): _stance(u))


func _fire_round(u: Dictionary, g: int, aim: Vector3, size: float, bloody: bool) -> void:
	if not is_instance_valid(u.node):
		return
	var muzzle := _muzzle(u)
	var dir := (aim - muzzle).normalized()
	WeaponFx.muzzle_flash(_fx, muzzle, dir, size)
	WeaponFx.eject_shell(_fx, muzzle - dir * 0.12, dir, g != 5)
	var fly := WeaponFx.tracer(_fx, muzzle, aim)
	get_tree().create_timer(fly).timeout.connect(func():
		if bloody:
			WeaponFx.blood(_fx, aim, dir, 0.6 if g == 7 else 1.0)
		else:
			var spot := Vector3(aim.x, 0.02, aim.z) if aim.y > 0.1 else aim
			WeaponFx.ricochet(_fx, spot, dir))


func _muzzle(u: Dictionary) -> Vector3:
	var w: Node3D = u.get("weapon")
	if w != null and is_instance_valid(w) and w.is_inside_tree():
		return to_local(w.global_transform * WeaponModels.muzzle(int(u.gear)))
	return u.node.position + Vector3(0, 0.36, 0) + Vector3(sin(u.node.rotation.y), 0, cos(u.node.rotation.y)) * 0.3


func _throw_knife(u: Dictionary, aim: Vector3, flight: float, hit: bool) -> void:
	if not is_instance_valid(u.node):
		return
	var k := WeaponModels.build(THROWING_KNIFE)
	_fx.add_child(k)
	var from := _muzzle(u)
	k.position = from
	var dir := (aim - from).normalized()
	k.rotation.y = atan2(dir.x, dir.z)
	var stick := aim if hit else Vector3(aim.x, 0.05, aim.z)
	var tw := k.create_tween()
	tw.tween_method(func(f: float):
		k.position = from.lerp(stick, f) + Vector3(0, sin(f * PI) * 0.12, 0)
		k.rotation.x = f * TAU * 3.0, 0.0, 1.0, flight)
	if hit:
		tw.tween_callback(k.queue_free)
	else:
		tw.tween_callback(func(): k.rotation.x = deg_to_rad(110))   # stuck in the street
		tw.tween_interval(4.0)
		tw.tween_property(k, "scale", Vector3.ZERO, 0.3)
		tw.tween_callback(k.queue_free)


func _lob_grenade(u: Dictionary, ground: Vector3) -> void:
	if not is_instance_valid(u.node):
		return
	var held: Node3D = u.get("weapon")
	if held != null and is_instance_valid(held):
		held.visible = false
		get_tree().create_timer(1.4).timeout.connect(func():
			if is_instance_valid(held):
				held.visible = true)
	var gr := WeaponModels.build(GRENADE)
	_fx.add_child(gr)
	var from := _muzzle(u)
	gr.position = from
	var peak := from.lerp(ground, 0.5) + Vector3(0, 1.0 + from.distance_to(ground) * 0.12, 0)
	var roll := ground + (ground - from).normalized() * 0.18
	roll.y = ground.y
	var tw := gr.create_tween()
	tw.tween_method(func(f: float):
		gr.position = from.lerp(peak, f).lerp(peak.lerp(ground, f), f)
		gr.rotation = Vector3(f * 9.0, f * 3.0, 0), 0.0, 1.0, 0.55)
	tw.tween_callback(func(): Sfx.play("grenade_bounce", -2.0, 0.05))
	tw.tween_property(gr, "position", ground.lerp(roll, 0.6) + Vector3(0, 0.08, 0), 0.12)
	tw.tween_property(gr, "position", roll, 0.12)
	tw.tween_interval(0.11)
	tw.tween_callback(gr.queue_free)


## The blow or bullet arrives: numbers, blood, sound, and down he goes.
func _land(u: Dictionary, t: Dictionary, ev: Dictionary, to2: Vector2i, dmg: int, g: int, dir: Vector3, aim: Vector3) -> void:
	if not is_instance_valid(u.node):
		return
	var gun: bool = WeaponModels.is_gun(g)
	if t.is_empty() or dmg <= 0:
		_float_text(_world(to2) if t.is_empty() else t.node.position, "miss", Color("#B5B9C2"))
		if gun:
			Sfx.play("bullet_miss", -4.0, 0.1)
		elif g == THROWING_KNIFE:
			Sfx.play("knife_thunk", -3.0, 0.08)
		return
	t.hp = maxi(0, int(t.hp) - dmg)
	_float_text(t.node.position, "-%d" % dmg, C_HIT)
	var body: Vector3 = t.node.position + Vector3(0, 0.34, 0)
	match g:
		0:
			Sfx.play("punch_hit", 0.0, 0.08)
			WeaponFx.impact(_fx, body, dir)
		CLUB, BATON:
			Sfx.play("club_hit" if g == CLUB else "baton_hit", 0.0, 0.07)
			WeaponFx.impact(_fx, body, dir)
			if dmg >= 3:
				WeaponFx.blood(_fx, body, dir, 0.5)
		SWITCHBLADE:
			Sfx.play("knife_stab" if randf() < 0.5 else "knife_slash", 0.0, 0.07)
			WeaponFx.blood(_fx, body, dir, 0.8)
		THROWING_KNIFE:
			Sfx.play("knife_thunk", 0.0, 0.07)
			Sfx.play("knife_stab", -6.0, 0.07)
			WeaponFx.blood(_fx, body, dir, 0.7)
		GRENADE:
			WeaponFx.blood(_fx, body, dir, 1.4)
		_:
			Sfx.play("bullet_flesh", -1.0, 0.08)
	if bool(ev.get("down", false)):
		_play(t.anim, "die", true)
		Sfx.play("body_fall", -2.0, 0.06, 0.45)
		_float_text(t.node.position + Vector3(0, 0.3, 0), "DOWN", Color("#F2C230"))
	_relabel(t, false)


## Easy Eddie's price for an unpaid loan: his men close in around the beaten boss and break his legs.
func _break_legs(v: Dictionary) -> void:
	if v.is_empty():
		return
	var spots := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var men: Array = []
	for u in _units.values():
		if int(u.side) == 1 and int(u.hp) > 0 and men.size() < spots.size():
			var spot: Vector2i = v.pos + spots[men.size()]
			u.pos = Vector2i(clampi(spot.x, 0, Fight.W - 1), clampi(spot.y, 0, Fight.H - 1))
			var d: Vector3 = _world(v.pos) - _world(u.pos)
			u.node.rotation.y = atan2(d.x, d.z)
			_play(u.anim, "walk")
			men.append(u)
	_play(v.anim, "die")
	_float_text(_world(Vector2i(maxi(v.pos.x, 3), v.pos.y)), "EDDIE COLLECTS", Color("#FF9C90"))
	for k in 2:
		get_tree().create_timer(1.0 + 0.7 * k).timeout.connect(func():
			for u in men:
				_play(u.anim, "attack-kick-right" if k == 0 else "attack-melee-right", true)
			_float_text(v.node.position + Vector3(0.3 * k, 0.3 * k, 0), "CRACK!", Color("#FFE27A"))
			Sfx.play("club_hit")
			_shake = 0.25)
	get_tree().create_timer(2.6).timeout.connect(func():
		for u in men:
			_stance(u))
	_timer = 3.0


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
