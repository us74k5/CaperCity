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
var _cues: Array = []   # sound cues raised while handling the current intent


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) ^ randi()
	rng.seed = seed_value
	state = {
		"phase": "lobby", "seed": seed_value, "month": 1, "target": 35,
		"players": {}, "order": [], "active": 0, "next_pid": 1,
		"room_host": 0, "city": CityGen.generate(seed_value),
		"log": [], "pending": {}, "winner": 0, "rev": 0, "cue": {"n": 0, "names": []},
	}
	_init_buildings()


# --------------------------------------------------------------------------- intents

## Returns "" on success or an error message.
func handle(peer: int, intent: Dictionary) -> String:
	var t: String = str(intent.get("t", ""))
	var err := ""
	_cues = []
	match t:
		"join":
			err = _join(peer, str(intent.get("name", "")), str(intent.get("crew", "")), false)
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
			if state.phase == "playing":
				_log("%s's turn was skipped by the host." % _active().name, "info")
				state.pending = {}
				_end_turn()
		_:
			if state.phase != "playing":
				return "The game is not running."
			var p := _active()
			if int(p.owner) != peer:
				return "It's not your turn."
			err = _handle_turn(p, t, intent)
	if _cues.size() > 0:
		state.cue = {"n": int(state.cue.n) + 1, "names": _cues.duplicate()}
	state.rev = int(state.rev) + 1
	return err


func _handle_turn(p: Dictionary, t: String, intent: Dictionary) -> String:
	if not state.pending.is_empty() and t != "pending":
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
		"end_turn":
			if int(p.inside) >= 0:
				_leave(p)
			_end_turn()
			return ""
	return "Unknown action."


# --------------------------------------------------------------------------- lobby

func _join(peer: int, pname: String, crew: String, local: bool) -> String:
	if state.phase != "lobby":
		return "The game has already started."
	if state.players.size() >= 6:
		return "The room is full."
	if not local:
		for pid in state.players:
			if int(state.players[pid].owner) == peer and not state.players[pid].local:
				return ""
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
		"inside": -1, "menu_path": [], "menu": [],
		"jail": 0, "holiday": 0, "room": false, "rent_paid": 0,
		"loan": 0, "loan_months": 0, "passport": false, "immunity": 0, "heat": 0,
		"radios": 0, "electronics": 0, "dirt": "", "hostage": {}, "ransom": {},
		"gang_war_used": false, "connected": true,
	}
	_log("%s joined with %s." % [pname, crew], "info")
	return ""


func _start(target: int) -> String:
	if state.phase != "lobby":
		return "Already started."
	if state.players.is_empty():
		return "Nobody has joined."
	state.target = clampi(target, 5, 200)
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
		if peer == state.room_host:
			state.room_host = 0 if state.players.is_empty() else int(state.players.values()[0].owner)
	state.rev = int(state.rev) + 1


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
		p.gang_war_used = false
		p.inside = -1
		p.menu_path = []
		_log("Month %d: %s's turn." % [state.month, p.name], "turn")
		_refresh_menu(p)
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
	_cue("month")
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
		var months := 1 + debt / 5000
		p.jail = int(p.jail) + months
		msg += ". Still short, so they handed %s to the cops (%d months)" % [p.name, months]
	p.loan = 0
	p.loan_months = 0
	_log(msg + ".", "bad")


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
	var cell: int = city.grid[ny * city.w + nx]
	if cell == CityGen.ROAD:
		p.pos = [nx, ny]
		p.steps = int(p.steps) - 1
		_maybe_police_check(p)
		_after_action(p)
		return ""
	if cell == CityGen.BUILDING:
		var b := _building_at(nx, ny)
		if b.is_empty():
			return "Nothing there."
		p.steps = int(p.steps) - 1
		_enter(p, b)
		return ""
	return "You can't go that way."


func _enter(p: Dictionary, b: Dictionary) -> void:
	p.inside = int(b.id)
	p.menu_path = []
	_log("%s walks into %s." % [p.name, b.name], "move")
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
	_check_win(p)
	if state.phase != "playing":
		return
	if state.pending.is_empty() and (int(p.steps) <= 0 or int(p.jail) > 0):
		if int(p.jail) == 0:
			_log("%s is out of steps." % p.name, "info")
		_end_turn()
		return
	_refresh_menu(p)


func _maybe_police_check(p: Dictionary) -> void:
	if int(p.immunity) > 0:
		return
	var rank := rank_of(p)
	var chance := 0.012 + 0.005 * rank + 0.007 * int(p.heat)
	if p.passport:
		chance *= 0.5
	if rng.randf() < chance:
		var why := "A routine check."
		if int(p.heat) >= 6:
			why = "They have a wanted poster with your face on it."
		_police_encounter(p, "Police checkpoint! " + why)


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
	p.menu_path = []
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
	if ok:
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
					m.append(_e("act:buy_gear:%d:%d" % [gi2, i], "Give it to %s" % mem.name, "now: %s" % Balance.GEAR[int(mem.gear)].name,
						fits and int(p.cash) >= int(g2.price), "Not smart or tough enough to handle it." if not fits else "Not enough cash.", 1))
			elif sub == "train":
				for i in crew_n:
					m.append(_e("sub:train_%d" % i, "Train %s" % p.crew[i].name, _stat_line(p.crew[i])))
			elif sub.begins_with("train_"):
				var mi := int(sub.substr(6))
				for s in ["muscle", "smarts", "nerve"]:
					m.append(_e("act:train:%d:%s" % [mi, s], "Train %s" % s.capitalize(), "$600 · 2 steps", int(p.cash) >= 600 and int(p.steps) >= 2, "Not enough cash or steps.", 2))
				m.append(_e("act:train:%d:all" % mi, "Full program (all three)", "$1500 · 4 steps", int(p.cash) >= 1500 and int(p.steps) >= 4, "Not enough cash or steps.", 4))
			else:
				m.append(_e("sub:buy_gear", "Buy weapons", "This dealer's stock varies"))
				m.append(_e("sub:train", "Train your crew", "Muscle, Smarts, Nerve"))
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
	if path.size() > 0:
		m.append(_e("back", "Back"))
	m.append(_e("leave", "Leave"))
	return m


func _blackmail_entry(p: Dictionary, b: Dictionary) -> Dictionary:
	var ok: bool = p.dirt == b.type
	return _e("act:blackmail", "Blackmail the boss", "Use your dirt · 2 steps", ok and int(p.steps) >= 2,
		"You've got nothing on them. Bartenders sell dirt." if not ok else "Not enough steps.", 2)


# --------------------------------------------------------------------------- crimes

const CRIMES := {
	"pickpocket": {"label": "Pick some pockets", "check": "smarts", "base": 0.55, "steps": 2, "loot": true, "fail": "police", "heat": 1},
	"pickpocket_train": {"label": "Work the crowded trains", "check": "smarts", "base": 0.65, "steps": 3, "loot": true, "fail": "police", "heat": 1},
	"rob_hotel": {"label": "Rob the front desk", "check": "nerve", "base": 0.5, "steps": 3, "pay": [800, 3000], "fail": "fight", "enemy": 4, "heat": 2},
	"bank_raid": {"label": "Hold up the teller", "check": "nerve", "base": 0.45, "steps": 3, "pay": [3000, 9000], "gear": Balance.PISTOL, "fail": "fight", "enemy": 9, "heat": 4},
	"crack_safe": {"label": "Crack the vault at night", "check": "smarts", "base": 0.35, "steps": 5, "pay": [8000, 20000], "fail": "police", "heat": 4, "rank": 1},
	"rob_store": {"label": "Rob the store", "check": "nerve", "base": 0.55, "steps": 2, "pay": [400, 1800], "fail": "fight", "enemy": 3, "heat": 2},
	"mail_train": {"label": "Rob the mail train", "check": "muscle", "base": 0.4, "steps": 6, "pay": [6000, 15000], "fail": "fight", "enemy": 10, "heat": 5, "rank": 2},
	"steal_containers": {"label": "Steal shipping containers", "check": "muscle", "base": 0.5, "steps": 4, "pay": [1500, 5000], "fail": "police", "heat": 2},
	"steal_electronics": {"label": "Clean out the electronics", "check": "smarts", "base": 0.5, "steps": 4, "goods": true, "fail": "police", "heat": 2},
	"money_transport": {"label": "Hit the armored truck", "check": "nerve", "base": 0.4, "steps": 5, "pay": [5000, 12000], "gear": Balance.PISTOL, "fail": "fight", "enemy": 11, "heat": 5, "rank": 3},
	"rob_pay_office": {"label": "Raid the city pay office", "check": "nerve", "base": 0.4, "steps": 4, "pay": [4000, 10000], "fail": "fight", "enemy": 8, "heat": 4, "rank": 2},
	"kidnap_child": {"label": "Kidnap a child", "check": "smarts", "base": 0.5, "steps": 3, "hostage": "child", "value": [4000, 9000], "fail": "fight", "enemy": 3, "heat": 4, "room": true, "no_hostage": true},
	"kidnap_villa": {"label": "Snatch the rich kid", "check": "smarts", "base": 0.4, "steps": 4, "hostage": "child", "value": [8000, 18000], "fail": "fight", "enemy": 5, "heat": 5, "room": true, "no_hostage": true, "rank": 1},
	"kidnap_dignitary": {"label": "Snatch the visiting dignitary", "check": "smarts", "base": 0.3, "steps": 5, "hostage": "dignitary", "value": [20000, 40000], "fail": "fight", "enemy": 10, "heat": 7, "room": true, "no_hostage": true, "rank": 4},
}


func _crime_odds(p: Dictionary, c: Dictionary) -> float:
	var stat: int = _best(p, str(c.check))
	var odds: float = float(c.base) + (stat - 40) / 150.0 + 0.01 * Balance.GEAR[_best_gear(p)].power - 0.015 * rank_of(p)
	return clampf(odds, 0.05, 0.95)


func _do_crime(p: Dictionary, key: String) -> void:
	var c: Dictionary = CRIMES[key]
	var b: Dictionary = state.city.buildings[int(p.inside)]
	p.heat = int(p.heat) + int(c.heat)
	if rng.randf() < _crime_odds(p, c):
		_crime_success(p, c, b, "")
		return
	match str(c.fail):
		"police":
			_police_encounter(p, "%s went wrong. The cops are here!" % c.label)
		"fight":
			var enemy: int = int(c.enemy) + rank_of(p)
			var r := _fight(p, enemy, true)
			if r.won:
				_crime_success(p, c, b, "It turned into a shootout. %s " % r.text)
			else:
				_result(p, "Busted", "It turned into a shootout and %s lost. %s" % [p.name, r.text], false)
				_arrest(p)


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
		_cue("kidnap")
		text += "%s grabbed %s and stashed them in the hotel room." % [p.name, who]
		_add_points(p, 1)
		_log("%s: %s" % [c.label, text], "crime")
		_offer_ransom(p, text)
		return
	_add_points(p, 1)
	_result(p, c.label, text, true)


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
		_cue("cash")
		_add_points(p, 1)
		_result(p, "Ransom collected", "The case was right where they said: $%d. The hostage goes home." % r.amount, true)
	else:
		var catch_odds := clampf(0.35 + (_best(p, "muscle") - 30) / 150.0 + int(p.crew[0].stamina) / 200.0, 0.1, 0.85)
		if rng.randf() < catch_odds:
			p.cash = int(p.cash) + int(r.amount)
			_add_points(p, 1)
			var t := "The %s bolted with the money case, but %s caught up. $%d collected." % ["kid" if kind == "child" else "hostage", p.name, r.amount]
			_result(p, "Ransom collected (barely)", t, true)
		else:
			_result(p, "Ransom: tricked!", "The %s tore loose and ran off with the money case. %s got nothing." % ["kid" if kind == "child" else "hostage", p.name], false)
	p.ransom = {}
	p.hostage = {}


# --------------------------------------------------------------------------- police & fights

func _police_encounter(p: Dictionary, text: String) -> void:
	if int(p.immunity) > 0:
		_log("The cops recognize %s and look the other way. The chief has been paid." % p.name, "info")
		return
	var bribe := 300 + 400 * rank_of(p)
	_cue("police_alert")
	state.pending = {"kind": "police", "player": p.id, "title": "Police!", "text": text, "options": [
		{"id": "bribe", "label": "Bribe them ($%d)" % bribe, "enabled": int(p.cash) >= bribe},
		{"id": "run", "label": "Run for it", "enabled": true},
		{"id": "fight", "label": "Shoot it out", "enabled": true},
	], "bribe": bribe}


func _police_choice(p: Dictionary, choice: String) -> void:
	var pend: Dictionary = state.pending
	state.pending = {}
	var cops := 4 + 2 * rank_of(p)
	match choice:
		"bribe":
			p.cash = int(p.cash) - int(pend.bribe)
			if rng.randf() < 0.85:
				_result(p, "Bribe accepted", "The officers pocket $%d and wave %s on." % [pend.bribe, p.name], true)
			else:
				var r := _fight(p, cops, true)
				if r.won:
					_result(p, "Double-crossed", "They took the money and drew their guns anyway. %s %s shot their way out." % [r.text, p.name], true)
					p.heat = int(p.heat) + 3
				else:
					_result(p, "Double-crossed", "They took the money and arrested %s for bribery. %s" % [p.name, r.text], false)
					_arrest(p)
		"run":
			var odds := clampf(0.3 + int(p.crew[0].stamina) / 120.0 + (_best(p, "smarts") - 40) / 300.0, 0.1, 0.8)
			if rng.randf() < odds:
				_result(p, "Got away", "%s ducked down an alley and lost them." % p.name, true)
				p.heat = int(p.heat) + 1
			else:
				var r2 := _fight(p, cops, true)
				if r2.won:
					_result(p, "Cornered", "They cornered %s, who fought free. %s" % [p.name, r2.text], true)
					p.heat = int(p.heat) + 3
				else:
					_result(p, "Caught", "They caught %s. %s" % [p.name, r2.text], false)
					_arrest(p)
		_:
			var r3 := _fight(p, cops, true)
			if r3.won:
				_result(p, "Shootout", "%s shot it out with the cops and won. %s" % [p.name, r3.text], true)
				p.heat = int(p.heat) + 4
			else:
				_result(p, "Shootout lost", "%s lost the shootout. %s" % [p.name, r3.text], false)
				_arrest(p)


func _arrest(p: Dictionary) -> void:
	_cue("jail_door")
	var months := 1 + rank_of(p) / 4
	p.jail = months
	p.heat = int(p.heat) / 2
	p.steps = 0
	p.inside = -1
	p.menu_path = []
	_log("%s was sentenced to %d month%s in jail." % [p.name, months, "" if months == 1 else "s"], "bad")


## Auto-resolved fight. Returns {won, text}. Crew members can be killed in lethal fights.
func _fight(p: Dictionary, enemy_power: int, lethal: bool) -> Dictionary:
	if not "gang_war" in _cues:
		_cue("shootout")
	var mine := _crew_power(p)
	var win_chance := mine / (mine + float(enemy_power))
	var won := rng.randf() < win_chance
	var lines: Array = []
	var killed: Array = []
	for i in range(p.crew.size() - 1, -1, -1):
		var m: Dictionary = p.crew[i]
		var dmg := rng.randi_range(2, 8) if won else rng.randi_range(6, 16)
		m.stamina = maxi(0, int(m.stamina) - dmg)
		if int(m.stamina) == 0 and lethal and i > 0 and rng.randf() < 0.35:
			killed.append(m.name)
			p.crew.remove_at(i)
	var downed := rng.randi_range(1, 3) if won else rng.randi_range(0, 1)
	if downed > 0:
		lines.append("%d of them went down." % downed)
	if killed.size() > 0:
		lines.append("%s didn't make it." % ", ".join(killed))
	return {"won": won, "text": " ".join(lines)}


func _crew_power(p: Dictionary) -> float:
	var total := 0.0
	for m in p.crew:
		var g: Dictionary = Balance.GEAR[int(m.gear)]
		total += float(g.power) * (0.6 + int(m.muscle) / 100.0) * (0.3 + 0.7 * minf(1.0, int(m.stamina) / float(Balance.STAMINA_CAP)))
	return maxf(total, 0.3)


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
	_cue("gang_war")
	var mine := _crew_power(p)
	var theirs := _crew_power(o)
	var won := rng.randf() < mine / (mine + theirs)
	var winner: Dictionary = p if won else o
	var loser: Dictionary = o if won else p
	var loot := int(loser.cash) / 4
	loser.cash = int(loser.cash) - loot
	winner.cash = int(winner.cash) + loot
	var r_w := _fight(winner, 1, true)
	var r_l := _fight(loser, 99, true)
	_add_points(winner, 1)
	var text := "%s's crew attacked %s's crew. %s won and took $%d. %s %s" % [p.crew_name, o.crew_name, winner.name, loot, r_w.text, r_l.text]
	_result(p, "Gang war!", text.strip_edges(), won)
	_check_win(o)
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
			_result(p, "New wheels", "%s drives off in a %s (%d steps per turn)." % [p.name, Balance.CARS[ci].name, Balance.CARS[ci].steps], true)
		"steal_car":
			var ci2 := int(a[1])
			var odds := clampf(0.7 - 0.05 * ci2 + (_best(p, "smarts") - 40) / 150.0, 0.08, 0.9)
			p.heat = int(p.heat) + 2
			if rng.randf() < odds:
				p.car = ci2
				_add_points(p, 1)
				_result(p, "Car stolen", "%s hot-wired a %s and peeled out of the lot." % [p.name, Balance.CARS[ci2].name], true)
			else:
				_police_encounter(p, "The alarm on the %s went off. The cops are here!" % Balance.CARS[ci2].name)
		"buy_gear":
			var gi := int(a[1])
			var mem: Dictionary = p.crew[int(a[2])]
			p.cash = int(p.cash) - int(Balance.GEAR[gi].price)
			mem.gear = gi
			_result(p, "Armed up", "%s now carries a %s." % [mem.name, Balance.GEAR[gi].name], true)
		"train":
			var mem2: Dictionary = p.crew[int(a[1])]
			var stats: Array = ["muscle", "smarts", "nerve"] if a[2] == "all" else [a[2]]
			p.cash = int(p.cash) - (1500 if a[2] == "all" else 600)
			var parts: Array = []
			for s in stats:
				var gain := rng.randi_range(4, 9)
				mem2[s] = mini(99, int(mem2[s]) + gain)
				parts.append("%s +%d" % [s.capitalize(), gain])
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
			var r2 := _fight(p, 4 + 2 * rank_of(p), true)
			p.heat = int(p.heat) + 3
			if r2.won:
				p.cash = int(p.cash) + pay
				_add_points(p, 1)
				_result(p, "Hit job done", "The target and his bodyguards are dealt with. %s collects $%d. %s" % [p.name, pay, r2.text], true)
			else:
				_result(p, "Hit job failed", "The bodyguards were ready for %s. %s" % [p.name, r2.text], false)
		"buy_dirt":
			p.cash = int(p.cash) - 2000
			p.dirt = BLACKMAIL_TYPES[rng.randi() % BLACKMAIL_TYPES.size()]
			_result(p, "Dirt bought", "The bartender slides over an envelope: photos of the boss of a %s. Pay them a visit." % Balance.BUILDINGS[p.dirt].label.to_lower(), true)
		"blackmail":
			p.dirt = ""
			if rng.randf() < 0.7:
				var amt := rng.randi_range(3000, 9000) + 1000 * rank_of(p)
				p.cash = int(p.cash) + amt
				_cue("cash")
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
			var game := a[1]
			var stake := int(a[2])
			var table := {"blackjack": [0.46, 2], "poker": [0.31, 3], "roulette": [0.15, 6]}
			var odds2: float = float(table[game][0]) + (_best(p, "smarts") - 50) / 1000.0
			if rng.randf() < odds2:
				var won_amt: int = stake * (int(table[game][1]) - 1)
				p.cash = int(p.cash) + won_amt
				_cue("gamble_win")
				_result(p, game.capitalize(), "%s wins $%d!" % [p.name, won_amt], true)
			else:
				p.cash = int(p.cash) - stake
				_cue("gamble_lose")
				_result(p, game.capitalize(), "The house wins. %s loses $%d." % [p.name, stake], false)
		"protection":
			var prot := int(b.get("protector", 0))
			var odds3 := clampf(0.45 + (_best(p, "nerve") - 40) / 120.0 + 0.04 * rank_of(p), 0.1, 0.9)
			if prot > 0 and state.players.has(prot):
				var r3 := _fight(p, int(_crew_power(state.players[prot])) + 2, true)
				if not r3.won:
					_result(p, "Turf trouble", "%s's people already run this block and they ran %s off. %s" % [state.players[prot].name, p.name, r3.text], false)
					return
			if rng.randf() < odds3:
				b.protector = p.id
				_add_points(p, 1)
				_result(p, "Protection racket", "%s now pays %s $300 every month to stay in one piece." % [b.name, p.name], true)
			else:
				_police_encounter(p, "The owner called the cops instead of paying.")
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
			_cue("holiday")
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
		"police":
			_police_choice(p, id)
		"choice":
			state.pending = {}
			if id.begins_with("ransom:"):
				var parts := id.split(":")
				_ransom_set(p, int(parts[1]), float(parts[2]))
	_after_action(p)
	return ""


func _result(p: Dictionary, title: String, text: String, good: bool) -> void:
	text = text.strip_edges().replace("  ", " ")
	if _cues.is_empty():
		_cue("success" if good else "fail")
	_log("%s: %s" % [title, text], "good" if good else "bad")
	state.pending = {"kind": "result", "player": p.id, "title": title, "text": text, "good": good,
		"options": [{"id": "ok", "label": "OK", "enabled": true}]}


# --------------------------------------------------------------------------- helpers

## Queue a music sting for every client (see scripts/audio/music.gd for the names).
func _cue(name: String) -> void:
	if not name in _cues:
		_cues.append(name)


func rank_of(p: Dictionary) -> int:
	return mini(8, int(p.points) * 9 / maxi(1, int(state.target)))


func _add_points(p: Dictionary, n: int) -> void:
	var before := rank_of(p)
	p.points = int(p.points) + n
	var after := rank_of(p)
	if after > before:
		_cue("rank_up")
		_log("%s is now a %s!" % [p.name, Balance.RANKS[after]], "big")


func _check_win(p: Dictionary) -> void:
	if int(p.points) >= int(state.target) and state.phase == "playing":
		state.phase = "over"
		state.winner = p.id
		state.pending = {}
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
	for b in state.city.buildings:
		if x >= int(b.x) and x < int(b.x) + int(b.w) and y >= int(b.y) and y < int(b.y) + int(b.h):
			return b
	return {}


func _entrance(b: Dictionary) -> Array:
	var city: Dictionary = state.city
	for dy in range(-1, int(b.h) + 1):
		for dx in range(-1, int(b.w) + 1):
			var x: int = int(b.x) + dx
			var y: int = int(b.y) + dy
			if x >= 0 and y >= 0 and x < city.w and y < city.h and city.grid[y * city.w + x] == CityGen.ROAD:
				return [x, y]
	return [int(b.x), int(b.y)]


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
				if x >= 0 and y >= 0 and x < city.w and y < city.h and city.grid[y * city.w + x] == CityGen.ROAD and not cells.has([x, y]):
					cells.append([x, y])
		if cells.size() >= 6:
			break
	return cells


func _log(text: String, kind: String) -> void:
	state.log.append({"text": text, "kind": kind, "month": state.month})
	if state.log.size() > 60:
		state.log.pop_front()
