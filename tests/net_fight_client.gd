extends SceneTree
## A police fight played through the real HUD by a networked client that dropped out and came back.
## Needs a dedicated server started with --test-hooks and a partner (tests/net_fight_test.sh runs it all):
##   --role=partner   joins first, starts the game, passes its own turns
##   --role=player    the real UI: joins, drops out, rejoins, then gets stopped by the police and fights
## The player fails if it ever waits 15 s with nothing it can press.

var net: Node
var main: Node
var role := "player"
var port := 7794
var elapsed := 0.0
var step := "join"
var stuck := 0.0
var fights := 0
var last_tap := 0.0
var midfight := false   # --midfight: drop out and come back after a few moves of the fight
var mid_taps := 0
var stall := false   # --stall: the player freezes at the police stop; the partner skips the turn
var how := "fight"   # --how=run: run for it and get caught first (the "Cornered" fight)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--port="):
			port = int(a.substr(7))
		elif a == "--stall":
			stall = true
		elif a == "--midfight":
			midfight = true
		elif a.begins_with("--how="):
			how = a.substr(6)


func _process(delta: float) -> bool:
	elapsed += delta
	if net == null:
		net = root.get_node_or_null("Net")
		if net == null:
			return false
		net.error_message.connect(func(m: String): print("[%s] server says: %s" % [role, m]))
		if role == "player":
			main = load("res://scenes/main.tscn").instantiate()
			root.add_child(main)
		net.join("127.0.0.1", port, "Bro" if role == "player" else "Me", "")
		return false
	if elapsed > 150.0:
		return _end(false, "timed out at step %s" % step)
	var s: Dictionary = net.state
	if s.is_empty() and step != "away":
		return false
	if role == "partner":
		return _partner(s)
	return _player(s, delta)


func _partner(s: Dictionary) -> bool:
	if s.phase == "lobby" and s.players.size() >= 2 and net.am_room_host() and step == "join":
		net.send_intent({"t": "start", "target": 200})
		step = "starting"
	elif s.phase == "playing" and step == "starting":
		step = "playing"
	elif stall and s.phase == "playing" and not net.is_my_turn() and s.pending.get("kind", "") == "police" \
			and elapsed - last_tap > 1.0:
		last_tap = elapsed
		net.send_intent({"t": "skip_stalled"})   # refused until the server's stall time has passed
	elif stall and step == "playing" and s.log.any(func(e): return "was skipped" in str(e.text)):
		return _end(true, "skipped the frozen turn")
	elif s.phase == "playing" and net.is_my_turn() and elapsed - last_tap > 0.3:
		last_tap = elapsed
		if not s.pending.is_empty():
			net.send_intent({"t": "pending", "id": s.pending.options[0].id})
		else:
			net.send_intent({"t": "end_turn"})
	elif s.phase == "lobby" and step == "playing" or elapsed > 140.0:
		return _end(true, "partner done")
	return false


func _player(s: Dictionary, delta: float) -> bool:
	var h: Variant = main.get("_hud")
	var hud: Node = h if is_instance_valid(h) else null
	match step:
		"join":
			if s.phase == "playing" and not net.my_player().is_empty() and midfight:
				step = "wait_turn"
			elif s.phase == "playing" and not net.my_player().is_empty():
				print("[player] in the game; dropping out")
				net.leave()
				main.show_menu()   # like closing the tab: the next join starts from the title screen
				step = "away"
				stuck = 0.0
		"away":
			stuck += delta
			if stuck > 2.0:
				net.join("127.0.0.1", port, "Bro", "")
				step = "back"
		"back":
			stuck += delta
			if stuck > 8.0 and stuck - delta <= 8.0:
				print("[player] still not back: phase=%s my_peer=%s players=%s" % [s.get("phase"), net.my_peer,
					s.get("players", {}).values().map(func(p): return [p.name, p.owner, p.connected])])
			if s.phase == "playing" and not net.my_player().is_empty() and midfight:
				print("[player] back mid-fight: pending=%s fight=%s" % [s.pending.get("kind", ""), not s.get("fight", {}).is_empty()])
				midfight = false
				step = "fight"
				stuck = 0.0
			elif s.phase == "playing" and not net.my_player().is_empty():
				print("[player] back with %s (%d crews)" % [net.my_player().crew_name, s.players.size()])
				step = "wait_turn"
		"wait_turn":
			if net.is_my_turn() and s.pending.is_empty() and hud != null:
				net.send_intent({"t": "test_police"})
				step = "police"
		"police":
			if stall:
				if s.pending.get("kind", "") == "police":
					step = "frozen"
					print("[player] frozen at the police stop")
				return false
			if s.pending.get("kind", "") == "police" and hud != null and hud._police_panel.visible:
				net.send_intent({"t": "pending", "id": how})
				fights += 1
				step = "fight"
				stuck = 0.0
		"frozen":
			if not net.is_my_turn():
				return _end(true, "the others skipped my frozen turn after %.0f s" % elapsed)
		"fight":
			var pend: Dictionary = s.pending
			var kind: String = pend.get("kind", "")
			var can_act := false
			if kind == "mini":
				can_act = true   # standing still in the chase until the cops catch us
			elif kind == "fight" and hud._can_fight():
				can_act = true
				if elapsed - last_tap > 0.1:
					last_tap = elapsed
					# Walk into the cops and never attack, so the crew goes down (like losing the fight).
					hud._on_fight_square(_choose(s.fight))
					mid_taps += 1
					if midfight and mid_taps == 3:
						print("[player] dropping out mid-fight")
						net.leave()
						main.show_menu()
						step = "away"
						stuck = 1.0   # back within a second, inside the 3 s grace
						return false
			elif kind == "result" and hud._modal.visible:
				print("[player] fight %d over: %s: %s" % [fights, pend.title, pend.text])
				net.send_intent({"t": "pending", "id": "ok"})
				return _end(true, "the fight finished and the result showed")
			elif not net.is_my_turn():
				print("[player] turn ended without a result card (pending=%s)" % kind)
				return _end(false, "no result card")
			if can_act:
				stuck = 0.0
			else:
				stuck += delta
				if stuck > 15.0:
					var f: Dictionary = s.get("fight", {})
					var fv: Node = main.get("_city_view").fight_view
					return _end(false, "STUCK: pending=%s fight side=%s cur=%s over=%s seq=%s | view busy=%s queue=%d timer=%.2f id=%s/%s seen=%s | modal=%s" % [
						kind, f.get("side"), f.get("cur"), f.get("over"), f.get("seq"), fv.busy(), fv._queue.size(), fv._timer,
						fv._fight_id, f.get("id"), fv._seen, hud._modal.visible])
	return false


## Step toward the nearest cop, or wait when boxed in.
func _choose(f: Dictionary) -> Vector2i:
	var o := Fight.options(f)
	var me: Dictionary = f.units[int(f.cur)]
	var best := Vector2i(int(me.x), int(me.y))
	var best_d := 999
	for c in o.move:
		for e in f.units:
			if int(e.side) == 1 and int(e.hp) > 0:
				var d := maxi(absi(int(e.x) - c.x), absi(int(e.y) - c.y))
				if d < best_d:
					best_d = d
					best = c
	if best_d == 999 and o.attack.size() > 0:
		return o.attack[0]
	return best


func _end(ok: bool, what: String) -> bool:
	print("[%s] %s: %s" % [role, "PASS" if ok else "FAIL", what])
	net.leave()
	quit(0 if ok else 1)
	return true
