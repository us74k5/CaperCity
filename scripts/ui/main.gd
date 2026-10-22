extends Node
## Screen manager: main menu → lobby → game. Everything is built in code.

const SETTINGS_PATH := "user://settings.cfg"
const COMPACT_SHORT_SIDE := 480.0   # phones: the UI is laid out as if the short side were this many px

var _layer: CanvasLayer
var _screen: Control
var _city_view: Node3D
var _hud: Control
var _toast: Label
var _toast_timer := 0.0
var _current := ""
var _rotate: Control


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
	UiTheme.compact = UiTheme.detect_compact()
	if UiTheme.compact:
		_build_rotate_hint()
		get_viewport().size_changed.connect(_fit_ui)
		_fit_ui()
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


## Scale the UI so a phone screen gets readable text and thumb-sized buttons.
func _fit_ui() -> void:
	var win := get_window()
	var w := float(win.size.x)
	var h := float(win.size.y)
	if w <= 0 or h <= 0:
		return
	var base := minf(w / 1280.0, h / 720.0)    # what canvas_items/expand stretch would give
	win.content_scale_factor = maxf(1.0, (minf(w, h) / COMPACT_SHORT_SIDE) / base)
	_update_rotate_hint()


## The game screen needs landscape on a phone; portrait gets a full-screen hint instead.
func _build_rotate_hint() -> void:
	var r := ColorRect.new()
	r.color = UiTheme.BG
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	var icon := UiTheme.label("⟳", 64, UiTheme.CORAL)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(icon)
	var l := UiTheme.label("Turn your phone sideways", 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var m := UiTheme.label("Caper City plays in landscape.", 16, UiTheme.MUTED)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m)
	r.visible = false
	_rotate = r
	_layer.add_child(r)


func _update_rotate_hint() -> void:
	if _rotate == null:
		return
	var vs := get_viewport().get_visible_rect().size
	_rotate.visible = _current == "game" and vs.y > vs.x
	_layer.move_child(_rotate, -1)


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
	_update_rotate_hint()


func _on_state() -> void:
	var s := Net.state
	if s.is_empty():
		return
	if s.phase == "lobby":
		if _current != "lobby":
			if _city_view:   # the game was ended: back to the lobby
				_city_view.queue_free()
				_city_view = null
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
	v.add_theme_constant_override("separation", 8 if UiTheme.compact else 12)
	v.custom_minimum_size = Vector2(440, 0)
	center.add_child(v)

	v.add_child(UiTheme.label("RIVAL CREWS · ONE TOWN · LIVE", 15, UiTheme.TEAL))
	var logo := VBoxContainer.new()
	var logo_size := 48 if UiTheme.compact else 76   # a landscape phone is short
	logo.add_theme_constant_override("separation", -logo_size * 9 / 20)
	logo.add_child(UiTheme.label("CAPER", logo_size, UiTheme.CORAL))
	logo.add_child(UiTheme.label("CITY", logo_size, UiTheme.TEXT))
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

	var web_url := Net.web_server_url()
	if web_url != "":
		_web_menu(v, name_in, crew_in, web_url)
		_set_screen(root, "menu")
		return

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


## In a browser there's one server: the one that served the page. No hosting, just Play.
func _web_menu(v: VBoxContainer, name_in: LineEdit, crew_in: LineEdit, url: String) -> void:
	var play_b := UiTheme.button("Play", true, 56)
	v.add_child(play_b)
	var note := UiTheme.label("Everyone who opens this page joins the same town. The first player in starts the game; anyone who comes later joins it with a new crew.", 14, UiTheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	play_b.pressed.connect(func():
		_save_settings(name_in.text, crew_in.text, "")
		var err := Net.join(url, Net.DEFAULT_PORT, _or(name_in.text, "Player"), crew_in.text)
		toast(err if err != "" else "Connecting…"))


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
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16 if UiTheme.compact else 28)
	center.add_child(cols)
	# Left: make your boss. Right: who's here, and starting.
	cols.add_child(preload("res://scripts/ui/creator.gd").new())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8 if UiTheme.compact else 12)
	v.custom_minimum_size = Vector2(260 if UiTheme.compact else 380, 0)
	cols.add_child(v)
	v.add_child(UiTheme.label("LOBBY", 15, UiTheme.TEAL))
	v.add_child(UiTheme.label("Waiting for crews", 26 if UiTheme.compact else 36))
	if Net.is_host() and not OS.has_feature("web"):
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

	v.add_child(UiTheme.label("Game length", 15, UiTheme.MUTED))
	_lobby_target = OptionButton.new()
	_lobby_target.add_item("Quick (20 points)", 20)
	_lobby_target.add_item("Standard (35 points)", 35)
	_lobby_target.add_item("Long (50 points)", 50)
	_lobby_target.select(1)
	_lobby_target.custom_minimum_size = Vector2(240, 44)
	v.add_child(_lobby_target)

	_lobby_local = UiTheme.button("Add a player on this device", false, 44)
	_lobby_local.pressed.connect(func():
		var n: int = Net.state.players.size() + 1
		Net.send_intent({"t": "add_local", "name": "Player %d" % n, "crew": ""}))
	v.add_child(_lobby_local)
	_lobby_start = UiTheme.button("Start the game", true, 52)
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
	var waiting := 0
	for pid in Net.state.players:
		var p: Dictionary = Net.state.players[pid]
		var who := ""
		for a in Balance.AVATARS:
			if a.id == p.avatar:
				who = " as %s" % a.name
		var status := "✓" if p.ready else "…"
		if not p.ready:
			waiting += 1
		var l := UiTheme.label("%s  %s%s%s" % [status, p.name, who, "  (you)" if int(p.owner) == Net.my_peer and not p.local else ""], 17, Color(p.color))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lobby_list.add_child(l)
	var host := Net.am_room_host()
	_lobby_start.visible = host
	_lobby_start.text = "Start the game" if waiting == 0 else "Start (%d still creating)" % waiting
	_lobby_start.tooltip_text = "" if waiting == 0 else "Anything they haven't picked or rolled is picked for them."
	_lobby_target.disabled = not host
	_lobby_local.visible = host
	if not host:
		_lobby_list.add_child(UiTheme.label("The host starts the game.", 15, UiTheme.MUTED))


# ------------------------------------------------------------------ game

func show_game() -> void:
	if _city_view == null:
		_city_view = preload("res://scripts/ui/city_view.gd").new()
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
