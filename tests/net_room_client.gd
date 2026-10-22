extends SceneTree
## Room test: joining a game in progress, getting your crew back, and ending the game.
## Start a dedicated server, then run the roles in this order (tests/net_room_test.sh does it all):
##   --role=host   joins, starts the game alone, then ends it once the latecomer is back
##   --role=late   joins the running game with a new crew, then drops out
##   --role=back   joins again from the same device and must get that crew back
##   --role=ghost  like late, but stays connected (a phone whose connection died without closing):
##                 when "back" arrives from the same device, the server must close this one
## Pass --token= so each role is its own device (or the same one).
## Each prints PASS or FAIL.

var net: Node
var role := "host"
var port := 7792
var elapsed := 0.0
var step := 0
var replaced := false
var url := ""   # e.g. --url=wss://SERVER/ws to test the live server


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--url="):
			url = a.substr(6)


func _process(delta: float) -> bool:
	if net == null:
		net = root.get_node_or_null("Net")
		if net == null:
			return false
		net.error_message.connect(func(m: String): print("[%s] server says: %s" % [role, m]))
		net.connection_lost.connect(func(_r: String): replaced = true)
		net.join(url if url != "" else "127.0.0.1", port, {"host": "Ana", "late": "Late"}.get(role, "Phone"), "")
		return false
	elapsed += delta
	if elapsed > 60.0:
		return _end(false, "timed out at step %d" % step)
	var s: Dictionary = net.state
	if s.is_empty():
		return false
	match role:
		"host":
			if step == 0 and s.phase == "lobby" and net.am_room_host():
				net.send_intent({"t": "start", "target": 50})
				step = 1
			elif step == 1 and s.phase == "playing" and _logged(s, "is back."):
				if s.players.size() != 3:
					return _end(false, "expected 3 crews (Ana, the late one, the ghost), got %d" % s.players.size())
				net.send_intent({"t": "end_game"})
				step = 2
			elif step == 2 and s.phase == "lobby":
				return _end(s.players.size() == 2 and net.am_room_host(), "lobby after ending: %d seated, host=%s" % [s.players.size(), net.am_room_host()])
		"late":
			if s.phase == "playing" and not net.my_player().is_empty():
				var me: Dictionary = net.my_player()
				return _end(s.order.has(me.id) and me.connected, "joined the running game as %s (turn order %s)" % [me.crew_name, s.order])
			if elapsed > 10.0:
				return _end(false, "only spectating: phase=%s players=%d" % [s.phase, s.players.size()])
		"ghost":
			if step == 0 and s.phase == "playing" and not net.my_player().is_empty():
				print("[ghost] joined as %s; staying connected" % net.my_player().crew_name)
				step = 1
			elif step == 1 and replaced:
				return _end(true, "the server closed this connection when the device came back")
		"back":
			if step == 0 and s.phase == "playing" and not net.my_player().is_empty():
				if s.players.size() != 3:
					return _end(false, "got a new crew instead of the old one (%d crews)" % s.players.size())
				print("[back] got my crew back: %s" % net.my_player().crew_name)
				step = 1
			elif step == 1 and s.phase == "lobby":
				return _end(not net.my_player().is_empty(), "seated in the new lobby")
	return false


func _logged(s: Dictionary, text: String) -> bool:
	for e in s.log:
		if str(e.text).ends_with(text):
			return true
	return false


func _end(ok: bool, what: String) -> bool:
	print("[%s] %s: %s" % [role, "PASS" if ok else "FAIL", what])
	net.leave()
	quit(0 if ok else 1)
	return true
