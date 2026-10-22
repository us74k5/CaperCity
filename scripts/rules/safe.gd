class_name Safe
extends RefCounted
## Safe cracking (see Mini), as in the original: three dials of 0-9. Every click of a dial makes a
## tone; on the right number the tone is slightly different. Find all three before the alarm goes.
## The combination never goes into the game state (everyone receives that); the server keeps it and
## passes it in. The state only says whether the current click sounded "odd".

const KEYS := 10


static func create(level: int) -> Dictionary:
	var secs := clampf(12.0 - 0.5 * level, 8.0, 12.0)   # the original gave about eight seconds
	return {"dials": [0, 0, 0], "cur": 0, "odd": false, "clicks": 0, "left": int(secs / Mini.TICK)}


## A fresh secret combination.
static func code(rng: RandomNumberGenerator) -> Array:
	return [rng.randi() % KEYS, rng.randi() % KEYS, rng.randi() % KEYS]


## Turn the current dial by `by` (+1 / -1), or pick dial `pick` (0..2).
static func input(m: Dictionary, intent: Dictionary, secret: Array) -> String:
	if m.over:
		return "It's over."
	if int(m.ready) > 0:
		return ""
	if intent.has("pick"):
		var i := int(intent.pick)
		if i < 0 or i > 2:
			return "Pick dial 1, 2 or 3."
		m.cur = i
	elif intent.has("turn"):
		var by := signi(int(intent.turn))
		var dials: Array = m.dials
		dials[int(m.cur)] = posmod(int(dials[int(m.cur)]) + by, KEYS)
		m.clicks = int(m.clicks) + 1
	else:
		return "Turn a dial."
	m.odd = int(m.dials[int(m.cur)]) == int(secret[int(m.cur)])
	if m.dials == secret:
		m.over = true
		m.won = true
	return ""


static func step(m: Dictionary) -> void:
	m.left = int(m.left) - 1
	if int(m.left) <= 0:
		m.over = true
		m.won = false   # the alarm
