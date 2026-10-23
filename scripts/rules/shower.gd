class_name Shower
extends RefCounted
## A month in jail is played, not skipped: the prison showers (see Mini). Keep hold of the soap:
## it keeps squirting left or right in your hands, and you tap the side it's sliding toward to
## catch it. It gets slipperier as the clock runs, and nobody holds on to the end: just before time
## is up it gets away from even the best player. Then it hits the tiles, Bubba sees it, and the
## scene cuts to him. There's no winning this one.
## The room is an open-bay shower ('#' walls); nobody walks, it's all in the hands.

const SECONDS := 15.0
const CUT_SECONDS := 5.0          # the soap on the floor, Bubba's close-up
const SURE_DROP := 0.4            # seconds before the end when it gets away no matter what
const ROOM := Rect2i(4, 3, 17, 11)
const SPOT := Vector2i(12, 8)     # you, under the middle shower
const BUBBA := Vector2i(16, 6)
const INMATES := [Vector2i(7, 5), Vector2i(8, 11), Vector2i(17, 11)]
const HEADS := [Vector2i(6, 3), Vector2i(9, 3), Vector2i(12, 3), Vector2i(15, 3), Vector2i(18, 3),
	Vector2i(6, 13), Vector2i(9, 13), Vector2i(12, 13), Vector2i(15, 13), Vector2i(18, 13)]
const KICK := 0.045               # how much a tap shoves the soap back
const DAMP := 0.93


static func create(_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var rows: Array = []
	for y in Mini.H:
		var r := ""
		for x in Mini.W:
			r += "." if ROOM.has_point(Vector2i(x, y)) else "#"
		rows.append(r)
	var m := {"rows": rows, "me": Mini.actor(SPOT, 0.0), "left": int(SECONDS / Mini.TICK),
		"phase": "hold", "soap": 0.0, "vel": 0.0, "push": 0.0, "gust": 0, "taps": 0, "held": 0.0,
		"drop_tick": -1, "cut": int(CUT_SECONDS / Mini.TICK), "fell": 0,
		"bubba": {"x": BUBBA.x, "y": BUBBA.y}, "inmates": INMATES.map(func(c): return [c.x, c.y]),
		"heads": HEADS.map(func(c): return [c.x, c.y])}
	m.me.dir = "S"
	_new_gust(m, rng)
	return m


## A tap: "W" catches soap sliding left, "E" soap sliding right. Each tap shoves it back the other
## way, so mashing one side throws it out the other.
static func input(m: Dictionary, dir: String) -> String:
	if m.phase != "hold" or int(m.ready) > 0:
		return ""
	match dir:
		"W":
			m.vel = float(m.vel) + KICK
		"E":
			m.vel = float(m.vel) - KICK
		_:
			return ""
	m.taps = int(m.taps) + 1
	return ""


## Lets go on purpose: straight to the floor.
static func let_go(m: Dictionary) -> void:
	if m.phase == "hold":
		_drop(m, signf(float(m.soap)) if float(m.soap) != 0.0 else 1.0)


static func step(m: Dictionary, rng: RandomNumberGenerator) -> void:
	if m.phase == "hold":
		m.left = int(m.left) - 1
		var k := 1.0 - float(m.left) / maxf(1.0, float(m.total))   # 0 -> 1 over the round
		m.gust = int(m.gust) - 1
		if int(m.gust) <= 0:
			_new_gust(m, rng)
		# The soap squirts one way, harder and harder; the hands' wobble adds a little noise.
		var accel := float(m.push) * (0.005 + 0.011 * k) + rng.randf_range(-0.0008, 0.0008) * (1.0 + 2.0 * k)
		m.vel = clampf((float(m.vel) + accel) * DAMP, -0.09, 0.09)
		m.soap = float(m.soap) + float(m.vel)
		if absf(float(m.soap)) < 1.0:
			m.held = float(m.total - int(m.left)) * Mini.TICK
		if absf(float(m.soap)) >= 1.0:
			_drop(m, signf(float(m.soap)))
		elif int(m.left) <= int(SURE_DROP / Mini.TICK):
			# Right before the end it shoots out of your hands, however well you've done.
			_drop(m, signf(float(m.vel)) if float(m.vel) != 0.0 else 1.0)
	else:
		m.cut = int(m.cut) - 1
		if int(m.cut) <= 0:
			m.over = true
			m.won = false


static func _drop(m: Dictionary, side: float) -> void:
	m.phase = "dropped"
	m.drop_tick = int(m.tick)
	m.fell = int(side)
	m.soap = clampf(float(m.soap), -1.0, 1.0)
	m.held = float(m.total - int(m.left)) * Mini.TICK


## The next squirt: which way, and for how long (0.4 to 1.2 s).
static func _new_gust(m: Dictionary, rng: RandomNumberGenerator) -> void:
	m.push = -1.0 if rng.randf() < 0.5 else 1.0
	# Lean the odds toward the middle so it doesn't run away while you're already catching it.
	if absf(float(m.soap)) > 0.35 and rng.randf() < 0.25:
		m.push = -signf(float(m.soap))
	m.gust = rng.randi_range(8, 24)
