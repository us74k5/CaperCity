extends SceneTree
## Joins a running server through the real UI and captures what a spectator sees.
## Needs a server and an active player (e.g. tests/net_client_test.gd with --start).
## Run: godot --path . --script res://tests/ui_spectator_test.gd -- --port=7792 --shots=DIR

var main: Node
var net: Node
var frame := 0
var port := 7792
var shots_dir := ""
var shots := 0
var spectated_updates := 0
var last_rev := -1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		net = root.get_node("Net")
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
	elif frame == 5:
		print("join: ", net.join("127.0.0.1", port, "Dev", "The Lucky Breaks"))
	elif frame > 5:
		var s: Dictionary = net.state
		if s.is_empty() or s.phase != "playing":
			return frame > 3000 and _end()
		if int(s.rev) != last_rev:
			last_rev = int(s.rev)
			if not net.is_my_turn():
				spectated_updates += 1
				if spectated_updates in [3, 25, 60]:
					_shot("spectating")
		if net.is_my_turn() and frame % 6 == 0:
			var a: Dictionary = net.active_player()
			if not s.pending.is_empty():
				net.send_intent({"t": "pending", "id": s.pending.options[0].id})
			elif int(a.inside) >= 0:
				net.send_intent({"t": "menu", "id": "leave"})
			else:
				net.send_intent({"t": "end_turn"})
		if frame > 3000 or shots >= 3:
			return _end()
	return false


func _shot(tag: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	if img and not img.is_empty() and shots_dir != "":
		shots += 1
		img.save_png("%s/spec_%02d_%s.png" % [shots_dir, shots, tag])


func _end() -> bool:
	print("spectator: updates while watching=%d shots=%d" % [spectated_updates, shots])
	quit(0)
	return true
