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
var tap_pos: Array = []
var fails := 0


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
		_click_nearest_building()
	elif tap_target >= 0:
		# Clicking the map no longer walks anywhere: still on the same square, nothing queued.
		if frame - tap_frame >= 120:
			var a0: Dictionary = net.active_player()
			var still: bool = a0.pos == tap_pos and int(a0.inside) == -1 and main.get("_hud")._path.is_empty()
			print("click-to-walk: %s" % ("off (stayed put)" if still else "FAILED: the click moved %s" % a0.name))
			if not still:
				fails += 1
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


## Clicks (press and release, no drag) on the nearest building, as a player would have to walk there.
func _click_nearest_building() -> void:
	var cv: Node = main.get("_city_view")
	var a: Dictionary = net.active_player()
	var best: Dictionary = {}
	for b in net.state.city.buildings:
		if best.is_empty() or Vector2(int(b.x), int(b.y)).distance_to(Vector2(int(a.pos[0]), int(a.pos[1]))) \
				< Vector2(int(best.x), int(best.y)).distance_to(Vector2(int(a.pos[0]), int(a.pos[1]))):
			best = b
	var at: Vector2 = cv.camera.unproject_position(Vector3(int(best.x) + 1, 0, int(best.y) + 1))
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		cv._unhandled_input(ev)
	tap_target = int(best.id)
	tap_frame = frame
	tap_pos = a.pos.duplicate()


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
	quit(1 if fails > 0 else 0)
	return true
