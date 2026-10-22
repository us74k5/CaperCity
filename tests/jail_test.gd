extends SceneTree
## Jail (car, weapons and a fine), going back to the scene of a crime, Easy Eddie's collectors, and
## the fight screen clearing after a won kidnapping's ransom prompt.
## Run: godot --headless --path . --script res://tests/jail_test.gd

var fails := 0
var gs: GameServer


func _init() -> void:
	gs = GameServer.new(11)
	gs.handle(1, {"t": "join", "name": "Ana", "crew": ""})
	gs.handle(2, {"t": "join", "name": "Bo", "crew": ""})
	gs.handle(1, {"t": "start", "target": 50})
	var ana: Dictionary = gs.state.players[1]
	var bo: Dictionary = gs.state.players[2]

	# Jail takes the car, every weapon and a $500 fine.
	ana.car = 2
	ana.cash = 3000
	ana.crew[0].gear = 3
	ana.crew.append(gs._new_member("Vic", false))
	ana.crew[1].gear = 1
	var text: String = gs._arrest(ana)
	print("arrest: ", text)
	_check(int(ana.jail) >= 1, "locked up")
	_check(int(ana.car) == 0, "the car is impounded")
	_check(ana.crew.all(func(m): return int(m.gear) == 0), "the weapons are gone")
	_check(int(ana.cash) == 2500, "a $500 fine (cash %d)" % ana.cash)
	_check("impounded" in text and "$500" in text, "the result says so")
	ana.jail = 0
	ana.cash = 200
	gs._arrest(ana)
	_check(int(ana.cash) == 0, "a short crew pays what it has")
	ana.jail = 0

	# Going back to where you committed a crime is an arrest on the spot.
	var lot := _building("car_dealer")
	var bank := _building("bank")
	ana.cash = 5000
	ana.inside = int(lot.id)
	gs._mark_scene(ana, lot)
	gs._result(ana, "Car stolen", "Got it.", true)
	_check("watching %s" % lot.name in str(gs.state.pending.text), "the result warns you off the scene")
	gs.state.pending = {}
	gs._leave(ana)
	ana.steps = 10
	gs._enter(ana, bank)
	_check(gs.state.pending.is_empty() and int(ana.inside) == int(bank.id), "other buildings are fine")
	gs._leave(ana)
	ana.car = 1
	gs._enter(ana, lot)
	_check(gs.state.pending.get("title", "") == "Back at the scene" and int(ana.jail) > 0, "back at the scene: arrested")
	_check(int(ana.car) == 0 and int(ana.inside) == -1, "and jailed like any arrest")
	_check(ana.scenes.is_empty(), "time served wipes the slate")
	gs.state.pending = {}
	ana.jail = 0
	ana.scenes = [int(lot.id)]
	ana.immunity = 2
	gs._enter(ana, lot)
	_check(int(ana.jail) == 0 and gs.state.pending.is_empty(), "a paid-off chief keeps the cops away")
	ana.immunity = 0
	gs._leave(ana)

	# Every kind of crime marks the building.
	ana.scenes = []
	ana.inside = int(bank.id)
	gs._do_crime(ana, "bank_raid")
	_check(ana.scenes.has(int(bank.id)), "a bank job marks the bank")
	gs.state.pending = {}
	gs.state.fight = {}
	gs.state.mini = {}
	ana.jail = 0
	ana.inside = int(lot.id)
	gs._exec(ana, PackedStringArray(["steal_car", "1"]))
	_check(ana.scenes.has(int(lot.id)), "stealing a car marks the lot")
	gs.state.pending = {}
	gs.state.fight = {}
	gs.state.mini = {}
	ana.jail = 0

	# A won kidnapping fight, then the ransom prompt: the fight screen must go away after it.
	var park := _building("playground")
	ana.inside = int(park.id)
	ana.steps = 10
	ana.hostage = {}
	ana.scenes = []
	gs._start_fight(ana, "Kidnap a child", "It went wrong.", Fight.squad("staff", 3, gs.rng),
		{"k": "crime", "key": "kidnap_child", "b": park.id})
	gs._mark_scene(ana, park)
	gs.state.fight.won = true
	gs.state.fight.over = true
	gs._end_fight(ana)
	gs._after_action(ana)
	_check(gs.state.pending.get("kind", "") == "choice", "won the fight, now the ransom (%s)" % gs.state.pending.get("kind", ""))
	_check("watching %s" % park.name in str(gs.state.pending.text), "the ransom prompt warns you off the playground")
	var opt: String = gs.state.pending.options[1].id
	_check(gs.handle(1, {"t": "pending", "id": opt}) == "", "set the ransom")
	_check(gs.state.fight.is_empty() and gs.state.mini.is_empty(), "the fight screen is gone")
	_check(gs.handle(1, {"t": "menu", "id": "leave"}) == "" and int(ana.inside) == -1, "and you can leave")

	# Easy Eddie: a reminder the month before, a short sentence, and news when you're back.
	gs.state.pending = {}
	ana.loan = 40000
	ana.loan_months = 1
	ana.cash = 1000
	ana.car = 2
	bo.loan = 1000
	bo.loan_months = 2
	_end_turns_until(2)
	_check(gs.state.pending.get("title", "") == "Easy Eddie", "Bo hears his loan is due (%s)" % gs.state.pending.get("title", ""))
	gs.state.pending = {}
	_end_turns_until(1, 2)   # Ana's loan falls due at the month's end
	_check(int(ana.loan) == 0 and int(ana.car) == 0, "the collectors took the car")
	print("eddie: ", gs.state.pending.get("text", ""))
	_check(gs.state.pending.get("title", "") == "While you were away", "Ana hears what happened when she's out")
	_check("collectors" in str(gs.state.pending.get("text", "")), "and why")

	print("jail: %s" % ("ok" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


## Ends turns until it's `pid`'s turn (after at least `min_turns` turns).
func _end_turns_until(pid: int, min_turns: int = 1) -> void:
	for i in 40:
		gs.state.pending = {}
		gs.handle(int(gs._active().owner), {"t": "end_turn"})
		if i + 1 >= min_turns and int(gs._active().id) == pid:
			return


func _building(type: String) -> Dictionary:
	for b in gs.state.city.buildings:
		if b.type == type:
			return b
	push_error("no " + type)
	return {}


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
