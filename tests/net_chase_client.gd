extends SceneTree
## Network chase check, client side (see net_chase_host.gd). Joins, then checks the chase arrives
## as a stream of updates whose ticks only go forward, and that the end comes through in full.

var net: Node
var frame := 0
var updates := 0
var last_tick := -1
var backwards := 0
var saw_chase := false


func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	if frame == 2:
		net = root.get_node("Net")
		net.mini_updated.connect(_on_chase)
		print("client: ", "ok" if net.join("127.0.0.1", 7796, "Bo", "") == "" else "failed")
	var s: Dictionary = net.state
	if not s.is_empty() and s.get("pending", {}).get("kind", "") == "mini":
		saw_chase = true
	elif saw_chase and not s.is_empty():
		var kind: String = s.pending.get("kind", "nothing")
		print("client: %d chase updates, %d out of order, ended in %s" % [updates, backwards, kind])
		var ok := updates > 20 and backwards == 0 and kind in ["fight", "result"]
		print("net chase: ", "ok" if ok else "FAIL")
		quit(0 if ok else 1)
		return true
	if frame > 6000:
		print("client: FAIL timeout (updates %d)" % updates)
		quit(1)
		return true
	return false


func _on_chase() -> void:
	updates += 1
	var t := int(net.state.mini.get("tick", -1))
	if t < last_tick:
		backwards += 1
	last_tick = t
