extends Control
## In-game HUD. Renders Net.state for everyone; only the active player's device can act.
## Spectators see the same menus and prompts, greyed out.

signal back_to_menu

var city_view: Node3D

const C_SIREN_RED := Color("#E5383B")
const C_SIREN_BLUE := Color("#2F6BFF")
const C_POLICE_BG := Color("#121A2E")

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
var _locker: PanelContainer     # the crew's stats, at the arms dealer (training and buying weapons)
var _locker_scroll: ScrollContainer
var _locker_text: RichTextLabel
var _creator_layer: Control    # character creation, for someone who joined a game under way
var _centre_btn: Button        # shown while the map is dragged away from the action
var _stall: PanelContainer      # "no word from X": lets anyone skip a turn that has hung
var _stall_label: Label
var _stall_check := 0.0
var _rev_seen := -1
var _rev_at := 0                # msec when the state last changed
var _leave_btn: Button
var _dpad: GridContainer
var _overlay: PanelContainer
var _overlay_box: VBoxContainer
var _overlay_kind := ""
var _path: Array = []        # queued directions from tap-to-walk
var _path_timer := 0.0
var _police_panel: PanelContainer
var _police_box: VBoxContainer
var _police_scroll: ScrollContainer   # phones only: the stop can be taller than the screen
var _me_panel: PanelContainer
var _siren: Array = []       # the two light bars on the police panel
var _fight_bar: PanelContainer
var _fight_title: Label
var _fight_status: RichTextLabel
var _fight_sides: Array = []  # two RichTextLabels: your side, their side
var _fight_wait: Button
var _fight_auto: Button
var _fight_quit: Button
var _fight_refresh := 0.0
var _mini_panel: Control
var _casino_bar: PanelContainer
var _casino_box: HBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Net.state_updated.connect(refresh)
	if city_view:
		city_view.cell_tapped.connect(_on_cell_tapped)
		city_view.fight_square_tapped.connect(_on_fight_square)
		city_view.table_tapped.connect(_on_table)
	_build()
	refresh()


func _build() -> void:
	# Top-left: you
	var me := PanelContainer.new()
	me.position = Vector2(12, 12)
	me.custom_minimum_size = Vector2(330, 0)
	_me_panel = me
	_me_label = _rich()
	_me_label.custom_minimum_size = Vector2(310, 74)
	me.add_child(_me_label)
	add_child(me)

	# Left, under it: the crew's stats while training or buying weapons.
	_locker = PanelContainer.new()
	_locker.add_theme_stylebox_override("panel", UiTheme.box(Color(0.055, 0.06, 0.075, 0.9), Color("#35D0BA").darkened(0.4), 14, 14, 1))
	_locker_scroll = ScrollContainer.new()
	_locker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_locker.add_child(_locker_scroll)
	_locker_text = _rich()
	_locker_text.custom_minimum_size = Vector2(300 if UiTheme.compact else 360, 0)
	_locker_text.add_theme_font_size_override("normal_font_size", 15)
	_locker_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locker_scroll.add_child(_locker_text)
	_locker.visible = false
	add_child(_locker)

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
	_menu_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.055, 0.06, 0.075, 0.86), Color(1, 1, 1, 0.07), 16, 16, 1))
	_menu_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_menu_panel.offset_left = -440
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
	if UiTheme.compact:
		# Phones: the menu runs the full height (over the standings) and the log keeps a few lines.
		_menu_panel.offset_top = 12
		_menu_panel.offset_bottom = -76
		lp.custom_minimum_size = Vector2(400, 92)
		_log.custom_minimum_size = Vector2(380, 82)
		_log.add_theme_font_size_override("normal_font_size", 14)

	# Bottom: action buttons
	_actions = HBoxContainer.new()
	_actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_actions.add_theme_constant_override("separation", 8)
	_crew_btn = UiTheme.button("Crew")
	_war_btn = UiTheme.button("Gang war")
	_skip_btn = UiTheme.button("Skip turn")
	_end_btn = UiTheme.button("End turn", true)
	_leave_btn = UiTheme.button("Leave")
	for b in [_leave_btn, _skip_btn, _crew_btn, _war_btn, _end_btn]:
		b.custom_minimum_size.x = 110
		_actions.add_child(b)
	_crew_btn.pressed.connect(func(): _show_overlay("crew"))
	_war_btn.pressed.connect(func(): _show_overlay("war"))
	_end_btn.pressed.connect(func(): Net.send_intent({"t": "end_turn"}))
	_skip_btn.pressed.connect(func(): Net.send_intent({"t": "skip"}))
	_leave_btn.pressed.connect(func(): _show_overlay("leave"))
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

	_build_police_panel()
	_build_fight_bar()
	_casino_bar = PanelContainer.new()
	_casino_bar.add_theme_stylebox_override("panel", UiTheme.box(Color(0.08, 0.04, 0.06, 0.92), Color("#E2B13C"), 18, 14, 2))
	_casino_box = HBoxContainer.new()
	_casino_box.add_theme_constant_override("separation", 12)
	_casino_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_casino_bar.add_child(_casino_box)
	_casino_bar.visible = false
	add_child(_casino_bar)
	_mini_panel = preload("res://scripts/ui/mini_panel.gd").new()
	_mini_panel.visible = false
	add_child(_mini_panel)

	_centre_btn = UiTheme.button("⌖ Centre", false, 44)
	_centre_btn.tooltip_text = "Back to the crew whose turn it is (Space)"
	_centre_btn.pressed.connect(func(): city_view.follow())
	_centre_btn.visible = false
	add_child(_centre_btn)

	_stall = PanelContainer.new()
	_stall.add_theme_stylebox_override("panel", UiTheme.box(Color("#15171C"), UiTheme.CORAL, 12, 12, 2))
	_stall.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_stall.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stall.position.y = 64
	var sv := HBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	_stall.add_child(sv)
	_stall_label = UiTheme.label("", 16)
	_stall_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sv.add_child(_stall_label)
	var sb := UiTheme.button("Skip their turn", true, 44)
	sb.pressed.connect(func(): Net.send_intent({"t": "skip_stalled"}))
	sv.add_child(sb)
	_stall.visible = false
	add_child(_stall)

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
	_centre_btn.reset_size()
	_centre_btn.position = Vector2(vs.x - _centre_btn.size.x - 12, _dpad.position.y - _centre_btn.size.y - 10)
	_stall.reset_size()
	_stall.position = Vector2((vs.x - _stall.size.x) / 2.0, _banner.position.y + _banner.size.y + 10)
	_standings_panel.reset_size()
	_standings_panel.position = Vector2(vs.x - _standings_panel.size.x - 12, 12)
	_banner.reset_size()
	_banner.position = Vector2((vs.x - _banner.size.x) / 2.0, 12)
	for c in [_modal, _overlay]:
		c.reset_size()
		c.position = (vs - c.size) / 2.0
	if not Net.state.get("fight", {}).is_empty() or not Net.state.get("mini", {}).is_empty():
		_modal.position.y = vs.y - _modal.size.y - 24   # keep the arena or minigame visible behind the result
	elif city_view != null and city_view.in_place() and city_view.place_view.casino != null:
		_modal.position = Vector2(vs.x - _modal.size.x - 16, 150)   # beside the table, not over it
	_mini_panel.reset_size()
	_mini_panel.position = Vector2((vs.x - _mini_panel.size.x) / 2.0, 12)   # in place of the turn banner
	if _police_scroll:
		_police_scroll.custom_minimum_size.y = minf(_police_box.get_combined_minimum_size().y + 36, vs.y - 46)
	_police_panel.reset_size()
	_police_panel.position = Vector2(vs.x - _police_panel.size.x - 12, maxf(12.0 if UiTheme.compact else 120.0, (vs.y - _police_panel.size.y) / 2.0))
	_fight_bar.custom_minimum_size.x = minf(vs.x - 24, 1100)
	_fight_bar.reset_size()
	_fight_bar.position = Vector2((vs.x - _fight_bar.size.x) / 2.0, vs.y - _fight_bar.size.y - 12)
	var lp: Control = _log.get_parent()
	lp.position = Vector2(12, vs.y - lp.size.y - 12)
	var lt := _me_panel.position.y + _me_panel.size.y + 10 if _me_panel.visible else 12.0
	_locker.position = Vector2(12, lt)
	_locker_scroll.custom_minimum_size = Vector2(0, minf(_locker_text.get_content_height() + 4, vs.y - lt - 40))
	_locker.reset_size()
	_casino_bar.reset_size()
	_casino_bar.position = Vector2((vs.x - _casino_bar.size.x) / 2.0, vs.y - _casino_bar.size.y - 16)
	if UiTheme.compact:
		_casino_bar.position.x = 12   # leave the turn buttons on the right uncovered
		if _menu_panel.visible:
			# centre the banner in the space between the you-panel and the building menu
			var left := _me_panel.position.x + _me_panel.size.x + 8
			_banner.position.x = maxf(left, (vs.x - 440 + left - _banner.size.x) / 2.0)


func _arrow_icon(dir: String) -> Texture2D:
	var rot: int = {"N": 0, "E": 90, "S": 180, "W": 270}[dir]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 26 26"><g transform="rotate(%d 13 13)"><path d="M13 4 L23 18 L3 18 Z" fill="#F2EEE6"/></g></svg>' % rot
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)


## Steps left, with the half step banked on the motorway: 12 steps and a half used shows "11½".
func _steps_text(p: Dictionary) -> String:
	var n := int(p.get("steps", 0))
	return "%d½" % (n - 1) if p.get("half_step", false) and n > 0 else str(n)


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
	_update_creator(s)
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
		if UiTheme.compact:
			_me_label.text += "[color=#B5B9C2] · month %d[/color]" % s.month   # the short banner leaves it out
	else:
		_me_label.text = "[color=#B5B9C2]Spectating[/color]"

	# banner
	if s.phase == "over":
		_banner_label.text = "GAME OVER"
		_banner.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.YELLOW, Color(0, 0, 0, 0), 999, 18))
	elif mine and UiTheme.compact:
		_banner_label.text = "YOUR TURN · %s steps" % _steps_text(active)
		_banner.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.CORAL, Color(0, 0, 0, 0), 999, 18))
	elif not active.is_empty() and UiTheme.compact:
		_banner_label.text = "WATCHING %s · %s steps" % [active.name.to_upper(), _steps_text(active)]
		_banner.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.TEAL, Color(0, 0, 0, 0), 999, 18))
	elif mine:
		_banner_label.text = "YOUR TURN · %s · Month %d · %s steps left" % [active.name, s.month, _steps_text(active)]
		_banner.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.CORAL, Color(0, 0, 0, 0), 999, 18))
	elif not active.is_empty():
		_banner_label.text = "WATCHING %s · Month %d · %s steps left" % [active.name.to_upper(), s.month, _steps_text(active)]
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
	_standings_panel.visible = not (UiTheme.compact and inside)
	_update_locker(s, active, inside)
	if inside:
		var b: Dictionary = s.city.buildings[int(active.inside)]
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", 0)
		head.add_child(UiTheme.label(Balance.BUILDINGS[b.type].label.to_upper(), 13, UiTheme.TEAL))
		var title := UiTheme.label(b.name, 26)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(title)
		if not mine:
			head.add_child(UiTheme.label("%s is choosing…" % active.name, 14, UiTheme.MUTED))
		_menu_box.add_child(head)
		var rule := ColorRect.new()
		rule.color = Color(1, 1, 1, 0.08)
		rule.custom_minimum_size.y = 1
		_menu_box.add_child(rule)
		for e in active.menu:
			_menu_box.add_child(_menu_row(e, mine))

	_refresh_casino(s, active, inside, mine)

	# pending prompt
	for c in _modal_box.get_children():
		c.queue_free()
	var pend: Dictionary = s.pending
	var kind: String = pend.get("kind", "")
	_modal.visible = _modal_should_show()
	_refresh_police(pend, s)
	_refresh_fight()
	var chasing: bool = s.phase == "playing" and not s.get("mini", {}).is_empty()
	_mini_panel.refresh()
	_banner.visible = not chasing
	if UiTheme.compact:
		_me_panel.visible = not chasing   # the minigame's panel takes the top of a phone screen
		if chasing:
			_standings_panel.visible = false
	var fighting: bool = kind == "fight" or not s.get("fight", {}).is_empty() or chasing
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
	_dpad.visible = s.phase == "playing" and int(active.get("inside", -1)) < 0 and not fighting
	if chasing and kind == "mini":
		_dpad.visible = mine   # the d-pad steers the runner
		for b3 in _dpad.get_children():
			if b3 is Button:
				b3.disabled = not mine
	_actions.visible = not fighting
	# Inside a building the place's scene fills the screen, as in the original; results come as cards.
	_log.get_parent().visible = not fighting and not inside
	if fighting:
		_menu_panel.visible = false

	if s.phase == "over":
		_show_overlay("over")
	elif _overlay.visible:
		_show_overlay(_overlay_kind)
	call_deferred("_layout")


## One row of a building's menu: a colored accent by kind (crime, more options, an action), the
## label with its details (or why it's not possible) underneath, and the step cost on the right.
## A container (not a Button) so it grows with wrapped text; it handles its own clicks and hover.
func _menu_row(e: Dictionary, mine: bool) -> PanelContainer:
	var id: String = e.id
	var accent := UiTheme.YELLOW
	if id.begins_with("act:crime:"):
		accent = UiTheme.CORAL
	elif id.begins_with("sub:"):
		accent = UiTheme.TEAL
	elif id == "leave" or id == "back":
		accent = Color(1, 1, 1, 0.25)
	var live: bool = mine and e.enabled
	var card := PanelContainer.new()
	var calm := UiTheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 10, 10, 0)
	var lit := UiTheme.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 10, 10, 0)
	card.add_theme_stylebox_override("panel", calm)
	card.mouse_filter = Control.MOUSE_FILTER_STOP if live else Control.MOUSE_FILTER_IGNORE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if live else Control.CURSOR_ARROW
	card.custom_minimum_size.y = 50
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var bar := ColorRect.new()
	bar.color = accent if e.enabled else Color(accent, 0.25)
	bar.custom_minimum_size = Vector2(4, 0)
	row.add_child(bar)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	var name_l := UiTheme.label(str(e.label) + ("  ›" if id.begins_with("sub:") else ""), 17, UiTheme.TEXT if e.enabled else UiTheme.MUTED.darkened(0.2))
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size.x = 200
	text.add_child(name_l)
	var info: String = e.info if e.enabled else e.reason
	if info != "":
		var info_l := UiTheme.label(info, 13, UiTheme.MUTED if e.enabled else UiTheme.RED_SOFT.darkened(0.15))
		info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_l.custom_minimum_size.x = 200
		text.add_child(info_l)
	row.add_child(text)
	if int(e.get("steps", 0)) > 0:
		var cost := UiTheme.label("%d step%s" % [e.steps, "" if int(e.steps) == 1 else "s"], 12, UiTheme.MUTED)
		cost.add_theme_stylebox_override("normal", UiTheme.box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 8, 6, 0))
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cost)
	card.add_child(row)
	if live:
		card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", lit))
		card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", calm))
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				Net.send_intent({"t": "menu", "id": id}))
	return card


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
		"leave":
			_overlay_box.add_child(UiTheme.label("LEAVE THE GAME", 14, UiTheme.CORAL))
			_overlay_box.add_child(UiTheme.label("Back to the title screen?", 30))
			var why := "Your crew stays in town and its turns are skipped. Come back on this device to pick it up again."
			if Net.is_host() and not Net.dedicated:
				why = "You're hosting this game: leaving ends it for everyone."
			var wl := UiTheme.label(why, 17, UiTheme.MUTED)
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_overlay_box.add_child(wl)
			var go := UiTheme.button("Leave game", true, 52)
			go.pressed.connect(func(): back_to_menu.emit())
			_overlay_box.add_child(go)
			if Net.am_room_host():
				var end := UiTheme.button("End the game for everyone", false, 52)
				end.pressed.connect(func():
					_overlay.visible = false
					Net.send_intent({"t": "end_game"}))
				_overlay_box.add_child(end)
				var el := UiTheme.label("Everyone goes back to the lobby, where a new game can be started.", 15, UiTheme.MUTED)
				el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_overlay_box.add_child(el)
		"over":
			var w: Dictionary = s.players.get(int(s.winner), {})
			_overlay_box.add_child(UiTheme.label("BOSS OF CAPER CITY", 16, UiTheme.YELLOW))
			_overlay_box.add_child(UiTheme.label("%s wins!" % w.get("name", "?"), 40, UiTheme.CORAL))
			_overlay_box.add_child(UiTheme.label("%s took over the town in %d months." % [w.get("crew_name", ""), s.month], 18))
			if Net.am_room_host():
				var again := UiTheme.button("New game", true, 52)
				again.pressed.connect(func(): Net.send_intent({"t": "end_game"}))
				_overlay_box.add_child(again)
			var b2 := UiTheme.button("Back to menu", not Net.am_room_host(), 52)
			b2.pressed.connect(func(): back_to_menu.emit())
			_overlay_box.add_child(b2)
			return
	var close := UiTheme.button("Close", false, 48)
	close.pressed.connect(func(): _overlay.visible = false)
	_overlay_box.add_child(close)
	call_deferred("_layout")


# ------------------------------------------------------------------ input

func _move(dir: String) -> void:
	if Net.state.get("pending", {}).get("kind", "") == "mini":
		_mini_press(dir)
	else:
		if city_view:
			city_view.follow()
		Net.send_intent({"t": "move", "dir": dir})


func _process(delta: float) -> void:
	var look_around: bool = city_view != null and city_view.free_look
	if _centre_btn.visible != look_around:
		_centre_btn.visible = look_around
		_layout()
	_stall_check -= delta
	if _stall_check <= 0.0:
		_stall_check = 0.5
		_update_stall()
	if _police_panel.visible:
		var red := int(Time.get_ticks_msec() / 160) % 2 == 0
		_siren[0].color = C_SIREN_RED if red else C_SIREN_RED.darkened(0.6)
		_siren[1].color = C_SIREN_BLUE.darkened(0.6) if red else C_SIREN_BLUE
	if _modal.visible != _modal_should_show():
		refresh()   # rebuilds the card too: it may have been held back when the state arrived
		_layout()
	if _mini_panel.visible:
		_layout_mini()
	if _fight_bar.visible:
		_fight_refresh -= delta
		if _fight_refresh <= 0.0:
			_fight_refresh = 0.15
			_refresh_fight()
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


## The crew's stats beside the arms dealer's menu: every member's Muscle, Smarts, Nerve and energy,
## and when picking who gets a weapon, whether each of them can handle it.
func _update_locker(s: Dictionary, active: Dictionary, inside: bool) -> void:
	var path: Array = active.get("menu_path", []) if inside else []
	var training := false
	var gear := -1
	for step in path:
		training = training or str(step).begins_with("train")
		if str(step).begins_with("gear_"):
			gear = int(str(step).substr(5))
		elif str(step) == "buy_gear" and gear < 0:
			gear = -2
	var show: bool = inside and s.city.buildings[int(active.inside)].type == "arms" and (training or gear != -1)
	if _locker.visible != show:
		_locker.visible = show
		call_deferred("_layout")
	if not show:
		return
	var lines: Array = ["[color=#35D0BA][b]%s[/b][/color]" % ("LOCKER ROOM · YOUR CREW" if training else "YOUR CREW")]
	var need: Dictionary = Balance.GEAR[gear] if gear >= 0 else {}
	if not need.is_empty():
		lines.append("[color=#B5B9C2]%s needs Smarts %d and Nerve %d[/color]" % [need.name, need.smarts, need.nerve])
	for i in active.crew.size():
		var m: Dictionary = active.crew[i]
		lines.append("")
		lines.append("[b]%s[/b]  [color=#B5B9C2]%s · %s · energy %d[/color]" % [m.name, "boss" if i == 0 else "crew",
			Balance.GEAR[int(m.gear)].name, int(m.stamina)])
		for stat in ["muscle", "smarts", "nerve"]:
			var v := int(m[stat])
			var mark := ""
			if not need.is_empty() and stat in ["smarts", "nerve"]:
				mark = "  [color=#35D0BA]✓[/color]" if v >= int(need[stat]) else "  [color=#FF9C90]✗ %d[/color]" % int(need[stat])
			lines.append("%s  %s  [b]%d[/b]%s" % [stat.capitalize().rpad(7), _stat_bar(v), v, mark])
	_locker_text.text = "\n".join(lines)
	call_deferred("_layout")


func _stat_bar(v: int) -> String:
	var n := clampi(roundi(v / 10.0), 0, 10)
	return "[color=#F2C230]%s[/color][color=#3A3F49]%s[/color]" % ["■".repeat(n), "■".repeat(10 - n)]


## Joined mid-game: make your boss first, over the town (the game carries on meanwhile).
func _update_creator(s: Dictionary) -> void:
	var creating := false
	for pid in s.players:
		var p: Dictionary = s.players[pid]
		if int(p.owner) == Net.my_peer and not p.local and not p.ready:
			creating = true
	if creating and _creator_layer == null:
		_creator_layer = ColorRect.new()
		(_creator_layer as ColorRect).color = Color(0.05, 0.06, 0.08, 0.82)
		_creator_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		_creator_layer.mouse_filter = Control.MOUSE_FILTER_STOP
		var c := CenterContainer.new()
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		_creator_layer.add_child(c)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		c.add_child(v)
		var title := UiTheme.label("A game is on. Make your boss and jump in.", 20, UiTheme.YELLOW)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(title)
		v.add_child(preload("res://scripts/ui/creator.gd").new())
		add_child(_creator_layer)
	elif not creating and _creator_layer != null:
		_creator_layer.queue_free()
		_creator_layer = null


## Offers to skip a turn that has gone quiet (the server checks the time too).
func _update_stall() -> void:
	var s := Net.state
	if s.is_empty():
		return
	if int(s.rev) != _rev_seen:
		_rev_seen = int(s.rev)
		_rev_at = Time.get_ticks_msec()
	var a := Net.active_player()
	var quiet := (Time.get_ticks_msec() - _rev_at) / 1000
	var show: bool = s.phase == "playing" and not a.is_empty() and not Net.is_my_turn() and not Net.my_player().is_empty() \
		and a.connected and quiet >= Net.STALL_SECONDS + 2
	if show:
		_stall_label.text = "No word from %s for %d seconds." % [a.name, quiet]
	if _stall.visible != show:
		_stall.visible = show
		_layout()


## Cheapest route to `goal` (a road cell, or a building cell to walk into), by the same rules as
## the server (CityGen.step_cost): one-way motorway lanes, cars only there, half a step a cell.
func _find_path(start: Vector2i, goal: Vector2i) -> Array:
	var city: Dictionary = Net.state.city
	var w: int = city.w
	var h: int = city.h
	if goal.x < 0 or goal.y < 0 or goal.x >= w or goal.y >= h:
		return []
	var goal_cell: int = city.grid[goal.y * w + goal.x]
	if goal_cell != CityGen.ROAD and goal_cell != CityGen.BUILDING:
		return []
	var has_car: bool = int(Net.active_player().get("car", 0)) > 0
	var goal_b := CityGen.building_at(city, goal.x, goal.y)   # tapping any part of a building means "go in"
	var best := {start: 0}
	var came := {start: ""}
	var open: Array = [start]
	while open.size() > 0:
		# Few hundred cells: a linear scan for the cheapest open cell is plenty.
		var k := 0
		for i in open.size():
			if best[open[i]] < best[open[k]]:
				k = i
		var cur: Vector2i = open[k]
		open.remove_at(k)
		if cur == goal or (not goal_b.is_empty() and cur != start and CityGen.building_at(city, cur.x, cur.y) == goal_b):
			goal = cur
			break
		for dname in CityGen.DIR_VEC:
			var cost := CityGen.step_cost(city, cur, dname, has_car)
			if cost <= 0:
				continue
			var nxt: Vector2i = cur + CityGen.DIR_VEC[dname]
			if city.grid[nxt.y * w + nxt.x] == CityGen.BUILDING and CityGen.building_at(city, nxt.x, nxt.y) != goal_b:
				continue   # only the building you tapped gets walked into
			var total: int = best[cur] + cost
			if not best.has(nxt) or total < best[nxt]:
				best[nxt] = total
				came[nxt] = dname
				if not nxt in open:
					open.append(nxt)
	if not came.has(goal):
		return []
	var out: Array = []
	var c: Vector2i = goal
	while c != start:
		var dn: String = came[c]
		out.push_front(dn)
		c -= CityGen.DIR_VEC[dn]
	return out


## Whole steps a route uses, counting half steps on the motorway the way the server banks them.
func _route_steps(start: Vector2i, route: Array) -> int:
	var city: Dictionary = Net.state.city
	var a := Net.active_player()
	var has_car: bool = int(a.get("car", 0)) > 0
	var half: bool = a.get("half_step", false)
	var used := 0
	var cur := start
	for d in route:
		var cost := CityGen.step_cost(city, cur, d, has_car)
		if cost >= 2:
			used += 1
		elif half:
			used += 1
			half = false
		else:
			half = true
		cur += CityGen.DIR_VEC[d]
	return used


## Chases run on this screen first (see MiniView.steer); everything else goes to the server.
func _mini_press(dir: String) -> void:
	if city_view and city_view.mini_view.steer(dir):
		return
	_mini_panel.press(dir)


## Direction keys in a minigame are caught before the buttons can use them to move focus around.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and Net.is_my_turn() and Net.state.get("pending", {}).get("kind", "") == "mini" \
			and Net.state.get("mini", {}).get("game", "") != "safe" and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		_unhandled_key_input(event)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	if event is InputEventKey and event.keycode == KEY_M:
		Music.toggle()
		return
	var map := {KEY_UP: "N", KEY_DOWN: "S", KEY_LEFT: "W", KEY_RIGHT: "E", KEY_W: "N", KEY_S: "S", KEY_A: "W", KEY_D: "E"}
	var chasing: bool = Net.state.get("pending", {}).get("kind", "") == "mini"
	var game: String = Net.state.get("mini", {}).get("game", "")
	if event is InputEventKey and chasing and Net.is_my_turn() and game == "safe" and event.keycode in [KEY_1, KEY_2, KEY_3]:
		Net.send_intent({"t": "mini", "pick": event.keycode - KEY_1})
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and map.has(event.keycode) and Net.is_my_turn() and chasing:
		# Chases keep you running, so one press is enough; in the step-by-step games holding a key repeats.
		if not event.echo or not game in ["escape", "catch"]:
			_mini_press(map[event.keycode])
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and map.has(event.keycode) and Net.is_my_turn() and Net.state.pending.is_empty():
		_path.clear()
		_move(map[event.keycode])
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_ESCAPE:
		if _overlay.visible and _overlay_kind != "over":
			_overlay.visible = false
		elif not _overlay.visible:
			_show_overlay("leave")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode in [KEY_ENTER, KEY_SPACE] and not Net.state.pending.is_empty():
		var pend: Dictionary = Net.state.pending
		if pend.kind == "result":
			Net.send_intent({"t": "pending", "id": "ok"})
		elif pend.kind == "fight" and event.keycode == KEY_SPACE and _can_fight():
			Net.send_intent({"t": "fight"})
	elif event is InputEventKey and event.keycode == KEY_SPACE and city_view != null and city_view.free_look:
		city_view.follow()


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
	var need := _route_steps(start, route)
	if need > int(a.steps):
		Net.error_message.emit("That's %d steps away. You have %d left." % [need, a.steps])
		return
	_path = route
	_path_timer = 0.0
	city_view.follow()


# ------------------------------------------------------------------ police stop

func _build_police_panel() -> void:
	_police_panel = PanelContainer.new()
	_police_panel.add_theme_stylebox_override("panel", UiTheme.box(C_POLICE_BG, C_SIREN_BLUE.darkened(0.3), 14, 0, 2))
	_police_panel.custom_minimum_size = Vector2(440, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_police_panel.add_child(outer)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	for col in [C_SIREN_RED, C_SIREN_BLUE]:
		var r := ColorRect.new()
		r.color = col
		r.custom_minimum_size = Vector2(0, 10)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(r)
		_siren.append(r)
	outer.add_child(bar)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 18)
	if UiTheme.compact:
		_police_scroll = ScrollContainer.new()
		_police_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_police_scroll.add_child(pad)
		outer.add_child(_police_scroll)
	else:
		outer.add_child(pad)
	_police_box = VBoxContainer.new()
	_police_box.add_theme_constant_override("separation", 10)
	pad.add_child(_police_box)
	_police_panel.visible = false
	add_child(_police_panel)


func _refresh_police(pend: Dictionary, s: Dictionary) -> void:
	for c in _police_box.get_children():
		c.queue_free()
	_police_panel.visible = pend.get("kind", "") == "police" and s.phase == "playing"
	if not _police_panel.visible:
		return
	var p: Dictionary = s.players.get(int(pend.player), {})
	_police_box.add_child(UiTheme.label("CITY POLICE", 14, Color("#8FB0FF")))
	_police_box.add_child(UiTheme.label(str(pend.title).to_upper(), 30, UiTheme.TEXT))
	var body := UiTheme.label(pend.text, 18)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(400, 0)
	_police_box.add_child(body)
	var facts := _rich()
	var boss: Dictionary = p.crew[0] if not p.is_empty() and p.crew.size() > 0 else {}
	facts.text = "[color=#FF9C90][b]%d officer%s[/b][/color] · armed with %s\n[color=#7FE6D6][b]Your crew: %d[/b][/color] · %s has %d energy · $%s cash" % [
		int(pend.get("cops", 1)), "" if int(pend.get("cops", 1)) == 1 else "s", str(pend.get("armed", "batons")).to_lower(),
		p.get("crew", []).size(), boss.get("name", "?"), int(boss.get("stamina", 0)), _money(int(p.get("cash", 0)))]
	_police_box.add_child(facts)
	var can: bool = not p.is_empty() and int(p.owner) == Net.my_peer
	if not can:
		_police_box.add_child(UiTheme.label("%s is deciding…" % p.get("name", "?"), 15, UiTheme.MUTED))
	for o in pend.options:
		var ob := UiTheme.button("%s\n%s" % [o.label, o.get("info", "")], o.id == "bribe", 64)
		ob.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ob.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ob.add_theme_font_size_override("font_size", 16)
		ob.disabled = not (can and o.get("enabled", true))
		var oid: String = o.id
		ob.pressed.connect(func(): Net.send_intent({"t": "pending", "id": oid}))
		_police_box.add_child(ob)


# ------------------------------------------------------------------ fight

func _build_fight_bar() -> void:
	_fight_bar = PanelContainer.new()
	_fight_bar.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.CORAL, 14, 16, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_fight_bar.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_fight_title = UiTheme.label("", 22, UiTheme.CORAL)
	top.add_child(_fight_title)
	_fight_status = _rich()
	_fight_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_fight_status)
	v.add_child(top)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	for i in 2:
		var r := _rich()
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_theme_font_size_override("normal_font_size", 15)
		cols.add_child(r)
		_fight_sides.append(r)
	v.add_child(cols)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var hint := UiTheme.label("Tap a teal square to step, or a red ring to attack. Shots fly straight and hit the first man in the way.", 14, UiTheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.custom_minimum_size.x = 260
	row.add_child(hint)
	_fight_wait = UiTheme.button("Wait", false, 48)
	_fight_auto = UiTheme.button("Auto-fight", false, 48)
	_fight_quit = UiTheme.button("Give up", false, 48)
	for b in [_fight_wait, _fight_auto, _fight_quit]:
		b.custom_minimum_size.x = 120
		row.add_child(b)
	_fight_wait.pressed.connect(func(): if _can_fight(): Net.send_intent({"t": "fight"}))
	_fight_auto.pressed.connect(func(): Net.send_intent({"t": "pending", "id": "auto"}))
	_fight_quit.pressed.connect(func(): Net.send_intent({"t": "pending", "id": "surrender"}))
	v.add_child(row)
	_fight_bar.visible = false
	add_child(_fight_bar)


func _layout_mini() -> void:
	var vs := get_viewport_rect().size
	_mini_panel.reset_size()
	_mini_panel.position = Vector2((vs.x - _mini_panel.size.x) / 2.0, 12)


# ------------------------------------------------------------------ casino

## In the casino the tables are the menu: click one to sit down. This bar holds the rest: the stakes
## as chips while you're seated, standing up, leaving, and anything else the casino offers.
func _refresh_casino(s: Dictionary, active: Dictionary, inside: bool, mine: bool) -> void:
	for c in _casino_box.get_children():
		_casino_box.remove_child(c)   # now, so the bar shrinks to fit this frame
		c.queue_free()
	var here: bool = inside and s.city.buildings[int(active.inside)].type == "casino"
	_casino_bar.visible = here and s.pending.get("kind", "") != "mini"
	if not here:
		return
	_menu_panel.visible = false
	var table: String = city_view.casino_table(active) if city_view else ""
	var free: bool = mine and s.pending.is_empty()
	var head := VBoxContainer.new()
	var title := UiTheme.label(table.to_upper() if table != "" else str(s.city.buildings[int(active.inside)].name).to_upper(), 20, Color("#E2B13C"))
	head.add_child(title)
	var sub := "Pick a table" if table == "" else "Place your bet"
	if not mine:
		sub = "%s is at the tables" % active.name
	head.add_child(UiTheme.label(sub, 14, UiTheme.MUTED))
	_casino_box.add_child(head)
	var chip_colors := [Color("#C8423B"), Color("#2F5FA8"), Color("#2B2F36")]
	var chip_i := 0
	for e in active.menu:
		var id: String = e.id
		if id == "leave" or id == "back" or id.begins_with("sub:game_"):
			continue
		var b: Button
		if id.begins_with("act:gamble:"):
			b = _chip_button(e.label.replace("Bet ", ""), chip_colors[chip_i % chip_colors.size()])
			chip_i += 1
		else:
			b = UiTheme.button(e.label, false, 52)
		b.tooltip_text = e.info if e.enabled else e.reason
		b.disabled = not (free and e.enabled)
		b.pressed.connect(func(): Net.send_intent({"t": "menu", "id": id}))
		_casino_box.add_child(b)
	if table != "":
		var up := UiTheme.button("Stand up", false, 52)
		up.disabled = not free
		up.pressed.connect(func(): Net.send_intent({"t": "menu", "id": "back"}))
		_casino_box.add_child(up)
	var out := UiTheme.button("Leave", false, 52)
	out.disabled = not free
	out.pressed.connect(func(): Net.send_intent({"t": "menu", "id": "leave"}))
	_casino_box.add_child(out)


## A round casino chip with the stake on it.
func _chip_button(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(84, 84)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var base := col
		if st == "hover":
			base = col.lightened(0.15)
		elif st == "pressed":
			base = col.darkened(0.2)
		elif st == "disabled":
			base = col.darkened(0.55)
		var box := UiTheme.box(base, Color("#F2EEE6") if st != "disabled" else Color(1, 1, 1, 0.2), 42, 6, 5)
		b.add_theme_stylebox_override(st, box)
	return b


func _on_table(game: String) -> void:
	if not Net.is_my_turn() or not Net.state.pending.is_empty():
		return
	var a := Net.active_player()
	var cur: String = city_view.casino_table(a)
	if cur == game:
		return
	if cur != "":
		Net.send_intent({"t": "menu", "id": "back"})
	Net.send_intent({"t": "menu", "id": "sub:game_" + game})


## The generic prompt card. Police stops and fights have their own panels, and a fight's result
## waits until the last moves have finished replaying.
func _modal_should_show() -> bool:
	var s := Net.state
	var pend: Dictionary = s.get("pending", {})
	var kind: String = pend.get("kind", "")
	if pend.is_empty() or s.get("phase", "") != "playing" or kind == "police" or kind == "fight" or kind == "mini":
		return false
	if city_view != null and city_view.casino_busy():
		return false   # the hand is still being played out on the table
	return s.get("fight", {}).is_empty() or city_view == null or not city_view.fight_view.busy()


func _can_fight() -> bool:
	var f: Dictionary = Net.state.get("fight", {})
	var busy: bool = city_view != null and city_view.fight_view.busy()
	return Net.is_my_turn() and Net.state.pending.get("kind", "") == "fight" and not f.is_empty() \
		and not f.over and int(f.side) == 0 and not busy


func _refresh_fight() -> void:
	var s := Net.state
	var f: Dictionary = s.get("fight", {})
	_fight_bar.visible = s.get("pending", {}).get("kind", "") == "fight" and not f.is_empty() and s.phase == "playing"
	if not _fight_bar.visible:
		return
	var a := Net.active_player()
	var busy: bool = city_view != null and city_view.fight_view.busy()
	_fight_title.text = "%s · ROUND %d" % [str(f.title).to_upper(), int(f.round)]
	var status := ""
	if busy:
		status = "[color=#B5B9C2]…[/color]"
	elif int(f.side) == 0 and int(f.cur) >= 0:
		var u: Dictionary = f.units[int(f.cur)]
		var g: Dictionary = Balance.GEAR[int(u.gear)]
		var who := "Your move" if Net.is_my_turn() else "%s's move" % a.get("name", "?")
		status = "[b]%s:[/b] [color=#F2C230]%s[/color] · %s, reach %d" % [who, u.name, g.name, g.reach]
	for side in 2:
		var lines: Array = []
		for u2 in f.units:
			if int(u2.side) != side:
				continue
			var hp := int(u2.hp)
			if city_view != null:
				hp = city_view.fight_view.shown_hp(int(u2.id), hp)
			var g2: Dictionary = Balance.GEAR[int(u2.gear)]
			var bar := _bar(hp, int(u2.max))
			if hp <= 0:
				lines.append("[color=#6E737C][s]%s[/s]  down[/color]" % u2.name)
			else:
				var col := "#7FE6D6" if side == 0 else "#FF9C90"
				if not busy and int(u2.id) == int(f.cur) and int(f.side) == 0:
					col = "#F2C230"
				lines.append("[color=%s]%s[/color]  %s %d  [color=#B5B9C2]%s[/color]" % [col, u2.name, bar, hp, g2.name])
		_fight_sides[side].text = "\n".join(lines)
	_fight_status.text = status
	var mine := Net.is_my_turn()
	_fight_wait.disabled = not _can_fight()
	# Resolved by the server, so they work while moves are still replaying: a way out if the screen hangs.
	_fight_auto.disabled = not mine
	_fight_quit.disabled = not mine


func _bar(hp: int, max_hp: int) -> String:
	var n := clampi(roundi(8.0 * hp / maxf(1.0, max_hp)), 0, 8)
	return "[color=#35D0BA]%s[/color][color=#3A3F49]%s[/color]" % ["|".repeat(n), "|".repeat(8 - n)]


func _on_fight_square(cell: Vector2i) -> void:
	if not _can_fight():
		return
	Net.send_intent({"t": "fight", "cell": [cell.x, cell.y]})
