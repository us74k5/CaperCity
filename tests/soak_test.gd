extends SceneTree
## Plays many random games through GameServer and checks invariants.
## Run: godot --headless --path . --script res://tests/soak_test.gd

var problems := 0


func _init() -> void:
	var games := 40
	var finished := 0
	var total_months := 0
	var max_bytes := 0
	var crimes_seen := {}
	for gi in games:
		var g := GameServer.new(1000 + gi)
		_ok(g.handle(1, {"t": "join", "name": "Ana", "crew": "Ana's Crew"}), "join")
		_ok(g.handle(1, {"t": "add_local", "name": "Bo", "crew": ""}), "add_local")
		_ok(g.handle(1, {"t": "add_local", "name": "Cy", "crew": ""}), "add_local")
		_ok(g.handle(1, {"t": "start", "target": 20}), "start")
		var rng := RandomNumberGenerator.new()
		rng.seed = gi
		var n := 0
		while g.state.phase == "playing" and n < 40000:
			n += 1
			var s: Dictionary = g.state
			var p: Dictionary = s.players[s.order[s.active]]
			var intent := {}
			var must_succeed := false
			if not s.pending.is_empty():
				var opts: Array = s.pending.options.filter(func(o): return o.get("enabled", true))
				intent = {"t": "pending", "id": opts[rng.randi() % opts.size()].id}
				must_succeed = true
			elif int(p.inside) >= 0:
				var entries: Array = p.menu.filter(func(e): return e.enabled)
				var acts: Array = entries.filter(func(e): return str(e.id).begins_with("act:"))
				var pick: Dictionary
				if acts.size() > 0 and rng.randf() < 0.6:
					pick = acts[rng.randi() % acts.size()]
				else:
					pick = entries[rng.randi() % entries.size()]
				if str(pick.id).begins_with("act:crime:"):
					crimes_seen[pick.id] = true
				intent = {"t": "menu", "id": pick.id}
				must_succeed = true
			else:
				var r := rng.randf()
				if r < 0.01:
					intent = {"t": "end_turn"}
				elif r < 0.02 and s.order.size() > 1:
					intent = {"t": "gang_war", "target": s.order[rng.randi() % s.order.size()]}
				else:
					intent = {"t": "move", "dir": ["N", "S", "E", "W"][rng.randi() % 4]}
			var err := g.handle(1, intent)
			if must_succeed and err != "":
				_fail("game %d: intent %s failed: %s" % [gi, intent, err])
			_check(g, gi)
			if problems > 20:
				break
		if g.state.phase == "over":
			finished += 1
		total_months += int(g.state.month)
		max_bytes = maxi(max_bytes, var_to_bytes(g.state).size())
	print("games finished: %d / %d, avg months: %.1f, largest state: %d bytes" % [finished, games, float(total_months) / games, max_bytes])
	print("crime actions exercised: %d" % crimes_seen.size())
	print("PROBLEMS: %d" % problems)
	quit(1 if problems > 0 else 0)


func _check(g: GameServer, gi: int) -> void:
	for pid in g.state.players:
		var p: Dictionary = g.state.players[pid]
		if p.crew.is_empty():
			_fail("game %d: %s has no crew (boss deleted)" % [gi, p.name])
		if int(p.cash) < 0:
			_fail("game %d: %s has negative cash %d" % [gi, p.name, p.cash])
		if int(p.steps) < 0:
			_fail("game %d: %s has negative steps %d" % [gi, p.name, p.steps])
		var cell: int = g.state.city.grid[int(p.pos[1]) * g.state.city.w + int(p.pos[0])]
		if cell != CityGen.ROAD:
			_fail("game %d: %s stands on a non-road cell %s" % [gi, p.name, p.pos])


func _ok(err: String, what: String) -> void:
	if err != "":
		_fail("%s: %s" % [what, err])


func _fail(msg: String) -> void:
	problems += 1
	if problems <= 20:
		print("PROBLEM: ", msg)
