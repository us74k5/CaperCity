class_name Jailbreak
extends RefCounted
## A month in jail is played, not skipped: the prison bathroom (see Mini). Slip out of your stall,
## get past Big Lou at the sinks and pry the vent off the far wall. You can get it almost all the
## way loose, but never quite: the vent only gives as fast as the clock runs, and the guards' round
## always arrives first. Then the guard walks in and collars you while Big Lou has a laugh.
## '#' wall, 'V' the vent (push into it to pry), 'D' the door the guard comes in by.

const SECONDS := 18
const CAUGHT_SECONDS := 5        # the guard's walk in and the laugh at the end
const MY_SPEED := 0.25
const GUARD_SPEED := 0.5
const DIG_MAX := 30
const MOST := 0.97               # the furthest the vent ever gets
const ROOM := Rect2i(3, 3, 19, 11)   # x 3..21, y 3..13, walls around it
const VENT := Vector2i(22, 8)
const DOOR := Vector2i(2, 8)
const START := Vector2i(11, 4)       # in the middle stall
const LOU := Vector2i(14, 11)        # Big Lou, by the sinks
const STALL_WALLS := [8, 14]         # stall dividers, the top rows
const TOILETS := [Vector2i(5, 3), Vector2i(11, 3), Vector2i(17, 3)]
const SINKS := [Vector2i(6, 13), Vector2i(9, 13), Vector2i(12, 13), Vector2i(16, 13), Vector2i(19, 13)]


static func create(_level: int, _rng: RandomNumberGenerator) -> Dictionary:
	var rows: Array = []
	for y in Mini.H:
		var r := ""
		for x in Mini.W:
			var c := Vector2i(x, y)
			var ch := "#"
			if ROOM.has_point(c):
				ch = "."
			if c in TOILETS or c in SINKS or (x in STALL_WALLS and y <= 5) or (y == 6 and x >= 3 and x <= 19 and x % 6 != 5 and x != 11):
				ch = "#"
			if c == VENT:
				ch = "V"
			elif c == DOOR:
				ch = "D"
			r += ch
		rows.append(r)
	var m := {"rows": rows, "me": Mini.actor(START, MY_SPEED), "queue": [], "left": int(SECONDS / Mini.TICK),
		"phase": "dig", "dig": 0, "dig_max": DIG_MAX, "lou": {"x": LOU.x, "y": LOU.y}, "guards": [], "caught_tick": -1,
		"grabbed": false, "toilets": TOILETS.map(func(c): return [c.x, c.y]), "sinks": SINKS.map(func(c): return [c.x, c.y])}
	m.me.dir = "S"
	return m


static func input(m: Dictionary, dir: String) -> String:
	if m.phase != "dig":
		return ""   # too late: the guard is here
	return Mini.queue_step(m, dir)


static func step(m: Dictionary) -> void:
	m.left = int(m.left) - 1
	var me: Dictionary = m.me
	var caught_ticks := int(CAUGHT_SECONDS / Mini.TICK)
	if m.phase == "dig" and int(m.left) <= caught_ticks:
		m.phase = "caught"
		m.caught_tick = int(m.tick)
		m.queue = []
		var g := Mini.actor(DOOR + Vector2i(1, 0), GUARD_SPEED)
		g.dir = "E"
		m.guards = [g]
	if m.phase == "dig":
		var d := Mini.next_step(m)
		if d != "":
			var to: Vector2i = Mini.cell_of(me) + Mini.DIRS[d]
			if to == VENT:
				m.dig = mini(int(m.dig) + 1, cap(m))
				me.mt = int(m.tick)   # the pry, for the animation
			elif not Mini.is_wall(m.rows, to) and Mini.mark(m.rows, to) != "D" and to != LOU:
				Mini.move_actor(m, me, to)
	else:
		_guard_walk(m)
	if int(m.left) <= 0:
		m.over = true
		m.won = false


## How far the vent can be pried by now: it keeps pace with the clock and tops out just short.
static func cap(m: Dictionary) -> int:
	var play := int(m.total) - int(CAUGHT_SECONDS / Mini.TICK)
	var played := clampi(int(m.total) - int(m.left), 0, play)
	return mini(int(floor(DIG_MAX * MOST * played / float(maxi(1, play)))), DIG_MAX - 1)


static func _guard_walk(m: Dictionary) -> void:
	var g: Dictionary = m.guards[0]
	var me := Mini.cell_of(m.me)
	var at := Mini.cell_of(g)
	if (at - me).length() <= 1.01:
		m.grabbed = true
		return
	g.acc = float(g.acc) + float(g.speed)
	if float(g.acc) < 1.0:
		return
	g.acc = float(g.acc) - 1.0
	var dist := Mini.distances(m.rows, me, {LOU: true})
	var best := at
	var best_d := 9999
	for k in Mini.DIRS:
		var n: Vector2i = at + Mini.DIRS[k]
		if dist.has(n) and int(dist[n]) < best_d:
			best_d = int(dist[n])
			best = n
			g.dir = k
	if best != at:
		Mini.move_actor(m, g, best)
