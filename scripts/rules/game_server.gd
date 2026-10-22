class_name GameServer
extends RefCounted
## Authoritative game rules. Owns the state; turns intents into state changes.
## No networking or rendering here: the server and tests drive it directly.
##
## Intents are Dictionaries with a "t" key (see handle()). The whole state is a plain
## Dictionary so it can be sent over the network and saved as-is.

const DIRS := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
const BLACKMAIL_TYPES := ["car_dealer", "casino", "bank", "dept_store", "villa", "city_hall", "police"]

var state: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _tokens := {}   # pid -> the device token that may reclaim that crew (kept out of the broadcast state)
var stale_peers: Array = []   # connections a returning device replaced; the network layer closes them


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) ^ randi()
	rng.seed = seed_value
	state = {
		"phase": "lobby", "seed": seed_value, "month": 1, "target": 35,
		"players": {}, "order": [], "active": 0, "next_pid": 1,
		"room_host": 0, "city": CityGen.generate(seed_value),
		"log": [], "pending": {}, "fight": {}, "mini": {}, "winner": 0, "rev": 0,
	}
	_init_buildings()


# --------------------------------------------------------------------------- intents

## Returns "" on success or an error message.
func handle(peer: int, intent: Dictionary) -> String:
	var t: String = str(intent.get("t", ""))
	var err := ""
	match t:
		"join":
			err = _join(peer, str(intent.get("name", "")), str(intent.get("crew", "")), false, str(intent.get("token", "")))
		"add_local":
			if peer != state.room_host:
				return "Only the room host can add local players."
			err = _join(peer, str(intent.get("name", "")), str(intent.get("crew", "")), true)
		"start":
			if peer != state.room_host:
				return "Only the room host can start."
			err = _start(int(intent.get("target", 35)))
		"skip":
			if peer != state.room_host:
				return "Only the room host can skip a turn."
			skip_turn("by the host")
		"avatar", "roll", "ready":
			var me := _creating(peer)
			if me.is_empty():
				return "Your boss is already on the streets."
			err = _create_step(me, t, intent)
		_:
			if state.phase != "playing":
				return "The game is not running."
			var p := _active()
			if int(p.owner) != peer:
				return "It's not your turn."
			err = _handle_turn(p, t, intent)
	state.rev = int(state.rev) + 1
	return err


## Ends the active player's turn from outside it (they're gone, or stuck).
func skip_turn(why: String) -> void:
	if state.phase != "playing":
		return
	_log("%s's turn was skipped %s." % [_active().name, why], "info")
	state.pending = {}
	state.fight = {}
	state.mini = {}
	_end_turn()
	state.rev = int(state.rev) + 1


## Advances a running minigame in real time. Returns 0 if nothing changed, 1 if only the minigame
## moved (send just that), or 2 if it ended and the whole state changed.
var _mini_clock := 0.0
var _safe_secret: Array = []     # the safe's combination stays here, out of the broadcast state


func tick(delta: float) -> int:
	var m: Dictionary = state.get("mini", {})
	if m.is_empty() or m.over or state.phase != "playing":
		_mini_clock = 0.0
		return 0
	_mini_clock += minf(delta, 0.25)
	var stepped := false
	while _mini_clock >= Mini.TICK and not m.over:
		_mini_clock -= Mini.TICK
		Mini.step(m, rng)
		stepped = true
	if m.over:
		_end_mini(_active())
		state.rev = int(state.rev) + 1
		return 2
	return 1 if stepped else 0


func _handle_turn(p: Dictionary, t: String, intent: Dictionary) -> String:
	if t == "mini" and state.pending.get("kind", "") == "mini":
		var m: Dictionary = state.mini
		var err := Safe.input(m, intent, _safe_secret) if m.game == "safe" else Mini.input(m, intent)
		if m.over:
			_end_mini(p)
		return err
	if not state.pending.is_empty() and t != "pending" and not (t == "fight" and state.pending.kind == "fight"):
		return "Answer the prompt first."
	match t:
		"move":
			return _move(p, str(intent.get("dir", "")))
		"menu":
			return _menu_choose(p, str(intent.get("id", "")))
		"pending":
			return _pending_choose(p, str(intent.get("id", "")))
		"gang_war":
			return _gang_war(p, int(intent.get("target", 0)))
		"fight":
			return _fight_intent(p, intent)
		"end_turn":
			if int(p.inside) >= 0:
				_leave(p)
			_end_turn()
			return ""
	return "Unknown action."


# --------------------------------------------------------------------------- lobby

## Joins the room. During a game a newcomer gets a fresh crew at the back of the turn order, and a
## device coming back (same token) takes over the crew it left behind.
func _join(peer: int, pname: String, crew: String, local: bool, token: String = "") -> String:
	if not local:
		for pid in state.players:
			if int(state.players[pid].owner) == peer and not state.players[pid].local:
				return ""
	if state.phase == "over":
		return "This game is over. The room host can start a new one."
	if local and state.phase != "lobby":
		return "The game has already started."
	if state.phase == "playing" and token != "":
		for pid in state.players:
			var old: Dictionary = state.players[pid]
			if not old.local and _tokens.get(pid, "") == token:
				if old.connected:
					stale_peers.append(int(old.owner))   # its old connection died without closing
					if int(state.room_host) == int(old.owner):
						state.room_host = peer
				old.owner = peer
				old.connected = true
				if state.room_host == 0:
					state.room_host = peer
				_log("%s is back." % old.name, "info")
				return ""
	if state.players.size() >= 6:
		return "The room is full."
	if state.room_host == 0:
		state.room_host = peer
	var pid: int = state.next_pid
	state.next_pid = pid + 1
	pname = pname.strip_edges().left(16)
	if pname == "":
		pname = "Player %d" % pid
	crew = crew.strip_edges().left(24)
	if crew == "":
		crew = "The %s Crew" % pname
	var boss := _new_member(pname, true)
	state.players[pid] = {
		"id": pid, "owner": peer, "local": local, "name": pname, "crew_name": crew,
		"color": Balance.PLAYER_COLORS[(pid - 1) % Balance.PLAYER_COLORS.size()],
		"cash": rng.randi_range(Balance.START_CASH[0], Balance.START_CASH[1]), "points": 0,
		"crew": [boss], "car": 0, "pos": [0, 0], "steps": 0, "steps_max": Balance.CARS[0].steps,
		"inside": -1, "menu_path": [], "menu": [], "half_step": false, "stopped": false,
		"jail": 0, "holiday": 0, "room": false, "rent_paid": 0,
		"loan": 0, "loan_months": 0, "passport": false, "immunity": 0, "heat": 0, "scenes": [], "new_scene": "", "news": "", "clean": false, "car_stolen": false,
		"radios": 0, "electronics": 0, "dirt": "", "hostage": {}, "ransom": {}, "suitcase": {},
		"gang_war_used": false, "connected": true,
		# Character creation (see _create_step): local seats skip it.
		"avatar": "", "ready": false, "rolls": {}, "rerolls": Balance.REROLLS,
	}
	if local:
		_auto_create(state.players[pid])
	if token != "":
		_tokens[pid] = token
	if state.phase == "playing":
		var cells := _road_cells_near_center()
		state.players[pid].pos = cells[state.order.size() % cells.size()]
		state.order.append(pid)
		_log("%s joins the game with %s." % [pname, crew], "big")
		return ""
	_log("%s joined with %s." % [pname, crew], "info")
	return ""


func _start(target: int) -> String:
	if state.phase != "lobby":
		return "Already started."
	if state.players.is_empty():
		return "Nobody has joined."
	state.target = clampi(target, 5, 200)
	for pid in state.players:
		if not state.players[pid].ready:
			_auto_create(state.players[pid])   # whatever they haven't picked or rolled yet is picked for them
	var order: Array = state.players.keys()
	_shuffle(order)
	state.order = order
	var start_cells := _road_cells_near_center()
	for i in order.size():
		var p: Dictionary = state.players[order[i]]
		p.pos = start_cells[i % start_cells.size()]
	state.phase = "playing"
	state.active = 0
	_log("The game is on! First to %d points becomes Boss of Caper City." % state.target, "big")
	_begin_turn()
	return ""


func set_connected(peer: int, connected: bool) -> void:
	for pid in state.players:
		var p: Dictionary = state.players[pid]
		if int(p.owner) == peer:
			p.connected = connected
	if state.phase == "lobby" and not connected:
		for pid in state.players.keys():
			if int(state.players[pid].owner) == peer:
				state.players.erase(pid)
	if peer == state.room_host and not connected:
		# Hand the room to someone still here, so a game can still be started or a turn skipped.
		state.room_host = 0
		for pid in state.players:
			if state.players[pid].connected:
				state.room_host = int(state.players[pid].owner)
				break
	state.rev = int(state.rev) + 1


# --------------------------------------------------------------------------- character creation

## The player `peer` is still creating, if any.
func _creating(peer: int) -> Dictionary:
	for pid in state.players:
		var p: Dictionary = state.players[pid]
		if int(p.owner) == peer and not p.local and not p.ready:
			return p
	return {}


## Picking a character, rolling a stat (once each, then re-rolls from a small pool), or done.
func _create_step(p: Dictionary, t: String, intent: Dictionary) -> String:
	match t:
		"avatar":
			var id := str(intent.get("id", ""))
			if not Balance.AVATARS.any(func(a): return a.id == id):
				return "Unknown character."
			for pid in state.players:
				var other: Dictionary = state.players[pid]
				if other.id != p.id and other.avatar == id:
					return "%s already picked that one." % other.name
			p.avatar = id
		"roll":
			var stat := str(intent.get("stat", ""))
			if not Balance.ROLL_STATS.has(stat):
				return "Unknown stat."
			var n := int(p.rolls.get(stat, 0))
			if n > 0:
				if int(p.rerolls) <= 0:
					return "No re-rolls left."
				p.rerolls = int(p.rerolls) - 1
			p.rolls[stat] = n + 1
			var r: Array = Balance.ROLL_STATS[stat].range
			var v := rng.randi_range(int(r[0]), int(r[1]))
			if stat == "cash":
				p.cash = v / 50 * 50
			else:
				p.crew[0][stat] = v
		"ready":
			if p.avatar == "":
				return "Pick your character first."
			for stat in Balance.ROLL_STATS:
				if not p.rolls.has(stat):
					return "Roll your %s first." % Balance.ROLL_STATS[stat].label
			p.ready = true
			_log("%s hits the streets." % p.name if state.phase == "playing" else "%s is ready." % p.name, "info")
	return ""


## Finishes a character for someone who didn't: a free avatar, and the stats they haven't rolled
## keep the random values they were given on joining.
func _auto_create(p: Dictionary) -> void:
	if p.avatar == "":
		var taken: Array = state.players.values().map(func(o): return o.avatar)
		for a in Balance.AVATARS:
			if not a.id in taken:
				p.avatar = a.id
				break
	for stat in Balance.ROLL_STATS:
		if not p.rolls.has(stat):
			p.rolls[stat] = 1
	p.ready = true


func _anyone_ready() -> bool:
	return state.players.values().any(func(o): return o.ready)


# --------------------------------------------------------------------------- turns & months

func _active() -> Dictionary:
	if state.order.is_empty():
		return {}
	return state.players[state.order[state.active]]


func _begin_turn() -> void:
	# Skips players in jail or on holiday; may run several month-ends if nobody can act.
	var guard := 0
	while guard < 50:
		guard += 1
		var p := _active()
		if not p.get("ready", true) and _anyone_ready():
			_advance_index()   # still creating their boss (joined mid-game)
			continue
		if int(p.jail) > 0:
			p.jail = int(p.jail) - 1
			if int(p.jail) == 0:
				_log("%s serves the last month in jail." % p.name, "info")
			else:
				_log("%s sits in jail (%d more month%s)." % [p.name, p.jail, "" if p.jail == 1 else "s"], "info")
			_advance_index()
			continue
		if int(p.holiday) > 0:
			p.holiday = int(p.holiday) - 1
			for m in p.crew:
				m.stamina = mini(int(m.stamina) + 8, Balance.STAMINA_CAP_HOLIDAY)
				for s in ["muscle", "smarts", "nerve"]:
					m[s] = mini(int(m[s]) + int(p.get("holiday_boost", 2)), 99)
			_log("%s is on holiday%s." % [p.name, "" if p.holiday == 0 else " (%d more)" % p.holiday], "info")
			_advance_index()
			continue
		p.steps_max = Balance.CARS[int(p.car)].steps
		p.steps = p.steps_max
		p.half_step = false
		p.stopped = false
		p.gang_war_used = false
		p.inside = -1
		p.menu_path = []
		_log("Month %d: %s's turn." % [state.month, p.name], "turn")
		_refresh_menu(p)
		if int(p.loan) > 0 and int(p.loan_months) == 1 and str(p.get("news", "")) == "":
			p.news = "Easy Eddie's loan is due at the end of this month: $%d. Pay it at a loan shark, or the collectors take your cash, your car and then you." % p.loan
		if str(p.get("news", "")) != "":
			_result(p, "Easy Eddie" if p.news.begins_with("Easy Eddie's loan") else "While you were away", p.news, false)
			p.news = ""
		return


func _advance_index() -> void:
	state.active = int(state.active) + 1
	if state.active >= state.order.size():
		state.active = 0
		_end_month()


func _end_turn() -> void:
	var p := _active()
	p.inside = -1
	p.menu_path = []
	p.menu = []
	if state.phase != "playing":
		return
	_advance_index()
	if state.phase == "playing":
		_begin_turn()


func _end_month() -> void:
	state.month = int(state.month) + 1
	_log("— Month %d begins —" % state.month, "big")
	for pid in state.order:
		var p: Dictionary = state.players[pid]
		for m in p.crew:
			var cap: int = Balance.STAMINA_CAP_HOLIDAY if int(p.holiday) > 0 else Balance.STAMINA_CAP
			m.stamina = mini(int(m.stamina) + 4 + int(m.muscle) / 12, maxi(cap, int(m.stamina)))
		p.heat = maxi(0, int(p.heat) - 2)
		if int(p.immunity) > 0:
			p.immunity = int(p.immunity) - 1
		if p.room:
			p.rent_paid = int(p.rent_paid) - 1
			if int(p.rent_paid) < 0:
				p.room = false
				p.rent_paid = 0
				_log("%s didn't pay the rent and got thrown out of the hotel room." % p.name, "bad")
		if int(p.loan) > 0:
			p.loan = int(ceil(float(p.loan) * (1.0 + Balance.LOAN_RATE)))
			p.loan_months = int(p.loan_months) - 1
			if int(p.loan_months) <= 0:
				_collect_loan(p)
		if not p.ransom.is_empty():
			p.ransom.months = int(p.ransom.months) - 1
			if int(p.ransom.months) <= 0:
				_log("%s never picked up the ransom. The deal is off." % p.name, "bad")
				p.ransom = {}
				p.hostage = {}
	# Protection money and fresh stock.
	for b in state.city.buildings:
		if int(b.get("protector", 0)) > 0 and state.players.has(int(b.protector)):
			var owner_p: Dictionary = state.players[int(b.protector)]
			owner_p.cash = int(owner_p.cash) + 300
		_restock(b)


func _collect_loan(p: Dictionary) -> void:
	var debt: int = p.loan
	var take := mini(debt, int(p.cash))
	p.cash = int(p.cash) - take
	debt -= take
	var msg := "Easy Eddie's collectors came for %s and took $%d" % [p.name, take]
	if debt > 0 and int(p.car) > 0:
		var car_value: int = Balance.CARS[int(p.car)].price / 2
		msg += ", plus the %s" % Balance.CARS[int(p.car)].name
		debt = maxi(0, debt - car_value)
		p.car = 0
	if debt > 0:
		var months := mini(1 + debt / 10000, 2)
		msg += ". Still short, so they handed %s to the cops for %d month%s. %s" % [p.name, months, "" if months == 1 else "s", _jail(p, months)]
	p.loan = 0
	p.loan_months = 0
	msg = msg.strip_edges()
	if not msg.ends_with("."):
		msg += "."
	_log(msg, "bad")
	p.news = msg


# --------------------------------------------------------------------------- movement

func _move(p: Dictionary, dir: String) -> String:
	if not DIRS.has(dir):
		return "Bad direction."
	if int(p.inside) >= 0:
		return "Leave the building first."
	if int(p.steps) <= 0:
		return "No steps left."
	var d: Vector2i = DIRS[dir]
	var nx: int = int(p.pos[0]) + d.x
	var ny: int = int(p.pos[1]) + d.y
	var city: Dictionary = state.city
	if nx < 0 or ny < 0 or nx >= city.w or ny >= city.h:
		return "Edge of town."
	var cost := CityGen.step_cost(city, Vector2i(int(p.pos[0]), int(p.pos[1])), dir, int(p.car) > 0)
	match cost:
		CityGen.NEEDS_CAR:
			return "The motorway is for cars only."
		CityGen.ONE_WAY:
			return "Wrong way: each motorway lane runs one way. Turn at the next exit."
		CityGen.BLOCKED:
			return "You can't go that way."
	_spend_step(p, cost)
	if city.grid[ny * city.w + nx] == CityGen.BUILDING:
		_enter(p, _building_at(nx, ny))
		return ""
	p.pos = [nx, ny]
	_maybe_police_check(p)
	_after_action(p)
	return ""


## A step costs 2 halves on the street and 1 on the motorway; half steps are banked until there are two.
func _spend_step(p: Dictionary, halves: int) -> void:
	if halves >= 2:
		p.steps = int(p.steps) - 1
	elif p.get("half_step", false):
		p.steps = int(p.steps) - 1
		p.half_step = false
	else:
		p.half_step = true


func _enter(p: Dictionary, b: Dictionary) -> void:
	p.inside = int(b.id)
	p.menu_path = []
	_log("%s walks into %s." % [p.name, b.name], "move")
	if _back_at_scene(p, b):
		_after_action(p)
		return
	# Ransom pickup happens on arrival.
	if not p.ransom.is_empty() and int(p.ransom.building) == int(b.id):
		_ransom_pickup(p)
	_refresh_menu(p)
	_after_action(p)


func _leave(p: Dictionary) -> void:
	p.inside = -1
	p.menu_path = []
	p.menu = []


func _after_action(p: Dictionary) -> void:
	if state.phase != "playing":
		return
	if state.pending.is_empty():
		state.fight = {}   # e.g. a won kidnapping fight followed by the ransom prompt
		state.mini = {}
	_check_win(p)
	if state.phase != "playing":
		return
	if state.pending.is_empty() and (int(p.steps) <= 0 or int(p.jail) > 0):
		if int(p.jail) == 0:
			_log("%s is out of steps." % p.name, "info")
		_end_turn()
		return
	_refresh_menu(p)


## A random stop while walking: at most one a turn, and never more than a few percent a step,
## however much heat you've built up (about one turn in six for a clean Rookie, two in three at most).
func _maybe_police_check(p: Dictionary) -> void:
	if int(p.immunity) > 0 or p.get("stopped", false):
		return
	var rank := rank_of(p)
	var chance := minf(0.006 + 0.003 * rank + 0.002 * mini(int(p.heat), 15), 0.04)
	if p.passport:
		chance *= 0.5
	if rng.randf() < chance:
		_random_stop(p)


## A checkpoint: what they find on you decides how hard they come down; nothing on you and no
## wanted poster (or fresh out of jail) and they let you go.
func _random_stop(p: Dictionary) -> void:
	p.stopped = true
	var sev := _evidence(p)
	if sev == 0 and (int(p.heat) < 6 or p.get("clean", false)):
		var who := "fresh out of jail with nothing on them" if p.get("clean", false) else "nothing on them"
		_result(p, "Police check", "The officers search %s, %s, and let them go." % [p.name, who], true)
		return
	var why := "They have a wanted poster with your face on it."
	if sev > 0:
		why = "They search you and find %s." % _evidence_text(p)
	_police_encounter(p, "Police checkpoint! " + why, maxi(sev, 3))


# --------------------------------------------------------------------------- building menus

func _refresh_menu(p: Dictionary) -> void:
	if int(p.inside) < 0:
		p.menu = []
		return
	p.menu = _build_menu(p)


func _menu_choose(p: Dictionary, id: String) -> String:
	if int(p.inside) < 0:
		return "You're not inside a building."
	if id == "leave":
		_log("%s steps back outside." % p.name, "move")
		_leave(p)
		return ""
	if id == "back":
		if p.menu_path.size() > 0:
			p.menu_path.pop_back()
		_refresh_menu(p)
		return ""
	var entry := {}
	for e in _build_menu(p):
		if e.id == id:
			entry = e
	if entry.is_empty():
		return "That option isn't available."
	if not entry.enabled:
		return entry.get("reason", "Not possible right now.")
	if id.begins_with("sub:"):
		p.menu_path.append(id.substr(4))
		_refresh_menu(p)
		return ""
	var cost: int = entry.get("steps", 0)
	p.steps = int(p.steps) - cost
	if not id.begins_with("act:gamble:"):
		p.menu_path = []   # (gamblers stay at their table for another hand)
	_exec(p, id.substr(4).split(":"))
	_after_action(p)
	return ""


func _e(id: String, label: String, info: String = "", enabled: bool = true, reason: String = "", steps: int = 0) -> Dictionary:
	return {"id": id, "label": label, "info": info, "enabled": enabled, "reason": reason, "steps": steps}


## Generic crime entry: checks rank, gear, steps.
func _crime_entry(p: Dictionary, key: String) -> Dictionary:
	var c: Dictionary = CRIMES[key]
	var info := "%s · %d steps" % [str(c.check).capitalize(), c.steps]
	if c.has("pay"):
		var mult := 1.0 + 0.15 * rank_of(p)
		info += " · $%s–%s" % [_k(int(c.pay[0] * mult)), _k(int(c.pay[1] * mult))]
	var ok := true
	var reason := ""
	if rank_of(p) < int(c.get("rank", 0)):
		ok = false
		reason = "Needs rank %s." % Balance.RANKS[int(c.rank)]
	elif c.has("gear") and _best_gear(p) < int(c.gear):
		ok = false
		reason = "Needs a %s or better." % Balance.GEAR[int(c.gear)].name
	elif c.get("room", false) and not p.room:
		ok = false
		reason = "You need a hotel room to hide them."
	elif c.get("no_hostage", false) and not p.hostage.is_empty():
		ok = false
		reason = "You're already holding someone."
	elif int(p.steps) < int(c.steps):
		ok = false
		reason = "Not enough steps."
	var odds := _crime_odds(p, c)
	if ok and c.has("mini"):
		info += " · " + MINI_HINTS[c.mini]
	elif ok:
		info += " · %d%%" % int(round(odds * 100))
	return _e("act:crime:" + key, c.label, info, ok, reason, c.steps)


func _build_menu(p: Dictionary) -> Array:
	var b: Dictionary = state.city.buildings[int(p.inside)]
	var path: Array = p.menu_path
	var m: Array = []
	var sub: String = path[path.size() - 1] if path.size() > 0 else ""
	var crew_n: int = p.crew.size()
	match b.type:
		"car_dealer":
			if sub == "buy_car":
				var trade: int = Balance.CARS[int(p.car)].price / 2
				for ci in b.stock:
					var car: Dictionary = Balance.CARS[int(ci)]
					var price: int = maxi(0, int(car.price) - trade)
					m.append(_e("act:buy_car:%d" % ci, car.name, "%d steps/turn · $%d after trade-in" % [car.steps, price],
						int(p.cash) >= price and int(ci) != int(p.car), "Not enough cash." if int(p.cash) < price else "You already drive one.", 1))
			elif sub == "steal_car":
				for ci in b.lot:
					var car2: Dictionary = Balance.CARS[int(ci)]
					var odds := clampf(0.7 - 0.05 * int(ci) + (_best(p, "smarts") - 40) / 150.0, 0.08, 0.9)
					m.append(_e("act:steal_car:%d" % ci, car2.name, "%d steps/turn · Smarts · %d%%" % [car2.steps, int(odds * 100)],
						int(p.steps) >= 3 and int(ci) != int(p.car), "Not enough steps.", 3))
			else:
				m.append(_e("sub:buy_car", "Buy a car", "Trade in your old one"))
				m.append(_e("sub:steal_car", "Steal a car from the lot", "The best cars can only be stolen"))
				m.append(_blackmail_entry(p, b))
		"arms":
			if sub == "buy_gear":
				for gi in b.stock:
					var g: Dictionary = Balance.GEAR[int(gi)]
					m.append(_e("sub:gear_%d" % gi, g.name, "$%d · power %d · needs Smarts %d, Nerve %d" % [g.price, g.power, g.smarts, g.nerve],
						int(p.cash) >= int(g.price), "Not enough cash."))
			elif sub.begins_with("gear_"):
				var gi2 := int(sub.substr(5))
				var g2: Dictionary = Balance.GEAR[gi2]
				for i in crew_n:
					var mem: Dictionary = p.crew[i]
					var fits: bool = int(mem.smarts) >= int(g2.smarts) and int(mem.nerve) >= int(g2.nerve)
					var short: Array = []
					if int(mem.smarts) < int(g2.smarts):
						short.append("Smarts %d (has %d)" % [g2.smarts, mem.smarts])
					if int(mem.nerve) < int(g2.nerve):
						short.append("Nerve %d (has %d)" % [g2.nerve, mem.nerve])
					m.append(_e("act:buy_gear:%d:%d" % [gi2, i], "Give it to %s" % mem.name,
						"now: %s · Smarts %d, Nerve %d" % [Balance.GEAR[int(mem.gear)].name, mem.smarts, mem.nerve],
						fits and int(p.cash) >= int(g2.price), ("Needs " + " and ".join(short) + ". Train at the gym.") if not fits else "Not enough cash.", 1))
			elif sub == "train":
				for i in crew_n:
					m.append(_e("sub:train_%d" % i, "Train %s" % p.crew[i].name, _stat_line(p.crew[i])))
			elif sub.begins_with("train_"):
				var mi := int(sub.substr(6))
				for s in ["muscle", "smarts", "nerve"]:
					m.append(_e("act:train:%d:%s" % [mi, s], "Train %s (now %d)" % [s.capitalize(), int(p.crew[mi][s])], "$600 · 2 steps · +4 to +9",
						int(p.cash) >= 600 and int(p.steps) >= 2 and int(p.crew[mi][s]) < 99, "Maxed out." if int(p.crew[mi][s]) >= 99 else "Not enough cash or steps.", 2))
				m.append(_e("act:train:%d:all" % mi, "Full program (all three)", "$1500 · 4 steps", int(p.cash) >= 1500 and int(p.steps) >= 4, "Not enough cash or steps.", 4))
			else:
				m.append(_e("sub:buy_gear", "Buy weapons", "This dealer's stock varies"))
				m.append(_e("sub:train", "Train your crew", "Muscle, Smarts, Nerve"))
				m.append(_e("act:practice:escape", "Practice escaping", "$150 · 1 step · four of the dealer's boys play cops", int(p.cash) >= 150, "Not enough cash.", 1))
				m.append(_e("act:practice:catch", "Practice catching a runner", "$150 · 1 step · grab the case back", int(p.cash) >= 150, "Not enough cash.", 1))
				m.append(_e("act:practice:sneak", "Practice sneaking past guards", "$150 · 1 step · the dealer's boys stand guard", int(p.cash) >= 150, "Not enough cash.", 1))
		"pub":
			if sub == "hire":
				for ri in b.recruits.size():
					var r: Dictionary = b.recruits[ri]
					var ok: bool = int(p.cash) >= int(r.price) and crew_n < Balance.MAX_CREW
					m.append(_e("act:hire:%d" % ri, r.name, "%s · $%d · %s" % [_stat_line(r), r.price, r.blurb], ok,
						"Your crew is full." if crew_n >= Balance.MAX_CREW else "Not enough cash.", 1))
			elif sub == "goods":
				m.append(_e("act:sell:radios", "Sell %d hot radios" % p.radios, "$%d each" % b.radio_price, int(p.radios) > 0, "You have none.", 1))
				m.append(_e("act:sell:electronics", "Sell %d electronics" % p.electronics, "$%d each" % b.elec_price, int(p.electronics) > 0, "You have none.", 1))
			elif sub == "jobs":
				var hit_pay := 2000 + 1500 * rank_of(p)
				m.append(_e("act:hit_job", "Take a hit job", "Fight bodyguards · 4 steps · $%d" % hit_pay, rank_of(p) >= 1 and int(p.steps) >= 4,
					"Nobody trusts a Rookie with this." if rank_of(p) < 1 else "Not enough steps.", 4))
				var case_pay := 1500 + 800 * rank_of(p)
				m.append(_e("act:take_suitcase", "Smuggle a suitcase abroad", "Take it through airport customs · pays $%d" % case_pay,
					p.get("suitcase", {}).is_empty(), "You're already carrying one.", 1))
				m.append(_e("act:buy_dirt", "Buy dirt on someone", "$2000 · use it for blackmail", int(p.cash) >= 2000 and p.dirt == "",
					"You already hold dirt." if p.dirt != "" else "Not enough cash.", 1))
			else:
				m.append(_e("sub:goods", "Deal in stolen goods", "Radios $%d · electronics $%d" % [b.radio_price, b.elec_price]))
				var can_hire: bool = rank_of(p) >= Balance.HIRE_MIN_RANK and p.room
				var why := "Come back when you're an %s." % Balance.RANKS[Balance.HIRE_MIN_RANK]
				if rank_of(p) >= Balance.HIRE_MIN_RANK and not p.room:
					why = "Recruits want a hotel room to crash in first."
				m.append(_e("sub:hire", "Hire crew", "%d looking for work" % b.recruits.size(), can_hire, why))
				m.append(_e("sub:jobs", "Ask about jobs", "Hits and blackmail material"))
				var kid: bool = not p.hostage.is_empty() and p.hostage.kind == "child" and p.ransom.is_empty()
				m.append(_e("act:sell_kid", "Sell the kid to the bartender", "$2500 · cheap labor", kid, "You aren't holding a child.", 1))
		"hotel":
			if sub == "rent":
				for months in [1, 3, 6]:
					var cost: int = Balance.ROOM_RENT * months
					m.append(_e("act:rent:%d" % months, "Pay %d month%s" % [months, "" if months == 1 else "s"], "$%d" % cost, int(p.cash) >= cost, "Not enough cash.", 1))
			else:
				if p.room:
					m.append(_e("sub:rent", "Pay rent", "Paid %d month%s ahead" % [p.rent_paid, "" if int(p.rent_paid) == 1 else "s"]))
				else:
					m.append(_e("act:rent:1", "Rent a room", "$%d/month · needed for hiring and hostages" % Balance.ROOM_RENT, int(p.cash) >= Balance.ROOM_RENT, "Not enough cash.", 1))
				m.append(_crime_entry(p, "rob_hotel"))
		"bank":
			m.append(_crime_entry(p, "bank_raid"))
			m.append(_crime_entry(p, "crack_safe"))
			m.append(_blackmail_entry(p, b))
		"print_shop":
			m.append(_e("act:fake_cash", "Buy counterfeit cash", "Pay $1000, get $2000 in fakes · raises heat", int(p.cash) >= 1000, "Not enough cash.", 1))
			m.append(_e("act:passport", "Get a fake passport", "$%d · halves police checks" % Balance.PASSPORT_PRICE, int(p.cash) >= Balance.PASSPORT_PRICE and not p.passport,
				"You already have one." if p.passport else "Not enough cash.", 1))
		"subway":
			if sub == "travel":
				var fare: int = 80 * crew_n
				for ob in state.city.buildings:
					if ob.type == "subway" and int(ob.id) != int(b.id):
						m.append(_e("act:travel:%d" % ob.id, ob.name, "$%d" % fare, int(p.cash) >= fare, "Not enough cash.", 1))
			else:
				m.append(_e("sub:travel", "Ride the subway", "Fast travel across town"))
				m.append(_crime_entry(p, "pickpocket_train"))
				m.append(_crime_entry(p, "pickpocket"))
		"police":
			if sub == "bribe":
				for months in [1, 2, 3]:
					var cost2: int = (2000 + 1000 * rank_of(p)) * months
					m.append(_e("act:bribe_chief:%d" % months, "%d month%s of looking away" % [months, "" if months == 1 else "s"], "$%d" % cost2,
						int(p.cash) >= cost2, "Not enough cash.", 2))
			elif sub == "free":
				for pid in state.order:
					var o: Dictionary = state.players[pid]
					if int(o.jail) > 0 and int(o.id) != int(p.id):
						var bail: int = 1500 * int(o.jail)
						m.append(_e("act:free:%d" % o.id, "Bail out %s" % o.name, "%d months left · $%d" % [o.jail, bail], int(p.cash) >= bail, "Not enough cash.", 2))
				if m.is_empty():
					m.append(_e("noop", "Nobody's in jail right now.", "", false, "Nobody to free."))
			else:
				m.append(_e("sub:bribe", "Bribe the chief", "No arrests while it lasts"))
				m.append(_e("sub:free", "Free a jailed rival", "They'll owe you"))
				m.append(_blackmail_entry(p, b))
		"station":
			if sub == "train":
				for ob2 in state.city.buildings:
					if ob2.type == "station" and int(ob2.id) != int(b.id):
						m.append(_e("act:travel:%d" % ob2.id, "Train to %s" % ob2.name, "$150", int(p.cash) >= 150, "Not enough cash.", 1))
			else:
				m.append(_e("act:buy_radios", "Buy hot radios", "5 for $750 · resell at pubs", int(p.cash) >= 750, "Not enough cash.", 1))
				m.append(_crime_entry(p, "mail_train"))
				m.append(_crime_entry(p, "pickpocket"))
				m.append(_e("sub:train", "Take the train", "To the other station"))
		"casino":
			if sub.begins_with("game_"):
				var game := sub.substr(5)
				for stake in [500, 1000, 5000]:
					m.append(_e("act:gamble:%s:%d" % [game, stake], "Bet $%d" % stake, "", int(p.cash) >= stake, "Not enough cash.", 1))
			else:
				m.append(_e("sub:game_blackjack", "Blackjack", "Wins often, pays 2x"))
				m.append(_e("sub:game_poker", "Poker", "Pays 3x"))
				m.append(_e("sub:game_roulette", "Roulette", "Long shot, pays 6x"))
				m.append(_blackmail_entry(p, b))
		"playground":
			m.append(_crime_entry(p, "kidnap_child"))
			m.append(_crime_entry(p, "pickpocket"))
		"supermarket":
			m.append(_crime_entry(p, "rob_store"))
			var prot := int(b.get("protector", 0))
			var info := "+$300 every month · Nerve"
			if prot == int(p.id):
				m.append(_e("noop", "Collect protection money", "Already paying you", false, "They already pay you."))
			else:
				if prot > 0 and state.players.has(prot):
					info += " · currently pays %s" % state.players[prot].name
				var ok2 := rank_of(p) >= Balance.PROTECTION_MIN_RANK and int(p.steps) >= 2
				m.append(_e("act:protection", "Collect protection money", info, ok2,
					"Nobody takes a %s seriously." % Balance.RANKS[rank_of(p)] if rank_of(p) < Balance.PROTECTION_MIN_RANK else "Not enough steps.", 2))
			m.append(_e("act:beg", "Beg for change", "No shame left", true, "", 1))
		"harbor":
			if sub == "goods":
				m.append(_e("act:sell:radios", "Sell %d hot radios" % p.radios, "$%d each" % b.radio_price, int(p.radios) > 0, "You have none.", 1))
				m.append(_e("act:sell:electronics", "Sell %d electronics" % p.electronics, "$%d each" % b.elec_price, int(p.electronics) > 0, "You have none.", 1))
			else:
				m.append(_crime_entry(p, "steal_containers"))
				m.append(_crime_entry(p, "pickpocket"))
				m.append(_e("sub:goods", "Dockside fence", "Sell stolen goods"))
		"loan_shark":
			if sub == "borrow":
				for amt in [5000, 10000, 20000]:
					m.append(_e("act:borrow:%d" % amt, "Borrow $%d" % amt, "5%%/month · %d months to repay" % Balance.LOAN_MONTHS,
						int(p.loan) + amt <= Balance.LOAN_MAX, "Eddie won't lend you that much.", 1))
			else:
				m.append(_e("sub:borrow", "Borrow money", "You owe $%d" % p.loan if int(p.loan) > 0 else "Up to $%d" % Balance.LOAN_MAX))
				m.append(_e("act:repay", "Repay the loan", "$%d owed · %d months left" % [p.loan, p.loan_months],
					int(p.loan) > 0 and int(p.cash) > 0, "You don't owe anything." if int(p.loan) == 0 else "No cash.", 1))
		"dept_store":
			m.append(_crime_entry(p, "steal_electronics"))
			m.append(_crime_entry(p, "money_transport"))
			m.append(_blackmail_entry(p, b))
		"villa":
			m.append(_crime_entry(p, "steal_electronics"))
			m.append(_crime_entry(p, "kidnap_villa"))
			m.append(_blackmail_entry(p, b))
		"city_hall":
			m.append(_crime_entry(p, "rob_pay_office"))
			m.append(_crime_entry(p, "kidnap_dignitary"))
			m.append(_blackmail_entry(p, b))
		"airport":
			if sub == "holiday":
				for hi in Balance.HOLIDAYS.size():
					var h: Dictionary = Balance.HOLIDAYS[hi]
					var cost3: int = int(h.cost) * crew_n
					m.append(_e("act:holiday:%d" % hi, "%s (1 month)" % h.name, "$%d for the crew · stats +%d" % [cost3, h.boost],
						int(p.cash) >= cost3, "Not enough cash.", 0))
			else:
				m.append(_e("sub:holiday", "Go on holiday", "Skip a month, come back stronger"))
				m.append(_e("act:smuggle", "Smuggle the suitcase through customs", "Sneak past customs · 3 steps",
					not p.get("suitcase", {}).is_empty(), "A bartender can give you one to carry.", 3))
	if path.size() > 0:
		m.append(_e("back", "Back"))
	m.append(_e("leave", "Leave"))
	for e in m:
		if e.enabled and int(e.steps) > int(p.steps):
			e.enabled = false
			e.reason = "Not enough steps (%d)." % e.steps
	return m


func _blackmail_entry(p: Dictionary, b: Dictionary) -> Dictionary:
	var ok: bool = p.dirt == b.type
	return _e("act:blackmail", "Blackmail the boss", "Use your dirt · 2 steps", ok and int(p.steps) >= 2,
		"You've got nothing on them. Bartenders sell dirt." if not ok else "Not enough steps.", 2)


# --------------------------------------------------------------------------- crimes

const CRIMES := {
	"pickpocket": {"label": "Pick some pockets", "check": "smarts", "base": 0.55, "steps": 2, "loot": true, "fail": "police", "sev": 2, "heat": 1},
	"pickpocket_train": {"label": "Work the crowded trains", "check": "smarts", "base": 0.65, "steps": 3, "loot": true, "fail": "police", "sev": 2, "heat": 1},
	"rob_hotel": {"label": "Rob the front desk", "check": "nerve", "base": 0.5, "steps": 3, "pay": [800, 3000], "fail": "fight", "foe": "staff", "enemy": 4, "sev": 3, "heat": 2},
	"bank_raid": {"label": "Hold up the teller", "check": "nerve", "base": 0.45, "steps": 3, "pay": [3000, 9000], "gear": Balance.PISTOL, "fail": "fight", "enemy": 9, "sev": 7, "heat": 4},
	"crack_safe": {"label": "Crack the vault at night", "check": "smarts", "base": 0.35, "steps": 5, "pay": [8000, 20000], "fail": "police", "sev": 7, "heat": 4, "rank": 1, "mini": "safe"},
	"rob_store": {"label": "Rob the store", "check": "nerve", "base": 0.55, "steps": 2, "pay": [400, 1800], "fail": "fight", "foe": "staff", "enemy": 3, "sev": 3, "heat": 2},
	"mail_train": {"label": "Rob the mail train", "check": "muscle", "base": 0.4, "steps": 6, "pay": [6000, 15000], "fail": "fight", "enemy": 10, "sev": 8, "heat": 5, "rank": 2, "mini": "train"},
	"steal_containers": {"label": "Steal shipping containers", "check": "muscle", "base": 0.5, "steps": 4, "pay": [1500, 5000], "fail": "police", "sev": 4, "heat": 2, "mini": "containers"},
	"steal_electronics": {"label": "Clean out the electronics", "check": "smarts", "base": 0.5, "steps": 4, "goods": true, "fail": "police", "sev": 4, "heat": 2, "mini": "loot"},
	"money_transport": {"label": "Hit the armored truck", "check": "nerve", "base": 0.4, "steps": 5, "pay": [5000, 12000], "gear": Balance.PISTOL, "fail": "fight", "enemy": 11, "sev": 8, "heat": 5, "rank": 3, "mini": "sneak"},
	"rob_pay_office": {"label": "Raid the city pay office", "check": "nerve", "base": 0.4, "steps": 4, "pay": [4000, 10000], "fail": "fight", "enemy": 8, "sev": 6, "heat": 4, "rank": 2},
	"kidnap_child": {"label": "Kidnap a child", "check": "smarts", "base": 0.5, "steps": 3, "hostage": "child", "value": [4000, 9000], "fail": "fight", "foe": "staff", "enemy": 3, "sev": 10, "heat": 4, "room": true, "no_hostage": true},
	"kidnap_villa": {"label": "Snatch the rich kid", "check": "smarts", "base": 0.4, "steps": 4, "hostage": "child", "value": [8000, 18000], "fail": "fight", "foe": "bodyguard", "enemy": 5, "sev": 10, "heat": 5, "room": true, "no_hostage": true, "rank": 1},
	"kidnap_dignitary": {"label": "Snatch the visiting dignitary", "check": "smarts", "base": 0.3, "steps": 5, "hostage": "dignitary", "value": [20000, 40000], "fail": "fight", "foe": "bodyguard", "enemy": 10, "sev": 10, "heat": 7, "room": true, "no_hostage": true, "rank": 4, "mini": "sneak"},
}


func _crime_odds(p: Dictionary, c: Dictionary) -> float:
	var stat: int = _best(p, str(c.check))
	var odds: float = float(c.base) + (stat - 40) / 150.0 + 0.01 * Balance.GEAR[_best_gear(p)].power - 0.015 * rank_of(p)
	return clampf(odds, 0.05, 0.95)


const MINI_HINTS := {"safe": "crack the dials", "train": "block the track", "containers": "push them to the truck",
	"loot": "push the goods out", "sneak": "sneak past the guards"}
const MINI_INTROS := {
	"crack_safe": ["Crack the vault", "Midnight in the vault. Three dials; listen for the click that sounds different. The alarm trips in seconds."],
	"mail_train": ["Stop the mail train", "Push containers onto the track before the mail train comes through. You need about %d."],
	"steal_containers": ["Steal containers", "Push containers onto the marked squares by the truck, then get out through the gate before the time is up."],
	"steal_electronics": ["Clean out the electronics", "Push the goods onto the marked squares by the back door, then get out before the time is up."],
	"money_transport": ["Into the depot", "Get inside without being seen. The guards look ahead and to the sides, never behind."],
	"kidnap_dignitary": ["Past the bodyguards", "Reach the guest suite without being seen. The guards look ahead and to the sides, never behind."],
}


func _do_crime(p: Dictionary, key: String) -> void:
	var c: Dictionary = CRIMES[key]
	var b: Dictionary = state.city.buildings[int(p.inside)]
	_mark_scene(p, b)
	p.heat = int(p.heat) + int(c.heat)
	if c.has("mini"):
		var game: String = c.mini
		var intro: Array = MINI_INTROS[key]
		if key == "steal_electronics" and b.type == "villa":
			game = "sneak"
			intro = ["Into the villa", "Get into the house without being seen. The guards look ahead and to the sides, never behind."]
		var text: String = intro[1] % clampi(8 + rank_of(p) / 2, 8, 12) if key == "mail_train" else intro[1]
		_start_mini(p, game, intro[0], text, rank_of(p), {"k": "crime", "key": key, "b": b.id})
		return
	if rng.randf() < _crime_odds(p, c):
		_crime_success(p, c, b, "")
		return
	match str(c.fail):
		"police":
			_police_encounter(p, "%s went wrong. The cops are here!" % c.label, int(c.sev))
		"fight":
			var enemy: int = int(c.enemy) + rank_of(p)
			var foe: String = c.get("foe", "guard")
			_start_fight(p, c.label, "%s went wrong. %s's people come at you." % [c.label, b.name],
				Fight.squad(foe, enemy, rng), {"k": "crime", "key": key, "b": b.id})


func _crime_success(p: Dictionary, c: Dictionary, b: Dictionary, prefix: String) -> void:
	var mult := 1.0 + 0.15 * rank_of(p)
	var text := prefix
	if c.has("pay"):
		var amt := int(rng.randi_range(int(c.pay[0]), int(c.pay[1])) * mult)
		p.cash = int(p.cash) + amt
		text += "%s got away with $%d." % [p.name, amt]
	elif c.get("loot", false):
		var item: Array = Balance.LOOT[rng.randi() % Balance.LOOT.size()]
		p.cash = int(p.cash) + int(item[1])
		text += "%s lifted %s and fenced it for $%d." % [p.name, item[0], item[1]]
	elif c.get("goods", false):
		var n := rng.randi_range(2, 5)
		p.electronics = int(p.electronics) + n
		text += "%s hauled out %d boxes of electronics. Sell them at a pub." % [p.name, n]
	elif c.has("hostage"):
		var value := rng.randi_range(int(c.value[0]), int(c.value[1]))
		var who := "a child from %s" % b.name if c.hostage == "child" else "the visiting dignitary"
		p.hostage = {"kind": c.hostage, "value": value, "from": b.name}
		text += "%s grabbed %s and stashed them in the hotel room." % [p.name, who]
		_add_points(p, 1)
		_log("%s: %s" % [c.label, text], "crime")
		_offer_ransom(p, text)
		return
	_add_points(p, 1)
	_result(p, c.label, text, true)


func _protection_attempt(p: Dictionary, b: Dictionary) -> void:
	var odds := clampf(0.45 + (_best(p, "nerve") - 40) / 120.0 + 0.04 * rank_of(p), 0.1, 0.9)
	if rng.randf() < odds:
		b.protector = p.id
		_add_points(p, 1)
		_result(p, "Protection racket", "%s now pays %s $300 every month to stay in one piece." % [b.name, p.name], true)
	else:
		_police_encounter(p, "The owner called the cops instead of paying.", 3)


# --------------------------------------------------------------------------- hostages

func _offer_ransom(p: Dictionary, intro: String) -> void:
	var v: int = p.hostage.value
	var opts: Array = [
		{"id": "ransom:%d:0.85" % int(v * 0.6), "label": "Ask $%d (safe)" % int(v * 0.6), "enabled": true},
		{"id": "ransom:%d:0.65" % v, "label": "Ask $%d (fair)" % v, "enabled": true},
		{"id": "ransom:%d:0.4" % int(v * 1.8), "label": "Ask $%d (greedy)" % int(v * 1.8), "enabled": true},
	]
	if p.hostage.kind == "child":
		opts.append({"id": "keep", "label": "Decide later (sell at a pub)", "enabled": true})
	if str(p.get("new_scene", "")) != "":
		intro += " The cops will be watching %s now: don't go back." % p.new_scene
		p.new_scene = ""
	state.pending = {"kind": "choice", "player": p.id, "title": "Ransom demand",
		"text": intro + " How much do you demand? The more you ask, the more likely they try to trick you.", "options": opts}


func _ransom_set(p: Dictionary, amount: int, chance: float) -> void:
	var candidates: Array = []
	for ob in state.city.buildings:
		if int(ob.id) != int(p.inside) and ob.type in ["playground", "supermarket", "pub", "station", "subway", "police", "harbor"]:
			candidates.append(ob)
	var drop: Dictionary = candidates[rng.randi() % candidates.size()]
	p.ransom = {"building": drop.id, "amount": amount, "chance": chance, "months": 3}
	var where := "the trash can behind %s" % drop.name
	if drop.type == "police":
		where = "the steps of police headquarters (the cops will love that)"
	_log("%s demanded $%d. Drop point: %s." % [p.name, amount, where], "crime")


func _ransom_pickup(p: Dictionary) -> void:
	var r: Dictionary = p.ransom
	var kind: String = p.hostage.get("kind", "child")
	if rng.randf() < float(r.chance):
		p.cash = int(p.cash) + int(r.amount)
		_add_points(p, 1)
		_result(p, "Ransom collected", "The case was right where they said: $%d. The hostage goes home." % r.amount, true)
	else:
		var who := "kid" if kind == "child" else "hostage"
		_start_mini(p, "catch", "After them!", "The %s tore loose and ran off with the money case! Catch them within %d seconds." % [who, Chase.CATCH_SECONDS],
			rank_of(p), {"k": "ransom", "amount": int(r.amount), "who": who})
	p.ransom = {}
	p.hostage = {}


# --------------------------------------------------------------------------- police & fights

## The police turn up. `sev` (0-10) is how bad what they caught you at is: it sets how many come,
## how hard they are to shake off and how hard to bribe. What you carry counts too (see _evidence).
func _police_encounter(p: Dictionary, text: String, sev: int = 3) -> void:
	if int(p.immunity) > 0:
		_log("The cops recognize %s and look the other way. The chief has been paid." % p.name, "info")
		return
	sev = clampi(maxi(sev, _evidence(p)), 0, 10)
	var bribe := 200 + 150 * sev + 300 * rank_of(p)
	var cops := _cops(p, sev)
	var on_foot := int(p.car) == 0
	var shake: String = ["Easy", "Easy", "Easy", "Easy", "Not easy", "Not easy", "Hard", "Hard", "Very hard", "Very hard", "Very hard"][sev]
	state.pending = {"kind": "police", "player": p.id, "title": "Police check", "text": text, "options": [
		{"id": "run", "label": "Make a run for it", "enabled": true,
			"info": "%s to shake them %s. If they catch you, you fight." % [shake, "on foot" if on_foot else "(you leave the car)"]},
		{"id": "bribe", "label": "Bribe them ($%d)" % bribe, "enabled": int(p.cash) >= bribe,
			"info": ("Usually works." if sev < 6 else "Risky for something this big.") + " They might take it and arrest you anyway." if int(p.cash) >= bribe else "You don't have $%d." % bribe},
		{"id": "fight", "label": "Shoot it out", "enabled": true, "info": "Fight them right here."},
	], "bribe": bribe, "cops": cops.size(), "armed": Balance.GEAR[cops[0].gear].name, "sev": sev,
		"response": "Full response" if sev >= 8 else ("Patrol cars" if sev >= 4 else "A beat cop" if cops.size() == 1 else "Beat cops")}


## How many officers come, and how armed, for a crime of severity `sev` (0-10): one or two for a
## pickpocket, four or five for a robbery, a whole squad for a kidnapping.
const COPS_BY_SEV := [1, 1, 2, 2, 3, 3, 4, 5, 6, 7, 8]


func _cops(p: Dictionary, sev: int) -> Array:
	sev = clampi(sev, 0, 10)
	return Fight.squad("police", 2 + sev + rank_of(p), rng, COPS_BY_SEV[sev])


## What the police find on you, as a severity (0 if nothing): stolen goods by how many, the
## smuggler's suitcase, a stolen car.
func _evidence(p: Dictionary) -> int:
	var sev := 0
	var goods := int(p.electronics) + int(p.radios)
	if goods > 10:
		sev = 10
	elif goods > 5:
		sev = 6
	elif goods > 0:
		sev = 2
	if not p.suitcase.is_empty():
		sev = maxi(sev, 6)
	if p.get("car_stolen", false) and int(p.car) > 0:
		sev = maxi(sev, 4)
	return sev


func _evidence_text(p: Dictionary) -> String:
	var found: Array = []
	var goods := int(p.electronics) + int(p.radios)
	if goods > 0:
		found.append("%d stolen device%s" % [goods, "" if goods == 1 else "s"])
	if not p.suitcase.is_empty():
		found.append("a locked suitcase")
	if p.get("car_stolen", false) and int(p.car) > 0:
		found.append("a stolen %s" % Balance.CARS[int(p.car)].name)
	return " and ".join(found)


func _police_choice(p: Dictionary, choice: String) -> void:
	var pend: Dictionary = state.pending
	state.pending = {}
	var sev := int(pend.get("sev", 3))
	var cops := _cops(p, sev)
	match choice:
		"bribe":
			p.cash = int(p.cash) - int(pend.bribe)
			if rng.randf() < 0.95 - 0.045 * sev:
				_result(p, "Bribe accepted", "The officers pocket $%d and wave %s on." % [pend.bribe, p.name], true)
			else:
				_start_fight(p, "Double-crossed", "They pocket the $%d, then arrest %s for bribery. Fight or go quietly." % [pend.bribe, p.name],
					cops, {"k": "police", "how": "double", "sev": sev})
		"run":
			_start_mini(p, "escape", "Run for it!", "%s breaks away into the back alleys. Stay clear of the cops for %d seconds." % [p.name, Chase.ESCAPE_SECONDS],
				sev, {"k": "police_run", "sev": sev})
		_:
			_start_fight(p, "Shootout", "%s goes for the gun. The officers take cover." % p.name, cops, {"k": "police", "how": "shootout", "sev": sev})


## Court and prison. Returns the sentence in months.
func _arrest(p: Dictionary, sev: int = 0) -> String:
	var months := 1 + rank_of(p) / 4 + (1 if sev >= 8 else 0)
	_log("%s was sentenced to %d month%s in jail." % [p.name, months, "" if months == 1 else "s"], "bad")
	return "The judge hands down %d month%s. %s" % [months, "" if months == 1 else "s", _jail(p, months)]


## Locks `p` up: the car is impounded, the crew's weapons are taken and there's a fine.
## Returns what happened, for the result text.
func _jail(p: Dictionary, months: int) -> String:
	p.jail = int(p.jail) + months
	p.heat = int(p.heat) / 2
	p.steps = 0
	p.inside = -1
	p.menu_path = []
	p.scenes = []   # time served
	p.new_scene = ""
	p.clean = true   # until the next crime, a stop with nothing on you ends with a wave
	p.car_stolen = false
	var lost: Array = []
	if int(p.car) > 0:
		lost.append("The %s was impounded." % Balance.CARS[int(p.car)].name)
		p.car = 0
	var guns: Array = []
	for m in p.crew:
		if int(m.gear) > 0:
			guns.append(Balance.GEAR[int(m.gear)].name)
			m.gear = 0
	var goods := int(p.electronics) + int(p.radios)
	if goods > 0 or not p.suitcase.is_empty():
		lost.append("The stolen goods went into the evidence room.")
		p.electronics = 0
		p.radios = 0
		p.suitcase = {}
	if guns.size() > 0:
		var listed: String = guns[-1] if guns.size() == 1 else "%s and %s" % [", ".join(guns.slice(0, -1)), guns[-1]]
		lost.append("The cops kept the %s." % listed)
	var fine := mini(Balance.JAIL_FINE, maxi(0, int(p.cash)))
	p.cash = int(p.cash) - fine
	if fine > 0:
		lost.append("The jail took a $%d fine." % fine)
	return " ".join(lost)


## Remembers a building where `p` committed a crime: walking back in later means arrest.
func _mark_scene(p: Dictionary, b: Dictionary) -> void:
	p.clean = false
	if not p.scenes.has(int(b.id)):
		p.scenes.append(int(b.id))
		p.new_scene = b.name


## Walking back into a building you hit: the cops are waiting. True if `p` was arrested.
func _back_at_scene(p: Dictionary, b: Dictionary) -> bool:
	if not p.get("scenes", []).has(int(b.id)) or int(p.immunity) > 0:
		return false
	_log("%s went back to %s. The cops were waiting." % [p.name, b.name], "bad")
	var text := "The police were staking out %s, and %s walked right back in. %s" % [b.name, p.name, _arrest(p)]
	_result(p, "Back at the scene", text, false)
	return true


## Opens a minigame (see Mini). `then` says what happens after.
func _start_mini(p: Dictionary, game: String, title: String, text: String, level: int, then: Dictionary) -> void:
	state.mini = Mini.create(game, title, level, rng, then)
	state.minis = int(state.get("minis", 0)) + 1
	state.mini.id = state.minis
	if game == "safe":
		_safe_secret = Safe.code(rng)
	_mini_clock = 0.0
	_log("%s: %s" % [title, text], "bad" if then.k == "police_run" else "crime")
	var quit := "Call the train now" if game == "train" else ("Bail out" if game in ["loot", "containers", "sneak", "safe"] else "Give up")
	state.pending = {"kind": "mini", "player": p.id, "title": title, "text": text, "options": [
		{"id": "give_up", "label": quit, "enabled": true},
	]}


func _end_mini(p: Dictionary) -> void:
	var m: Dictionary = state.mini
	var then: Dictionary = m.then
	var won: bool = m.won
	state.pending = {}
	match str(then.k):
		"police_run":
			if won:
				p.heat = int(p.heat) + 1
				_result(p, "Got away", "%s lost the cops in the back alleys." % p.name, true)
			else:
				var how := "%s gave up and turned around." % p.name if m.gave_up else "They cut %s off in an alley." % p.name
				state.mini = {}
				_start_fight(p, "Cornered", "%s No way out but through them." % how,
					_cops(p, int(then.sev)), {"k": "police", "how": "caught", "sev": int(then.sev)})
		"ransom":
			if won:
				p.cash = int(p.cash) + int(then.amount)
				_add_points(p, 1)
				_result(p, "Ransom collected (barely)", "%s caught up with the %s and got the case back: $%d." % [p.name, then.who, then.amount], true)
			else:
				_result(p, "Ransom: tricked!", "The %s got away with the money case. %s got nothing." % [then.who, p.name], false)
		"practice":
			_result(p, "Practice run", _practice_line(m), won)
		"crime":
			_crime_mini_outcome(p, m, then)
		"smuggle":
			p.suitcase = {}
			if won:
				p.cash = int(p.cash) + int(then.pay)
				_add_points(p, 1)
				_result(p, "Suitcase delivered", "%s slipped past customs. In the terminal a man in a grey coat takes the case and pays $%d." % [p.name, then.pay], true)
			elif m.gave_up:
				_result(p, "Suitcase dumped", "%s lost their nerve and dumped the case in a bin. The bartender won't be pleased." % p.name, false)
			else:
				_police_encounter(p, "Customs spotted %s with the suitcase and called the police!" % p.name, 6)
	_after_action(p)


func _practice_line(m: Dictionary) -> String:
	var used := (int(m.total) - int(m.left)) * Mini.TICK
	match str(m.game):
		"escape":
			return "You lasted the full %d seconds. The 'cops' are impressed." % Chase.ESCAPE_SECONDS if m.won else "Caught after %.1f seconds. Again?" % used
		"catch":
			return "Caught the runner with %.1f seconds to spare." % Mini.seconds_left(m) if m.won else "The runner got away. Again?"
		"sneak":
			return "Out the door in %.1f seconds and nobody saw a thing." % used if m.won else "Spotted. In a real job that's the alarm. Again?"
	return "Done."


## What happens after a crime's minigame (see CRIMES "mini").
func _crime_mini_outcome(p: Dictionary, m: Dictionary, then: Dictionary) -> void:
	var c: Dictionary = CRIMES[then.key]
	var b: Dictionary = state.city.buildings[int(then.b)]
	var won: bool = m.won
	var crime_then := {"k": "crime", "key": then.key, "b": b.id}
	var guards := Fight.squad(c.get("foe", "guard"), int(c.get("enemy", 6)) + rank_of(p), rng)
	match str(m.game):
		"safe":
			if won:
				_crime_success(p, c, b, "Click, click, click... the vault swings open. ")
			else:
				state.mini = {}
				_start_fight(p, "Alarm!", "The siren goes off and the police storm the vault.",
					_cops(p, int(c.sev)), {"k": "police", "how": "caught", "sev": int(c.sev)})
		"train":
			if won:
				state.mini = {}
				_start_fight(p, "Mail train", "The train grinds to a halt against the containers (%d hit it). The guards jump out." % int(m.train.hits),
					guards, crime_then)
			else:
				_result(p, "The train got through", "Only %d container%s on the track: the mail train smashed through and was gone." % [int(m.got), "" if int(m.got) == 1 else "s"], false)
		"containers", "loot":
			if not won:
				if m.gave_up:
					_result(p, "Bailed out", "%s slipped out empty-handed." % p.name, false)
				else:
					_police_encounter(p, "Time's up: the police were waiting at the gate!", int(c.sev))
			elif int(m.got) == 0:
				_result(p, "Nothing taken", "%s got out, but nothing made it onto the truck." % p.name, false)
			else:
				_add_points(p, 1)
				var mult := 1.0 + 0.15 * rank_of(p)
				if m.game == "containers":
					var amt := int(int(m.got) * rng.randi_range(300, 450) * mult)
					p.cash = int(p.cash) + amt
					_result(p, c.label, "%d container%s on the truck. The fence pays $%d." % [int(m.got), "" if int(m.got) == 1 else "s", amt], true)
				else:
					p.electronics = int(p.electronics) + int(m.got)
					_result(p, c.label, "%s hauled out %d boxes of electronics. Sell them at a pub." % [p.name, int(m.got)], true)
		"sneak":
			match str(then.key):
				"steal_electronics":   # a villa: in without being seen, then the looting
					if won:
						state.mini = {}
						_start_mini(p, "loot", "Clean out the electronics", "You're in. Push the goods to the back door and get out before the owners wake.",
							rank_of(p), crime_then)
						return
					_police_encounter(p, "A light snaps on. The owner saw you and called the police!", int(c.sev))
				"money_transport":
					if won:
						state.mini = {}
						_start_fight(p, c.label, "%s waited inside until the armored truck pulled up. Now take it from the guards." % p.name, guards, crime_then)
					else:
						_police_encounter(p, "A guard spotted %s and raised the alarm!" % p.name, int(c.sev))
				_:
					if won:
						_crime_success(p, c, b, "Past the guards without a sound. ")
					else:
						state.mini = {}
						_start_fight(p, c.label, "A guard spotted %s. The bodyguards close in." % p.name, guards, crime_then)


## Opens the fight screen: `p`'s crew (left) against `foes` (right). `then` says what happens after.
func _start_fight(p: Dictionary, title: String, text: String, foes: Array, then: Dictionary) -> void:
	state.fight = Fight.create(title, Fight.crew_units(p, 0), foes, then, true)
	state.fights = int(state.get("fights", 0)) + 1
	state.fight.id = state.fights
	_log("%s: %s" % [title, text], "bad")
	state.pending = {"kind": "fight", "player": p.id, "title": title, "text": text, "options": [
		{"id": "auto", "label": "Auto-fight", "enabled": true},
		{"id": "surrender", "label": "Give up", "enabled": true},
	]}


func _fight_intent(p: Dictionary, intent: Dictionary) -> String:
	if state.fight.is_empty() or state.fight.over:
		return "There's no fight on."
	var err := ""
	if intent.has("cell"):
		var c: Array = intent.cell
		err = Fight.act_toward(state.fight, Vector2i(int(c[0]), int(c[1])), rng)
	else:
		err = Fight.wait(state.fight, rng)
	if err == "" and state.fight.over:
		_end_fight(p)
		_after_action(p)
	return err


## Writes the fight's damage back to every crew involved, then applies what the fight was about.
func _end_fight(p: Dictionary) -> void:
	var f: Dictionary = state.fight
	var downed := 0
	var killed: Array = []
	var units: Array = f.units.duplicate()
	units.sort_custom(func(a, b): return int(a.ci) > int(b.ci))   # back to front, so removals keep indexes
	for u in units:
		if int(u.side) == 1 and int(u.hp) == 0:
			downed += 1
		if not state.players.has(int(u.owner)):
			continue
		var o: Dictionary = state.players[int(u.owner)]
		var ci := int(u.ci)
		if ci < 0 or ci >= o.crew.size():
			continue
		o.crew[ci].stamina = int(u.hp)
		if int(u.hp) == 0 and f.lethal and ci > 0 and rng.randf() < 0.35:
			killed.append(o.crew[ci].name)
			o.crew.remove_at(ci)
	var lines: Array = []
	if f.surrendered:
		lines.append("%s gave up." % p.name)
	if downed > 0:
		lines.append("%d of them went down." % downed)
	if killed.size() > 0:
		lines.append("%s didn't make it." % ", ".join(killed))
	state.pending = {}
	_fight_outcome(p, f.then, bool(f.won), " ".join(lines))
	if state.pending.is_empty():
		state.fight = {}   # nothing to show over the arena, so go straight back to town


func _fight_outcome(p: Dictionary, then: Dictionary, won: bool, text: String) -> void:
	match str(then.k):
		"police":
			var how: String = then.how
			if won:
				var titles := {"shootout": "Shootout won", "double": "Double-crossed", "caught": "Cornered"}
				var lead := {"shootout": "%s shot it out with the cops and won." % p.name,
					"double": "They took the money and drew their guns anyway. %s shot their way out." % p.name,
					"caught": "They cornered %s, who fought free." % p.name}
				p.heat = int(p.heat) + (4 if how == "shootout" else 3)
				_result(p, titles[how], "%s %s" % [lead[how], text], true)
			else:
				_result(p, "Arrested", "The cops took %s in. %s %s" % [p.name, text, _arrest(p, int(then.get("sev", 0)))], false)
		"crime":
			var c: Dictionary = CRIMES[then.key]
			if won:
				_crime_success(p, c, state.city.buildings[int(then.b)], "It turned into a fight. %s " % text)
			else:
				_result(p, "Busted", "%s lost the fight and the cops picked up the pieces. %s %s" % [p.name, text, _arrest(p, int(c.sev))], false)
		"hit_job":
			if won:
				p.cash = int(p.cash) + int(then.pay)
				_add_points(p, 1)
				_result(p, "Hit job done", "The target and his bodyguards are dealt with. %s collects $%d. %s" % [p.name, then.pay, text], true)
			else:
				_result(p, "Hit job failed", "The bodyguards were ready for %s. %s" % [p.name, text], false)
		"protection":
			var prot: Dictionary = state.players.get(int(then.prot), {})
			if won:
				_protection_attempt(p, state.city.buildings[int(then.b)])
			else:
				_result(p, "Turf trouble", "%s's people already run this block and they ran %s off. %s" % [prot.get("name", "Someone"), p.name, text], false)
		"gang_war":
			var o: Dictionary = state.players[int(then.target)]
			var winner: Dictionary = p if won else o
			var loser: Dictionary = o if won else p
			var loot := int(loser.cash) / 4
			loser.cash = int(loser.cash) - loot
			winner.cash = int(winner.cash) + loot
			_add_points(winner, 1)
			_result(p, "Gang war!", "%s's crew took on %s's crew. %s won and took $%d. %s" % [p.crew_name, o.crew_name, winner.name, loot, text], won)
			_check_win(o)


func _gang_war(p: Dictionary, target: int) -> String:
	if p.gang_war_used:
		return "One gang war per turn."
	if not state.players.has(target) or target == int(p.id):
		return "Pick a rival."
	var o: Dictionary = state.players[target]
	if int(o.jail) > 0 or int(o.holiday) > 0:
		return "%s isn't around." % o.name
	if int(p.steps) < 3:
		return "Not enough steps (3)."
	p.steps = int(p.steps) - 3
	p.gang_war_used = true
	_start_fight(p, "Gang war", "%s's crew jumps %s's crew. The winner takes a quarter of the loser's cash." % [p.crew_name, o.crew_name],
		Fight.crew_units(o, 1), {"k": "gang_war", "target": o.id})
	_after_action(p)
	return ""


# --------------------------------------------------------------------------- actions

func _exec(p: Dictionary, a: PackedStringArray) -> void:
	var b: Dictionary = state.city.buildings[int(p.inside)]
	match a[0]:
		"crime":
			_do_crime(p, a[1])
		"buy_car":
			var ci := int(a[1])
			var price: int = maxi(0, int(Balance.CARS[ci].price) - int(Balance.CARS[int(p.car)].price) / 2)
			p.cash = int(p.cash) - price
			p.car = ci
			p.car_stolen = false
			_result(p, "New wheels", "%s drives off in a %s (%d steps per turn)." % [p.name, Balance.CARS[ci].name, Balance.CARS[ci].steps], true)
		"steal_car":
			var ci2 := int(a[1])
			var odds := clampf(0.7 - 0.05 * ci2 + (_best(p, "smarts") - 40) / 150.0, 0.08, 0.9)
			p.heat = int(p.heat) + 2
			_mark_scene(p, b)
			if rng.randf() < odds:
				p.car = ci2
				p.car_stolen = true
				_add_points(p, 1)
				_result(p, "Car stolen", "%s hot-wired a %s and peeled out of the lot." % [p.name, Balance.CARS[ci2].name], true)
			else:
				_police_encounter(p, "The alarm on the %s went off. The cops are here!" % Balance.CARS[ci2].name, 3 + ci2 / 3)
		"buy_gear":
			var gi := int(a[1])
			var mem: Dictionary = p.crew[int(a[2])]
			p.cash = int(p.cash) - int(Balance.GEAR[gi].price)
			mem.gear = gi
			_result(p, "Armed up", "%s now carries a %s." % [mem.name, Balance.GEAR[gi].name], true)
		"practice":
			p.cash = int(p.cash) - 150
			var texts := {"escape": "Four of the dealer's boys in borrowed uniforms. Stay clear for %d seconds." % Chase.ESCAPE_SECONDS,
				"catch": "One of the dealer's boys grabs a case and runs. Catch him within %d seconds." % Chase.CATCH_SECONDS,
				"sneak": "The back warehouse, with the dealer's boys on patrol. Reach the door without being seen."}
			_start_mini(p, a[1], "Practice: " + a[1], texts[a[1]], 0, {"k": "practice"})
		"train":
			var mem2: Dictionary = p.crew[int(a[1])]
			var stats: Array = ["muscle", "smarts", "nerve"] if a[2] == "all" else [a[2]]
			p.cash = int(p.cash) - (1500 if a[2] == "all" else 600)
			var parts: Array = []
			for s in stats:
				var before := int(mem2[s])
				mem2[s] = mini(99, before + rng.randi_range(4, 9))
				parts.append("%s %d → %d" % [s.capitalize(), before, mem2[s]])
			_result(p, "Training done", "%s: %s." % [mem2.name, ", ".join(parts)], true)
		"hire":
			var r: Dictionary = b.recruits[int(a[1])]
			p.cash = int(p.cash) - int(r.price)
			var recruit := r.duplicate(true)
			recruit.erase("price")
			recruit.erase("blurb")
			p.crew.append(recruit)
			b.recruits.remove_at(int(a[1]))
			_result(p, "New recruit", "%s joins %s." % [recruit.name, p.crew_name], true)
		"sell":
			var what := a[1]
			var n: int = p[what]
			var each: int = b.radio_price if what == "radios" else b.elec_price
			p[what] = 0
			p.cash = int(p.cash) + n * each
			_result(p, "Sold", "%s sold %d %s for $%d." % [p.name, n, what, n * each], true)
		"buy_radios":
			p.cash = int(p.cash) - 750
			p.radios = int(p.radios) + 5
			_result(p, "Hot radios", "5 car radios, no questions asked. Pubs pay $200–$320 each.", true)
		"hit_job":
			var pay := 2000 + 1500 * rank_of(p)
			p.heat = int(p.heat) + 3
			_start_fight(p, "Hit job", "The target steps out with his bodyguards. Pay on delivery: $%d." % pay,
				Fight.squad("bodyguard", 4 + 2 * rank_of(p), rng), {"k": "hit_job", "pay": pay})
		"take_suitcase":
			p.suitcase = {"pay": 1500 + 800 * rank_of(p)}
			_result(p, "A heavy suitcase", "The bartender hands over a locked suitcase. Get it through customs at the airport and someone will pay $%d. Don't open it." % p.suitcase.pay, true)
		"smuggle":
			p.heat = int(p.heat) + 1
			_mark_scene(p, b)
			_start_mini(p, "sneak", "Customs", "Get the suitcase through the customs hall without an officer seeing you.",
				rank_of(p), {"k": "smuggle", "pay": int(p.suitcase.pay)})
		"buy_dirt":
			p.cash = int(p.cash) - 2000
			p.dirt = BLACKMAIL_TYPES[rng.randi() % BLACKMAIL_TYPES.size()]
			_result(p, "Dirt bought", "The bartender slides over an envelope: photos of the boss of a %s. Pay them a visit." % Balance.BUILDINGS[p.dirt].label.to_lower(), true)
		"blackmail":
			p.dirt = ""
			_mark_scene(p, b)
			if rng.randf() < 0.7:
				var amt := rng.randi_range(3000, 9000) + 1000 * rank_of(p)
				p.cash = int(p.cash) + amt
				_add_points(p, 1)
				_result(p, "Blackmail", "The boss of %s turns pale and pays $%d to make it go away." % [b.name, amt], true)
			else:
				_result(p, "Blackmail flopped", "The photos show the boss of %s with his own wife. Worthless." % b.name, false)
		"sell_kid":
			p.cash = int(p.cash) + 2500
			p.hostage = {}
			_add_points(p, 1)
			_result(p, "Sold", "The bartender pays $2500 and takes the kid into the back.", true)
		"rent":
			var months := int(a[1])
			p.cash = int(p.cash) - Balance.ROOM_RENT * months
			if p.room:
				p.rent_paid = int(p.rent_paid) + months
			else:
				p.room = true
				p.rent_paid = months - 1
			_result(p, "Hotel room", "%s has a room at %s, paid up for %d month%s." % [p.name, b.name, int(p.rent_paid) + 1, "" if int(p.rent_paid) == 0 else "s"], true)
		"fake_cash":
			p.cash = int(p.cash) + 1000
			p.heat = int(p.heat) + 3
			_result(p, "Counterfeit", "$2000 in very convincing fakes. Cops get suspicious faster now.", true)
		"passport":
			p.cash = int(p.cash) - Balance.PASSPORT_PRICE
			p.passport = true
			_result(p, "New identity", "Fresh fake passport. Police checks will happen half as often.", true)
		"travel":
			var dest: Dictionary = state.city.buildings[int(a[1])]
			var fare: int = 150 if b.type == "station" else 80 * p.crew.size()
			p.cash = int(p.cash) - fare
			p.pos = _entrance(dest)
			p.inside = int(dest.id)
			p.menu_path = []
			_log("%s rode across town to %s." % [p.name, dest.name], "move")
			_back_at_scene(p, dest)
		"bribe_chief":
			var months2 := int(a[1])
			var cost := (2000 + 1000 * rank_of(p)) * months2
			p.cash = int(p.cash) - cost
			p.immunity = int(p.immunity) + months2
			_result(p, "The chief is on the payroll", "No arrests for %s for %d month%s." % [p.name, months2, "" if months2 == 1 else "s"], true)
		"free":
			var o: Dictionary = state.players[int(a[1])]
			var bail: int = 1500 * int(o.jail)
			p.cash = int(p.cash) - bail
			o.jail = 0
			_result(p, "Jailbreak, legally", "%s paid $%d and %s walks free. Don't forget who did that." % [p.name, bail, o.name], true)
		"gamble":
			# Played for real (see Casino); the deal rides along in the result so the table can show it.
			var game := a[1]
			var stake := int(a[2])
			var won := rng.randf() < Casino.win_chance(game, _best(p, "smarts"))
			var show := Casino.deal(game, won, rng)
			var how := ""
			match game:
				"blackjack":
					how = "%d against the dealer's %d. " % [show.you_total, show.house_total]
					if int(show.you_total) > 21:
						how = "Bust with %d. " % show.you_total
					elif int(show.house_total) > 21:
						how = "The dealer busts with %d. " % show.house_total
				"poker":
					how = "%s against the house's %s. " % [show.you_hand, show.house_hand]
				"roulette":
					how = "%d %s. " % [show.number, show.color] + ("Right in your line! " if won else "Your line was %d-%d. " % [show.line, int(show.line) + 5])
			if won:
				var won_amt: int = stake * (int(Casino.TABLES[game][1]) - 1)
				p.cash = int(p.cash) + won_amt
				_result(p, game.capitalize(), "%s%s wins $%d!" % [how, p.name, won_amt], true)
			else:
				p.cash = int(p.cash) - stake
				_result(p, game.capitalize(), "%sThe house wins. %s loses $%d." % [how, p.name, stake], false)
			state.hands = int(state.get("hands", 0)) + 1
			show.n = state.hands
			state.pending.show = show
		"protection":
			var prot := int(b.get("protector", 0))
			if prot > 0 and prot != int(p.id) and state.players.has(prot):
				var rival: Dictionary = state.players[prot]
				_start_fight(p, "Turf war", "%s's people already run %s, and they don't share." % [rival.name, b.name],
					Fight.crew_units(rival, 1), {"k": "protection", "prot": prot, "b": b.id})
				return
			_mark_scene(p, b)
			_protection_attempt(p, b)
		"beg":
			if rng.randf() < 0.3:
				_result(p, "Thrown out", "The manager threw %s out of %s. Humiliating." % [p.name, b.name], false)
			else:
				var coins := rng.randi_range(10, 120)
				p.cash = int(p.cash) + coins
				_result(p, "Spare change", "%s begged up $%d. The underworld is laughing." % [p.name, coins], true)
		"borrow":
			var amt2 := int(a[1])
			p.cash = int(p.cash) + amt2
			if int(p.loan) == 0:
				p.loan_months = Balance.LOAN_MONTHS
			p.loan = int(p.loan) + amt2
			_result(p, "Loan", "Eddie counts out $%d. You owe $%d, due in %d months at 5%% a month." % [amt2, p.loan, p.loan_months], true)
		"repay":
			var pay2 := mini(int(p.cash), int(p.loan))
			p.cash = int(p.cash) - pay2
			p.loan = int(p.loan) - pay2
			if int(p.loan) == 0:
				p.loan_months = 0
			_result(p, "Repaid", "%s paid Eddie $%d. Still owed: $%d." % [p.name, pay2, p.loan], true)
		"holiday":
			var h: Dictionary = Balance.HOLIDAYS[int(a[1])]
			p.cash = int(p.cash) - int(h.cost) * p.crew.size()
			p.holiday = 1
			p.holiday_boost = h.boost
			_log("%s and crew flew off to %s." % [p.name, h.name], "info")
			p.steps = 0


# --------------------------------------------------------------------------- pending prompts

func _pending_choose(p: Dictionary, id: String) -> String:
	var pend: Dictionary = state.pending
	if pend.is_empty():
		return "Nothing to answer."
	if int(pend.get("player", 0)) != int(p.id):
		return "Not your prompt."
	var valid := false
	for o in pend.get("options", []):
		if o.id == id and o.get("enabled", true):
			valid = true
	if not valid:
		return "Not an option."
	match str(pend.kind):
		"result":
			state.pending = {}
			state.fight = {}
			state.mini = {}
		"police":
			_police_choice(p, id)
		"mini":
			Mini.give_up(state.mini)
			if state.mini.over:
				_end_mini(p)
			return ""
		"fight":
			if id == "auto":
				Fight.auto(state.fight, rng)
			else:
				Fight.surrender(state.fight)
			_end_fight(p)
		"choice":
			state.pending = {}
			if id.begins_with("ransom:"):
				var parts := id.split(":")
				_ransom_set(p, int(parts[1]), float(parts[2]))
	_after_action(p)
	return ""


func _result(p: Dictionary, title: String, text: String, good: bool) -> void:
	if str(p.get("new_scene", "")) != "":
		text += " The cops will be watching %s now: don't go back." % p.new_scene
		p.new_scene = ""
	text = text.strip_edges().replace("  ", " ")
	_log("%s: %s" % [title, text], "good" if good else "bad")
	state.pending = {"kind": "result", "player": p.id, "title": title, "text": text, "good": good,
		"options": [{"id": "ok", "label": "OK", "enabled": true}]}


# --------------------------------------------------------------------------- helpers

func rank_of(p: Dictionary) -> int:
	return mini(8, int(p.points) * 9 / maxi(1, int(state.target)))


func _add_points(p: Dictionary, n: int) -> void:
	var before := rank_of(p)
	p.points = int(p.points) + n
	var after := rank_of(p)
	if after > before:
		_log("%s is now a %s!" % [p.name, Balance.RANKS[after]], "big")


func _check_win(p: Dictionary) -> void:
	if int(p.points) >= int(state.target) and state.phase == "playing":
		state.phase = "over"
		state.winner = p.id
		state.pending = {}
		state.fight = {}
		state.mini = {}
		_log("%s is the new Boss of Caper City!" % p.name, "big")


func _best(p: Dictionary, stat: String) -> int:
	var best := 0
	for m in p.crew:
		best = maxi(best, int(m[stat]))
	return best


func _best_gear(p: Dictionary) -> int:
	var best := 0
	for m in p.crew:
		best = maxi(best, int(m.gear))
	return best


func _stat_line(m: Dictionary) -> String:
	return "S%d M%d Sm%d N%d" % [m.stamina, m.muscle, m.smarts, m.nerve]


func _k(v: int) -> String:
	return "%dk" % (v / 1000) if v >= 1000 else str(v)


func _new_member(mname: String, boss: bool) -> Dictionary:
	var lo := 1 if boss else 5
	return {"name": mname, "stamina": rng.randi_range(20, Balance.STAMINA_CAP), "muscle": rng.randi_range(lo, 99) if boss else rng.randi_range(5, 70),
		"smarts": rng.randi_range(lo, 99) if boss else rng.randi_range(5, 90), "nerve": rng.randi_range(lo, 99) if boss else rng.randi_range(5, 90), "gear": 0}


func _random_name() -> String:
	var first: String = Balance.FIRST_NAMES[rng.randi() % Balance.FIRST_NAMES.size()]
	if rng.randf() < 0.5:
		return "%s \"%s\" %s" % [first, Balance.NICKNAMES[rng.randi() % Balance.NICKNAMES.size()], Balance.LAST_NAMES[rng.randi() % Balance.LAST_NAMES.size()]]
	return "%s %s" % [first, Balance.LAST_NAMES[rng.randi() % Balance.LAST_NAMES.size()]]


const BLURBS := ["Says he did ten years for bank jobs.", "Quiet. Very good with locks.", "Used to drive getaway cars.",
	"Ex-boxer with a short fuse.", "Claims to know every cop in town.", "Talks big. Might be all talk.",
	"Former bodyguard, fired for 'enthusiasm'.", "Can open any safe, or so she says.", "Looks harmless. Isn't."]


func _init_buildings() -> void:
	for b in state.city.buildings:
		_restock(b)


func _restock(b: Dictionary) -> void:
	match b.type:
		"car_dealer":
			b.stock = _pick_n(range(1, 8), 3)
			b.lot = _pick_n(range(3, 11), 3)
		"arms":
			b.stock = _pick_n(range(1, 9), rng.randi_range(4, 6))
			b.stock.sort()
		"pub", "harbor":
			b.radio_price = rng.randi_range(200, 320)
			b.elec_price = rng.randi_range(400, 700)
			if b.type == "pub":
				b.recruits = []
				for i in rng.randi_range(1, 3):
					var r := _new_member(_random_name(), false)
					r.gear = rng.randi_range(0, 5)
					r.price = rng.randi_range(18, 60) * 100
					r.blurb = BLURBS[rng.randi() % BLURBS.size()]
					b.recruits.append(r)


func _pick_n(src: Array, n: int) -> Array:
	var a := src.duplicate()
	_shuffle(a)
	return a.slice(0, n)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _building_at(x: int, y: int) -> Dictionary:
	return CityGen.building_at(state.city, x, y)


func _entrance(b: Dictionary) -> Array:
	return CityGen.entrance(state.city, b)


func _road_cells_near_center() -> Array:
	var city: Dictionary = state.city
	var cells: Array = []
	var cx: int = city.w / 2
	var cy: int = city.h / 2
	for r in range(0, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := cx + dx
				var y := cy + dy
				if x >= 0 and y >= 0 and x < city.w and y < city.h and city.grid[y * city.w + x] == CityGen.ROAD \
						and not CityGen.is_motorway(city.roads[y * city.w + x]) and not cells.has([x, y]):
					cells.append([x, y])
		if cells.size() >= 6:
			break
	return cells


func _log(text: String, kind: String) -> void:
	state.log.append({"text": text, "kind": kind, "month": state.month})
	if state.log.size() > 60:
		state.log.pop_front()
