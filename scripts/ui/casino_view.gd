extends Node3D
## Inside the casino: carpet, slot machines along the wall, and three tables (blackjack, poker,
## roulette) with their dealers. Click a table to sit down at it; the camera moves in to the table.
## When a hand is played (the result's "show"; see Casino) the cards are dealt, turned and counted
## on the felt, or the wheel spins and the ball drops, and the chips go to the winner. busy() is true
## until it's all played out, so the HUD holds the result card back till then.

const MODELS := "res://assets/models/"
const TOP := 0.62                 # table height
const PERSON := 1.5
const C_FELT := Color("#1E6B45")
const C_RIM := Color("#5A3520")
const C_GOLD := Color("#E2B13C")
const C_CARPET := Color("#5A1622")
const C_WALL := Color("#2A1621")
const TABLE_POS := {"blackjack": Vector3(-7, 0, -2.5), "poker": Vector3(0, 0, -4.2), "roulette": Vector3(7, 0, -2.5)}
const TABLE_INFO := {"blackjack": "pays 2× · wins most often", "poker": "pays 3×", "roulette": "pays 6× · a long shot"}
const DEALERS := {"blackjack": "character-female-c", "poker": "character-male-b", "roulette": "character-male-e"}
const CHIP_COLORS := [Color("#C8423B"), Color("#2F5FA8"), Color("#2B2F36"), Color("#E8E3D6"), Color("#3E8A5C")]

var _me: Node3D
var _me_anim: AnimationPlayer
var _rings := {}                   # game -> MeshInstance3D (hover / seat ring)
var _signs := {}                   # game -> Label3D over the table (shown from across the room)
var _seat := ""
var _hover := ""
var _table_cards: Node3D           # everything dealt for the current hand
var _wheel: Node3D
var _ball: MeshInstance3D
var _steps: Array = []             # [time, Callable] still to run for the hand being shown
var _clock := 0.0
var _hold := 0.0
var _spin := {}                    # roulette spin in progress
var _cam := Transform3D()
var _cam_ready := false
var _played := ""                  # key of the last hand shown, so it plays once
var _slot_screens: Array = []
var _t := 0.0


func build(b: Dictionary, look: String) -> void:
	_room(b)
	for g in TABLE_POS:
		_table(g)
	_me = load(MODELS + "characters/" + look + ".glb").instantiate()
	_me.scale = Vector3.ONE * PERSON
	add_child(_me)
	_me_anim = _anim(_me)
	_me_anim.play("idle")
	_table_cards = Node3D.new()
	add_child(_table_cards)
	sit("")


## Which table the player is at ("" = standing in the room).
func sit(game: String) -> void:
	if game == _seat and _me.position != Vector3.ZERO:
		return
	_seat = game
	if game == "":
		_me.position = Vector3(0, 0, 2.2)
		_me.rotation.y = PI
	else:
		# At the near-left corner, turned toward the dealer, so the felt stays in view.
		_me.position = TABLE_POS[game] + Vector3(-1.9, 0, 1.2)
		_me.rotation.y = PI - 0.9
	_update_rings()


func hover(game: String) -> void:
	if game != _hover:
		_hover = game
		_update_rings()


## The table under a screen ray, or "".
func pick(from: Vector3, dir: Vector3) -> String:
	var best := ""
	var best_d := INF
	for g in TABLE_POS:
		var c: Vector3 = global_position + TABLE_POS[g]
		var box := AABB(c - Vector3(2.5, 0, 1.9), Vector3(5.0, 1.6, 3.8))
		var hit = box.intersects_ray(from, dir)
		if hit != null and from.distance_to(hit) < best_d:
			best_d = from.distance_to(hit)
			best = g
	return best


func played() -> String:
	return _played


func busy() -> bool:
	return not _steps.is_empty() or _hold > 0.0 or not _spin.is_empty()


## Plays out a hand once (keyed by `key`).
func play(show: Dictionary, key: String) -> void:
	if key == _played or not show.has("outcome") or not show.has("game"):
		return
	_played = key
	sit(str(show.game))
	for c in _table_cards.get_children():
		c.queue_free()
	_steps.clear()
	_clock = 0.0
	match str(show.game):
		"blackjack":
			_play_blackjack(show)
		"poker":
			_play_poker(show)
		"roulette":
			_play_roulette(show)


## The camera: the whole room, or close in on the table you're sitting at.
func camera_pose(aspect: float) -> Transform3D:
	var eye := Vector3(0, 8.6, 11.5)
	var look := Vector3(0, 0.6, -2.6)
	if aspect < 1.2:
		eye = Vector3(0, 11.5, 15.5)
	if _seat != "":
		var t: Vector3 = TABLE_POS[_seat]
		eye = t + Vector3(0, 5.4, 4.4)
		look = t + Vector3(0, 0.3, -0.5)
	var target := Transform3D(Basis.looking_at(look - eye, Vector3.UP), global_position + eye)
	if not _cam_ready:
		_cam = target
		_cam_ready = true
	_cam = _cam.interpolate_with(target, 0.08)
	return _cam


func _process(delta: float) -> void:
	_t += delta
	for i in _slot_screens.size():
		var mat: StandardMaterial3D = _slot_screens[i]
		mat.emission_energy_multiplier = 0.9 + 0.6 * absf(sin(_t * 2.2 + i * 1.3))
	if _hold > 0.0:
		_hold -= delta
	if not _steps.is_empty():
		_clock += delta
		while not _steps.is_empty() and _steps[0][0] <= _clock:
			var s: Array = _steps.pop_front()
			(s[1] as Callable).call()
	if not _spin.is_empty():
		_run_spin(delta)


# ------------------------------------------------------------------ playing a hand

func _at(time: float, f: Callable) -> void:
	_steps.append([time, f])


func _play_blackjack(s: Dictionary) -> void:
	var t: Vector3 = TABLE_POS.blackjack
	var shoe := t + Vector3(1.6, TOP, -1.0)
	var you: Array = s.you
	var house: Array = s.house
	var cards := {}
	_bet(t + Vector3(0, TOP, 0.75))
	var time := 0.4
	var slot := func(who: String, i: int) -> Vector3:
		return t + Vector3(-0.9 + i * 0.45, TOP + 0.05 + i * 0.002, 0.25 if who == "you" else -0.85)
	for i in 2:
		var ci := i
		_at(time, func(): cards["y%d" % ci] = _deal(you[ci], shoe, slot.call("you", ci), true))
		time += 0.4
		_at(time, func(): cards["h%d" % ci] = _deal(house[ci], shoe, slot.call("house", ci), ci == 0))
		time += 0.4
	for i in range(2, you.size()):
		var ci := i
		time += 0.25
		_at(time, func(): _deal(you[ci], shoe, slot.call("you", ci), true))
		time += 0.4
	_at(time, func(): _label(_count_text(Casino.total(you)), t + Vector3(-1.6, TOP + 0.5, 0.25), Color.WHITE))
	time += 0.5
	if Casino.total(you) <= 21:
		_at(time, func(): _flip(cards.get("h1")))
		time += 0.5
		for i in range(2, house.size()):
			var ci := i
			_at(time, func(): _deal(house[ci], shoe, slot.call("house", ci), true))
			time += 0.45
		_at(time, func(): _label(_count_text(Casino.total(house)), t + Vector3(-1.6, TOP + 0.5, -0.85), Color.WHITE))
		time += 0.4
	_finish(s, time, t + Vector3(0, TOP, 0.75), t + Vector3(0.6, TOP, -1.4))


func _play_poker(s: Dictionary) -> void:
	var t: Vector3 = TABLE_POS.poker
	var deck_at := t + Vector3(0, TOP, -0.6)
	var you: Array = s.you
	var house: Array = s.house
	var mine: Array = []
	var theirs: Array = []
	_bet(t + Vector3(0, TOP, 0.6))
	var time := 0.4
	for i in 5:
		var ci := i
		_at(time, func(): mine.append(_deal(you[ci], deck_at, t + Vector3(-0.9 + ci * 0.45, TOP + 0.05, 0.15), false)))
		time += 0.18
		_at(time, func(): theirs.append(_deal(house[ci], deck_at, t + Vector3(-0.9 + ci * 0.45, TOP + 0.05, -1.15), false)))
		time += 0.18
	time += 0.4
	for i in 5:
		var ci := i
		_at(time, func(): _flip(mine[ci]))
		time += 0.15
	_at(time, func(): _label(str(s.you_hand), t + Vector3(0, TOP + 0.55, 0.15), Color.WHITE))
	time += 0.8
	for i in 5:
		var ci := i
		_at(time, func(): _flip(theirs[ci]))
		time += 0.15
	_at(time, func(): _label(str(s.house_hand), t + Vector3(0, TOP + 0.55, -1.15), Color.WHITE))
	time += 0.6
	_finish(s, time, t + Vector3(0, TOP, 0.6), t + Vector3(0, TOP, -1.6))


func _play_roulette(s: Dictionary) -> void:
	var t: Vector3 = TABLE_POS.roulette
	# Our chips on the six-number line, then the spin.
	var line := int(s.line)
	var bet_at := _layout_pos(line + 1) + Vector3(0.14, 0, 0)
	_bet(bet_at)
	_at(0.5, func():
		_spin = {"t": 0.0, "len": 4.2, "pocket": int(s.pocket), "w0": _wheel.rotation.y}
		_ball.visible = true)
	_hold = 5.0
	var time := 4.9
	_at(time, func():
		var n := int(s.number)
		_label("%d %s" % [n, str(s.color).to_upper()], t + Vector3(-1.4, TOP + 1.0, 0), _num_color(n).lightened(0.4))
		_marker(_layout_pos(n)))
	time += 0.6
	_finish(s, time, bet_at, t + Vector3(0.6, TOP, -1.0))


## Chips go to the winner, the player reacts, and after a beat the result card can show.
func _finish(s: Dictionary, time: float, bet_at: Vector3, house_at: Vector3) -> void:
	var won: bool = s.outcome == "win"
	_at(time, func():
		if won:
			_bet(bet_at + Vector3(0.3, 0, 0))
		else:
			for c in _table_cards.get_children():
				if c.has_meta("chip"):
					create_tween().tween_property(c, "position", house_at + Vector3(0, c.position.y - TOP, 0), 0.5)
		_me_anim.play("emote-yes" if won else "emote-no", 0.1)
		_me_anim.queue("idle"))
	_at(time + 1.4, func(): pass)


func _run_spin(delta: float) -> void:
	_spin.t = float(_spin.t) + delta
	var T: float = _spin.len
	var t := minf(float(_spin.t), T)
	# The wheel turns one way and slows; the ball runs the other way, slows, and drops into its pocket.
	var w := float(_spin.w0) + 5.0 * (t - t * t / (2.0 * T))
	_wheel.rotation.y = w
	var w_end := float(_spin.w0) + 5.0 * (T - T / 2.0)
	var pocket_angle := -TAU * float(_spin.pocket) / 37.0
	var ball_end := w_end + pocket_angle
	var ball := ball_end + 2.6 * pow(T - t, 2.0) / T * 3.0
	var r := 0.62 if t < T - 0.8 else lerpf(0.62, 0.47, (t - (T - 0.8)) / 0.8)
	if t >= T:
		ball = w + pocket_angle
		r = 0.47
	_ball.position = _wheel.position + Vector3(cos(ball) * r, 0.1, -sin(ball) * r)
	if float(_spin.t) >= T + 0.4:
		_spin = {}


func _deal(card: Array, from: Vector3, to: Vector3, face_up: bool) -> Node3D:
	var n := Node3D.new()
	var face := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.012, 0.5)
	face.mesh = box
	face.material_override = _flat(Color("#F4F1EA"))
	n.add_child(face)
	var l := Label3D.new()
	l.text = Casino.card_name(card)
	l.font_size = 72
	l.pixel_size = 0.0028
	l.modulate = Color("#C0282D") if Casino.is_red(card) else Color("#16181C")
	l.outline_size = 0
	l.rotation.x = -PI / 2
	l.position.y = 0.008
	l.shaded = false
	n.add_child(l)
	var back := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.37, 0.004, 0.51)
	back.mesh = bb
	back.material_override = _flat(Color("#8E1E2A"))
	back.position.y = 0.01
	back.visible = not face_up
	back.name = "back"
	n.add_child(back)
	n.position = from
	_table_cards.add_child(n)
	create_tween().tween_property(n, "position", to, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return n


func _flip(n) -> void:
	if n == null or not is_instance_valid(n):
		return
	var back: Node3D = n.get_node("back")
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3(0.05, 1, 1), 0.1)
	tw.tween_callback(func(): back.visible = false)
	tw.tween_property(n, "scale", Vector3.ONE, 0.1)


## A little stack of chips.
func _bet(at: Vector3) -> void:
	for i in 4:
		var c := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.11
		cyl.bottom_radius = 0.11
		cyl.height = 0.035
		c.mesh = cyl
		c.material_override = _flat(CHIP_COLORS[i % CHIP_COLORS.size()])
		c.position = at + Vector3(0, 0.06 + i * 0.037, 0)
		c.set_meta("chip", true)
		_table_cards.add_child(c)


func _label(text: String, at: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = at
	_table_cards.add_child(l)


func _marker(at: Vector3) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.12
	m.mesh = cyl
	var mat := _flat(Color.WHITE)
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	m.material_override = mat
	m.position = at + Vector3(0, 0.08, 0)
	_table_cards.add_child(m)


func _count_text(n: int) -> String:
	return "BUST %d" % n if n > 21 else str(n)


# ------------------------------------------------------------------ the room

func _room(b: Dictionary) -> void:
	# Carpet: a burgundy weave with a gold diamond, drawn once into a small repeating texture.
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(C_CARPET)
	for y in 32:
		for x in 32:
			var d := absi(x - 16) + absi(y - 16)
			if d == 12 or d == 13:
				img.set_pixel(x, y, Color("#8C5A2A"))
			elif d < 3:
				img.set_pixel(x, y, Color("#7A2432"))
	var tex := ImageTexture.create_from_image(img)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(28, 20)
	floor.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = tex
	fm.uv1_scale = Vector3(14, 10, 1)
	fm.roughness = 1.0
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	floor.material_override = fm
	floor.position = Vector3(0, 0, -2)
	add_child(floor)
	# Walls with a gold rail, and the casino's name in lights.
	for w in [[Vector3(0, 2.4, -12), Vector3(28, 4.8, 0.3)], [Vector3(-14, 2.4, -2), Vector3(0.3, 4.8, 20)], [Vector3(14, 2.4, -2), Vector3(0.3, 4.8, 20)]]:
		_box(w[1], w[0], C_WALL)
	_box(Vector3(28, 0.12, 0.34), Vector3(0, 1.1, -11.8), C_GOLD)
	_box(Vector3(28, 0.12, 0.34), Vector3(0, 4.7, -11.8), C_GOLD)
	var sign := Label3D.new()
	sign.text = str(b.name).to_upper()
	sign.font_size = 160
	sign.pixel_size = 0.01
	sign.modulate = Color("#FF6FB0")
	sign.outline_size = 24
	sign.outline_modulate = Color("#6A1040")
	sign.shaded = false
	sign.position = Vector3(0, 3.6, -11.8)
	add_child(sign)
	# Slot machines along the back wall.
	for i in 11:
		var x := -12.0 + i * 2.4
		if absf(x) < 2.0:
			continue
		var cab := Color("#3A2A5A") if i % 2 == 0 else Color("#5A2A3A")
		_box(Vector3(1.0, 1.7, 0.8), Vector3(x, 0.85, -10.9), cab)
		_box(Vector3(1.04, 0.12, 0.84), Vector3(x, 1.72, -10.9), C_GOLD)
		var scr := _box(Vector3(0.7, 0.5, 0.05), Vector3(x, 1.2, -10.48), Color("#FFE27A"))
		var mat: StandardMaterial3D = scr.material_override
		mat.emission_enabled = true
		mat.emission = Color("#FFB83A") if i % 3 else Color("#7FE6D6")
		_slot_screens.append(mat)
		var top := _box(Vector3(0.3, 0.3, 0.3), Vector3(x, 2.0, -10.9), Color("#FF5D4F"))
		(top.material_override as StandardMaterial3D).emission_enabled = true
		(top.material_override as StandardMaterial3D).emission = Color("#FF5D4F")
	# Warm lamps over each table.
	for g in TABLE_POS:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#FFD9A0")
		lamp.light_energy = 1.6
		lamp.omni_range = 6.0
		lamp.position = TABLE_POS[g] + Vector3(0, 3.2, 0)
		add_child(lamp)
		var shade := _box(Vector3(1.6, 0.2, 0.6), TABLE_POS[g] + Vector3(0, 3.6, 0), Color("#1E5A3A"))
		(shade.material_override as StandardMaterial3D).emission_enabled = true
		(shade.material_override as StandardMaterial3D).emission = Color("#2E8A5A")
	# A few patrons and a bouncer by the door.
	_extra("character-female-b", Vector3(-11, 0, -9.6), 0.0)
	_extra("character-male-f", Vector3(10.5, 0, -9.6), 0.2)
	_extra("character-male-d", Vector3(-12.6, 0, 4.0), PI / 2)


func _table(g: String) -> void:
	var t: Vector3 = TABLE_POS[g]
	if g == "roulette":
		_box(Vector3(4.6, 0.1, 2.4), t + Vector3(0, TOP - 0.05, 0), C_RIM)
		_box(Vector3(4.4, 0.04, 2.2), t + Vector3(0, TOP + 0.01, 0), C_FELT)
		_box(Vector3(4.2, TOP - 0.1, 2.0), t + Vector3(0, (TOP - 0.1) / 2.0, 0), Color("#3A2216"))
		# The wheel: a dish of 37 coloured pockets that turns.
		_wheel = Node3D.new()
		_wheel.position = t + Vector3(-1.4, TOP + 0.05, 0)
		add_child(_wheel)
		var dish := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.78
		cyl.bottom_radius = 0.7
		cyl.height = 0.1
		dish.mesh = cyl
		dish.material_override = _flat(C_RIM)
		_wheel.add_child(dish)
		for i in 37:
			var n: int = Casino.WHEEL[i]
			var a := TAU * i / 37.0
			var p := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.11, 0.03, 0.2)
			p.mesh = pb
			p.material_override = _flat(_num_color(n))
			p.position = Vector3(cos(a) * 0.55, 0.06, -sin(a) * 0.55)
			p.rotation.y = a
			_wheel.add_child(p)
		var hub := _box(Vector3(0.18, 0.2, 0.18), Vector3.ZERO, C_GOLD)
		hub.reparent(_wheel, false)
		hub.position = Vector3(0, 0.12, 0)
		_ball = MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.05
		sph.height = 0.1
		_ball.mesh = sph
		_ball.material_override = _flat(Color.WHITE)
		_ball.visible = false
		add_child(_ball)
		# The betting layout: 0, then 1-36 in three rows.
		_box(Vector3(0.24, 0.02, 0.84), _layout_pos(0), _num_color(0))
		for n in range(1, 37):
			_box(Vector3(0.21, 0.02, 0.26), _layout_pos(n), _num_color(n))
	else:
		var felt := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 2.2
		c.bottom_radius = 2.2
		c.height = 0.06
		felt.mesh = c
		felt.material_override = _flat(C_FELT)
		felt.scale = Vector3(1.0, 1.0, 0.62)
		felt.position = t + Vector3(0, TOP, 0)
		add_child(felt)
		var rim := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = 2.38
		rc.bottom_radius = 2.38
		rc.height = 0.08
		rim.mesh = rc
		rim.material_override = _flat(C_RIM)
		rim.scale = Vector3(1.0, 1.0, 0.64)
		rim.position = t + Vector3(0, TOP - 0.03, 0)
		add_child(rim)
		_box(Vector3(1.4, TOP - 0.06, 0.8), t + Vector3(0, (TOP - 0.06) / 2.0, 0), Color("#3A2216"))
	var dealer := _extra(DEALERS[g], t + Vector3(0, 0, -1.75 if g != "poker" else -1.6), 0.0)
	dealer.scale = Vector3.ONE * PERSON
	# Name and payout over the table.
	var l := Label3D.new()
	l.text = "%s\n%s" % [g.to_upper(), TABLE_INFO[g]]
	l.font_size = 54
	l.pixel_size = 0.006
	l.modulate = C_GOLD
	l.outline_size = 12
	l.outline_modulate = Color(0.1, 0.05, 0.02, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = t + Vector3(0, 2.6, -0.6)
	add_child(l)
	_signs[g] = l
	# The ring that lights up when you point at the table or sit there.
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 2.55
	tor.outer_radius = 2.7
	ring.mesh = tor
	ring.scale = Vector3(1.0, 1.0, 0.75)
	var rm := _flat(C_GOLD)
	rm.emission_enabled = true
	rm.emission = C_GOLD
	ring.material_override = rm
	ring.position = t + Vector3(0, 0.03, 0)
	ring.visible = false
	add_child(ring)
	_rings[g] = ring


func _layout_pos(n: int) -> Vector3:
	var t: Vector3 = TABLE_POS.roulette
	if n == 0:
		return t + Vector3(-0.35, TOP + 0.04, 0)
	var col := (n - 1) / 3
	var row := 2 - (n - 1) % 3
	return t + Vector3(-0.1 + col * 0.23, TOP + 0.04, -0.3 + row * 0.3)


func _num_color(n: int) -> Color:
	return Color("#1E8A4A") if n == 0 else (Color("#B8262E") if n in Casino.REDS else Color("#1A1C20"))


func _update_rings() -> void:
	for g in _signs:
		_signs[g].visible = _seat == ""
	for g in _rings:
		_rings[g].visible = g == _hover or g == _seat
		(_rings[g].material_override as StandardMaterial3D).emission_energy_multiplier = 1.6 if g == _seat else 0.7


func _extra(model: String, pos: Vector3, turn: float) -> Node3D:
	var n: Node3D = load(MODELS + "characters/" + model + ".glb").instantiate()
	n.position = pos
	n.rotation.y = turn
	n.scale = Vector3.ONE * PERSON
	add_child(n)
	var ap := _anim(n)
	ap.play("idle")
	ap.seek(randf() * ap.current_animation_length)
	return n


func _anim(n: Node) -> AnimationPlayer:
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
	return ap


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _flat(col)
	m.position = pos
	add_child(m)
	return m


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m
