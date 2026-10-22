extends SceneTree
## Network chase check, host side. Hosts on port 7796, waits for net_chase_client.gd to join,
## starts a game, forces a police stop and makes a run for it, then lets the server's clock run
## the chase (as in a real game) and quits a moment after it ends.
##   godot --headless --path . --script res://tests/net_chase_host.gd &
##   godot --headless --path . --script res://tests/net_chase_client.gd

var net: Node
var frame := 0
var started := false
var done_at := -1


func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	if frame == 2:
		net = root.get_node("Net")
		print("host: ", "ok" if net.host(7796, "Rosa", "The Night Owls") == "" else "failed")
	elif not started and net.state.players.size() >= 2:
		started = true
		net.send_intent({"t": "start", "target": 20})
		var p: Dictionary = net.active_player()
		net.server._police_encounter(p, "Police checkpoint!")
		net.server._police_choice(p, "run")
		net._broadcast()
		print("host: chase %d started" % int(net.state.mini.id))
	elif started and done_at < 0 and net.state.pending.get("kind", "") != "mini":
		done_at = frame
		print("host: chase over, now %s" % net.state.pending.get("kind", "nothing"))
	elif done_at > 0 and frame > done_at + 60:
		quit(0)
		return true
	if frame > 6000:
		print("host: FAIL timeout")
		quit(1)
		return true
	return false
