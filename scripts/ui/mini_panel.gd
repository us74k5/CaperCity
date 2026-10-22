extends VBoxContainer
## The minigame HUD (Net.state.mini; see Mini): a bar along the top with the title, a hint, the
## clock, how it's going (boxes on the truck, containers on the track...) and the bail-out button.
## For the safe it adds the three dials, and plays the clicks: each turn of a dial makes a tone,
## and on the right number the tone is a little lower. Everyone watching hears and sees the same.

const C_BG := Color("#121A2E")
const TONE := 880.0
const ODD_TONE := 800.0

var _bar: PanelContainer
var _title: Label
var _hint: Label
var _score: Label
var _clock: Label
var _quit: Button
var _safe: PanelContainer
var _dials: Array = []          # [{panel, digit}]
var _meter: ColorRect
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _clicks := -1
var _meter_h := 0.0
var _mini_id := -1


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", UiTheme.box(C_BG, UiTheme.CORAL, 14, 14, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var v := VBoxContainer.new()
	_title = UiTheme.label("", 22, UiTheme.CORAL)
	_hint = UiTheme.label("", 15, UiTheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 440
	_score = UiTheme.label("", 16, UiTheme.TEAL)
	v.add_child(_title)
	v.add_child(_hint)
	v.add_child(_score)
	row.add_child(v)
	_clock = UiTheme.label("", 40, UiTheme.YELLOW)
	_clock.custom_minimum_size.x = 120
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_clock)
	_quit = UiTheme.button("Give up", false, 48)
	_quit.custom_minimum_size.x = 130
	_quit.pressed.connect(func(): Net.send_intent({"t": "pending", "id": "give_up"}))
	row.add_child(_quit)
	_bar.add_child(row)
	add_child(_bar)
	_build_safe()
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.3
	_player.stream = gen
	add_child(_player)


func _build_safe() -> void:
	_safe = PanelContainer.new()
	_safe.add_theme_stylebox_override("panel", UiTheme.box(Color("#1C1F26"), Color("#6E7787"), 18, 18, 2))
	_safe.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		var up := UiTheme.button("▲", false, 44)
		up.pressed.connect(func(): _pick_and_turn(i, 1))
		var face := PanelContainer.new()
		face.custom_minimum_size = Vector2(96, 110)
		var digit := UiTheme.label("0", 64, UiTheme.TEXT)
		digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		digit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		face.add_child(digit)
		face.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _pick(i))
		var down := UiTheme.button("▼", false, 44)
		down.pressed.connect(func(): _pick_and_turn(i, -1))
		col.add_child(up)
		col.add_child(face)
		col.add_child(down)
		row.add_child(col)
		_dials.append({"panel": face, "digit": digit})
	v.add_child(row)
	# The stethoscope: a bar that jumps with every click (a touch shorter on the odd one).
	var ear := HBoxContainer.new()
	ear.alignment = BoxContainer.ALIGNMENT_CENTER
	ear.add_theme_constant_override("separation", 10)
	ear.add_child(UiTheme.label("Stethoscope", 14, UiTheme.MUTED))
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", UiTheme.box(Color("#0E1015"), Color("#3A3F4A"), 6, 2, 1))
	well.custom_minimum_size = Vector2(160, 36)
	_meter = ColorRect.new()
	_meter.color = UiTheme.TEAL
	_meter.custom_minimum_size = Vector2(150, 0)
	well.add_child(_meter)
	ear.add_child(well)
	v.add_child(ear)
	_safe.add_child(v)
	_safe.visible = false
	add_child(_safe)


## The minigame's state changed (or a frame passed): redraw.
func refresh() -> void:
	var m: Dictionary = Net.state.get("mini", {})
	visible = not m.is_empty() and Net.state.get("phase", "") == "playing"
	if not visible:
		return
	var pend: Dictionary = Net.state.get("pending", {})
	var mine: bool = Net.is_my_turn() and pend.get("kind", "") == "mini"
	_title.text = str(m.get("title", "")).to_upper()
	_hint.text = _hint_text(m, mine)
	_score.text = _score_text(m)
	_score.visible = _score.text != ""
	if int(m.ready) > 0 and not m.over:
		_clock.text = str(ceili(int(m.ready) * Mini.TICK))
	elif m.get("phase", "") == "train":
		_clock.text = "TRAIN!"
	else:
		_clock.text = "%.1f" % Mini.seconds_left(m)
	var urgent: bool = not m.over and Mini.seconds_left(m) <= 5.0 and int(m.ready) <= 0 and m.get("phase", "") != "train"
	_clock.add_theme_color_override("font_color", UiTheme.CORAL if urgent else UiTheme.YELLOW)
	_quit.visible = mine and not m.over and m.get("phase", "") != "train"
	if pend.get("kind", "") == "mini" and pend.options.size() > 0:
		_quit.text = pend.options[0].label
	_safe.visible = m.game == "safe"
	if m.game == "safe":
		_refresh_safe(m, mine)
	if int(m.id) != _mini_id:
		_mini_id = int(m.id)
		_clicks = int(m.get("clicks", 0))


func _process(delta: float) -> void:
	if not visible:
		return
	refresh()
	_meter_h = maxf(0.0, _meter_h - delta * 3.0)
	_meter.custom_minimum_size.x = 150.0 * _meter_h
	_meter.size.x = 150.0 * _meter_h


func _hint_text(m: Dictionary, mine: bool) -> String:
	var who: String = Net.active_player().get("name", "?")
	if m.over:
		match str(m.game):
			"escape":
				return "You got away!" if m.won else "They caught you!"
			"catch":
				return "Got the case!" if m.won else "They got away."
			"sneak":
				return "Through the door!" if m.won else ("Out of time!" if int(m.get("spotted", -1)) == -2 else "Spotted!")
			"safe":
				return "The vault swings open!" if m.won else "ALARM!"
			"train":
				return "The train is stopped!" if m.won else "The train got through."
		return "Out!" if m.won else "Time's up!"
	if int(m.ready) > 0:
		return "Get ready… arrows, WASD or the pad." if mine else "%s is about to start." % who
	match str(m.game):
		"escape":
			return "Keep away from the cops until the clock runs out."
		"catch":
			return "Catch the runaway with the case before the clock runs out."
		"sneak":
			return "Reach the door. Stay out of the lit squares: guards see ahead and to the sides, never behind."
		"loot":
			return "Push the boxes onto the yellow squares, then leave by the exit. One box at a time."
		"containers":
			return "Push containers onto the yellow squares, then out through the gate. One at a time."
		"train":
			if m.get("phase", "") == "train":
				return "Here it comes…"
			return "Push containers up onto the track. Call the train when you're ready."
		"safe":
			return "Up/down turns the dial, left/right picks one. Listen for the click that sounds different."
	return ""


func _score_text(m: Dictionary) -> String:
	match str(m.game):
		"loot":
			return "Boxes on the squares: %d of %d" % [int(m.got), m.items.size()]
		"containers":
			return "Containers on the squares: %d of %d" % [int(m.got), m.items.size()]
		"train":
			if m.get("phase", "") == "train":
				return "Hits: %d · need %d to stop it" % [int(m.train.hits), int(m.need)]
			return "On the track: %d · need %d" % [int(m.got), int(m.need)]
		"sneak":
			return "%d guards on patrol" % m.guards.size()
	return ""


func _refresh_safe(m: Dictionary, mine: bool) -> void:
	for i in 3:
		var d: Dictionary = _dials[i]
		d.digit.text = str(int(m.dials[i]))
		var cur: bool = i == int(m.cur)
		d.panel.add_theme_stylebox_override("panel", UiTheme.box(Color("#2A2F3A") if cur else Color("#171A20"),
			UiTheme.YELLOW if cur else Color("#3A3F4A"), 12, 6, 3 if cur else 1))
	for b in _safe.find_children("*", "Button", true, false):
		b.disabled = not mine or m.over
	var clicks := int(m.get("clicks", 0))
	if clicks != _clicks:
		_clicks = clicks
		_beep(bool(m.odd))
		_meter_h = 0.86 if m.odd else 1.0


## A short click-tone; the odd one is lower.
func _beep(odd: bool) -> void:
	if not _player.playing:
		_player.play()
	_playback = _player.get_stream_playback()
	if _playback == null:
		return
	var rate := 22050.0
	var freq := ODD_TONE if odd else TONE
	var n := int(rate * 0.07)
	for i in n:
		var env := 1.0 - float(i) / n
		var s := sin(TAU * freq * i / rate) * 0.35 * env
		if _playback.can_push_buffer(1):
			_playback.push_frame(Vector2(s, s))


func _pick(i: int) -> void:
	Net.send_intent({"t": "mini", "pick": i})


func _pick_and_turn(i: int, by: int) -> void:
	var m: Dictionary = Net.state.get("mini", {})
	if int(m.get("cur", -1)) != i:
		_pick(i)
	Net.send_intent({"t": "mini", "turn": by})


## Keyboard and d-pad: steering for the grid games; for the safe, up/down turns and left/right picks.
func press(dir: String) -> void:
	var m: Dictionary = Net.state.get("mini", {})
	if m.get("game", "") == "safe":
		match dir:
			"N":
				Net.send_intent({"t": "mini", "turn": 1})
			"S":
				Net.send_intent({"t": "mini", "turn": -1})
			"W":
				_pick(posmod(int(m.cur) - 1, 3))
			"E":
				_pick(posmod(int(m.cur) + 1, 3))
	else:
		Net.send_intent({"t": "mini", "dir": dir})
