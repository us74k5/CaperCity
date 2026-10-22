extends Node
## Screen manager: main menu → lobby → game. Everything is built in code.

const SETTINGS_PATH := "user://settings.cfg"

var _layer: CanvasLayer
var _screen: Control
var _city_view: Node3D
var _hud: Control
var _toast: Label
var _toast_timer := 0.0
var _current := ""


func _ready() -> void:
	if Net.dedicated:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)
	_toast = UiTheme.label("", 18, UiTheme.TEXT)
	_toast.add_theme_stylebox_override("normal", UiTheme.box(Color("#3D2422"), UiTheme.CORAL, 10, 14))
	_toast.visible = false
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position.y -= 90
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Net.state_updated.connect(_on_state)
	Net.error_message.connect(toast)
	Net.connection_lost.connect(func(reason: String):
		Net.leave()
		show_menu()
		toast(reason))
	show_menu()


func _process(delta: float) -> void:
	if _toast and _toast.visible:
		_toast_timer -= delta
		if _toast_timer <= 0:
			_toast.visible = false


func toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_timer = 3.0
	_toast.reset_size()
	_toast.position.x = (get_viewport().get_visible_rect().size.x - _toast.size.x) / 2.0
	_layer.move_child(_toast, -1)


func _set_screen(c: Control, name_: String) -> void:
	if _screen:
		_screen.queue_free()
	_screen = c
	_current = name_
	c.theme = UiTheme.make()
	_layer.add_child(c)
	if _toast.get_parent():
		_layer.remove_child(_toast)
	_layer.add_child(_toast)
	_toast.theme = c.theme


func _on_state() -> void:
	var s := Net.state
	if s.is_empty():
		return
	if s.phase == "lobby":
		if _current != "lobby":
			show_lobby()
		else:
			_refresh_lobby()
	elif _current != "game":
		show_game()


# ------------------------------------------------------------------ settings

func _load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return {"name": cfg.get_value("player", "name", ""), "crew": cfg.get_value("player", "crew", ""),
		"address": cfg.get_value("net", "address", "127.0.0.1")}


func _save_settings(n: String, c: String, a: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", n)
	cfg.set_value("player", "crew", c)
	cfg.set_value("net", "address", a)
	cfg.save(SETTINGS_PATH)


# ------------------------------------------------------------------ main menu

func show_menu() -> void:
	if _city_view:
		_city_view.queue_free()
		_city_view = null
	var root := ColorRect.new()
	root.color = UiTheme.BG
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(440, 0)
	center.add_child(v)

	v.add_child(UiTheme.label("RIVAL CREWS · ONE TOWN · LIVE", 15, UiTheme.TEAL))
	var logo := VBoxContainer.new()
	logo.add_theme_constant_override("separation", -34)
	logo.add_child(UiTheme.label("CAPER", 76, UiTheme.CORAL))
	logo.add_child(UiTheme.label("CITY", 76, UiTheme.TEXT))
	v.add_child(logo)
	v.add_child(UiTheme.label("Pull the job. Dodge the cops. Run the town.", 18, UiTheme.MUTED))

	var st := _load_settings()
	var name_in := LineEdit.new()
	name_in.placeholder_text = "Your name"
	name_in.text = st.name
	name_in.max_length = 16
	var crew_in := LineEdit.new()
	crew_in.placeholder_text = "Crew name (e.g. The Night Owls)"
	crew_in.text = st.crew
	crew_in.max_length = 24
	var addr_in := LineEdit.new()
	addr_in.placeholder_text = "Server address to join, e.g. 192.168.1.20"
	addr_in.text = st.address
	for le in [name_in, crew_in]:
		le.custom_minimum_size = Vector2(0, 48)
		v.add_child(le)

	var host_b := UiTheme.button("Host a game", true, 56)
	v.add_child(host_b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	addr_in.custom_minimum_size = Vector2(0, 48)
	addr_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(addr_in)
	var join_b := UiTheme.button("Join", false, 48)
	join_b.custom_minimum_size.x = 110
	row.add_child(join_b)
	v.add_child(row)
	var solo_b := UiTheme.button("Solo test (you + a local rival)", false, 48)
	v.add_child(solo_b)
	var music_b := UiTheme.button("Music: On" if Music.playing else "Music: Off", false, 44)
	music_b.pressed.connect(func(): music_b.text = "Music: On" if Music.toggle() else "Music: Off")
	v.add_child(music_b)
	var note := UiTheme.label("Friends on the same Wi-Fi join with your address. Port %d. Press M in game to toggle music." % Net.DEFAULT_PORT, 14, UiTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)

	host_b.pressed.connect(func():
		_save_settings(name_in.text, crew_in.text, addr_in.text)
		var err := Net.host(Net.DEFAULT_PORT, _or(name_in.text, "Boss"), crew_in.text)
		if err != "":
			toast(err))
	join_b.pressed.connect(func():
		_save_settings(name_in.text, crew_in.text, addr_in.text)
		var err := Net.join(addr_in.text, Net.DEFAULT_PORT, _or(name_in.text, "Player"), crew_in.text)
		if err != "":
			toast(err)
		else:
			toast("Connecting…"))
	solo_b.pressed.connect(func():
		_save_settings(name_in.text, crew_in.text, addr_in.text)
		var err := Net.host(Net.DEFAULT_PORT, _or(name_in.text, "Boss"), crew_in.text)
		if err != "":
			toast(err)
			return
		Net.send_intent({"t": "add_local", "name": "Rival", "crew": "The Other Guys"}))
	_set_screen(root, "menu")


func _or(s: String, fallback: String) -> String:
	return fallback if s.strip_edges() == "" else s


# ------------------------------------------------------------------ lobby

var _lobby_list: VBoxContainer
var _lobby_start: Button
var _lobby_target: OptionButton
var _lobby_local: Button


func show_lobby() -> void:
	var root := ColorRect.new()
	root.color = UiTheme.BG
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(520, 0)
	center.add_child(v)
	v.add_child(UiTheme.label("LOBBY", 15, UiTheme.TEAL))
	v.add_child(UiTheme.label("Waiting for crews", 40))
	if Net.is_host():
		var ips: Array = []
		for ip in IP.get_local_addresses():
			if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				ips.append(ip)
		var addr_l := UiTheme.label("Friends join at: %s  (port %d)" % [", ".join(ips) if ips.size() > 0 else "your IP address", Net.DEFAULT_PORT], 16, UiTheme.YELLOW)
		addr_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(addr_l)
	var panel := PanelContainer.new()
	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 6)
	panel.add_child(_lobby_list)
	v.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(UiTheme.label("Game length", 16, UiTheme.MUTED))
	_lobby_target = OptionButton.new()
	_lobby_target.add_item("Quick (20 points)", 20)
	_lobby_target.add_item("Standard (35 points)", 35)
	_lobby_target.add_item("Long (50 points)", 50)
	_lobby_target.select(1)
	_lobby_target.custom_minimum_size = Vector2(240, 44)
	row.add_child(_lobby_target)

	_lobby_local = UiTheme.button("Add a player on this device", false, 44)
	_lobby_local.pressed.connect(func():
		var n: int = Net.state.players.size() + 1
		Net.send_intent({"t": "add_local", "name": "Player %d" % n, "crew": ""}))
	v.add_child(_lobby_local)
	_lobby_start = UiTheme.button("Start the game", true, 56)
	_lobby_start.pressed.connect(func():
		Net.send_intent({"t": "start", "target": _lobby_target.get_selected_id()}))
	v.add_child(_lobby_start)
	var leave := UiTheme.button("Leave", false, 44)
	leave.pressed.connect(func():
		Net.leave()
		show_menu())
	v.add_child(leave)
	_set_screen(root, "lobby")
	_refresh_lobby()


func _refresh_lobby() -> void:
	if _lobby_list == null or not is_instance_valid(_lobby_list):
		return
	for c in _lobby_list.get_children():
		c.queue_free()
	for pid in Net.state.players:
		var p: Dictionary = Net.state.players[pid]
		var l := UiTheme.label("•  %s  —  %s%s" % [p.name, p.crew_name, "  (this device)" if int(p.owner) == Net.my_peer else ""], 18, Color(p.color))
		_lobby_list.add_child(l)
	var host := Net.am_room_host()
	_lobby_start.visible = host
	_lobby_target.disabled = not host
	_lobby_local.visible = host
	if not host:
		_lobby_list.add_child(UiTheme.label("The host starts the game.", 15, UiTheme.MUTED))


# ------------------------------------------------------------------ game

func show_game() -> void:
	if _city_view == null:
		_city_view = preload("res://scripts/ui/city_view_3d.gd").new()
		add_child(_city_view)
	_city_view.set_city(Net.state.city)
	var hud: Control = preload("res://scripts/ui/hud.gd").new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.city_view = _city_view
	hud.back_to_menu.connect(func():
		Net.leave()
		show_menu())
	_set_screen(hud, "game")
	_hud = hud
	hud.refresh()
