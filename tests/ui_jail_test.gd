extends SceneTree
## On screen: a month in jail played as the showers (keeping hold of the soap through the HUD's
## keys, the drop and the cut to Bubba), the wheelchair on the map after release, and
## Easy Eddie's gang breaking the boss's legs on the fight screen before the result card.
## Run: godot --path . --script res://tests/ui_jail_test.gd [-- --shots=DIR]  (headless works too)

var main: Node
var net: Node
var hud: Node
var frame := 0
var shots_dir := ""
var fails := 0
var step := "start"
var at := 0
var shots := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		net = root.get_node("Net")
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
	elif frame == 10:
		net.host(7798, "Rosa", "The Night Owls")
		net.send_intent({"t": "add_local", "name": "Dev", "crew": "The Lucky Breaks"})
		net.send_intent({"t": "start", "target": 20})
	elif frame == 30:
		hud = main.get("_hud")
		# Rosa (the host) goes to jail for a month; play through to her next turn.
		var rosa: Dictionary = net.server.state.players[1]
		net.server._jail(rosa, 1)
		while int(net.server._active().id) != 1 or net.server.state.get("mini", {}).is_empty():
			net.server.state.pending = {}
			net.server.handle(int(net.server._active().owner), {"t": "end_turn"})
		net._broadcast()
		step = "jail"
		at = frame
	elif frame > 30:
		return _run()
	return false


func _run() -> bool:
	var s: Dictionary = net.state
	var m: Dictionary = s.get("mini", {})
	match step:
		"jail":
			if frame - at == 5:
				_check(m.get("game", "") == "shower" and main.get("_city_view").in_mini(), "the jail month is a minigame on screen")
			if m.is_empty():
				return false
			if int(m.ready) > 0:
				return false
			var mv: Node = main.get("_city_view").mini_view
			if not shots.has("start"):
				shots.start = true
				_shot("shower_start")
			if m.phase == "hold":
				# Catch it like a player would, through the HUD's keys: tap the side it's heading for.
				var ahead := float(m.soap) + float(m.vel) * 5.0
				if frame % 2 == 0 and absf(ahead) > 0.2:
					hud._move("E" if ahead > 0 else "W")
				if float(m.held) > 6.0 and not shots.has("hold"):
					shots.hold = true
					_shot("shower_holding")
			else:
				var since := int(m.tick) - int(m.drop_tick)
				if since > 10 and not shots.has("drop"):
					shots.drop = true
					_check(mv.cam_shot().is_empty(), "the drop is seen from above first")
					_shot("shower_drop")
				if since > 75 and not shots.has("bubba"):
					shots.bubba = true
					_check(not mv.cam_shot().is_empty(), "then it cuts to Bubba")
					_check(mv._bubba.say.visible and str(mv._bubba.say.text) == "Gotcha, hee hee hee", "Gotcha, hee hee hee")
					_shot("shower_bubba")
			if s.pending.get("kind", "") == "result":
				_check(not m.won, "nobody wins the shower")
				print("shower: held %.1f s; %s" % [float(m.held), s.pending.text])
				_shot("shower_result")
				net.send_intent({"t": "pending", "id": "ok"})
				step = "release"
				at = frame
		"release":
			# Dev's turn, then Rosa's: out, in a wheelchair.
			if int(net.server._active().id) != 1:
				net.server.state.pending = {}
				net.server.handle(int(net.server._active().owner), {"t": "end_turn"})
				net._broadcast()
				return false
			if not s.pending.is_empty() and s.pending.kind == "result":
				print("release: ", s.pending.text)
				net.send_intent({"t": "pending", "id": "ok"})
				return false
			if frame - at > 40:
				var tk: Dictionary = main.get("_city_view")._tokens[1]
				_check(tk.chair != null and tk.chair.visible, "a wheelchair on the map")
				main.get("_city_view").zoom = 6.0
				step = "chair_shot"
				at = frame
		"chair_shot":
			if frame - at == 30:
				_shot("wheelchair")
				var rosa: Dictionary = net.server.state.players[1]
				rosa.loan = 12000
				rosa.eddie_due = true
				net.server.state.pending = {}
				net.server.handle(1, {"t": "end_turn"})
				while int(net.server._active().id) != 1:
					net.server.state.pending = {}
					net.server.handle(int(net.server._active().owner), {"t": "end_turn"})
				net._broadcast()
				step = "eddie"
				at = frame
		"eddie":
			if frame - at == 20:
				_check(s.pending.get("kind", "") == "fight" and str(s.fight.then.k) == "eddie", "Eddie's gang at the start of the turn")
				_shot("eddie_fight")
				net.send_intent({"t": "pending", "id": "surrender"})
			elif frame - at > 20:
				var fv: Node = main.get("_city_view").fight_view
				if frame - at == 60:
					_shot("eddie_legs")
					_check(fv.busy() and not hud._modal.visible, "the legs scene plays before the result")
				if hud._modal.visible:
					print("eddie: ", s.pending.text)
					_check(s.players[1].legs_broken, "legs broken")
					_shot("eddie_result")
					step = "done"
				elif frame - at > 1500:
					_check(false, "Eddie's result never showed")
					step = "done"
		"done":
			print("ui jail: ", "ok" if fails == 0 else "%d FAILED" % fails)
			quit(1 if fails > 0 else 0)
			return true
	if frame > 6000:
		_check(false, "stuck at " + step)
		step = "done"
	return false


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("%s/jail_%s.png" % [shots_dir, tag])


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
