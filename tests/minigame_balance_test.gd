extends SceneTree
## Bots play the real-time minigames many times and print how often they win, to check the balance
## (and that every generated level can be won).
## Run: godot --headless --path . --script res://tests/minigame_balance_test.gd

func _init():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for game in ["escape", "catch", "sneak", "train"]:
		for level in [0, 4, 8]:
			var wins := 0
			var n := 150
			var secs := 0.0
			for g in n:
				var m := Mini.create(game, "t", level, rng, {})
				m.ready = 0
				while not m.over:
					if int(m.tick) % 2 == 0:
						var d := _bot(m, rng)
						if game in ["escape", "catch"]:
							Mini.input(m, {"dir": d})
						elif d != "" and m.queue.is_empty():
							Mini.input(m, {"dir": d})
						elif game == "train" and d == "" and m.get("phase", "") == "push":
							Mini.give_up(m)
					Mini.step(m, rng)
				wins += int(m.won)
				secs += (int(m.total) - int(m.left)) * Mini.TICK
			print("%s level %d: bot wins %d%%, avg %.1fs" % [game, level, wins * 100 / n, secs / n])
	quit()


func _bot(m: Dictionary, rng: RandomNumberGenerator) -> String:
	var me := Mini.cell_of(m.me)
	match str(m.game):
		"catch":
			var dist := Mini.distances(m.rows, Mini.cell_of(m.foes[0]))
			return _min_dir(m.rows, me, dist)
		"escape":
			return _escape(m, me, rng)
		"sneak":
			# Head for the door through squares no guard can see now or after its next step.
			var unsafe := {}
			for g in m.guards:
				for c in Sneak.sight(m.rows, g):
					unsafe[c] = true
				var route: Array = g.route
				var nxt: Vector2i = route[(int(g.at) + 1) % route.size()]
				var g2: Dictionary = g.duplicate()
				g2.x = nxt.x
				g2.y = nxt.y
				g2.dir = Sneak._dir_to(nxt, route[(int(g.at) + 2) % route.size()])
				for c in Sneak.sight(m.rows, g2):
					unsafe[c] = true
			var door := Vector2i(Mini.W - 2, 1)
			var dist2 := Mini.distances(m.rows, door, unsafe)
			if not dist2.has(me):
				dist2 = Mini.distances(m.rows, door)
			var best := ""
			var bd: int = int(dist2.get(me, 999))
			for d in Mini.DIRS:
				var n: Vector2i = me + Mini.DIRS[d]
				if not unsafe.has(n) and dist2.has(n) and int(dist2[n]) < bd:
					bd = int(dist2[n])
					best = d
			return best
		"train":
			# Push the nearest container in row 2 up onto the track: stand below it and push north.
			if m.get("phase", "") != "push":
				return ""
			var blocked := {}
			for it in m.items:
				blocked[Mini.cell_of(it)] = true
			var dist3 := Mini.distances(m.rows, me, blocked)
			var best_c := Vector2i(-1, -1)
			var best_d := 9999
			for it in m.items:
				var c := Mini.cell_of(it)
				if c.y >= 2 and c.y <= 6 and Mini.mark(m.rows, c + Vector2i(0, -1)) != "#":
					var clear := true
					for y in range(1, c.y):
						if Push.item_at(m, Vector2i(c.x, y)) >= 0 and y != 1:
							clear = false
					if Push.item_at(m, Vector2i(c.x, 1)) >= 0:
						clear = false
					var below := c + Vector2i(0, 1)
					if clear and dist3.has(below) and int(dist3[below]) < best_d:
						best_d = int(dist3[below])
						best_c = c
			if best_c.x < 0:
				return ""
			var below2 := best_c + Vector2i(0, 1)
			if me == below2:
				return "N"
			var to := Mini.distances(m.rows, below2, blocked)
			return _min_dir(m.rows, me, to)
	return ""


func _min_dir(rows: Array, me: Vector2i, dist: Dictionary) -> String:
	var best := ""
	var bd := 9999
	for d in Mini.DIRS:
		var n: Vector2i = me + Mini.DIRS[d]
		if not Mini.is_wall(rows, n) and int(dist.get(n, 9999)) < bd:
			bd = int(dist.get(n, 9999))
			best = d
	return best


## For each way out, follow the corridor to the next junction and score how much sooner we get there
## than the nearest cop; pick the safest.
func _escape(m: Dictionary, me: Vector2i, rng: RandomNumberGenerator) -> String:
	var maps: Array = []
	for f in m.foes:
		maps.append(Mini.distances(m.rows, Mini.cell_of(f)))
	var best := ""
	var bs := -9999.0
	for d in Mini.DIRS:
		var n: Vector2i = me + Mini.DIRS[d]
		if Mini.is_wall(m.rows, n):
			continue
		var at := n
		var dir: String = d
		var steps := 1
		var worst := 9999.0
		while true:
			for mp in maps:
				worst = minf(worst, float(mp.get(at, 99)) * 1.7 - steps)
			var ex := Chase.exits(m.rows, at, dir, true)
			if ex.size() != 1 or steps >= 8:
				break
			dir = ex[0]
			at += Mini.DIRS[dir]
			steps += 1
		var sc := worst + rng.randf() * 0.2
		if d == m.me.dir:
			sc += 0.5
		if sc > bs:
			bs = sc
			best = d
	return best
