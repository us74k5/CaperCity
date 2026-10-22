class_name Mini
extends RefCounted
## Real-time minigames, as in the original. The server steps them at a fixed tick (Net drives
## GameServer.tick) and players only send inputs, so everyone watches the same game.
## Each game is a plain Dictionary in state.mini with a "game" key:
##   escape, catch          -> Chase  (run from the cops / catch the runaway)
##   sneak                  -> Sneak  (reach the door without a guard seeing you)
##   loot, containers, train -> Push  (push goods onto the marked squares; stop the mail train)
##   safe                   -> Safe   (three dials; listen for the odd tone)
## Grid games share a W x H grid of rows ('#' wall, '.' floor, plus per-game marks) and these helpers.
## Levels are made by our own generators, never the original's.

const W := 25
const H := 17
const TICK := 0.05
const READY_TICKS := 40          # 2 s of "get ready" before anything moves
const DIRS := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
const BACK := {"N": "S", "S": "N", "E": "W", "W": "E", "": ""}
const GRID_GAMES := ["escape", "catch", "sneak", "loot", "containers", "train"]


## A new game. `level` 0..8 sets the difficulty; `then` says what happens after (the server's business).
static func create(game: String, title: String, level: int, rng: RandomNumberGenerator, then: Dictionary) -> Dictionary:
	var m: Dictionary
	match game:
		"escape", "catch":
			m = Chase.create(game, level, rng)
		"sneak":
			m = Sneak.create(level, rng)
		"loot", "containers", "train":
			m = Push.create(game, level, rng)
		"safe":
			m = Safe.create(level)
	m.game = game
	m.title = title
	m.then = then
	m.level = level
	m.tick = 0
	m.over = false
	m.won = false
	m.gave_up = false
	if not m.has("ready"):
		m.ready = READY_TICKS
	m.total = int(m.left)
	return m


## A player input: {"dir": "N"} for the grid games, {"turn": 1}/{"dial": i} for the safe.
static func input(m: Dictionary, intent: Dictionary) -> String:
	if m.over:
		return "It's over."
	match str(m.game):
		"escape", "catch":
			return Chase.steer(m, str(intent.get("dir", "")))
		"sneak", "loot", "containers", "train":
			return queue_step(m, str(intent.get("dir", "")))
	return "Not for this game."


## One tick of the simulation.
static func step(m: Dictionary, rng: RandomNumberGenerator) -> void:
	if m.over:
		return
	m.tick = int(m.tick) + 1
	if int(m.ready) > 0:
		m.ready = int(m.ready) - 1
		return
	match str(m.game):
		"escape", "catch":
			Chase.step(m, rng)
		"sneak":
			Sneak.step(m)
		"loot", "containers", "train":
			Push.step(m)
		"safe":
			Safe.step(m)


## Give up / bail out. Most games count it as a loss; for the train it calls the train in early.
static func give_up(m: Dictionary) -> void:
	if m.game == "train" and m.get("phase", "") == "push":
		Push.call_train(m)
		return
	m.over = true
	m.won = false
	m.gave_up = true


static func seconds_left(m: Dictionary) -> float:
	return int(m.left) * TICK


static func is_grid(m: Dictionary) -> bool:
	return str(m.get("game", "")) in GRID_GAMES


# ------------------------------------------------------------------ shared grid helpers

static func is_wall(rows: Array, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return true
	return (rows[cell.y] as String)[cell.x] == "#"


static func mark(rows: Array, cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
		return "#"
	return (rows[cell.y] as String)[cell.x]


## Steps from `from` to every floor square (`blocked` squares, e.g. crates, count as walls).
static func distances(rows: Array, from: Vector2i, blocked := {}) -> Dictionary:
	var dist := {from: 0}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in DIRS.values():
			var n: Vector2i = cur + d
			if not dist.has(n) and not is_wall(rows, n) and not blocked.has(n):
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	return dist


static func actor(cell: Vector2i, speed: float) -> Dictionary:
	return {"x": cell.x, "y": cell.y, "px": cell.x, "py": cell.y, "mt": 0, "dir": "", "acc": 0.0, "speed": speed}


static func move_actor(m: Dictionary, a: Dictionary, cell: Vector2i) -> void:
	a.px = int(a.x)
	a.py = int(a.y)
	a.x = cell.x
	a.y = cell.y
	a.mt = int(m.tick)


static func cell_of(a: Dictionary) -> Vector2i:
	return Vector2i(int(a.x), int(a.y))


## Step-by-step games: each press queues one step (holding a key repeats it). Up to two are queued
## so quick taps aren't lost, but you never slide further than you meant to.
static func queue_step(m: Dictionary, dir: String) -> String:
	if dir == "":
		m.queue = []
		return ""
	if not DIRS.has(dir):
		return "Pick a direction."
	if m.queue.size() < 2:
		m.queue.append(dir)
	return ""


## Takes the next queued step if the player's legs are ready. Returns the direction or "".
static func next_step(m: Dictionary) -> String:
	var me: Dictionary = m.me
	me.acc = minf(1.0, float(me.acc) + float(me.speed))
	if float(me.acc) < 1.0 or m.queue.is_empty():
		return ""
	me.acc = float(me.acc) - 1.0
	var d: String = m.queue.pop_front()
	me.dir = d
	return d
