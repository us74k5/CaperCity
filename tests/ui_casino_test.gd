extends SceneTree
## Walks into the casino, sits at each table by clicking it (through the HUD's table handler), bets
## with a chip, and checks the hand plays out on the table before the result card shows.
## Run: godot --path . --script res://tests/ui_casino_test.gd [-- --shots=DIR]   (headless works too)

const TABLES := ["blackjack", "poker", "roulette"]

var main: Node
var net: Node
var hud: Node
var frame := 0
var shots_dir := ""
var step := "enter"
var table := ""
var queue: Array = TABLES.duplicate()
var at := 0


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
		print("host: ", "ok" if net.host(7797, "Rosa", "The Night Owls") == "" else "failed")
		net.send_intent({"t": "add_local", "name": "Dev", "crew": "The Lucky Breaks"})
		net.send_intent({"t": "start", "target": 20})
	elif frame == 20:
		hud = main.get("_hud")
		var p: Dictionary = net.active_player()
		p.cash = 50000
		p.steps = 25
		for b in net.state.city.buildings:
			if b.type == "casino":
				net.server._enter(p, b)
				break
		net._broadcast()
		at = frame
	elif frame > 20:
		return _tick()
	return false


func _tick() -> bool:
	var view: Node = main.get("_city_view")
	var p: Dictionary = net.active_player()
	match step:
		"enter":
			if frame - at == 40:
				if view.place_view.casino == null:
					print("FAIL: no casino interior")
					return _finish(1)
				if hud._menu_panel.visible or not hud._casino_bar.visible:
					print("FAIL: casino should show its bar, not the menu panel")
					return _finish(1)
				_shot("room")
				step = "sit"
		"sit":
			table = queue.pop_front()
			hud._on_table(table)
			if view.casino_table(net.active_player()) != table:
				print("FAIL: didn't sit at the %s table" % table)
				return _finish(1)
			at = frame
			step = "bet"
		"bet":
			if frame - at == 30:
				_shot(table + "_seated")
				net.send_intent({"t": "menu", "id": "act:gamble:%s:500" % table})
				at = frame
				step = "watch"
		"watch":
			var pend: Dictionary = net.state.pending
			if frame - at == 2 and hud._modal.visible:
				print("FAIL: result card showed before the %s hand was played" % table)
				return _finish(1)
			if frame - at == 60:
				_shot(table + "_playing")
			if hud._modal.visible:
				_shot(table + "_result")
				print("%s: %s (after %d frames, %d fps)" % [table, pend.text, frame - at, Engine.get_frames_per_second()])
				if hud._modal_box.get_child_count() == 0:
					print("FAIL: the result card is empty")
					return _finish(1)
				net.send_intent({"t": "pending", "id": "ok"})
				step = "sit" if not queue.is_empty() else "done"
				at = frame
			elif frame - at > 1500:
				print("FAIL: %s hand never finished" % table)
				return _finish(1)
		"done":
			print("casino: all tables played")
			return _finish(0)
	return false


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("%s/casino_%s.png" % [shots_dir, tag])


func _finish(code: int) -> bool:
	quit(code)
	return true
