extends SceneTree
## Loads the real main scene, hosts a game with a local rival, and plays through the HUD.
## Run: godot --headless --path . --script res://tests/ui_smoke_test.gd [-- --shots=DIR]

var main: Node
var frame := 0
var net: Node
var shots_dir := ""
var shot_n := 0
var tap_target := -1
var tap_frame := 0


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
		_shot("menu")
		var err: String = net.host(7791, "Rosa", "The Night Owls")
		print("host: ", "ok" if err == "" else err)
		net.send_intent({"t": "add_local", "name": "Dev", "crew": "The Lucky Breaks"})
	elif frame == 20:
		_shot("lobby")
		net.send_intent({"t": "start", "target": 20})
	elif frame == 30:
		_shot("town")
		_tap_nearest_building()
	elif tap_target >= 0:
		var a0: Dictionary = net.active_player()
		if int(a0.inside) == tap_target:
			print("tap-to-walk: entered building %d after %d frames" % [tap_target, frame - tap_frame])
			_shot("tap_walk")
			tap_target = -1
		elif frame - tap_frame > 3000 or not net.state.pending.is_empty():
			print("tap-to-walk: did not arrive (inside=%s pending=%s)" % [a0.inside, not net.state.pending.is_empty()])
			tap_target = -1
	elif frame > 30 and frame < 900:
		var s: Dictionary = net.state
		if s.phase != "playing":
			return _finish()
		var a: Dictionary = net.active_player()
		if frame % 4 == 0:
			if not s.pending.is_empty():
				if frame % 40 == 0:
					_shot("prompt")
				net.send_intent({"t": "pending", "id": s.pending.options.filter(func(o): return o.get("enabled", true))[0].id})
			elif int(a.inside) >= 0:
				if frame % 24 == 0:
					_shot("building")
				var en: Array = a.menu.filter(func(e): return e.enabled)
				net.send_intent({"t": "menu", "id": en[randi() % en.size()].id})
			else:
				_go_toward_building(a, s)
	elif frame == 900:
		_leave_via_menu()
	elif frame >= 906:
		return _finish()
	return false


func _tap_nearest_building() -> void:
	var hud: Node = main.get("_hud")
	var a: Dictionary = net.active_player()
	var start := Vector2i(int(a.pos[0]), int(a.pos[1]))
	var best := -1
	var best_len := 999
	for b in net.state.city.buildings:
		var route: Array = hud._find_path(start, Vector2i(int(b.x), int(b.y)))
		if route.size() > 0 and route.size() < best_len and route.size() <= int(a.steps):
			best = int(b.id)
			best_len = route.size()
	if best < 0:
		print("tap-to-walk: no reachable building")
		return
	var tb: Dictionary = net.state.city.buildings[best]
	print("tap-to-walk: tapping %s, %d steps away" % [tb.name, best_len])
	tap_target = best
	tap_frame = frame
	hud._on_cell_tapped(Vector2i(int(tb.x), int(tb.y)))


func _go_toward_building(a: Dictionary, s: Dictionary) -> void:
	var dirs := ["N", "S", "E", "W"]
	net.send_intent({"t": "move", "dir": dirs[randi() % 4]})


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	await process_frame
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		shot_n += 1
		img.save_png("%s/%02d_%s.png" % [shots_dir, shot_n, tag])


## The in-game Leave button: confirm, and you're back on the title screen.
func _leave_via_menu() -> void:
	var hud: Node = main.get("_hud")
	hud._leave_btn.emit_signal("pressed")
	for c in hud._overlay_box.get_children():
		if c is Button and c.text == "Leave game":
			c.emit_signal("pressed")
			return
	print("FAIL: no Leave game button in the leave overlay")


func _finish() -> bool:
	var s: Dictionary = net.state
	print("ui smoke: frames=%d phase=%s month=%s log_lines=%d" % [frame, s.get("phase", "-"), s.get("month", "-"), s.get("log", []).size()])
	if frame >= 900:
		print("leave: %s" % ("back on the title screen" if main.get("_current") == "menu" else "FAIL: still on %s" % main.get("_current")))
	_shot("end")
	quit(0)
	return true
