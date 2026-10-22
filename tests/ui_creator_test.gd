extends SceneTree
## Character creation in the lobby (rolling every stat on its button, flipping characters, ready),
## dragging the map without moving anyone, and the arms dealer's store, gym and crew stats.
## Run: godot --path . --script res://tests/ui_creator_test.gd [-- --shots=DIR] [--mobile]  (headless works too)

var main: Node
var net: Node
var frame := 0
var shots_dir := ""
var fails := 0
var creator: Node
var arms_id := -1
var start_pos := []
var spin_wait := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)


func _process(_d: float) -> bool:
	frame += 1
	match frame:
		2:
			net = root.get_node("Net")
			main = load("res://scenes/main.tscn").instantiate()
			root.add_child(main)
		10:
			net.host(7796, "Rosa", "The Night Owls")
		20:
			creator = _find_creator(main)
			_check(creator != null and creator.visible, "the lobby shows the character creator")
			_shot("lobby")
			for stat in Balance.ROLL_STATS:
				creator._roll(stat)
		26:
			_shot("rolling")
			_check(creator._reels.muscle.spin >= 0.0, "the reels spin")
		120:
			if creator._reels.values().any(func(r): return r.spin >= 0.0) and spin_wait < 2000:
				spin_wait += 1
				frame -= 1   # the reels spin for a set time, so wait for them however fast frames come
				return false
			var me: Dictionary = net.state.players[1]
			_check(me.rolls.size() == Balance.ROLL_STATS.size(), "every stat rolled (%s)" % me.rolls)
			_check(creator._reels.muscle.spin < 0.0 and creator._reels.muscle.value.text == str(me.crew[0].muscle), "the reel landed on the rolled number")
			_check(creator._reels.muscle.button.text == "RE-ROLL", "the button turns into a re-roll")
			var before: String = me.avatar
			creator._flip(1)
			_check(net.state.players[1].avatar != before and net.state.players[1].avatar != "", "the arrows change character")
		130:
			_shot("rolled")
			creator._ready_b.pressed.emit()
		140:
			_check(net.state.players[1].ready, "ready")
			_shot("ready")
			net.send_intent({"t": "add_local", "name": "Dev", "crew": "The Lucky Breaks"})
			net.send_intent({"t": "start", "target": 20})
		170:
			var cv: Node = main.get("_city_view")
			var a: Dictionary = net.active_player()
			start_pos = a.pos.duplicate()
			var cam0: Vector3 = cv._cam_target
			_drag(cv, MOUSE_BUTTON_LEFT, Vector2(640, 360), Vector2(380, 250))
			_check(cv.free_look, "dragging the map looks around")
			_check(cv._cam_target.distance_to(cam0) > 2.0, "the camera moved (%.1f)" % cv._cam_target.distance_to(cam0))
			_check(net.active_player().pos == start_pos and main.get("_hud")._path.is_empty(), "dragging doesn't walk")
			var cam1: Vector3 = cv._cam_target
			_drag(cv, MOUSE_BUTTON_RIGHT, Vector2(500, 300), Vector2(700, 420))
			_check(cv._cam_target.distance_to(cam1) > 1.0, "the right button drags too")
		180:
			_shot("look_around")
			_check(main.get("_hud")._centre_btn.visible, "the Centre button shows while looking around")
			main.get("_hud")._centre_btn.pressed.emit()
			_check(not main.get("_city_view").free_look, "Centre goes back to the crew")
		200:
			var p: Dictionary = net.server._active()
			for b in net.state.city.buildings:
				if b.type == "arms" and arms_id < 0:
					arms_id = int(b.id)
			p.inside = arms_id
			p.menu_path = []
			p.cash = 20000
			p.crew[0].smarts = 30
			p.crew[0].nerve = 80
			net.server._refresh_menu(p)
			net._broadcast()
		240:
			var pv: Node = main.get("_city_view").place_view
			_check(pv.arms != null and pv.arms.mode == "shop", "the arms dealer is a store you walk into")
			_shot("gun_store")
			net.send_intent({"t": "menu", "id": "sub:buy_gear"})
		250:
			var pick := ""
			for e in net.active_player().menu:
				if str(e.id).begins_with("sub:gear_") and pick == "":
					var gi := int(str(e.id).substr(9))
					if int(Balance.GEAR[gi].smarts) > 30:
						pick = e.id
			if pick == "":
				pick = net.active_player().menu[0].id
			net.send_intent({"t": "menu", "id": pick})
		280:
			var hud: Node = main.get("_hud")
			_check(hud._locker.visible, "buying a weapon shows the crew's stats")
			_check("needs" in hud._locker_text.text, "and who can't handle it")
			var reason := ""
			for e in net.active_player().menu:
				if not e.enabled:
					reason = str(e.get("reason", ""))
			print("gear refused because: ", reason)
			_shot("buy_gear")
			net.send_intent({"t": "menu", "id": "back"})
			net.send_intent({"t": "menu", "id": "back"})
			net.send_intent({"t": "menu", "id": "sub:train"})
		330:
			var pv2: Node = main.get("_city_view").place_view
			_check(pv2.arms.mode == "gym", "training takes you into the gym")
			_check(main.get("_hud")._locker.visible and "LOCKER" in main.get("_hud")._locker_text.text, "the locker room shows the crew's stats")
			_shot("gym")
			net.send_intent({"t": "menu", "id": "sub:train_0"})
		350:
			_shot("gym_member")
			for e in net.active_player().menu:
				if str(e.id).ends_with(":muscle"):
					net.send_intent({"t": "menu", "id": e.id})
					break
		370:
			if net.state.pending.get("kind", "") != "result" and spin_wait < 4000:
				spin_wait += 1
				frame -= 1   # wait for the training result however slowly frames come
				return false
			print("training: ", net.state.pending.get("kind", "-"), " ", net.state.pending.get("title", "-"), " ", net.state.pending.get("text", "?"), " inside=", net.active_player().inside, " path=", net.active_player().menu_path)
			_check("→" in str(net.state.pending.get("text", "")), "training shows before and after")
			_shot("trained")
			net.send_intent({"t": "pending", "id": "ok"})
			# Someone who joins mid-game makes their boss over the town.
			var me: Dictionary = net.server.state.players[1]
			net.server._active().inside = -1
			me.ready = false
			me.rolls = {}
			net._broadcast()
		400:
			_check(main.get("_hud")._creator_layer != null, "a mid-game joiner gets the creator over the town")
			_shot("midgame_creator")
		410:
			print("ui creator: ", "ok" if fails == 0 else "%d FAILED" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false


func _drag(cv: Node, button: int, from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = from
	cv._unhandled_input(down)
	for i in range(1, 11):
		var mv := InputEventMouseMotion.new()
		mv.position = from.lerp(to, i / 10.0)
		cv._unhandled_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = to
	cv._unhandled_input(up)


func _find_creator(n: Node) -> Node:
	if n.get_script() != null and n.get_script().resource_path.ends_with("ui/creator.gd"):
		return n
	for c in n.get_children():
		var f := _find_creator(c)
		if f:
			return f
	return null


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	await process_frame
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("%s/creator_%s.png" % [shots_dir, tag])


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
