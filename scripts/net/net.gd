extends Node
## Autoload "Net". Server-authoritative networking over WebSockets.
##
## One process runs the GameServer (the host, or a dedicated headless server). Clients
## send intents; the server applies them and broadcasts the full state to everyone.
## Spectating needs nothing extra: every client renders the same state stream.
##
## Dedicated server:  godot --headless --path . -- --server --port=7777

signal state_updated
signal error_message(text: String)
signal connection_lost(reason: String)
signal joined

const DEFAULT_PORT := 7777
const BUFFER := 4 * 1024 * 1024

var server: GameServer = null
var state: Dictionary = {}
var my_peer := 0
var dedicated := false
var _join_info := {}


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
		var err := host(port, "", "")
		dedicated = true
		print("[server] Caper City dedicated server ", "listening on port %d" % port if err == "" else err)


func _new_peer() -> WebSocketMultiplayerPeer:
	var p := WebSocketMultiplayerPeer.new()
	p.inbound_buffer_size = BUFFER
	p.outbound_buffer_size = BUFFER
	p.max_queued_packets = 4096
	return p


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
		server.handle(1, {"t": "join", "name": player_name, "crew": crew})
	_broadcast()
	joined.emit()
	return ""


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
	_join_info = {"name": player_name, "crew": crew}
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	server = null
	state = {}
	my_peer = 0


func is_host() -> bool:
	return server != null


func send_intent(intent: Dictionary) -> void:
	if server != null:
		var err := server.handle(my_peer, intent)
		if err != "":
			error_message.emit(err)
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
	state = server.state
	if multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
		_rpc_state.rpc(server.state)
	state_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(intent: Dictionary) -> void:
	if server == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var err := server.handle(sender, intent)
	if err != "":
		_rpc_error.rpc_id(sender, err)
	_broadcast()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(s: Dictionary) -> void:
	state = s
	state_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_error(msg: String) -> void:
	error_message.emit(msg)


func _on_connected() -> void:
	my_peer = multiplayer.get_unique_id()
	_rpc_intent.rpc_id(1, {"t": "join", "name": _join_info.get("name", ""), "crew": _join_info.get("crew", "")})
	joined.emit()


func _on_peer_connected(id: int) -> void:
	if server != null:
		server.set_connected(id, true)
		_rpc_state.rpc_id(id, server.state)


func _on_peer_disconnected(id: int) -> void:
	if server != null:
		server.set_connected(id, false)
		_broadcast()
