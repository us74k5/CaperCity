class_name Fight
## Turn-based street fight on a small grid, as in the 1993 reference game: the attacker's men start
## on the left, the enemy's on the right. Sides take turns; on its side's turn each man acts once,
## either stepping one square (8 directions) or attacking in a straight line. A shot or blow travels
## up to the weapon's reach and stops at the first man in its path, friend or foe, so men in front
## shield the men behind. A man at 0 energy is out. The fight ends when one side has nobody standing.
##
## The fight is a plain Dictionary (lives in the game state, so spectators see it). Side 0 is the
## active player; side 1 is played by the AI. Every change is appended to `events` so clients can
## animate the moves in order.

const W := 12
const H := 8
const MAX_ROUNDS := 40
const DIRS8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const KEEP_EVENTS := 60

## Who you can end up fighting. low = their weapon when weak; power (see squad()) sets their numbers and kit.
const FOES := {
	"police": {"name": "Officer", "look": "cop", "low": 2},
	"guard": {"name": "Guard", "look": "guard", "low": 2},
	"bodyguard": {"name": "Bodyguard", "look": "thug", "low": 3},
	"staff": {"name": "Staff", "look": "civilian", "low": 1},
}


static func unit(uname: String, side: int, gear: int, hp: int, max_hp: int, muscle: int, smarts: int, look: String,
		owner: int = 0, crew_index: int = -1) -> Dictionary:
	return {"name": uname, "side": side, "gear": gear, "hp": maxi(1, hp), "max": maxi(1, max_hp), "muscle": muscle,
		"smarts": smarts, "look": look, "owner": owner, "ci": crew_index, "x": 0, "y": 0, "acted": false}


## A player's crew as fighters. Energy (stamina) is their hit points.
static func crew_units(p: Dictionary, side: int) -> Array:
	var out: Array = []
	for i in p.crew.size():
		var m: Dictionary = p.crew[i]
		out.append(unit(m.name, side, int(m.gear), int(m.stamina), Balance.STAMINA_CAP, int(m.muscle), int(m.smarts), "crew", int(p.id), i))
	return out


## An enemy squad sized and armed from `power` (about 3 for a shop owner up to 20+ for a SWAT-sized response).
static func squad(kind: String, power: int, rng: RandomNumberGenerator, count: int = -1) -> Array:
	var foe: Dictionary = FOES[kind]
	if count < 0:
		count = clampi(1 + power / 4, 1, 6)
	var gear: int = foe.low       # batons for beat cops, clubs for shop staff
	if power >= 14:
		gear = 7
	elif power >= 10:
		gear = 6
	elif power >= 6:
		gear = 5
	var hp := clampi(12 + power * 2, 14, 45)
	var out: Array = []
	for i in count:
		# Every squad has a couple of lighter-armed men, so they don't all hit like the leader.
		var g := gear if i < 2 or rng.randf() < 0.5 else maxi(1, gear - 2)
		out.append(unit("%s %d" % [foe.name, i + 1], 1, g, hp, hp, 30 + power * 3, 30 + power * 3, foe.look))
	return out


static func create(title: String, mine: Array, theirs: Array, then: Dictionary, lethal: bool) -> Dictionary:
	var units: Array = []
	for side in 2:
		var group: Array = mine if side == 0 else theirs
		for i in group.size():
			var u: Dictionary = group[i]
			u.id = units.size()
			# Two columns per side (front and back), filling from the middle rows outward.
			u.x = (1 if i % 2 == 0 else 0) if side == 0 else (W - 2 if i % 2 == 0 else W - 1)
			u.y = clampi(H / 2 + _spread(i / 2), 0, H - 1)
			units.append(u)
	var f := {"title": title, "w": W, "h": H, "units": units, "side": 0, "round": 1, "cur": -1,
		"events": [], "seq": 0, "over": false, "won": false, "surrendered": false, "then": then, "lethal": lethal}
	_next(f)
	return f


static func _spread(i: int) -> int:
	# 0, -1, 1, -2, 2, ... so the men line up around the middle row.
	return (i + 1) / 2 * (1 if i % 2 == 0 else -1)


# ------------------------------------------------------------------ player actions

## The current man acts toward `cell`: an empty square next to him = step there; anything else in a
## straight line (or an occupied square next to him) = attack in that direction. Returns "" or an error.
static func act_toward(f: Dictionary, cell: Vector2i, rng: RandomNumberGenerator) -> String:
	if f.over or int(f.side) != 0 or int(f.cur) < 0:
		return "Not your move."
	var u: Dictionary = f.units[int(f.cur)]
	var d := cell - Vector2i(int(u.x), int(u.y))
	if d == Vector2i.ZERO:
		return "Pick a square next to them, or a target in a straight line."
	var near := maxi(absi(d.x), absi(d.y)) == 1
	if near and _inside(cell) and _at(f, cell).is_empty():
		_move(f, u, d)
	elif d.x == 0 or d.y == 0 or absi(d.x) == absi(d.y):
		_attack(f, u, Vector2i(signi(d.x), signi(d.y)), rng)
	else:
		return "Attacks only go in straight lines (across or diagonal)."
	_done(f, u, rng)
	return ""


static func wait(f: Dictionary, rng: RandomNumberGenerator) -> String:
	if f.over or int(f.side) != 0 or int(f.cur) < 0:
		return "Not your move."
	var u: Dictionary = f.units[int(f.cur)]
	_event(f, {"k": "wait", "a": u.id})
	_done(f, u, rng)
	return ""


## Lets the AI play your side too until the fight is over.
static func auto(f: Dictionary, rng: RandomNumberGenerator) -> void:
	while not f.over:
		if int(f.side) == 0 and int(f.cur) >= 0:
			var u: Dictionary = f.units[int(f.cur)]
			_ai_act(f, u, rng)
			_done(f, u, rng)
		else:
			break


static func surrender(f: Dictionary) -> void:
	f.over = true
	f.won = false
	f.surrendered = true
	f.cur = -1


# ------------------------------------------------------------------ turn flow

static func _done(f: Dictionary, u: Dictionary, rng: RandomNumberGenerator) -> void:
	u.acted = true
	if _check_end(f):
		return
	_next(f)
	if int(f.side) == 1:
		for e in f.units:
			if int(e.side) == 1 and int(e.hp) > 0 and not e.acted:
				_ai_act(f, e, rng)
				e.acted = true
				if _check_end(f):
					return
		_new_round(f)


static func _new_round(f: Dictionary) -> void:
	f.round = int(f.round) + 1
	if int(f.round) > MAX_ROUNDS:
		# Nobody wins a stand-off in the street; the other side's backup arrives.
		_event(f, {"k": "backup"})
		f.over = true
		f.won = false
		f.cur = -1
		return
	for e in f.units:
		e.acted = false
	f.side = 0
	_next(f)


## Points `cur` at the next man of the side to move, or switches sides when they've all acted.
static func _next(f: Dictionary) -> void:
	for e in f.units:
		if int(e.side) == int(f.side) and int(e.hp) > 0 and not e.acted:
			f.cur = e.id
			return
	if int(f.side) == 0:
		f.side = 1
		f.cur = -1
	else:
		_new_round(f)


static func _check_end(f: Dictionary) -> bool:
	var alive := [0, 0]
	for e in f.units:
		if int(e.hp) > 0:
			alive[int(e.side)] += 1
	if alive[0] > 0 and alive[1] > 0:
		return false
	f.over = true
	f.won = alive[0] > 0
	f.cur = -1
	return true


# ------------------------------------------------------------------ moves and attacks

static func _move(f: Dictionary, u: Dictionary, d: Vector2i) -> void:
	var from := [int(u.x), int(u.y)]
	u.x = int(u.x) + d.x
	u.y = int(u.y) + d.y
	_event(f, {"k": "move", "a": u.id, "from": from, "to": [u.x, u.y]})


static func _attack(f: Dictionary, u: Dictionary, d: Vector2i, rng: RandomNumberGenerator) -> void:
	var g: Dictionary = Balance.GEAR[int(u.gear)]
	var pos := Vector2i(int(u.x), int(u.y))
	var end := pos
	var target: Dictionary = {}
	var dist := 0
	for step in range(1, int(g.reach) + 1):
		var c := pos + d * step
		if not _inside(c):
			break
		end = c
		target = _at(f, c)
		if not target.is_empty():
			dist = step
			break
	var ev := {"k": "attack", "a": u.id, "from": [pos.x, pos.y], "to": [end.x, end.y], "melee": int(g.reach) == 1,
		"t": -1, "dmg": 0, "down": false}
	if not target.is_empty():
		ev.t = target.id
		var aim: float = float(g.aim) + (int(u.smarts) - 40) / 400.0 - 0.03 * (dist - 1)
		if rng.randf() < clampf(aim, 0.05, 0.97):
			var dmg := rng.randi_range(int(g.power), int(g.power) * 2)
			if int(g.reach) == 1:
				dmg += int(u.muscle) / 25
			target.hp = maxi(0, int(target.hp) - dmg)
			ev.dmg = dmg
			ev.down = int(target.hp) == 0
	_event(f, ev)


static func _ai_act(f: Dictionary, u: Dictionary, rng: RandomNumberGenerator) -> void:
	var g: Dictionary = Balance.GEAR[int(u.gear)]
	var pos := Vector2i(int(u.x), int(u.y))
	# Shoot the weakest enemy that's first in line within reach.
	var best_dir := Vector2i.ZERO
	var best_hp := 1 << 30
	for d in DIRS8:
		for step in range(1, int(g.reach) + 1):
			var c: Vector2i = pos + d * step
			if not _inside(c):
				break
			var t := _at(f, c)
			if t.is_empty():
				continue
			if int(t.side) != int(u.side) and int(t.hp) < best_hp:
				best_hp = int(t.hp)
				best_dir = d
			break
	if best_dir != Vector2i.ZERO:
		_attack(f, u, best_dir, rng)
		return
	# Otherwise close in on the nearest enemy, preferring squares that line up a shot.
	var best_step := Vector2i.ZERO
	var best_score := _score(f, u, pos)
	for d in DIRS8:
		var c: Vector2i = pos + d
		if not _inside(c) or not _at(f, c).is_empty():
			continue
		var s := _score(f, u, c) + rng.randf() * 0.1
		if s < best_score:
			best_score = s
			best_step = d
	if best_step != Vector2i.ZERO:
		_move(f, u, best_step)
	else:
		_event(f, {"k": "wait", "a": u.id})


## Lower is better: distance to the nearest enemy, minus a bonus for being lined up within reach.
static func _score(f: Dictionary, u: Dictionary, c: Vector2i) -> float:
	var reach: int = Balance.GEAR[int(u.gear)].reach
	var best := 999.0
	for e in f.units:
		if int(e.side) == int(u.side) or int(e.hp) <= 0:
			continue
		var d := Vector2i(int(e.x), int(e.y)) - c
		var dist := maxi(absi(d.x), absi(d.y))
		var s := float(dist)
		if (d.x == 0 or d.y == 0 or absi(d.x) == absi(d.y)) and dist <= reach:
			s -= 0.5
		best = minf(best, s)
	return best


# ------------------------------------------------------------------ helpers

static func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


static func _at(f: Dictionary, c: Vector2i) -> Dictionary:
	for e in f.units:
		if int(e.hp) > 0 and int(e.x) == c.x and int(e.y) == c.y:
			return e
	return {}


static func _event(f: Dictionary, ev: Dictionary) -> void:
	f.seq = int(f.seq) + 1
	ev.n = f.seq
	f.events.append(ev)
	if f.events.size() > KEEP_EVENTS:
		f.events = f.events.slice(f.events.size() - KEEP_EVENTS)


## Squares the current man can act on: {"move": [...], "attack": [...]} (attack = enemies in reach and in line).
static func options(f: Dictionary) -> Dictionary:
	var out := {"move": [], "attack": []}
	if f.over or int(f.cur) < 0:
		return out
	var u: Dictionary = f.units[int(f.cur)]
	var pos := Vector2i(int(u.x), int(u.y))
	var reach: int = Balance.GEAR[int(u.gear)].reach
	for d in DIRS8:
		var c: Vector2i = pos + d
		if _inside(c) and _at(f, c).is_empty():
			out.move.append(c)
		for step in range(1, reach + 1):
			var c2: Vector2i = pos + d * step
			if not _inside(c2):
				break
			var t := _at(f, c2)
			if not t.is_empty():
				if int(t.side) != int(u.side):
					out.attack.append(c2)
				break
	return out
