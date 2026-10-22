extends SceneTree
## Character creation rules (avatars, stat rolls, re-rolls, ready, joining mid-game) and how often
## the police stop you while walking.
## Run: godot --headless --path . --script res://tests/creation_test.gd

var fails := 0


func _init() -> void:
	var gs := GameServer.new(7)
	gs.handle(1, {"t": "join", "name": "Ana", "crew": ""})
	gs.handle(2, {"t": "join", "name": "Bo", "crew": ""})
	var ana: Dictionary = gs.state.players[1]
	var bo: Dictionary = gs.state.players[2]
	_check(not ana.ready and ana.avatar == "", "a new player starts out creating")
	_check(gs.handle(1, {"t": "ready"}) != "", "can't be ready without a character")
	_check(gs.handle(1, {"t": "avatar", "id": "character-male-a"}) == "", "pick a character")
	_check(gs.handle(2, {"t": "avatar", "id": "character-male-a"}) != "", "two players can't pick the same one")
	_check(gs.handle(1, {"t": "avatar", "id": "character-male-c"}) != "", "the cop isn't on the list")
	_check(gs.handle(1, {"t": "ready"}) != "", "can't be ready before rolling")
	for stat in Balance.ROLL_STATS:
		_check(gs.handle(1, {"t": "roll", "stat": stat}) == "", "roll %s" % stat)
		var r: Array = Balance.ROLL_STATS[stat].range
		var v := int(ana.cash) if stat == "cash" else int(ana.crew[0][stat])
		_check(v >= int(r[0]) and v <= int(r[1]), "%s rolled in range (%d)" % [stat, v])
	_check(int(ana.cash) % 50 == 0, "the bankroll is a round number")
	for i in Balance.REROLLS:
		_check(gs.handle(1, {"t": "roll", "stat": "muscle"}) == "", "re-roll %d" % (i + 1))
	_check(gs.handle(1, {"t": "roll", "stat": "muscle"}) != "", "no more re-rolls")
	_check(gs.handle(1, {"t": "ready"}) == "" and ana.ready, "ready")
	_check(gs.handle(1, {"t": "roll", "stat": "smarts"}) != "", "no rolling after ready")

	# The host starts while Bo is still creating: Bo is finished off automatically.
	gs.handle(1, {"t": "start", "target": 50})
	_check(gs.state.phase == "playing" and bo.ready and bo.avatar != "" and bo.avatar != ana.avatar, "start finishes everyone (Bo got %s)" % bo.avatar)

	# Someone joining mid-game creates their boss; their turns are skipped until then.
	gs.handle(3, {"t": "join", "name": "Cy", "crew": ""})
	var cy: Dictionary = gs.state.players[3]
	_check(not cy.ready and gs.state.order.has(3), "a latecomer is seated but still creating")
	var turns_seen := {}
	for i in 12:
		turns_seen[int(gs.state.order[gs.state.active])] = true
		gs.state.pending = {}
		gs.handle(int(gs._active().owner), {"t": "end_turn"})
	_check(not turns_seen.has(3), "no turns while creating")
	_check(gs.handle(3, {"t": "avatar", "id": "character-female-f"}) == "", "the latecomer picks a free character")
	for stat in Balance.ROLL_STATS:
		gs.handle(3, {"t": "roll", "stat": stat})
	_check(gs.handle(3, {"t": "ready"}) == "" and cy.ready, "the latecomer gets ready")
	turns_seen.clear()
	for i in 12:
		turns_seen[int(gs.state.order[gs.state.active])] = true
		gs.state.pending = {}
		gs.handle(int(gs._active().owner), {"t": "end_turn"})
	_check(turns_seen.has(3), "turns once ready (saw %s, order %s)" % [turns_seen.keys(), gs.state.order])

	# Police: at most one random stop a turn, even with a lot of heat.
	var p: Dictionary = ana
	var stops := 0
	var turns := 400
	for t in turns:
		p.stopped = false
		p.heat = 30
		p.immunity = 0
		var this_turn := 0
		for step in 30:
			gs.state.pending = {}
			gs._maybe_police_check(p)
			if gs.state.pending.get("kind", "") == "police":
				this_turn += 1
		_check(this_turn <= 1, "at most one stop a turn")
		stops += this_turn
	var rate := float(stops) / turns
	print("police: %.2f stops a turn at heat 30" % rate)
	_check(rate > 0.4 and rate < 0.85, "a hot crew still gets stopped most turns, not every step")
	p.heat = 0
	stops = 0
	for t in turns:
		p.stopped = false
		for step in 30:
			gs.state.pending = {}
			gs._maybe_police_check(p)
			if gs.state.pending.get("kind", "") == "police":
				stops += 1
	print("police: %.2f stops a turn for a clean crew" % (float(stops) / turns))
	_check(float(stops) / turns < 0.3, "a clean crew is rarely stopped")

	print("creation: %s" % ("ok" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
