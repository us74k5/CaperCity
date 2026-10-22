class_name Chase
extends RefCounted
## The maze chases (see Mini), the original's escape minigames:
##   "escape": slip away from four cops. Stay free until the clock runs out; if they catch you, it's a fight.
##   "catch":  the runaway grabbed the ransom case. Catch them before the clock runs out.
## Every chase gets a fresh braided maze from our own generator. Movement is cell by cell; an actor with
## speed s moves one cell every 1/s ticks and keeps going the way it's headed, so a tapped direction
## keeps you running and turns can be queued early.
## The runner's own screen moves them the moment a key is pressed and reports each square (place);
## the server checks the step and the speed, and does the catching. Difficulty is the cops' speed.

const ESCAPE_SECONDS := 20
const CATCH_SECONDS := 15
const MY_SPEED := 0.25           # cells per tick: 5 a second


static func create(kind: String, level: int, rng: RandomNumberGenerator) -> Dictionary:
	var rows := maze(rng)
	var mid := Vector2i(11 + 2 * (rng.randi() % 2), 7 + 2 * (rng.randi() % 2))
	var c := {
		"rows": rows, "want": "", "foes": [], "me": Mini.actor(mid, MY_SPEED),
		"left": int((ESCAPE_SECONDS if kind == "escape" else CATCH_SECONDS) / Mini.TICK),
	}
	if kind == "escape":
		var speed := cop_speed(level)
		for corner in [Vector2i(1, 1), Vector2i(Mini.W - 2, 1), Vector2i(1, Mini.H - 2), Vector2i(Mini.W - 2, Mini.H - 2)]:
			c.foes.append(Mini.actor(corner, speed))
	else:
		# The runaway starts a short head start away.
		var dist := Mini.distances(rows, mid)
		var picks: Array = []
		for k in dist:
			if int(dist[k]) >= 9 and int(dist[k]) <= 13:
				picks.append(k)
		var start: Vector2i = picks[rng.randi() % picks.size()] if picks.size() > 0 else Vector2i(1, 1)
		c.foes.append(Mini.actor(start, clampf(0.225 + 0.003 * level, 0.225, 0.25)))
	return c


## How fast the cops run for a crime of severity `level` (0-10): from under half your speed for a
## pickpocket to nearly yours for a kidnapping.
static func cop_speed(level: int) -> float:
	return 0.08 + 0.014 * clampi(level, 0, 10)


## The runner's client stepped onto `cell`. It must be next to where they are, not a wall, and not
## faster than running speed (with a step of slack for the network bunching reports up). A refused
## step is dropped quietly: the client sees it wasn't taken and snaps back.
static func place(c: Dictionary, cell: Vector2i) -> String:
	if int(c.ready) > 0:
		return ""
	var me: Dictionary = c.me
	var at := Mini.cell_of(me)
	if cell == at:
		return ""
	var d := cell - at
	if absi(d.x) + absi(d.y) != 1 or Mini.is_wall(c.rows, cell):
		return ""
	if not c.get("client", false):
		c.client = true
		me.acc = 1.0
	if float(me.acc) <= -1.0:
		return ""
	me.acc = float(me.acc) - 1.0
	for k in Mini.DIRS:
		if Mini.DIRS[k] == d:
			me.dir = k
	c.want = ""
	Mini.move_actor(c, me, cell)
	for f in c.foes:
		var f_now := Mini.cell_of(f)
		if f_now == cell or f_now == at:   # ran into them, or through them
			c.over = true
			c.won = c.game == "catch"
	return ""


## Which way the player wants to run next ("" to stop).
static func steer(c: Dictionary, dir: String) -> String:
	if dir != "" and not Mini.DIRS.has(dir):
		return "Pick a direction."
	c.want = dir
	if dir == "":
		c.me.dir = ""
	return ""


static func step(c: Dictionary, rng: RandomNumberGenerator) -> void:
	c.left = int(c.left) - 1
	var me: Dictionary = c.me
	var was := Mini.cell_of(me)
	if c.get("client", false):
		me.acc = minf(1.0, float(me.acc) + float(me.speed))
	else:
		_move_me(c)
	for i in c.foes.size():
		var f: Dictionary = c.foes[i]
		var f_was := Mini.cell_of(f)
		if c.game == "escape":
			_move_cop(c, i, rng)
		else:
			_move_runner(c, rng)
		var now := Mini.cell_of(me)
		var f_now := Mini.cell_of(f)
		# Caught: on the same square, or passing through each other.
		if now == f_now or (now == f_was and f_now == was):
			c.over = true
			c.won = c.game == "catch"
			return
	if int(c.left) <= 0:
		c.over = true
		c.won = c.game == "escape"


## A braided maze: a random spanning maze on a lattice of cells (odd coordinates), with every dead end
## knocked through and a few extra gaps, so there are always loops to run around and no traps.
static func maze(rng: RandomNumberGenerator) -> Array:
	var W := Mini.W
	var H := Mini.H
	var open := {}   # Vector2i -> true for floor cells
	var cw := (W - 1) / 2
	var ch := (H - 1) / 2
	var seen := {Vector2i(0, 0): true}
	var stack: Array = [Vector2i(0, 0)]
	open[Vector2i(1, 1)] = true
	while stack.size() > 0:
		var cur: Vector2i = stack.back()
		var next: Array = []
		for d in Mini.DIRS.values():
			var n: Vector2i = cur + d
			if n.x >= 0 and n.y >= 0 and n.x < cw and n.y < ch and not seen.has(n):
				next.append(n)
		if next.is_empty():
			stack.pop_back()
			continue
		var n2: Vector2i = next[rng.randi() % next.size()]
		seen[n2] = true
		open[n2 * 2 + Vector2i.ONE] = true
		open[cur + n2 + Vector2i.ONE] = true   # the wall between them
		stack.append(n2)
	# Knock through dead ends.
	for y in ch:
		for x in cw:
			var cell := Vector2i(x * 2 + 1, y * 2 + 1)
			var ways: Array = []
			var walls: Array = []
			for d in Mini.DIRS.values():
				var between: Vector2i = cell + d
				var beyond: Vector2i = cell + d * 2
				if beyond.x <= 0 or beyond.y <= 0 or beyond.x >= W - 1 or beyond.y >= H - 1:
					continue
				if open.has(between):
					ways.append(d)
				else:
					walls.append(between)
			if ways.size() <= 1 and walls.size() > 0:
				open[walls[rng.randi() % walls.size()]] = true
	# A few more gaps for extra routes.
	for i in 8:
		var wx := rng.randi_range(1, W - 2)
		var wy := rng.randi_range(1, H - 2)
		if (wx % 2) != (wy % 2):
			open[Vector2i(wx, wy)] = true
	var rows: Array = []
	for y in H:
		var r := ""
		for x in W:
			r += "." if open.has(Vector2i(x, y)) else "#"
		rows.append(r)
	return rows


# ------------------------------------------------------------------ movement

static func _move_me(c: Dictionary) -> void:
	var me: Dictionary = c.me
	me.acc = minf(1.0, float(me.acc) + float(me.speed))
	if float(me.acc) < 1.0:
		return
	var at := Mini.cell_of(me)
	var want: String = c.want
	if want != "" and not Mini.is_wall(c.rows, at + Mini.DIRS[want]):
		me.dir = want
	var dir: String = me.dir
	if dir == "" or Mini.is_wall(c.rows, at + Mini.DIRS[dir]):
		return   # wait at the wall, ready to go the moment a way opens
	me.acc = float(me.acc) - 1.0
	Mini.move_actor(c, me, at + Mini.DIRS[dir])


## Cops close in from different sides: one heads straight for you, one for where you're running to,
## one for where you came from, and one wanders in your general direction. Cops don't turn back
## unless they hit a dead end, and avoid bunching up on the same square.
static func _move_cop(c: Dictionary, i: int, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = c.foes[i]
	f.acc = float(f.acc) + float(f.speed)
	if float(f.acc) < 1.0:
		return
	f.acc = float(f.acc) - 1.0
	var me: Dictionary = c.me
	var you := Mini.cell_of(me)
	var target := you
	match i % 4:
		1:
			target = _walk(c.rows, you, me.dir, 4)
		2:
			target = _walk(c.rows, you, Mini.BACK[me.dir], 3)
		3:
			if rng.randf() < 0.3:
				target = Vector2i(rng.randi_range(1, Mini.W - 2), rng.randi_range(1, Mini.H - 2))
	var dist := Mini.distances(c.rows, _nearest_floor(c.rows, target))
	var at := Mini.cell_of(f)
	var best := ""
	var best_score := INF
	for d in exits(c.rows, at, f.dir, true):
		var n: Vector2i = at + Mini.DIRS[d]
		var score := float(dist.get(n, 999)) + rng.randf() * 0.5
		for j in c.foes.size():
			if j != i and int(c.foes[j].x) == n.x and int(c.foes[j].y) == n.y:
				score += 3.0
		if n == you:
			score = -1.0
		if score < best_score:
			best_score = score
			best = d
	if best != "":
		f.dir = best
		Mini.move_actor(c, f, at + Mini.DIRS[best])


## The runaway keeps as far from you as it can, with the odd panicked wrong turn.
static func _move_runner(c: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = c.foes[0]
	f.acc = float(f.acc) + float(f.speed)
	if float(f.acc) < 1.0:
		return
	f.acc = float(f.acc) - 1.0
	var dist := Mini.distances(c.rows, Mini.cell_of(c.me))
	var at := Mini.cell_of(f)
	var options := exits(c.rows, at, f.dir, false)
	if options.is_empty():
		return
	var best: String = options[rng.randi() % options.size()]
	if rng.randf() > 0.15:
		var best_d := -1.0
		for d in options:
			# Room to run matters too: prefer squares with more ways out.
			var n: Vector2i = at + Mini.DIRS[d]
			var score := float(dist.get(n, 0)) + 0.4 * exits(c.rows, n, d, false).size() + rng.randf() * 0.3
			if score > best_d:
				best_d = score
				best = d
	f.dir = best
	Mini.move_actor(c, f, at + Mini.DIRS[best])


## Open directions from `at`. With no_reverse, turning back is only allowed at a dead end.
static func exits(rows: Array, at: Vector2i, facing: String, no_reverse: bool) -> Array:
	var out: Array = []
	for d in Mini.DIRS:
		if not Mini.is_wall(rows, at + Mini.DIRS[d]) and not (no_reverse and d == Mini.BACK[facing]):
			out.append(d)
	if out.is_empty() and no_reverse and facing != "" and not Mini.is_wall(rows, at + Mini.DIRS[Mini.BACK[facing]]):
		out.append(Mini.BACK[facing])
	return out


## Up to n squares from `from` heading `dir`, stopping at walls.
static func _walk(rows: Array, from: Vector2i, dir: String, n: int) -> Vector2i:
	var at := from
	if dir == "":
		return at
	for i in n:
		if Mini.is_wall(rows, at + Mini.DIRS[dir]):
			break
		at += Mini.DIRS[dir]
	return at


static func _nearest_floor(rows: Array, cell: Vector2i) -> Vector2i:
	cell = Vector2i(clampi(cell.x, 1, Mini.W - 2), clampi(cell.y, 1, Mini.H - 2))
	if not Mini.is_wall(rows, cell):
		return cell
	for d in Mini.DIRS.values():
		if not Mini.is_wall(rows, cell + d):
			return cell + d
	return Vector2i(1, 1)
