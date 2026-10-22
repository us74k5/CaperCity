extends SceneTree
## Forces a police stop in a real game, picks "Shoot it out" on the police panel, then plays the
## fight by tapping squares through the HUD, the way a player would.
## Run: godot --path . --script res://tests/ui_fight_test.gd [-- --shots=DIR]   (headless works too)

var main: Node
var net: Node
var hud: Node
var frame := 0
var shots_dir := ""
var shot_n := 0
var taps := 0
var phase := "setup"


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
		print("host: ", "ok" if net.host(7793, "Rosa", "The Night Owls") == "" else "failed")
		net.send_intent({"t": "add_local", "name": "Dev", "crew": "The Lucky Breaks"})
		net.send_intent({"t": "start", "target": 20})
	elif frame == 20:
		hud = main.get("_hud")
		var p: Dictionary = net.active_player()
		p.crew[0].gear = Balance.PISTOL
		net.server._police_encounter(p, "Police checkpoint! They have a wanted poster with your face on it.")
		net._broadcast()
	elif frame == 50:
		_shot("police_stop")
		var pend: Dictionary = net.state.pending
		print("police stop: kind=%s options=%s" % [pend.kind, pend.options.map(func(o): return o.id)])
		net.send_intent({"t": "pending", "id": "fight"})
		phase = "fight"
	elif phase == "fight":
		var pend2: Dictionary = net.state.pending
		if pend2.get("kind", "") == "result" and not hud._modal.visible:
			return false
		if pend2.get("kind", "") == "result":
			_shot("fight_over")
			var fv: Node = main.get("_city_view").fight_view
			for u in net.state.fight.units:
				if fv.shown_hp(int(u.id), -1) != int(u.hp):
					print("FAIL: %s shows %d energy, really has %d" % [u.name, fv.shown_hp(int(u.id), -1), u.hp])
					return _finish(1)
			print("fight over after %d taps: %s: %s" % [taps, pend2.title, pend2.text])
			return _finish(0)
		if pend2.get("kind", "") != "fight":
			print("FAIL: expected a fight, got ", pend2.get("kind", "nothing"))
			return _finish(1)
		if frame == 60:
			_shot("fight_start")
		if hud._can_fight() and frame % 3 == 0:
			var cell := _choose(net.state.fight)
			hud._on_fight_square(cell)
			taps += 1
			if taps == 6:
				_shot("fight_mid")
		if frame > 6000:
			print("FAIL: fight did not finish (%d taps)" % taps)
			return _finish(1)
	return false


## Attack anything in range, otherwise step toward the nearest enemy.
func _choose(f: Dictionary) -> Vector2i:
	var o := Fight.options(f)
	if o.attack.size() > 0:
		return o.attack[0]
	var me: Dictionary = f.units[int(f.cur)]
	var best: Vector2i = o.move[0] if o.move.size() > 0 else Vector2i(int(me.x), int(me.y))
	var best_d := 999
	for c in o.move:
		for e in f.units:
			if int(e.side) == 1 and int(e.hp) > 0:
				var d := maxi(absi(int(e.x) - c.x), absi(int(e.y) - c.y))
				if d < best_d:
					best_d = d
					best = c
	return best


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	await process_frame
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		shot_n += 1
		img.save_png("%s/fight_%02d_%s.png" % [shots_dir, shot_n, tag])


func _finish(code: int) -> bool:
	quit(code)
	return true
