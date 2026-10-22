class_name Push
extends RefCounted
## The pushing games (see Mini), as in the original. You push one item at a time (never two in a
## row) with each step:
##   "loot":       a shop or villa at night. Push the goods onto the marked squares (the van's loading
##                 bay), then get out through the exit before the time is up, or the police get you.
##   "containers": the same at the docks with shipping containers.
##   "train":      push containers onto the track before the mail train comes. Every one it hits slows
##                 it down; enough of them and it stops, and the guards come out to fight.
## Grid marks: 'o' a target square, 'E' the exit, 't' the track (items can go there, you can't).
## Layouts are our own generator: rooms with a few shelves, every item placed where it can be pushed
## in all four directions to start with.

const MY_SPEED := 0.2            # 4 steps a second
const TRAIN_SPEED := 0.55        # squares per tick when the train comes in
const TRAIN_LEN := 9.0


static func create(kind: String, level: int, rng: RandomNumberGenerator) -> Dictionary:
	if kind == "train":
		return _train_yard(level, rng)
	var grid := _blank()
	var shelves := 5 if kind == "loot" else 7
	var zone := Vector2i(3, 3) if kind == "loot" else Vector2i(4, 5)
	var n_items := 9 if kind == "loot" else 14
	var secs := (45 if kind == "loot" else 55) - level
	# Target squares on the right, the exit on the left wall.
	var z0 := Vector2i(rng.randi_range(Mini.W - 3 - zone.x - 4, Mini.W - 3 - zone.x), rng.randi_range(3, Mini.H - 3 - zone.y))
	for y in zone.y:
		for x in zone.x:
			grid[z0.y + y][z0.x + x] = "o"
	var ey := rng.randi_range(3, Mini.H - 4)
	grid[ey][0] = "E"
	var start := Vector2i(1, ey)
	for i in shelves * 4:
		if shelves <= 0:
			break
		if _try_shelf(grid, rng, start):
			shelves -= 1
	var items := _scatter(grid, rng, n_items, start, 3)
	return {"rows": _join(grid), "me": Mini.actor(start, MY_SPEED), "items": items, "queue": [],
		"left": int(secs / Mini.TICK), "got": 0, "need": 0}


static func _train_yard(level: int, rng: RandomNumberGenerator) -> Dictionary:
	var grid := _blank()
	for x in Mini.W:
		grid[1][x] = "t"
	var need := clampi(8 + level / 2, 8, 12)
	var start := Vector2i(Mini.W / 2, Mini.H - 2)
	var items: Array = []
	# A row of containers already up against the track, and the rest of the yard to fetch from.
	var xs: Array = range(2, Mini.W - 2)
	xs.shuffle()
	for x in xs.slice(0, need - 3):
		items.append(_item(Vector2i(x, 2)))
	var taken := {}
	for it in items:
		taken[Vector2i(int(it.x), int(it.y))] = true
	items += _scatter(grid, rng, 22, start, 2, taken, 4)
	return {"rows": _join(grid), "me": Mini.actor(start, MY_SPEED), "items": items, "queue": [],
		"left": int((40 - level) / Mini.TICK), "phase": "push", "need": need, "got": 0,
		"train": {"x": -TRAIN_LEN - 6.0, "v": TRAIN_SPEED, "hits": 0}}


static func step(m: Dictionary) -> void:
	if m.get("phase", "") == "train":
		_run_train(m)
		return
	m.left = int(m.left) - 1
	var d := Mini.next_step(m)
	if d != "":
		_try_move(m, d)
		if m.over:
			return
	m.got = on_targets(m)
	if int(m.left) <= 0:
		if m.game == "train":
			call_train(m)
		else:
			m.over = true
			m.won = false   # still inside when the time ran out: the police are at the door


## Items on target squares (or, for the train, on the track).
static func on_targets(m: Dictionary) -> int:
	var n := 0
	var goal := "t" if m.game == "train" else "o"
	for it in m.items:
		if Mini.mark(m.rows, Mini.cell_of(it)) == goal:
			n += 1
	return n


## Time's up (or the player called it): here comes the train.
static func call_train(m: Dictionary) -> void:
	m.got = on_targets(m)
	m.phase = "train"
	m.queue = []
	m.left = 0


static func item_at(m: Dictionary, cell: Vector2i) -> int:
	for i in m.items.size():
		if Mini.cell_of(m.items[i]) == cell:
			return i
	return -1


static func _try_move(m: Dictionary, d: String) -> void:
	var me: Dictionary = m.me
	var to: Vector2i = Mini.cell_of(me) + Mini.DIRS[d]
	var mk := Mini.mark(m.rows, to)
	if mk == "#" or mk == "t":
		return
	var it := item_at(m, to)
	if it >= 0:
		var beyond: Vector2i = to + Mini.DIRS[d]
		var bm := Mini.mark(m.rows, beyond)
		if bm == "#" or bm == "E" or item_at(m, beyond) >= 0:
			return   # can't push into a wall, out the door, or two at once
		if bm == "t" and d != "N":
			return
		Mini.move_actor(m, m.items[it], beyond)
	Mini.move_actor(m, me, to)
	if mk == "E":
		m.got = on_targets(m)
		m.over = true
		m.won = true


## The train rolls along the track; every container in the way slows it and gets knocked aside.
static func _run_train(m: Dictionary) -> void:
	var tr: Dictionary = m.train
	var front := float(tr.x) + float(tr.v)
	for it in m.items:
		if int(it.y) == 1 and not it.get("hit", false) and float(it.x) <= front:
			it.hit = true
			it.mt = int(m.tick)
			tr.hits = int(tr.hits) + 1
			tr.v = maxf(0.0, float(tr.v) - TRAIN_SPEED / float(m.need))
			front = minf(front, float(it.x))
	tr.x = front
	if float(tr.v) <= 0.001:
		m.over = true
		m.won = true    # stopped: the guards come out
	elif float(tr.x) - TRAIN_LEN > Mini.W + 1:
		m.over = true
		m.won = false   # it got through


# ------------------------------------------------------------------ layout

static func _blank() -> Array:
	var grid: Array = []
	for y in Mini.H:
		var row: Array = []
		for x in Mini.W:
			row.append("#" if x == 0 or y == 0 or x == Mini.W - 1 or y == Mini.H - 1 else ".")
		grid.append(row)
	return grid


static func _join(grid: Array) -> Array:
	var rows: Array = []
	for row in grid:
		rows.append("".join(row))
	return rows


## A short shelf, kept a square clear of every other wall and mark so it never boxes anything in.
static func _try_shelf(grid: Array, rng: RandomNumberGenerator, start: Vector2i) -> bool:
	var horiz := rng.randf() < 0.6
	var length := rng.randi_range(2, 4)
	var at := Vector2i(rng.randi_range(3, Mini.W - 4), rng.randi_range(3, Mini.H - 4))
	var cells: Array = []
	for i in length:
		cells.append(at + (Vector2i(i, 0) if horiz else Vector2i(0, i)))
	for c in cells:
		if c.x < 3 or c.y < 3 or c.x > Mini.W - 4 or c.y > Mini.H - 4:
			return false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if not n in cells and grid[n.y][n.x] != ".":
					return false
		if (c - start).length() < 3:
			return false
	for c in cells:
		grid[c.y][c.x] = "#"
	return true


## Up to n items on plain floor away from walls, marks, each other and the start, from row min_y down.
static func _scatter(grid: Array, rng: RandomNumberGenerator, n: int, start: Vector2i, gap: int, taken := {}, min_y := 2) -> Array:
	var spots: Array = []
	for y in range(maxi(2, min_y), Mini.H - 2):
		for x in range(2, Mini.W - 2):
			spots.append(Vector2i(x, y))
	spots.shuffle()
	var out: Array = []
	for c in spots:
		if out.size() >= n:
			break
		if (c - start).length() < gap or taken.has(c):
			continue
		var clear := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var k: Vector2i = c + Vector2i(dx, dy)
				if grid[k.y][k.x] != "." or (taken.has(k) and k != c):
					clear = false
		if not clear:
			continue
		out.append(_item(c))
		taken[c] = true
	return out


static func _item(c: Vector2i) -> Dictionary:
	return {"x": c.x, "y": c.y, "px": c.x, "py": c.y, "mt": 0}
