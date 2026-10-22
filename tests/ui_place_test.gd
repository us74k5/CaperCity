extends SceneTree
## Puts the active player inside one building of every type in turn and checks the street-level
## scene of that place comes up (and goes away on leaving).
## Run: godot --path . --script res://tests/ui_place_test.gd [-- --shots=DIR]   (headless works too)

var main: Node
var net: Node
var frame := 0
var shots_dir := ""
var types: Array = []
var current := ""
var wait := 0


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
		print("host: ", "ok" if net.host(7794, "Rosa", "The Night Owls") == "" else "failed")
		net.send_intent({"t": "add_local", "name": "Dev", "crew": "The Lucky Breaks"})
		net.send_intent({"t": "start", "target": 20})
	elif frame == 20:
		types = Balance.BUILDINGS.keys()
		net.active_player().car = 2
	elif frame > 20:
		if wait > 0:
			wait -= 1
			return false
		var view: Node = main.get("_city_view")
		var p: Dictionary = net.active_player()
		if current != "":
			if not view.in_place() or not view.place_view.showing():
				print("FAIL: no scene inside the %s" % current)
				return _finish(1)
			_shot(current)
			print("%s: %d fps" % [current, Engine.get_frames_per_second()])
			net.send_intent({"t": "menu", "id": "leave"})
			current = ""
			wait = 3
			return false
		if view.place_view.showing() and int(p.inside) < 0:
			wait = 1
			return false
		if types.is_empty():
			print("place scenes: all %d building types ok" % Balance.BUILDINGS.size())
			return _finish(0)
		current = types.pop_front()
		for b in net.state.city.buildings:
			if b.type == current:
				p.steps = 25
				net.server._enter(p, b)
				net._broadcast()
				break
		wait = 25
	return false


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("%s/place_%s.png" % [shots_dir, tag])


func _finish(code: int) -> bool:
	quit(code)
	return true
