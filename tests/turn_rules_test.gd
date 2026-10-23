extends SceneTree
## Turn rules: the police reset every turn, the impound lot, a crew fighting a stakeout, jail turns
## played as the showers (nobody keeps hold of the soap), the wheelchair after jail, Easy Eddie's
## gang for an unpaid loan, casino payouts and the runaway kid's speed.
## Run: godot --headless --path . --script res://tests/turn_rules_test.gd

var fails := 0
var gs: GameServer
var ana: Dictionary
var bo: Dictionary


func _init() -> void:
	gs = GameServer.new(21)
	gs.handle(1, {"t": "join", "name": "Ana", "crew": ""})
	gs.handle(2, {"t": "join", "name": "Bo", "crew": ""})
	gs.handle(1, {"t": "start", "target": 50})
	ana = gs.state.players[1]
	bo = gs.state.players[2]
	_to_turn(1)

	_police_reset()
	_impound()
	_stakeout()
	_jail_turns()
	_eddie()
	_casino()
	_kid()

	print("turn rules: %s" % ("ok" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


func _police_reset() -> void:
	var bank := _building("bank")
	ana.inside = int(bank.id)
	gs._mark_scene(ana, bank)
	gs.state.pending = {}
	ana.walk_out = false
	gs._leave(ana)
	gs._police_encounter(ana, "Test stop.", 3)
	_check(gs.state.pending.kind == "police", "a stop is on")
	gs.skip_turn("for the test")
	_check(gs.state.pending.get("kind", "") != "police", "the stop doesn't carry into the next turn")
	_to_turn(1)
	_check(ana.scenes.is_empty(), "a new turn: last turn's crime scenes are open again")
	ana.steps = 20
	gs._enter(ana, bank)
	_check(gs.state.pending.is_empty() and int(ana.inside) == int(bank.id) and int(ana.jail) == 0, "the bank can be robbed again")
	gs._leave(ana)


func _impound() -> void:
	ana.cash = 5000
	ana.car = 3
	ana.car_stolen = false
	gs._jail(ana, 1)
	_check(int(ana.car) == 0 and int(ana.impound) == 3, "a bought car goes to the impound lot")
	ana.jail = 0
	ana.steps = 10
	var hq := _building("police")
	ana.inside = int(hq.id)
	ana.menu_path = []
	var fee := GameServer.impound_fee(3)
	var found := false
	for e in gs._build_menu(ana):
		if e.id == "act:impound":
			found = e.enabled
	_check(found, "police HQ offers the car back (%s)" % str(gs._build_menu(ana).map(func(e): return [e.id, e.enabled, e.reason])))
	var before := int(ana.cash)
	gs._exec(ana, PackedStringArray(["impound"]))
	_check(int(ana.car) == 3 and int(ana.impound) == 0 and int(ana.cash) == before - fee, "paid $%d and got it back" % fee)
	gs.state.pending = {}
	gs._leave(ana)
	ana.car = 9
	ana.car_stolen = true
	gs._jail(ana, 1)
	ana.jail = 0
	_check(int(ana.car) == 0 and int(ana.impound) == 0, "a stolen car is gone for good")
	ana.inside = int(hq.id)
	for e in gs._build_menu(ana):
		_check(e.id != "act:impound", "and there's nothing to pay for")
	gs._leave(ana)


func _stakeout() -> void:
	var store := _building("bank")
	ana.jail = 0
	ana.immunity = 0
	ana.steps = 20
	ana.scenes = [int(store.id)]
	while ana.crew.size() > 1:
		ana.crew.pop_back()
	gs._enter(ana, store)
	_check(int(ana.jail) > 0 and gs.state.pending.get("kind", "") == "result", "on your own: arrested on the spot")
	gs.state.pending = {}
	ana.jail = 0
	ana.jail_served = 0
	ana.scenes = [int(store.id)]
	ana.crew.append(gs._new_member("Vic", false))
	gs._enter(ana, store)
	_check(gs.state.pending.get("kind", "") == "fight" and int(ana.jail) == 0, "with a crew: a fight first, no jail yet")
	gs.handle(1, {"t": "pending", "id": "surrender"})
	_check(int(ana.jail) > 0, "lose it, and then it's jail")
	gs.handle(1, {"t": "pending", "id": "ok"})


func _jail_turns() -> void:
	ana.jail = 2
	ana.jail_served = 0
	ana.wheelchair = 0
	ana.crew[0].stamina = 30
	ana.car = 4
	ana.car_stolen = false
	_to_turn(1)
	_check(gs.state.pending.get("kind", "") == "mini" and gs.state.mini.game == "shower", "a jail month is the showers, not a skipped turn")
	# The best anyone could play it: sharp eyes, fast thumbs. Still drops it, right at the end.
	var held: Array = []
	for seed in 60:
		held.append(_shower(seed, 1, 2, "best"))
	held.sort()
	print("shower: the best player held on %.1f-%.1f s of %.0f" % [held[0], held[-1], Shower.SECONDS])
	_check(float(held[0]) >= Shower.SECONDS - Shower.SURE_DROP - 0.2, "the best players hold on nearly to the end")
	_check(float(held[-1]) < Shower.SECONDS, "but nobody gets to the end")
	var lazy: Array = []
	var mash: Array = []
	for seed in 60:
		lazy.append(_shower(seed, 1, 2, "none"))
		mash.append(_shower(seed, 1, 2, "mash"))
	lazy.sort()
	mash.sort()
	_check(float(lazy[30]) < 5.0, "hands off, it's gone in seconds (median %.1f s)" % lazy[30])
	_check(float(mash[-1]) < 2.0, "mashing one side throws it out the other")
	# This turn's shower, played to the end: the cut to Bubba, then the energy.
	var m: Dictionary = gs.state.mini
	m.ready = 0
	var before := int(ana.crew[0].stamina)
	var cut_from := -1
	while not m.over:
		Mini.step(m, gs.rng)
		if m.phase == "dropped" and cut_from < 0:
			cut_from = int(m.tick)
	_check(cut_from > 0 and int(m.tick) - cut_from >= int(Shower.CUT_SECONDS / Mini.TICK) - 1 and not m.won, "the soap drops, then Bubba's scene plays out")
	gs._end_mini(ana)
	_check(int(ana.crew[0].stamina) == before - Balance.SHOWER_STAMINA, "%d less energy after the shower" % Balance.SHOWER_STAMINA)
	gs.handle(1, {"t": "pending", "id": "ok"})
	_check(gs._active() != ana, "the jail turn ends after it")
	_to_turn(1)
	_check(gs.state.mini.get("game", "") == "shower", "the second month too")
	before = int(ana.crew[0].stamina)
	gs.handle(1, {"t": "pending", "id": "give_up"})
	_check(not gs.state.mini.over and gs.state.mini.phase == "dropped", "letting go still plays the scene")
	while not gs.state.mini.over:
		gs.tick(Mini.TICK)
	_check(int(ana.crew[0].stamina) == before - Balance.SHOWER_STAMINA, "and costs the energy too")
	gs.handle(1, {"t": "pending", "id": "ok"})
	while ana.crew.size() > 1:
		ana.crew.pop_back()
	_to_turn(1)
	gs.state.pending = {}
	_check(ana.chair and int(ana.steps_max) == Balance.WHEELCHAIR_STEPS, "in a wheelchair, on %d steps" % Balance.WHEELCHAIR_STEPS)
	_check(not gs._driving(ana), "and nobody to drive the car")
	var dir := ""
	for d in ["N", "S", "E", "W"]:
		var c: Vector2i = Vector2i(int(ana.pos[0]), int(ana.pos[1])) + GameServer.DIRS[d]
		if CityGen.step_cost(gs.state.city, Vector2i(int(ana.pos[0]), int(ana.pos[1])), d, true) == CityGen.NEEDS_CAR:
			dir = d
	if dir != "":
		_check(gs._move(ana, dir) != "", "no motorway in a wheelchair")
	gs.handle(1, {"t": "end_turn"})
	_to_turn(1)
	gs.state.pending = {}
	_check(ana.chair, "two months in: two turns in the chair (turn 2)")
	ana.crew.append(gs._new_member("Driver", false))
	_check(gs._driving(ana), "a crew member can drive")
	gs.handle(1, {"t": "end_turn"})
	_to_turn(1)
	gs.state.pending = {}
	_check(not ana.chair and int(ana.steps_max) == Balance.CARS[int(ana.car)].steps, "then back on your feet and in the car")


func _eddie() -> void:
	ana.loan = 20000
	ana.loan_months = 1
	ana.eddie_due = false
	_to_turn(2)
	gs.state.pending = {}
	gs.handle(2, {"t": "end_turn"})   # the month ends: the loan falls due
	_check(ana.eddie_due or gs.state.pending.get("title", "") == "Easy Eddie", "an unpaid loan sends Eddie")
	_to_turn(1)
	var f: Dictionary = gs.state.fight
	_check(gs.state.pending.get("kind", "") == "fight" and str(f.then.k) == "eddie", "Eddie's crew is waiting at the start of the turn")
	var gang: Array = f.units.filter(func(u): return int(u.side) == 1)
	_check(gang.size() >= 5 and gang[0].name == "Easy Eddie", "Eddie and his whole gang (%d)" % gang.size())
	for u in gang:
		_check(int(u.gear) in [Balance.RIFLE, Balance.MACHINE_GUN], "%s carries a rifle or a machine gun" % u.name)
		var r: Array = Balance.ROLL_STATS.muscle.range
		_check(int(u.muscle) >= int(r[0]) and int(u.muscle) <= int(r[1]) and int(u.max) <= int(Balance.ROLL_STATS.stamina.range[1]), "%s has plain stats" % u.name)
	# Win: the debt is gone, and Eddie doesn't come back for it.
	f.won = true
	f.over = true
	gs._end_fight(ana)
	_check(int(ana.loan) == 0 and not ana.eddie_due and not ana.legs_broken, "beat them: the debt is settled")
	gs.state.pending = {}
	gs.state.fight = {}
	gs.handle(1, {"t": "end_turn"})
	_to_turn(1)
	_check(str(gs.state.get("fight", {}).get("then", {}).get("k", "")) != "eddie", "and he doesn't come again")
	gs.state.pending = {}
	# Lose: legs broken, for good.
	ana.loan = 9000
	ana.eddie_due = true
	gs.handle(1, {"t": "end_turn"})
	_to_turn(1)
	gs.handle(1, {"t": "pending", "id": "surrender"})
	_check(ana.legs_broken and int(ana.stamina_penalty) == Balance.LEGS_STAMINA and int(ana.loan) == 0, "lose: legs broken, energy down %d for good" % Balance.LEGS_STAMINA)
	var legs := false
	for ev in gs.state.fight.events:
		legs = legs or ev.k == "legs"
	_check(legs, "the fight screen plays it out")
	gs.handle(1, {"t": "pending", "id": "ok"})
	while ana.crew.size() > 1:
		ana.crew.pop_back()
	for i in 3:
		gs.state.pending = {}
		gs.handle(int(gs._active().owner), {"t": "end_turn"})
		_to_turn(1)
		gs.state.pending = {}
	_check(ana.chair and not gs._driving(ana), "still in the wheelchair turns later, and nobody to drive")
	_check(int(ana.crew[0].stamina) <= Balance.STAMINA_CAP - Balance.LEGS_STAMINA, "energy never gets back above %d" % (Balance.STAMINA_CAP - Balance.LEGS_STAMINA))
	gs._jail(ana, 1)
	gs.handle(1, {"t": "end_turn"})
	_to_turn(1)
	gs.handle(1, {"t": "pending", "id": "give_up"})
	gs.handle(1, {"t": "pending", "id": "ok"})
	_to_turn(1)
	gs.state.pending = {}
	_check(ana.legs_broken and ana.chair, "jail and release don't heal it")
	ana.crew.append(gs._new_member("Wheels", false))
	ana.car = 2
	_check(gs._driving(ana) and ana.chair, "a crew driver gets the car out; the chair stays")


func _casino() -> void:
	gs.state.pending = {}
	var casino := _building("casino")
	ana.inside = int(casino.id)
	ana.cash = 10000
	ana.menu_path = ["game_blackjack"]
	for i in 6:
		var before := int(ana.cash)
		gs._exec(ana, PackedStringArray(["gamble", "blackjack", "500"]))
		var won: bool = gs.state.pending.good
		var want := before + (500 * (int(Casino.TABLES.blackjack[1]) - 1) if won else -500)
		_check(int(ana.cash) == want, "hand %d paid once, at once ($%d -> $%d)" % [i, before, ana.cash])
		gs.handle(1, {"t": "pending", "id": "ok"})
		_check(int(ana.cash) == want, "and closing the card doesn't pay again")
	gs._leave(ana)


func _kid() -> void:
	var rng := RandomNumberGenerator.new()
	for level in [0, 4, 8]:
		var c := Chase.create("catch", level, rng)
		_check(float(c.foes[0].speed) < Chase.MY_SPEED and float(c.foes[0].speed) <= 0.235, "level %d: the kid runs a little slower (%.3f)" % [level, c.foes[0].speed])


# ------------------------------------------------------------------ helpers

## One shower on its own: `lag` ticks to see the soap, a tap at most every `every` ticks. "best"
## taps the side it's heading for, "none" never taps, "mash" taps right and only right.
func _shower(seed: int, lag: int, every: int, how: String) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var m := Mini.create("shower", "Shower time", 0, r, {})
	m.ready = 0
	var seen: Array = []
	var last := -99
	while m.phase == "hold":
		seen.append([float(m.soap), float(m.vel)])
		var s: Array = seen[maxi(0, seen.size() - 1 - lag)]
		var ahead: float = s[0] + s[1] * 5.0
		if int(m.tick) - last >= every:
			var dir := ""
			if how == "best":
				dir = "E" if ahead > 0.2 else ("W" if ahead < -0.2 else "")
			elif how == "mash":
				dir = "E"
			if dir != "":
				Mini.input(m, {"dir": dir})
				last = int(m.tick)
		Mini.step(m, r)
	return float(m.held)


## Ends turns (clearing prompts) until it's `pid`'s.
func _to_turn(pid: int) -> void:
	for i in 40:
		if int(gs._active().id) == pid and i > 0:
			return
		if i == 0 and int(gs._active().id) == pid:
			return
		gs.state.pending = {}
		gs.state.fight = {}
		gs.state.mini = {}
		gs.handle(int(gs._active().owner), {"t": "end_turn"})
		while gs.state.get("mini", {}).get("game", "") == "shower" and int(gs._active().id) != pid:
			gs.state.pending = {}
			gs.state.mini = {}
			gs._after_action(gs._active())


func _building(type: String) -> Dictionary:
	for b in gs.state.city.buildings:
		if b.type == type:
			return b
	return {}


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
