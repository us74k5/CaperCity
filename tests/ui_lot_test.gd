extends SceneTree
## The car dealer's lot (cars for sale up front, the ones to steal in the back) and the camera
## walking in among them while you pick one to steal.
## Run: godot --path . --script res://tests/ui_lot_test.gd [-- --shots=DIR]  (headless works too)

var main: Node
var net: Node
var frame := 0
var shots_dir := ""
var fails := 0


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
			net.host(7797, "Rosa", "The Night Owls")
		20:
			net.send_intent({"t": "add_local", "name": "Dev", "crew": "The Lucky Breaks"})
			net.send_intent({"t": "start", "target": 20})
		40:
			var p: Dictionary = net.server._active()
			for b in net.state.city.buildings:
				if b.type == "car_dealer":
					p.inside = int(b.id)
					break
			p.menu_path = []
			p.steps = 20
			net.server._refresh_menu(p)
			net._broadcast()
		90:
			var pv: Node = main.get("_city_view").place_view
			_check(pv.lot != null and pv.lot.mode == "lot", "the car dealer is a lot")
			_check(pv.lot._tags.size() >= 6, "every car has its tag (%d)" % pv.lot._tags.size())
			_shot("lot")
			net.send_intent({"t": "menu", "id": "sub:steal_car"})
		150:
			var pv2: Node = main.get("_city_view").place_view
			_check(pv2.lot.mode == "steal", "picking a car to steal walks in among them")
			_shot("steal")
		160:
			print("ui lot: ", "ok" if fails == 0 else "%d FAILED" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false


func _shot(tag: String) -> void:
	if shots_dir == "":
		return
	await process_frame
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("%s/lot_%s.png" % [shots_dir, tag])


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
