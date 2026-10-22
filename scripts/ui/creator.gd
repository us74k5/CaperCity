extends PanelContainer
## Character creation: pick your boss (a turning 3D preview, arrows to flip through) and roll each
## stat on its own casino button. The server does the rolling (see GameServer._create_step); a reel
## spins until its number arrives, then lands on it. Each stat is rolled once, plus a few re-rolls.
## Lives in the lobby, and over the town for someone who joins a game already under way.

const C_FELT := Color("#123B2A")
const C_GOLD := Color("#E2B13C")
const C_REEL := Color("#0B0C0F")
const SPIN_MIN := 0.9       # seconds a reel spins at least, even if the number is already back
const SPIN_MAX := 4.0       # give up waiting for the server after this long

var _idx := 0               # index into Balance.AVATARS of the character on show
var _claimed := false
var _viewport: SubViewport
var _pivot: Node3D
var _model: Node3D
var _model_id := ""
var _name_l: Label
var _tag_l: Label
var _note_l: Label
var _reels := {}            # stat -> {value: Label, button: Button, spin: float (-1 = still), seen: int, tick: float}
var _rerolls_l: Label
var _ready_b: Button
var _t := 0.0


func _ready() -> void:
	var small := UiTheme.compact
	add_theme_stylebox_override("panel", UiTheme.box(Color("#15171C"), C_GOLD.darkened(0.3), 16, 14 if small else 20, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14 if small else 22)
	add_child(row)

	# Left: the character.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	left.add_child(UiTheme.label("CHOOSE YOUR BOSS", 13, UiTheme.TEAL))
	var vc := SubViewportContainer.new()
	vc.stretch = true
	vc.custom_minimum_size = Vector2(150, 170) if small else Vector2(220, 250)
	left.add_child(vc)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	vc.add_child(_viewport)
	_build_stage()
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 6)
	left.add_child(pick)
	var prev := UiTheme.button("‹", false, 40)
	prev.custom_minimum_size.x = 40
	prev.pressed.connect(func(): _flip(-1))
	pick.add_child(prev)
	_name_l = UiTheme.label("", 22 if small else 26)
	_name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_child(_name_l)
	var nxt := UiTheme.button("›", false, 40)
	nxt.custom_minimum_size.x = 40
	nxt.pressed.connect(func(): _flip(1))
	pick.add_child(nxt)
	_tag_l = UiTheme.label("", 13, UiTheme.MUTED)
	_tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tag_l.custom_minimum_size.x = vc.custom_minimum_size.x
	left.add_child(_tag_l)
	var perk := UiTheme.label("Special ability: coming soon", 12, UiTheme.YELLOW.darkened(0.15))
	perk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(perk)

	# Right: the stats, one slot reel and button each.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 5 if small else 8)
	row.add_child(right)
	right.add_child(UiTheme.label("ROLL YOUR STATS", 13, UiTheme.TEAL))
	for stat in Balance.ROLL_STATS:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		right.add_child(r)
		var name_l := UiTheme.label(Balance.ROLL_STATS[stat].label, 16 if small else 18)
		name_l.custom_minimum_size.x = 84 if small else 100
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(name_l)
		var reel := PanelContainer.new()
		reel.add_theme_stylebox_override("panel", UiTheme.box(C_REEL, C_GOLD, 8, 6, 2))
		reel.custom_minimum_size = Vector2(104 if small else 120, 0)
		r.add_child(reel)
		var val := UiTheme.label("?", 22 if small else 26, UiTheme.YELLOW)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		reel.add_child(val)
		var b := _casino_button()
		b.custom_minimum_size = Vector2(96 if small else 110, 40 if small else 46)
		b.pressed.connect(_roll.bind(stat))
		r.add_child(b)
		_reels[stat] = {"value": val, "button": b, "spin": -1.0, "seen": 0, "tick": 0.0}
	_rerolls_l = UiTheme.label("", 14, UiTheme.MUTED)
	right.add_child(_rerolls_l)
	_ready_b = UiTheme.button("Hit the streets", true, 46 if small else 52)
	_ready_b.pressed.connect(func(): Net.send_intent({"t": "ready"}))
	right.add_child(_ready_b)
	_note_l = UiTheme.label("", 13, UiTheme.MUTED)
	_note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_l.custom_minimum_size.x = 300 if small else 360
	right.add_child(_note_l)
	Net.state_updated.connect(refresh)
	refresh()


## A round red-and-gold button, like the spin button on a slot machine.
func _casino_button() -> Button:
	var b := Button.new()
	b.text = "ROLL"
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color("#FFF4D6"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("#8A8F99"))
	b.add_theme_stylebox_override("normal", UiTheme.box(Color("#C8231B"), C_GOLD, 24, 8, 3))
	b.add_theme_stylebox_override("hover", UiTheme.box(Color("#E2382E"), Color("#FFE27A"), 24, 8, 3))
	b.add_theme_stylebox_override("pressed", UiTheme.box(Color("#8E1712"), C_GOLD, 24, 8, 3))
	b.add_theme_stylebox_override("disabled", UiTheme.box(Color("#2A2D33"), Color("#4A4E57"), 24, 8, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _build_stage() -> void:
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, 1.0, 3.5)
	cam.look_at_from_position(cam.position, Vector3(0, 0.72, 0), Vector3.UP)
	_viewport.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-30), 0)
	key.light_energy = 1.1
	_viewport.add_child(key)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#AEB8D0")
	env.environment.ambient_light_energy = 0.6
	_viewport.add_child(env)
	# A spotlit disc to stand on.
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.8
	cyl.height = 0.08
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = C_FELT
	disc.material_override = mat
	disc.position.y = -0.04
	_viewport.add_child(disc)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)


func _show_model(id: String) -> void:
	if id == _model_id:
		return
	_model_id = id
	if _model:
		_model.queue_free()
	_model = load("res://assets/models/characters/" + id + ".glb").instantiate()
	_model.scale = Vector3.ONE * 1.45
	_pivot.add_child(_model)
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var ap: AnimationPlayer = aps[0]
		ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")


func _me() -> Dictionary:
	for pid in Net.state.get("players", {}):
		var p: Dictionary = Net.state.players[pid]
		if int(p.owner) == Net.my_peer and not p.local:
			return p
	return {}


func _taken_by_others() -> Dictionary:
	var me := _me()
	var out := {}
	for pid in Net.state.get("players", {}):
		var p: Dictionary = Net.state.players[pid]
		if p.avatar != "" and int(p.id) != int(me.get("id", -1)):
			out[p.avatar] = p.name
	return out


func _flip(step: int) -> void:
	var me := _me()
	if me.is_empty() or me.ready:
		return
	var taken := _taken_by_others()
	for i in Balance.AVATARS.size():
		_idx = posmod(_idx + step, Balance.AVATARS.size())
		if not taken.has(Balance.AVATARS[_idx].id):
			break
	Net.send_intent({"t": "avatar", "id": Balance.AVATARS[_idx].id})
	refresh()


func _roll(stat: String) -> void:
	var r: Dictionary = _reels[stat]
	if r.spin >= 0.0:
		return
	r.spin = 0.0
	r.button.disabled = true
	Net.send_intent({"t": "roll", "stat": stat})


func refresh() -> void:
	var me := _me()
	visible = not me.is_empty()   # a spectator (full room) has no boss to make
	if me.is_empty() or not is_instance_valid(_ready_b):
		return
	var taken := _taken_by_others()
	# The character: theirs if picked, otherwise the first free one, claimed straight away.
	if me.avatar != "":
		for i in Balance.AVATARS.size():
			if Balance.AVATARS[i].id == me.avatar:
				_idx = i
	elif not _claimed:
		_claimed = true
		_flip(1 if taken.has(Balance.AVATARS[_idx].id) else 0)
		return
	var av: Dictionary = Balance.AVATARS[_idx]
	_show_model(av.id)
	_name_l.text = av.name
	_tag_l.text = av.tag
	var rolls: Dictionary = me.get("rolls", {})
	var left := int(me.get("rerolls", 0))
	for stat in _reels:
		var r: Dictionary = _reels[stat]
		var n := int(rolls.get(stat, 0))
		if r.spin < 0.0:
			r.seen = n
			r.value.text = _value_text(stat, _stat_value(me, stat)) if n > 0 else "?"
		r.button.text = "ROLL" if n == 0 else "RE-ROLL"
		r.button.disabled = me.ready or r.spin >= 0.0 or (n > 0 and left <= 0)
	_rerolls_l.text = "Re-rolls left: %d  (each stat rolls once free)" % left
	var missing: Array = []
	for stat in Balance.ROLL_STATS:
		if not rolls.has(stat):
			missing.append(Balance.ROLL_STATS[stat].label)
	_ready_b.disabled = me.ready or not missing.is_empty() or me.avatar == ""
	if me.ready:
		_ready_b.text = "Ready ✓"
		_note_l.text = "Waiting for the host to start." if Net.state.phase == "lobby" else "Heading into town…"
	else:
		_ready_b.text = "Hit the streets"
		_note_l.text = "Still to roll: %s." % ", ".join(missing) if not missing.is_empty() else "Happy with that? A re-roll can go either way."


func _stat_value(me: Dictionary, stat: String) -> int:
	return int(me.cash) if stat == "cash" else int(me.crew[0][stat])


func _value_text(stat: String, v: int) -> String:
	if stat == "cash":
		var s := str(v)
		return "$" + (s.left(s.length() - 3) + "," + s.right(3) if s.length() > 3 else s)
	return str(v)


func _process(delta: float) -> void:
	_t += delta
	if _pivot:
		_pivot.rotation.y = sin(_t * 0.6) * 0.6
	var me := _me()
	for stat in _reels:
		var r: Dictionary = _reels[stat]
		if r.spin < 0.0:
			continue
		r.spin += delta
		var arrived: bool = not me.is_empty() and int(me.get("rolls", {}).get(stat, 0)) > int(r.seen)
		if (arrived and r.spin >= SPIN_MIN) or r.spin >= SPIN_MAX:
			r.spin = -1.0
			var lbl: Label = r.value
			lbl.modulate = Color(1.6, 1.4, 0.6)
			create_tween().tween_property(lbl, "modulate", Color.WHITE, 0.6)
			refresh()
			continue
		# Spinning: fast at first, slowing as it nears the end.
		r.tick -= delta
		if r.tick <= 0.0:
			r.tick = 0.04 + 0.12 * clampf(r.spin / SPIN_MIN, 0.0, 1.0) * (1.0 if arrived else 0.3)
			var range_: Array = Balance.ROLL_STATS[stat].range
			var v := randi_range(int(range_[0]), int(range_[1]))
			r.value.text = _value_text(stat, v / 50 * 50 if stat == "cash" else v)
