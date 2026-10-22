extends SceneTree
## Plays every real-time minigame through the HUD: a police stop -> "Make a run for it" (escape),
## then each of the others started as practice from inside the docks. Inputs go through the same d-pad/keys path as a
## player's (random steering, or the safe's dials). Checks each comes up on screen and ends with a result.
## Run: godot --path . --script res://tests/ui_minigame_test.gd [-- --shots=DIR]   (headless works too)

const GAMES := ["catch", "sneak", "loot", "containers", "train", "safe"]

var main: Node
var net: Node
var hud: Node
var frame := 0
var shots_dir := ""
var current := ""
var queue: Array = GAMES.duplicate()
var started_at := 0              # Time.get_ticks_msec() when the current game began
var last_input := 0
var shot_mid := false
var start_at_frame := 0          # the next game starts on this frame, once the docks scene is up
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 7
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
		print("host: ", "ok" if net.host(7795, "Rosa", "The Night Owls") == "" else "failed")
		net.send_intent({"t": "add_local", "name": "Dev", "crew": "The Lucky Breaks"})
		net.send_intent({"t": "start", "target": 20})
	elif frame == 20:
		hud = main.get("_hud")
		var p: Dictionary = net.active_player()
		net.server._police_encounter(p, "Police checkpoint!")
		net._broadcast()
	elif frame == 30:
		net.send_intent({"t": "pending", "id": "run"})
		current = "escape"
		started_at = Time.get_ticks_msec()
	elif start_at_frame > 0:
		if frame >= start_at_frame:
			start_at_frame = 0
			_start(current)
	elif current != "":
		return _play()
	return false


func _play() -> bool:
	var s: Dictionary = net.state
	var pend: String = s.pending.get("kind", "")
	var m: Dictionary = s.get("mini", {})
	var view: Node = main.get("_city_view")
	if pend == "mini":
		var on_screen: bool = hud._mini_panel.visible and (view.in_mini() if m.game != "safe" else hud._mini_panel._safe.visible)
		if not on_screen:
			print("FAIL: %s running but not on screen" % current)
			return _finish(1)
		if m.game != "safe" and view.place_view.visible:
			print("FAIL: %s is staged with the building scene still showing over it" % current)
			return _finish(1)
		var ms := Time.get_ticks_msec() - started_at
		if not shot_mid and int(m.ready) <= 0 and ms > 4000:
			shot_mid = true
			_shot(current)
		if Time.get_ticks_msec() - last_input > 60 and int(m.ready) <= 0:
			last_input = Time.get_ticks_msec()
			if m.game == "safe":
				hud._mini_panel.press(["N", "N", "N", "E", "S"][rng.randi() % 5])
			else:
				hud._move(["N", "S", "E", "W"][rng.randi() % 4])
		if m.game == "train" and ms > 8000 and m.get("phase", "") == "push":
			hud._mini_panel._quit.emit_signal("pressed")   # call the train
		if ms > 90000:
			print("FAIL: %s never ended" % current)
			return _finish(1)
		return false
	# Over: whatever came after (a result, a fight, a police stop) - note it, clear it, next game.
	print("%s: ended in %s (%s)" % [current, pend, s.pending.get("title", "")])
	if pend == "":
		print("FAIL: %s ended with nothing on screen" % current)
		return _finish(1)
	if pend == "fight":
		net.send_intent({"t": "pending", "id": "surrender"})
	elif pend == "police":
		net.send_intent({"t": "pending", "id": "bribe" if s.pending.options[1].enabled else "fight"})
		if net.state.pending.get("kind", "") == "fight":
			net.send_intent({"t": "pending", "id": "surrender"})
	if net.state.pending.get("kind", "") == "result":
		net.send_intent({"t": "pending", "id": "ok"})
	if queue.is_empty():
		print("minigames: all %d played through the HUD" % (GAMES.size() + 1))
		return _finish(0)
	current = queue.pop_front()
	var p: Dictionary = net.active_player()
	p.jail = 0
	p.steps = 25
	p.cash = 9000
	# From inside the docks, like a real robbery: the building's scene must make way for the game.
	for b in net.state.city.buildings:
		if b.type == "harbor":
			p.inside = int(b.id)
			break
	net._broadcast()
	start_at_frame = frame + 10
	return false


func _start(game: String) -> void:
	if not main.get("_city_view").place_view.showing():
		print("FAIL: the docks scene never came up")
	net.server._start_mini(net.active_player(), game, "Practice: " + game, "Test run.", 2, {"k": "practice"})
	net._broadcast()
	started_at = Time.get_ticks_msec()
	shot_mid = false


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("%s/mini_%s.png" % [shots_dir, tag])


func _finish(code: int) -> bool:
	quit(code)
	return true
