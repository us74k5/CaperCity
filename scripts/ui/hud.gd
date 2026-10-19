extends Control
## In-game HUD. Renders Net.state for everyone; only the active player's device can act.
## Spectators see the same menus and prompts, greyed out.

signal back_to_menu

var city_view: Node

var _me_label: RichTextLabel
var _banner: PanelContainer
var _banner_label: Label
var _standings: RichTextLabel
var _standings_panel: PanelContainer
var _menu_panel: PanelContainer
var _menu_box: VBoxContainer
var _modal: PanelContainer
var _modal_box: VBoxContainer
var _log: RichTextLabel
var _actions: HBoxContainer
var _end_btn: Button
var _war_btn: Button
var _crew_btn: Button
var _skip_btn: Button
var _dpad: GridContainer
var _overlay: PanelContainer
var _overlay_box: VBoxContainer
var _overlay_kind := ""
var _path: Array = []        # queued directions from tap-to-walk
var _path_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Net.state_updated.connect(refresh)
	if city_view:
		city_view.cell_tapped.connect(_on_cell_tapped)
	_build()
	refresh()


func _build() -> void:
	# Top-left: you
	var me := PanelContainer.new()
	me.position = Vector2(12, 12)
	me.custom_minimum_size = Vector2(330, 0)
	_me_label = _rich()
	_me_label.custom_minimum_size = Vector2(310, 74)
	me.add_child(_me_label)
	add_child(me)

	# Top-center: turn banner
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position.y = 12
	_banner_label = UiTheme.label("", 18, UiTheme.CORAL_DARK)
	_banner.add_child(_banner_label)
	add_child(_banner)

	# Top-right: standings
	var st := PanelContainer.new()
	_standings_panel = st
	st.custom_minimum_size = Vector2(300, 0)
	_standings = _rich()
	_standings.custom_minimum_size = Vector2(280, 120)
	st.add_child(_standings)
	add_child(st)

	# Right: building menu
	_menu_panel = PanelContainer.new()
	_menu_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_menu_panel.offset_left = -470
	_menu_panel.offset_right = -12
	_menu_panel.offset_top = 210
	_menu_panel.offset_bottom = -84
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 8)
	_menu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_menu_box)
	_menu_panel.add_child(scroll)
	add_child(_menu_panel)

	# Bottom-left: log
	var lp := PanelContainer.new()
	lp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lp.position = Vector2(12, -232)
	lp.custom_minimum_size = Vector2(520, 160)
	_log = _rich()
	_log.fit_content = false
	_log.scroll_active = true
	_log.custom_minimum_size = Vector2(500, 150)
	_log.scroll_following = true
	lp.add_child(_log)
	add_child(lp)

	# Bottom: action buttons
	_actions = HBoxContainer.new()
	_actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_actions.add_theme_constant_override("separation", 8)
	_crew_btn = UiTheme.button("Crew")
	_war_btn = UiTheme.button("Gang war")
	_skip_btn = UiTheme.button("Skip turn")
	_end_btn = UiTheme.button("End turn", true)
	for b in [_skip_btn, _crew_btn, _war_btn, _end_btn]:
		b.custom_minimum_size.x = 110
		_actions.add_child(b)
	_crew_btn.pressed.connect(func(): _show_overlay("crew"))
	_war_btn.pressed.connect(func(): _show_overlay("war"))
	_end_btn.pressed.connect(func(): Net.send_intent({"t": "end_turn"}))
	_skip_btn.pressed.connect(func(): Net.send_intent({"t": "skip"}))
	add_child(_actions)

	# Bottom-center: d-pad
	_dpad = GridContainer.new()
	_dpad.columns = 3
	_dpad.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	for cell in ["", "N", "", "W", "S", "E"]:
		if cell == "":
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(56, 52)
			_dpad.add_child(sp)
		else:
			var b2 := UiTheme.button("", false, 52)
			b2.custom_minimum_size.x = 56
			b2.icon = _arrow_icon(cell)
			b2.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b2.tooltip_text = {"N": "Up", "S": "Down", "E": "Right", "W": "Left"}[cell]
			var d: String = cell
			b2.pressed.connect(func(): _move(d))
			_dpad.add_child(b2)
	add_child(_dpad)

	# Center: pending prompt (everyone sees it)
	_modal = PanelContainer.new()
	_modal.add_theme_stylebox_override("panel", UiTheme.box(Color("#15171C"), UiTheme.TEAL, 14, 20, 2))
	_modal.set_anchors_preset(Control.PRESET_CENTER)
	_modal.custom_minimum_size = Vector2(520, 0)
	_modal_box = VBoxContainer.new()
	_modal_box.add_theme_constant_override("separation", 10)
	_modal.add_child(_modal_box)
	add_child(_modal)

	# Overlays: crew, gang war, game over
	_overlay = PanelContainer.new()
	_overlay.add_theme_stylebox_override("panel", UiTheme.box(Color("#15171C"), UiTheme.BORDER_2, 14, 20, 1))
	_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.custom_minimum_size = Vector2(640, 0)
	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 8)
	_overlay.add_child(_overlay_box)
	_overlay.visible = false
	add_child(_overlay)
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var vs := get_viewport_rect().size
	_actions.reset_size()
	_actions.position = Vector2(vs.x - _actions.size.x - 12, vs.y - _actions.size.y - 12)
	_dpad.reset_size()
	_dpad.position = Vector2(vs.x - _dpad.size.x - 12, vs.y - _actions.size.y - _dpad.size.y - 24)
	_standings_panel.reset_size()
	_standings_panel.position = Vector2(vs.x - _standings_panel.size.x - 12, 12)
	_banner.reset_size()
	_banner.position = Vector2((vs.x - _banner.size.x) / 2.0, 12)
	for c in [_modal, _overlay]:
		c.reset_size()
		c.position = (vs - c.size) / 2.0
	var lp: Control = _log.get_parent()
	lp.position = Vector2(12, vs.y - lp.size.y - 12)


func _arrow_icon(dir: String) -> Texture2D:
	var rot: int = {"N": 0, "E": 90, "S": 180, "W": 270}[dir]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 26 26"><g transform="rotate(%d 13 13)"><path d="M13 4 L23 18 L3 18 Z" fill="#F2EEE6"/></g></svg>' % rot
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("bold_font_size", 18)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ------------------------------------------------------------------ refresh

func refresh() -> void:
	var s := Net.state
	if s.is_empty() or not is_instance_valid(_me_label):
		return
	var active := Net.active_player()
	var mine := Net.is_my_turn()
	var me := Net.my_player()

	# you
	if not me.is_empty():
		var rank: String = Balance.RANKS[mini(8, int(me.points) * 9 / maxi(1, int(s.target)))]
		var car: String = Balance.CARS[int(me.car)].name
		var extra := ""
		if int(me.jail) > 0:
			extra = "  [color=#FF9C90]in jail[/color]"
		_me_label.text = "[b][color=%s]%s[/color][/b] · %s%s\n%s · [b]%d[/b] / %d pts   [color=#F2C230][b]$%s[/b][/color]\n[color=#B5B9C2]%s · crew %d · %s[/color]" % [
			me.color, me.name, me.crew_name, extra, rank, me.points, s.target, _money(int(me.cash)), car, me.crew.size(),
			"room rented" if me.room else "no room"]
	else:
		_me_label.text = "[color=#B5B9C2]Spectating[/color]"

	# banner
	if s.phase == "over":
		_banner_label.text = "GAME OVER"
		_banner.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.YELLOW, Color(0, 0, 0, 0), 999, 18))
	elif mine:
		_banner_label.text = "YOUR TURN · %s · Month %d · %d steps left" % [active.name, s.month, active.steps]
		_banner.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.CORAL, Color(0, 0, 0, 0), 999, 18))
	elif not active.is_empty():
		_banner_label.text = "WATCHING %s · Month %d · %d steps left" % [active.name.to_upper(), s.month, active.steps]
		_banner.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.TEAL, Color(0, 0, 0, 0), 999, 18))
	_banner_label.add_theme_color_override("font_color", UiTheme.CORAL_DARK)

	# standings
	var lines: Array = ["[b]Standings[/b]  [color=#B5B9C2]first to %d[/color]" % s.target]
	var ids: Array = s.order.duplicate() if s.order.size() > 0 else s.players.keys()
	ids.sort_custom(func(a, b): return int(s.players[a].points) > int(s.players[b].points))
	for pid in ids:
		var p: Dictionary = s.players[pid]
		var tag := ""
		if int(p.jail) > 0:
			tag = " [color=#FF9C90]jail %d[/color]" % p.jail
		elif int(p.holiday) > 0:
			tag = " [color=#7FE6D6]holiday[/color]"
		if not p.connected:
			tag += " [color=#8E939D](offline)[/color]"
		var arrow := "» " if not active.is_empty() and int(active.id) == int(p.id) else "   "
		lines.append("%s[color=%s]•[/color] %s  [b]%d[/b]  [color=#F2C230]$%s[/color]%s" % [arrow, p.color, p.name, p.points, _money(int(p.cash)), tag])
	_standings.text = "\n".join(lines)

	# log
	var log_lines: Array = []
	var colors := {"good": "#7FE6D6", "bad": "#FF9C90", "big": "#F2C230", "turn": "#FF5D4F", "crime": "#F2C230"}
	var shown: Array = s.log.filter(func(e): return e.kind != "move")
	for e in shown.slice(maxi(0, shown.size() - 12)):
		var c: String = colors.get(e.kind, "#D9D5CC")
		log_lines.append("[color=%s]%s[/color]" % [c, e.text])
	_log.text = "\n".join(log_lines)

	# building menu
	for c in _menu_box.get_children():
		c.queue_free()
	var inside: bool = not active.is_empty() and int(active.inside) >= 0 and s.phase == "playing"
	_menu_panel.visible = inside
	if inside:
		var b: Dictionary = s.city.buildings[int(active.inside)]
		_menu_box.add_child(UiTheme.label(Balance.BUILDINGS[b.type].label.to_upper(), 14, UiTheme.TEAL))
		var title := UiTheme.label(b.name, 26)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_menu_box.add_child(title)
		if not mine:
			_menu_box.add_child(UiTheme.label("%s is choosing…" % active.name, 15, UiTheme.MUTED))
		for e in active.menu:
			var text: String = e.label
			var info: String = e.info if e.enabled else e.reason
			if info != "":
				text += "\n" + info
			var btn := UiTheme.button(text, false, 56)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.add_theme_font_size_override("font_size", 16)
			btn.disabled = not (mine and e.enabled)
			if e.id == "leave":
				btn.theme_type_variation = ""
			var id: String = e.id
			btn.pressed.connect(func(): Net.send_intent({"t": "menu", "id": id}))
			_menu_box.add_child(btn)

	# pending prompt
	for c in _modal_box.get_children():
		c.queue_free()
	var pend: Dictionary = s.pending
	_modal.visible = not pend.is_empty() and s.phase == "playing"
	if _modal.visible:
		var col := UiTheme.TEAL
		if pend.kind == "police":
			col = UiTheme.CORAL
		elif pend.kind == "result" and not pend.get("good", true):
			col = UiTheme.RED_SOFT
		_modal.add_theme_stylebox_override("panel", UiTheme.box(Color("#15171C"), col, 14, 20, 2))
		_modal_box.add_child(UiTheme.label(str(pend.title).to_upper(), 22, col))
		var body := UiTheme.label(pend.text, 18)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(480, 0)
		_modal_box.add_child(body)
		var owner_p: Dictionary = s.players.get(int(pend.player), {})
		var can: bool = not owner_p.is_empty() and int(owner_p.owner) == Net.my_peer
		if not can:
			_modal_box.add_child(UiTheme.label("Waiting for %s…" % owner_p.get("name", "?"), 15, UiTheme.MUTED))
		for o in pend.options:
			var ob := UiTheme.button(o.label, o.id == "ok" or pend.kind == "police" and o.id == "bribe", 52)
			ob.disabled = not (can and o.get("enabled", true))
			var oid: String = o.id
			ob.pressed.connect(func(): Net.send_intent({"t": "pending", "id": oid}))
			_modal_box.add_child(ob)

	# action buttons
	var free_to_act: bool = mine and pend.is_empty()
	_end_btn.disabled = not free_to_act
	_war_btn.disabled = not free_to_act or active.get("gang_war_used", false) or s.players.size() < 2
	_skip_btn.visible = Net.am_room_host() and s.phase == "playing" and not active.is_empty() and not active.connected
	for b2 in _dpad.get_children():
		if b2 is Button:
			b2.disabled = not free_to_act or int(active.get("inside", -1)) >= 0
	_dpad.visible = s.phase == "playing" and int(active.get("inside", -1)) < 0

	if s.phase == "over":
		_show_overlay("over")
	elif _overlay.visible:
		_show_overlay(_overlay_kind)
	call_deferred("_layout")


func _money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


# ------------------------------------------------------------------ overlays

func _show_overlay(kind: String) -> void:
	_overlay_kind = kind
	for c in _overlay_box.get_children():
		c.queue_free()
	var s := Net.state
	_overlay.visible = true
	match kind:
		"crew":
			var me := Net.my_player()
			if me.is_empty():
				_overlay.visible = false
				return
			_overlay_box.add_child(UiTheme.label("YOUR CREW · %d OF %d" % [me.crew.size(), Balance.MAX_CREW], 14, UiTheme.TEAL))
			_overlay_box.add_child(UiTheme.label(me.crew_name, 30))
			for m in me.crew:
				var l := UiTheme.label("%s   Stamina %d · Muscle %d · Smarts %d · Nerve %d · %s" % [m.name, m.stamina, m.muscle, m.smarts, m.nerve, Balance.GEAR[int(m.gear)].name], 17)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_overlay_box.add_child(l)
			var extras: Array = []
			if int(me.radios) > 0:
				extras.append("%d hot radios" % me.radios)
			if int(me.electronics) > 0:
				extras.append("%d boxes of electronics" % me.electronics)
			if me.dirt != "":
				extras.append("dirt on a %s boss" % Balance.BUILDINGS[me.dirt].label.to_lower())
			if not me.hostage.is_empty():
				extras.append("holding a hostage" + (" (ransom pickup pending)" if not me.ransom.is_empty() else ""))
			if int(me.loan) > 0:
				extras.append("owes Eddie $%d (%d months)" % [me.loan, me.loan_months])
			if me.passport:
				extras.append("fake passport")
			if int(me.immunity) > 0:
				extras.append("police chief bribed (%d months)" % me.immunity)
			if extras.size() > 0:
				var el := UiTheme.label("Holding: " + ", ".join(extras), 16, UiTheme.YELLOW)
				el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_overlay_box.add_child(el)
		"war":
			_overlay_box.add_child(UiTheme.label("GANG WAR · 3 STEPS", 14, UiTheme.CORAL))
			_overlay_box.add_child(UiTheme.label("Hit a rival crew. Winner takes a quarter of the loser's cash.", 17))
			var active := Net.active_player()
			for pid in s.order:
				var p: Dictionary = s.players[pid]
				if int(p.id) == int(active.id):
					continue
				var b := UiTheme.button("Attack %s (%s, crew of %d)" % [p.name, p.crew_name, p.crew.size()], false, 52)
				b.disabled = int(p.jail) > 0 or int(p.holiday) > 0 or not Net.is_my_turn()
				var target: int = p.id
				b.pressed.connect(func():
					_overlay.visible = false
					Net.send_intent({"t": "gang_war", "target": target}))
				_overlay_box.add_child(b)
		"over":
			var w: Dictionary = s.players.get(int(s.winner), {})
			_overlay_box.add_child(UiTheme.label("BOSS OF CAPER CITY", 16, UiTheme.YELLOW))
			_overlay_box.add_child(UiTheme.label("%s wins!" % w.get("name", "?"), 40, UiTheme.CORAL))
			_overlay_box.add_child(UiTheme.label("%s took over the town in %d months." % [w.get("crew_name", ""), s.month], 18))
			var b2 := UiTheme.button("Back to menu", true, 52)
			b2.pressed.connect(func(): back_to_menu.emit())
			_overlay_box.add_child(b2)
			return
	var close := UiTheme.button("Close", false, 48)
	close.pressed.connect(func(): _overlay.visible = false)
	_overlay_box.add_child(close)
	call_deferred("_layout")


# ------------------------------------------------------------------ input

func _move(dir: String) -> void:
	Net.send_intent({"t": "move", "dir": dir})


func _process(delta: float) -> void:
	if _path.is_empty():
		return
	_path_timer -= delta
	if _path_timer > 0.0:
		return
	var a := Net.active_player()
	if not Net.is_my_turn() or not Net.state.pending.is_empty() or a.is_empty() or int(a.inside) >= 0 or int(a.steps) <= 0:
		_path.clear()
		return
	_move(_path.pop_front())
	_path_timer = 0.16


## Shortest road route to `goal` (a road cell, or a building cell to walk into).
func _find_path(start: Vector2i, goal: Vector2i) -> Array:
	var city: Dictionary = Net.state.city
	var w: int = city.w
	var h: int = city.h
	var grid: PackedByteArray = city.grid
	if goal.x < 0 or goal.y < 0 or goal.x >= w or goal.y >= h:
		return []
	var goal_cell: int = grid[goal.y * w + goal.x]
	if goal_cell != CityGen.ROAD and goal_cell != CityGen.BUILDING:
		return []
	var dirs := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
	var came := {start: ""}
	var queue: Array = [start]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			break
		for dname in dirs:
			var nxt: Vector2i = cur + dirs[dname]
			if came.has(nxt) or nxt.x < 0 or nxt.y < 0 or nxt.x >= w or nxt.y >= h:
				continue
			var cell: int = grid[nxt.y * w + nxt.x]
			if cell == CityGen.ROAD or nxt == goal:
				came[nxt] = dname
				queue.append(nxt)
	if not came.has(goal):
		return []
	var out: Array = []
	var c: Vector2i = goal
	while c != start:
		var dn: String = came[c]
		out.push_front(dn)
		c -= dirs[dn]
	return out


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	var map := {KEY_UP: "N", KEY_DOWN: "S", KEY_LEFT: "W", KEY_RIGHT: "E", KEY_W: "N", KEY_S: "S", KEY_A: "W", KEY_D: "E"}
	if event is InputEventKey and map.has(event.keycode) and Net.is_my_turn() and Net.state.pending.is_empty():
		_path.clear()
		_move(map[event.keycode])
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode in [KEY_ENTER, KEY_SPACE] and not Net.state.pending.is_empty():
		var pend: Dictionary = Net.state.pending
		if pend.kind == "result":
			Net.send_intent({"t": "pending", "id": "ok"})


func _on_cell_tapped(cell: Vector2i) -> void:
	if not Net.is_my_turn() or not Net.state.pending.is_empty():
		return
	var a := Net.active_player()
	if int(a.inside) >= 0:
		return
	var start := Vector2i(int(a.pos[0]), int(a.pos[1]))
	var route := _find_path(start, cell)
	if route.is_empty():
		return
	if route.size() > int(a.steps):
		Net.error_message.emit("That's %d steps away. You have %d left." % [route.size(), a.steps])
		return
	_path = route
	_path_timer = 0.0
