extends SceneTree
## Network smoke test. Start a dedicated server first:
##   godot --headless --path . -- --server --port=7790
## Then run two of these (the first one becomes room host and starts the game):
##   godot --headless --path . --script res://tests/net_client_test.gd -- --name=Ana --start
##   godot --headless --path . --script res://tests/net_client_test.gd -- --name=Bo
## Each client plays random moves on its own turns and prints what it sees.

var net: Node
var my_name := "Tester"
var starter := false
var port := 7790
var url := ""   # e.g. --url=ws://127.0.0.1:8088/ws to go through the nginx proxy
var ticks := 0
var seen_other_moves := 0
var my_moves := 0
var last_rev := -1
var started := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			my_name = a.substr(7)
		elif a == "--start":
			starter = true
		elif a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--url="):
			url = a.substr(6)


func _process(_delta: float) -> bool:
	if net == null:
		net = root.get_node_or_null("Net")
		if net == null:
			return false
		net.error_message.connect(func(m: String): print("[%s] server says: %s" % [my_name, m]))
		var err: String = net.join(url if url != "" else "127.0.0.1", port, my_name, my_name + "'s Crew")
		print("[%s] join: %s" % [my_name, "ok" if err == "" else err])
		return false
	ticks += 1
	var s: Dictionary = net.state
	if s.is_empty():
		return ticks > 600 and _done("never received state")
	if s.phase == "lobby" and starter and s.players.size() >= 2 and not started:
		started = true
		print("[%s] starting with %d players" % [my_name, s.players.size()])
		net.send_intent({"t": "start", "target": 20})
	if int(s.rev) != last_rev:
		last_rev = int(s.rev)
		if s.phase == "playing":
			var a: Dictionary = net.active_player()
			if not net.is_my_turn():
				seen_other_moves += 1
	if s.phase == "playing" and net.is_my_turn() and ticks % 3 == 0:
		var a2: Dictionary = net.active_player()
		my_moves += 1
		if not s.pending.is_empty():
			net.send_intent({"t": "pending", "id": s.pending.options[0].id})
		elif int(a2.inside) >= 0:
			net.send_intent({"t": "menu", "id": "leave"})
		elif my_moves % 15 == 0:
			net.send_intent({"t": "end_turn"})
		else:
			net.send_intent({"t": "move", "dir": ["N", "S", "E", "W"][randi() % 4]})
	if ticks > 900:
		return _done("finished")
	return false


func _done(why: String) -> bool:
	var s: Dictionary = net.state
	print("[%s] %s: phase=%s month=%s my_actions=%d state_updates_while_spectating=%d players=%d" % [
		my_name, why, s.get("phase", "?"), s.get("month", "?"), my_moves, seen_other_moves, s.get("players", {}).size()])
	quit(0)
	return true
