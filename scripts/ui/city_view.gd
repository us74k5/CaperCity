extends Node2D
## Draws the city top-down from Net.state and animates player tokens.
## Placeholder art drawn in code (our own shapes); real sprites replace this later.

signal cell_tapped(cell: Vector2i)

const CELL := 64
const C_GRASS := Color("#3E7A4C")
const C_ROAD := Color("#2B2E35")
const C_WALK := Color("#80858F")
const C_LINE := Color("#E8B931")
const C_WHITE := Color("#D9DCE1")
const C_TREE := Color("#2F6B3F")
const C_TREE_HI := Color("#4C9A5B")

var city: Dictionary = {}
var _display_pos := {}     # pid -> Vector2 (pixels), animated
var _font: Font
var _t := 0.0
var camera: Camera2D


func _ready() -> void:
	_font = ThemeDB.fallback_font
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()


func set_city(c: Dictionary) -> void:
	city = c
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if Net.state.is_empty() or city.is_empty():
		return
	for pid in Net.state.players:
		var p: Dictionary = Net.state.players[pid]
		var target := _token_target(p)
		var cur: Vector2 = _display_pos.get(pid, target)
		_display_pos[pid] = cur.lerp(target, minf(1.0, delta * 12.0))
	var a := Net.active_player()
	if not a.is_empty():
		camera.position = _display_pos.get(a.id, camera.position)
	queue_redraw()


func _token_target(p: Dictionary) -> Vector2:
	if int(p.inside) >= 0:
		var b: Dictionary = city.buildings[int(p.inside)]
		return Vector2((int(b.x) + 1) * CELL, (int(b.y) + 1) * CELL)
	return Vector2((int(p.pos[0]) + 0.5) * CELL, (int(p.pos[1]) + 0.5) * CELL)


func _unhandled_input(event: InputEvent) -> void:
	var pressed := false
	var screen_pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
		screen_pos = event.position
	# Touch arrives as emulated mouse clicks (Godot default), so one branch handles both.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.4, 0.4), Vector2(2, 2))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.4, 0.4), Vector2(2, 2))
	if pressed:
		var world := get_canvas_transform().affine_inverse() * screen_pos
		cell_tapped.emit(Vector2i(floori(world.x / CELL), floori(world.y / CELL)))


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if city.is_empty():
		return
	var w: int = city.w
	var h: int = city.h
	draw_rect(Rect2(-CELL * 4, -CELL * 4, (w + 8) * CELL, (h + 8) * CELL), C_GRASS)
	var grid: PackedByteArray = city.grid
	for y in h:
		for x in w:
			if grid[y * w + x] == CityGen.ROAD:
				_draw_road(x, y, grid, w, h)
	for y in h:
		for x in w:
			if grid[y * w + x] != CityGen.ROAD:
				_draw_curbs(x, y, grid, w, h)
	for t in city.trees:
		_draw_tree(Vector2((t[0] + 0.5) * CELL, (t[1] + 0.5) * CELL), 18)
	for d in city.decor:
		_draw_decor(d)
	for b in city.buildings:
		_draw_building(b)
	_draw_markers()
	_draw_tokens()


func _is_road(grid: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and grid[y * w + x] == CityGen.ROAD


func _draw_road(x: int, y: int, grid: PackedByteArray, w: int, h: int) -> void:
	var r := Rect2(x * CELL, y * CELL, CELL, CELL)
	draw_rect(r, C_ROAD)
	var n := _is_road(grid, w, h, x, y - 1)
	var s := _is_road(grid, w, h, x, y + 1)
	var e := _is_road(grid, w, h, x + 1, y)
	var wv := _is_road(grid, w, h, x - 1, y)
	var cx := r.position.x + CELL / 2.0
	var cy := r.position.y + CELL / 2.0
	var junction := int(n) + int(s) + int(e) + int(wv) >= 3
	if junction:
		# crosswalk stripes on the arms of the junction
		for arm in [[n, Vector2(0, -1)], [s, Vector2(0, 1)], [e, Vector2(1, 0)], [wv, Vector2(-1, 0)]]:
			if not arm[0]:
				continue
			var dvec: Vector2 = arm[1]
			for i in range(-2, 3):
				var off := Vector2(cx, cy) + dvec * (CELL * 0.42)
				if dvec.x == 0:
					draw_rect(Rect2(off.x + i * 11 - 3, off.y - 4, 6, 8), C_WHITE)
				else:
					draw_rect(Rect2(off.x - 4, off.y + i * 11 - 3, 8, 6), C_WHITE)
		return
	if (e or wv) and not (n or s):
		draw_line(Vector2(r.position.x, cy - 2), Vector2(r.end.x, cy - 2), C_LINE, 2)
		draw_line(Vector2(r.position.x, cy + 2), Vector2(r.end.x, cy + 2), C_LINE, 2)
	elif (n or s) and not (e or wv):
		draw_line(Vector2(cx - 2, r.position.y), Vector2(cx - 2, r.end.y), C_LINE, 2)
		draw_line(Vector2(cx + 2, r.position.y), Vector2(cx + 2, r.end.y), C_LINE, 2)
	else:
		# a corner: dashed white arc-ish marker
		draw_circle(Vector2(cx, cy), 3, C_WHITE)


func _draw_curbs(x: int, y: int, grid: PackedByteArray, w: int, h: int) -> void:
	var r := Rect2(x * CELL, y * CELL, CELL, CELL)
	var k := 8.0
	if _is_road(grid, w, h, x, y - 1):
		draw_rect(Rect2(r.position.x, r.position.y, CELL, k), C_WALK)
	if _is_road(grid, w, h, x, y + 1):
		draw_rect(Rect2(r.position.x, r.end.y - k, CELL, k), C_WALK)
	if _is_road(grid, w, h, x - 1, y):
		draw_rect(Rect2(r.position.x, r.position.y, k, CELL), C_WALK)
	if _is_road(grid, w, h, x + 1, y):
		draw_rect(Rect2(r.end.x - k, r.position.y, k, CELL), C_WALK)


func _draw_tree(c: Vector2, rad: float) -> void:
	draw_circle(c, rad, C_TREE)
	draw_circle(c - Vector2(rad * 0.3, rad * 0.3), rad * 0.45, C_TREE_HI)


func _draw_decor(d: Dictionary) -> void:
	var r := Rect2(int(d.x) * CELL + 8, int(d.y) * CELL + 8, CELL * 2 - 16, CELL * 2 - 16)
	match d.kind:
		"houses":
			var roof := [Color("#A14B3B"), Color("#8C6A4F"), Color("#6F7F8F"), Color("#A88A5A")]
			for i in 4:
				var hr := Rect2(r.position + Vector2((i % 2) * r.size.x / 2 + 4, (i / 2) * r.size.y / 2 + 4), r.size / 2 - Vector2(8, 8))
				draw_rect(hr, roof[(int(d.x) + i) % 4])
				draw_line(hr.position + Vector2(0, hr.size.y / 2), hr.end - Vector2(0, hr.size.y / 2), Color(0, 0, 0, 0.25), 2)
		"park":
			draw_rect(r, Color("#4A8A57"))
			_draw_tree(r.position + Vector2(24, 24), 16)
			_draw_tree(r.end - Vector2(24, 24), 18)
			_draw_tree(r.position + Vector2(r.size.x - 26, 28), 12)
		"parking":
			draw_rect(r, Color("#33363D"))
			for i in 4:
				draw_line(r.position + Vector2(8 + i * 26, 0), r.position + Vector2(8 + i * 26, 30), C_WHITE, 2)
			draw_rect(Rect2(r.position + Vector2(12, 4), Vector2(18, 26)), Color("#4F7BC4"))
		"pond":
			draw_circle(r.get_center(), r.size.x * 0.38, Color("#3F86A6"))
			draw_circle(r.get_center() + Vector2(-8, -6), r.size.x * 0.12, Color("#5FA8C9"))
		_:
			draw_rect(r, Color("#5A5F6B"))
			draw_rect(r.grow(-6), Color("#6C7280"))
			draw_rect(Rect2(r.position + Vector2(14, 14), Vector2(26, 18)), Color("#9FA6AE"))


func _draw_building(b: Dictionary) -> void:
	var info: Dictionary = Balance.BUILDINGS[b.type]
	var r := Rect2(int(b.x) * CELL + 6, int(b.y) * CELL + 6, int(b.w) * CELL - 12, int(b.h) * CELL - 12)
	var col := Color(info.color)
	match b.type:
		"playground":
			draw_rect(r, Color("#4A8A57"))
			draw_rect(Rect2(r.position + Vector2(20, 22), Vector2(40, 8)), Color("#C9643A"))
			draw_rect(Rect2(r.position + Vector2(60, 50), Vector2(30, 30)), Color("#E2C26A"))
			_draw_tree(r.position + Vector2(24, r.size.y - 22), 14)
			_draw_tree(r.end - Vector2(18, r.size.y - 18), 12)
		"villa":
			draw_rect(r, Color("#4A8A57"))
			var house := Rect2(r.position + Vector2(10, 10), r.size * Vector2(0.75, 0.6))
			draw_rect(house, col.darkened(0.25))
			draw_rect(house.grow(-5), col)
			draw_circle(r.end - Vector2(22, 22), 14, Color("#5FA8C9"))
		_:
			draw_rect(r, col.darkened(0.35))
			draw_rect(r.grow(-6), col)
			# rooftop details
			draw_rect(Rect2(r.position + Vector2(14, 14), Vector2(30, 20)), Color("#9FA6AE"))
			for i in 4:
				draw_line(r.position + Vector2(18 + i * 7, 16), r.position + Vector2(18 + i * 7, 32), Color("#6E747C"), 2)
			draw_circle(r.position + Vector2(r.size.x - 24, 26), 9, Color("#8C8F96"))
	if info.sign != "":
		var sign_rect := Rect2(r.position.x + 10, r.end.y - 34, r.size.x - 20, 22)
		draw_rect(sign_rect, Color("#1F2229"))
		draw_string(_font, Vector2(sign_rect.position.x, sign_rect.position.y + 16), info.sign,
			HORIZONTAL_ALIGNMENT_CENTER, sign_rect.size.x, 13, Color("#FFD27A"))
	draw_string(_font, Vector2(int(b.x) * CELL, int(b.y) * CELL + 2 * CELL + 13), b.name,
		HORIZONTAL_ALIGNMENT_CENTER, 2 * CELL, 11, Color(1, 1, 1, 0.85))


func _draw_markers() -> void:
	# Your ransom drop point, visible to the kidnapper only.
	var me := Net.my_player()
	if me.is_empty() or me.ransom.is_empty():
		return
	var b: Dictionary = city.buildings[int(me.ransom.building)]
	var c := Vector2((int(b.x) + 1) * CELL, (int(b.y) + 1) * CELL)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_arc(c, 70 + 6 * pulse, 0, TAU, 40, Color(0.95, 0.76, 0.19, 0.9), 4)
	draw_string(_font, c + Vector2(-60, -76), "RANSOM DROP", HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color("#F2C230"))


func _draw_tokens() -> void:
	var active := Net.active_player()
	for pid in Net.state.players:
		var p: Dictionary = Net.state.players[pid]
		if int(p.jail) > 0 or int(p.holiday) > 0:
			continue
		var pos: Vector2 = _display_pos.get(pid, _token_target(p))
		var col := Color(p.color)
		var is_active: bool = not active.is_empty() and int(active.id) == int(p.id)
		if is_active:
			var pulse := 0.5 + 0.5 * sin(_t * 5.0)
			draw_arc(pos, 30 + 3 * pulse, 0, TAU, 32, Color("#35D0BA"), 3)
		if int(p.car) > 0:
			var body := Rect2(pos - Vector2(22, 12), Vector2(44, 24))
			draw_rect(body.grow(2), Color("#15171C"))
			draw_rect(body, col)
			draw_rect(Rect2(body.position + Vector2(26, 3), Vector2(10, 18)), Color("#1E2430"))
			draw_rect(Rect2(body.position + Vector2(5, 3), Vector2(6, 18)), Color("#1E2430"))
		else:
			draw_circle(pos, 13, Color("#15171C"))
			draw_circle(pos, 11, col)
			draw_circle(pos + Vector2(0, -2), 5, Color("#E2B98F"))
		draw_string(_font, pos + Vector2(-50, -20), p.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color.WHITE)
