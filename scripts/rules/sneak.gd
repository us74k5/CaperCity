class_name Sneak
extends RefCounted
## Sneak past the guards (see Mini), as in the original: reach the door without being seen.
## Guards walk fixed loops around the blocks (desks, shelves, crates) and look ahead and to both
## sides, but never behind them, so you can slip along behind one. Bumping into a guard, being in
## sight, or running out of time means you're spotted.
## The floor plan is our own generator: a lattice of blocks with corridors between, some blocks
## merged into longer runs and some cleared into open halls. 'D' marks the door.

const SECONDS := 60
const MY_SPEED := 0.2            # 4 squares a second
const SIGHT_AHEAD := 6
const SIGHT_SIDE := 2
const COLS := [1, 5, 9, 13, 17, 21, 23]   # corridor columns
const ROWS := [1, 4, 7, 10, 13, 15]       # corridor rows


static func create(level: int, rng: RandomNumberGenerator) -> Dictionary:
	var start := Vector2i(1, Mini.H - 2)
	var door := Vector2i(Mini.W - 2, 1)
	var open := {}
	for y in range(1, Mini.H - 1):
		for x in range(1, Mini.W - 1):
			if x in COLS or y in ROWS:
				open[Vector2i(x, y)] = true
	# Clear a block or two into open halls (more ground to cross in sight of the guards).
	var blocks := _blocks()
	for i in 2:
		var b: Rect2i = blocks[rng.randi() % blocks.size()]
		if rng.randf() < 0.7:
			for y in range(b.position.y, b.end.y):
				for x in range(b.position.x, b.end.x):
					open[Vector2i(x, y)] = true
	# Merge some neighbouring blocks by closing the corridor stub between them, keeping everything connected.
	for i in 14:
		var cx: int = COLS[rng.randi_range(1, COLS.size() - 2)]
		var cy: int = ROWS[rng.randi_range(0, ROWS.size() - 2)]
		var seg: Array = []
		if rng.randf() < 0.5:
			for y in range(cy + 1, _next(ROWS, cy)):
				seg.append(Vector2i(cx, y))
		else:
			var x0: int = COLS[rng.randi_range(0, COLS.size() - 2)]
			var ry: int = ROWS[rng.randi_range(1, ROWS.size() - 2)]
			for x in range(x0 + 1, _next(COLS, x0)):
				seg.append(Vector2i(x, ry))
		_try_close(open, seg, start, door)
	var rows := _rows(open, door)

	# Guards: each walks the loop around one block (or merged run), starting at different points.
	var guards: Array = []
	var routes: Array = []
	var want := clampi(3 + level / 3, 3, 5)
	var tries := 0
	while guards.size() < want and tries < 80:
		tries += 1
		var loop := _loop_around(rows, Vector2i(rng.randi_range(2, Mini.W - 3), rng.randi_range(2, Mini.H - 3)))
		if loop.size() < 8 or loop.size() > 40:
			continue
		var bad := false
		for c in loop:
			if (c - start).length() < 4.5 or c == door:
				bad = true
		for r in routes:
			if r[0] == loop[0]:
				bad = true
		if bad:
			continue
		if rng.randf() < 0.5:
			loop.reverse()
		var at := rng.randi() % loop.size()
		var g := Mini.actor(loop[at], clampf(0.1 + 0.008 * level, 0.1, 0.17))
		g.route = loop
		g.at = at
		g.dir = _dir_to(loop[at], loop[(at + 1) % loop.size()])
		if start in sight(rows, g):
			continue   # no guard may be looking at you when the lights go up
		guards.append(g)
		routes.append(loop)
	var m := {"rows": rows, "me": Mini.actor(start, MY_SPEED), "guards": guards, "queue": [],
		"left": int(SECONDS / Mini.TICK), "spotted": -1}
	m.me.dir = "N"
	return m


static func step(m: Dictionary) -> void:
	m.left = int(m.left) - 1
	var me: Dictionary = m.me
	var d := Mini.next_step(m)
	if d != "":
		var to: Vector2i = Mini.cell_of(me) + Mini.DIRS[d]
		if not Mini.is_wall(m.rows, to):
			if _guard_at(m, to) >= 0:
				_spot(m, _guard_at(m, to))
				return
			Mini.move_actor(m, me, to)
			if Mini.mark(m.rows, to) == "D":
				m.over = true
				m.won = true
				return
	for i in m.guards.size():
		var g: Dictionary = m.guards[i]
		g.acc = float(g.acc) + float(g.speed)
		if float(g.acc) >= 1.0:
			g.acc = float(g.acc) - 1.0
			var route: Array = g.route
			var nxt := (int(g.at) + 1) % route.size()
			if route[nxt] == Mini.cell_of(me):
				_spot(m, i)
				return
			g.at = nxt
			g.dir = _dir_to(Mini.cell_of(g), route[nxt])
			Mini.move_actor(m, g, route[nxt])
			# Look where we're about to walk next.
			g.dir = _dir_to(route[nxt], route[(nxt + 1) % route.size()])
	for i in m.guards.size():
		if Mini.cell_of(me) in sight(m.rows, m.guards[i]):
			_spot(m, i)
			return
	if int(m.left) <= 0:
		m.over = true
		m.won = false
		m.spotted = -2   # out of time


## The squares a guard can see: straight ahead, and a little to each side, never behind.
static func sight(rows: Array, g: Dictionary) -> Array:
	var at := Mini.cell_of(g)
	var out: Array = [at]
	var d: String = g.dir
	if d == "":
		return out
	var ahead: Vector2i = Mini.DIRS[d]
	var side := Vector2i(-ahead.y, ahead.x)
	for v in [[ahead, SIGHT_AHEAD], [side, SIGHT_SIDE], [-side, SIGHT_SIDE]]:
		var c := at
		for i in int(v[1]):
			c += v[0]
			if Mini.is_wall(rows, c):
				break
			out.append(c)
	return out


static func _spot(m: Dictionary, i: int) -> void:
	m.over = true
	m.won = false
	m.spotted = i


static func _guard_at(m: Dictionary, cell: Vector2i) -> int:
	for i in m.guards.size():
		if Mini.cell_of(m.guards[i]) == cell:
			return i
	return -1


static func _dir_to(a: Vector2i, b: Vector2i) -> String:
	for d in Mini.DIRS:
		if a + Mini.DIRS[d] == b:
			return d
	return ""


static func _next(list: Array, v: int) -> int:
	var i := list.find(v)
	return list[mini(i + 1, list.size() - 1)]


## The blocks between corridors, as rectangles.
static func _blocks() -> Array:
	var out: Array = []
	for yi in ROWS.size() - 1:
		for xi in COLS.size() - 1:
			var x0: int = COLS[xi] + 1
			var y0: int = ROWS[yi] + 1
			var w: int = COLS[xi + 1] - x0
			var h: int = ROWS[yi + 1] - y0
			if w > 0 and h > 0:
				out.append(Rect2i(x0, y0, w, h))
	return out


## Fills a corridor stub if the floor stays in one piece.
static func _try_close(open: Dictionary, seg: Array, start: Vector2i, door: Vector2i) -> void:
	for c in seg:
		if not open.has(c) or c == start or c == door:
			return
	for c in seg:
		open.erase(c)
	var rows := _rows(open, door)
	var dist := Mini.distances(rows, start)
	var floor_n := 0
	for k in open:
		floor_n += 1
	if dist.size() < floor_n:
		for c in seg:
			open[c] = true


static func _rows(open: Dictionary, door: Vector2i) -> Array:
	var rows: Array = []
	for y in Mini.H:
		var r := ""
		for x in Mini.W:
			var c := Vector2i(x, y)
			r += "D" if c == door else ("." if open.has(c) else "#")
		rows.append(r)
	return rows


## The clockwise ring of floor squares around the wall block containing `inside`, or [] if there's
## no closed ring (the block touches the outer wall, or the ring is broken).
static func _loop_around(rows: Array, inside: Vector2i) -> Array:
	if not Mini.is_wall(rows, inside):
		return []
	# Flood the block.
	var block := {inside: true}
	var queue: Array = [inside]
	while queue.size() > 0:
		var c: Vector2i = queue.pop_back()
		for d in Mini.DIRS.values():
			var n: Vector2i = c + d
			if not block.has(n) and Mini.is_wall(rows, n):
				if n.x <= 0 or n.y <= 0 or n.x >= Mini.W - 1 or n.y >= Mini.H - 1:
					return []
				block[n] = true
				queue.append(n)
	# Its bounding box must be a plain rectangle for a simple loop.
	var lo := inside
	var hi := inside
	for c in block:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	if block.size() != (hi.x - lo.x + 1) * (hi.y - lo.y + 1):
		return []
	var ring: Array = []
	for x in range(lo.x - 1, hi.x + 2):
		ring.append(Vector2i(x, lo.y - 1))
	for y in range(lo.y, hi.y + 2):
		ring.append(Vector2i(hi.x + 1, y))
	for x in range(hi.x, lo.x - 2, -1):
		ring.append(Vector2i(x, hi.y + 1))
	for y in range(hi.y, lo.y - 1, -1):
		ring.append(Vector2i(lo.x - 1, y))
	for c in ring:
		if Mini.is_wall(rows, c) or Mini.mark(rows, c) == "D":
			return []
	return ring
