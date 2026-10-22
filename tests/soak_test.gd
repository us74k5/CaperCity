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
	var fights_moves := 0
	var minis := {}
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
			if s.pending.get("kind", "") == "mini" and rng.randf() < 0.97:
				# Play at random and let the server's clock run, as Net does every frame.
				var mg: Dictionary = s.mini
				if int(mg.tick) == 0:
					minis[mg.game] = int(minis.get(mg.game, 0)) + 1
				if mg.game == "safe":
					intent = {"t": "mini", "turn": [1, -1][rng.randi() % 2]} if rng.randf() < 0.8 else {"t": "mini", "pick": rng.randi() % 3}
				else:
					intent = {"t": "mini", "dir": ["N", "S", "E", "W", ""][rng.randi() % 5]}
				var e1: String = g.handle(1, intent)
				if e1 != "" and e1 != "It's over.":
					_fail("game %d: minigame input %s failed: %s" % [gi, intent, e1])
				for i in rng.randi_range(1, 12):
					if g.tick(Mini.TICK) == 2:
						break
				_check(g, gi)
				continue
			elif s.pending.get("kind", "") == "fight" and rng.randf() < 0.8:
				# Play the fight by hand: mostly legal moves and attacks, sometimes a wait or a random square.
				var fo := Fight.options(s.fight)
				var cells: Array = fo.attack + fo.move
				var r0 := rng.randf()
				if r0 < 0.05:
					intent = {"t": "fight"}
				elif r0 < 0.1 or cells.is_empty():
					intent = {"t": "fight", "cell": [rng.randi() % Fight.W, rng.randi() % Fight.H]}
				else:
					var c: Vector2i = fo.attack[0] if fo.attack.size() > 0 and rng.randf() < 0.7 else cells[rng.randi() % cells.size()]
					intent = {"t": "fight", "cell": [c.x, c.y]}
					must_succeed = true
				fights_moves += 1
			elif not s.pending.is_empty():
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
	print("crime actions exercised: %d, hand-played fight moves: %d" % [crimes_seen.size(), fights_moves])
	print("minigames played: %s" % minis)
	print("PROBLEMS: %d" % problems)
	quit(1 if problems > 0 else 0)


func _check(g: GameServer, gi: int) -> void:
	var f: Dictionary = g.state.fight
	if not f.is_empty():
		if g.state.pending.get("kind", "") == "fight" and f.over:
			_fail("game %d: fight is over but the fight prompt is still up" % gi)
		var taken := {}
		for u in f.units:
			if int(u.hp) < 0 or int(u.hp) > int(u.max) + Balance.STAMINA_CAP_HOLIDAY:
				_fail("game %d: fighter %s has energy %d" % [gi, u.name, u.hp])
			if int(u.x) < 0 or int(u.y) < 0 or int(u.x) >= Fight.W or int(u.y) >= Fight.H:
				_fail("game %d: fighter %s is off the field" % [gi, u.name])
			if int(u.hp) > 0:
				var key := Vector2i(int(u.x), int(u.y))
				if taken.has(key):
					_fail("game %d: two fighters on %s" % [gi, key])
				taken[key] = true
	var c: Dictionary = g.state.get("mini", {})
	if g.state.pending.get("kind", "") == "mini":
		if c.is_empty() or c.over:
			_fail("game %d: minigame prompt is up without a running minigame" % gi)
	if Mini.is_grid(c):
		for a in [c.me] + c.get("foes", []) + c.get("guards", []) + c.get("items", []):
			if Mini.is_wall(c.rows, Vector2i(int(a.x), int(a.y))):
				_fail("game %d: %s: something in a wall at %d,%d" % [gi, c.game, a.x, a.y])
		var seen := {}
		for it in c.get("items", []):
			var k := Vector2i(int(it.x), int(it.y))
			if seen.has(k) or k == Vector2i(int(c.me.x), int(c.me.y)):
				_fail("game %d: %s: two things on %s" % [gi, c.game, k])
			seen[k] = true
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
