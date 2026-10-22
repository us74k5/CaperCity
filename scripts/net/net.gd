extends Node
## Autoload "Net". Server-authoritative networking over WebSockets.
##
## One process runs the GameServer (the host, or a dedicated headless server). Clients
## send intents; the server applies them and broadcasts the full state to everyone.
## Spectating needs nothing extra: every client renders the same state stream.
##
## Dedicated server:  godot --headless --path . -- --server --port=7777
## A dedicated server is one room. Anyone who arrives mid-game joins it with a new crew (or gets back
## the crew they left, by device token); the room host can end the game, and it goes back to a fresh
## lobby by itself once no player is left in it.
## Browser builds connect to the page's own host at /ws (see deploy/nginx.conf).

signal state_updated
signal error_message(text: String)
signal connection_lost(reason: String)
signal joined
signal mini_updated

const DEFAULT_PORT := 7777
const BUFFER := 4 * 1024 * 1024
const TOKEN_PATH := "user://device.cfg"
const STALL_SECONDS := 60   # a turn with no word from its player this long can be skipped by anyone

var server: GameServer = null
var state: Dictionary = {}
var my_peer := 0
var dedicated := false
var _join_info := {}
var _port := DEFAULT_PORT
var _offline_wait := 0.0
var test_hooks := false   # --test-hooks: lets tests force situations (see _apply)
var stall_seconds := STALL_SECONDS   # server side; --stall-seconds= for tests
var _seats := {}   # server side: peer -> the join intent it sent, to seat it again in a new game
var _turn_key := ""          # server side: whose turn it is, to notice when it changes
var _heard_from_active := 0  # server side: msec when the active player last sent anything (or the turn began)
var _last_pending := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): connection_lost.emit("Couldn't reach the server."))
	multiplayer.server_disconnected.connect(func(): connection_lost.emit("The server closed the connection."))
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		var port := DEFAULT_PORT
		for a in args:
			if a.begins_with("--port="):
				port = int(a.substr(7))
		dedicated = true
		test_hooks = "--test-hooks" in args
		for a in args:
			if a.begins_with("--stall-seconds="):
				stall_seconds = int(a.substr(16))
		_port = port
		var err := host(port, "", "")
		print("[server] Caper City dedicated server ", "listening on port %d" % port if err == "" else err)


func _new_peer() -> WebSocketMultiplayerPeer:
	var p := WebSocketMultiplayerPeer.new()
	p.inbound_buffer_size = BUFFER
	p.outbound_buffer_size = BUFFER
	p.max_queued_packets = 4096
	return p


## Real-time minigames run on the server's clock. While one runs, only its small state goes out
## each tick; the full state follows when it ends.
func _process(delta: float) -> void:
	if server == null:
		return
	_skip_offline_turn(delta)
	match server.tick(delta):
		1:
			if multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
				_rpc_mini.rpc(server.state.mini)
			mini_updated.emit()
		2:
			_broadcast()


## Start hosting. Pass an empty name for a dedicated server (no local player).
func host(port: int, player_name: String, crew: String) -> String:
	leave()
	var peer := _new_peer()
	var err := peer.create_server(port)
	if err != OK:
		return "Couldn't open port %d (error %d). Is another game already running?" % [port, err]
	multiplayer.multiplayer_peer = peer
	server = GameServer.new()
	my_peer = 1
	if player_name != "" or crew != "":
		_apply(1, {"t": "join", "name": player_name, "crew": crew})
	_broadcast()
	joined.emit()
	return ""


## Where a browser build should connect: the server that served the page, through its /ws proxy.
func web_server_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var loc: Variant = JavaScriptBridge.eval("location.protocol + '//' + location.host", true)
	if typeof(loc) != TYPE_STRING or not str(loc).begins_with("http"):
		return ""
	return str(loc).replace("https://", "wss://").replace("http://", "ws://") + "/ws"


func join(address: String, port: int, player_name: String, crew: String) -> String:
	leave()
	var url := address.strip_edges()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		if not ":" in url:
			url = "%s:%d" % [url, port]
		url = "ws://" + url
	var peer := _new_peer()
	var err := peer.create_client(url)
	if err != OK:
		return "Couldn't connect to %s (error %d)." % [url, err]
	multiplayer.multiplayer_peer = peer
	_join_info = {"name": player_name, "crew": crew, "token": device_token()}
	return ""


## A random id kept on this device, so coming back to a running game hands you your old crew.
func device_token() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--token="):   # tests run several "devices" on one machine
			return a.substr(8)
	var cfg := ConfigFile.new()
	cfg.load(TOKEN_PATH)
	var token: String = cfg.get_value("net", "token", "")
	if token == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		token = "%08x%08x" % [rng.randi(), rng.randi()]
		cfg.set_value("net", "token", token)
		cfg.save(TOKEN_PATH)
	return token


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	server = null
	state = {}
	my_peer = 0
	_seats = {}


func is_host() -> bool:
	return server != null


func send_intent(intent: Dictionary) -> void:
	if server != null:
		var err := _apply(my_peer, intent)
		if err != "":
			error_message.emit(err)
		if not _mini_running(intent):
			_broadcast()
	elif my_peer != 0:
		_rpc_intent.rpc_id(1, intent)


# ---------------------------------------------------------------- queries for the UI

func active_player() -> Dictionary:
	if state.is_empty() or state.get("order", []).is_empty():
		return {}
	return state.players[state.order[state.active]]


func is_my_turn() -> bool:
	var p := active_player()
	return not p.is_empty() and int(p.owner) == my_peer and state.phase == "playing"


func my_player() -> Dictionary:
	## The player this device "is". With local seats, prefer the active one.
	var p := active_player()
	if not p.is_empty() and int(p.owner) == my_peer:
		return p
	if state.is_empty():
		return {}
	for pid in state.players:
		if int(state.players[pid].owner) == my_peer:
			return state.players[pid]
	return {}


func am_room_host() -> bool:
	return not state.is_empty() and int(state.room_host) == my_peer


# ---------------------------------------------------------------- plumbing

func _broadcast() -> void:
	if server == null:
		return
	_watch_turn()
	state = server.state
	if multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
		_rpc_state.rpc(server.state)
	state_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(intent: Dictionary) -> void:
	if server == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var err := _apply(sender, intent)
	if err != "":
		_rpc_error.rpc_id(sender, err)
		_say("%s: %s refused: %s" % [_who(sender), intent.get("t", "?"), err])
	if not _mini_running(intent):
		_broadcast()


## Keys during a running minigame: the next tick sends the minigame's own small update, so there's
## no need to send the whole game (tens of KB) to everyone on every key press.
func _mini_running(intent: Dictionary) -> bool:
	var m: Dictionary = server.state.get("mini", {})
	return str(intent.get("t", "")) == "mini" and not m.is_empty() and not m.over


@rpc("authority", "call_remote", "reliable")
func _rpc_state(s: Dictionary) -> void:
	state = s
	state_updated.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_mini(c: Dictionary) -> void:
	# Only newer ticks of the minigame already on screen (a late packet must not revive a finished game).
	var cur: Dictionary = state.get("mini", {})
	if not cur.is_empty() and not cur.over and int(c.get("id", -1)) == int(cur.get("id", -2)) and int(c.tick) > int(cur.tick):
		state.mini = c
		mini_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_error(msg: String) -> void:
	error_message.emit(msg)


func _on_connected() -> void:
	my_peer = multiplayer.get_unique_id()
	_rpc_intent.rpc_id(1, {"t": "join", "name": _join_info.get("name", ""), "crew": _join_info.get("crew", ""),
		"token": _join_info.get("token", "")})
	joined.emit()


func _on_peer_connected(id: int) -> void:
	if server != null:
		server.set_connected(id, true)
		_rpc_state.rpc_id(id, server.state)


func _on_peer_disconnected(id: int) -> void:
	if server == null:
		return
	_say("%s left" % _who(id))
	server.set_connected(id, false)
	_seats.erase(id)
	if dedicated and server.state.phase != "lobby" and not _anyone_playing():
		_say("no players left; opening a fresh lobby")
		_reset_room()
	_broadcast()


## Server side: the room-level intents, then the game's own.
func _apply(sender: int, intent: Dictionary) -> String:
	var active := server._active()
	if not active.is_empty() and int(active.owner) == sender:
		_heard_from_active = Time.get_ticks_msec()
	match str(intent.get("t", "")):
		"join":
			_seats[sender] = intent
			var jerr := server.handle(sender, intent)
			for old in server.stale_peers:
				_say("closing %d: its device came back as %d" % [old, sender])
				if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
					multiplayer.multiplayer_peer.disconnect_peer(old)
			server.stale_peers.clear()
			_say("%s joined (%s): %s" % [_who(sender), server.state.phase, jerr if jerr != "" else "ok"])
			return jerr
		"skip_stalled":
			if active.is_empty() or server.state.phase != "playing" or int(active.owner) == sender:
				return "Nothing to skip."
			if _who(sender).begins_with("peer "):
				return "Only players can skip a turn."
			var quiet := (Time.get_ticks_msec() - _heard_from_active) / 1000
			if active.connected and quiet < stall_seconds:
				return "%s still has %d seconds." % [active.name, stall_seconds - quiet]
			_say("%s skipped %s's turn after %d s of silence (pending=%s)" % [_who(sender), active.name, quiet, server.state.pending.get("kind", "")])
			server.skip_turn("(no word from them for %d seconds)" % quiet)
			return ""
		"test_police":
			var a: Dictionary = server._active()
			if test_hooks and not a.is_empty() and int(a.owner) == sender:
				server._police_encounter(a, "Police checkpoint! (test)")
			return ""
		"end_game":
			if sender != int(server.state.room_host):
				return "Only the room host can end the game."
			var who: Dictionary = {}
			for pid in server.state.players:
				if int(server.state.players[pid].owner) == sender:
					who = server.state.players[pid]
			_reset_room()
			var msg := "%s ended the game. Back in the lobby." % who.get("name", "The host")
			if multiplayer.get_peers().size() > 0:
				_rpc_error.rpc(msg)
			if my_peer == 1 and not dedicated:
				error_message.emit(msg)
			return ""
	return server.handle(sender, intent)


func _anyone_playing() -> bool:
	for pid in server.state.players:
		if server.state.players[pid].connected and not server.state.players[pid].local:
			return true
	return false


## A fresh lobby with everyone still here seated again (the room host first, so they keep the room).
func _reset_room() -> void:
	var host_peer := int(server.state.room_host)
	var locals: Array = []
	for pid in server.state.players:
		var p: Dictionary = server.state.players[pid]
		if p.local:
			locals.append({"t": "add_local", "name": p.name, "crew": p.crew_name})
	server = GameServer.new()
	var here: Array = multiplayer.get_peers()
	if not dedicated:
		here.append(1)
	for peer in [host_peer] + _seats.keys():
		if _seats.has(peer) and peer in here:
			server.handle(peer, _seats[peer])
	for intent in locals:
		server.handle(host_peer, intent)


## A player who dropped out can't take their turn; after a short grace the server skips it.
func _skip_offline_turn(delta: float) -> void:
	var a := active_player()
	if server.state.phase != "playing" or a.is_empty() or a.connected:
		_offline_wait = 0.0
		return
	_offline_wait += delta
	if _offline_wait >= 3.0:
		_offline_wait = 0.0
		_say("skipping %s's turn: offline" % a.name)
		server.handle(int(server.state.room_host), {"t": "skip"})
		_broadcast()


## Server side: notes whose turn it is and what they're being asked, for the log and the stall timer.
func _watch_turn() -> void:
	var a := server._active()
	var key := "" if a.is_empty() or server.state.phase != "playing" else "%s:%s:%s" % [a.id, server.state.month, server.state.active]
	if key != _turn_key:
		_turn_key = key
		_heard_from_active = Time.get_ticks_msec()
		if key != "":
			_say("month %s: %s's turn" % [server.state.month, a.name])
	var pend: String = server.state.pending.get("kind", "")
	if pend != _last_pending:
		_last_pending = pend
		if pend != "":
			_say("  %s: %s (%s)" % [a.get("name", "?"), pend, server.state.pending.get("title", "")])


func _who(peer: int) -> String:
	for pid in server.state.players:
		if int(server.state.players[pid].owner) == peer:
			return "%s[%d]" % [server.state.players[pid].name, peer]
	return "peer %d" % peer


func _say(msg: String) -> void:
	if dedicated:
		print("[server] ", msg)
