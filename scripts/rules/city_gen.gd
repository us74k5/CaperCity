class_name CityGen
## Builds the Caper City street grid and places buildings. Deterministic for a given seed.
##
## Grid cells: 0 = lot/grass, 1 = road, 2 = building, 3 = decor (trees, houses, pond, parking).
## Roads run every 6 columns and every 5 rows; each block holds four 2x2 building slots.

const W := 37
const H := 31
const COL_STEP := 6
const ROW_STEP := 5

const LOT := 0
const ROAD := 1
const BUILDING := 2
const DECOR := 3

const DECOR_KINDS := ["houses", "park", "parking", "pond", "offices", "houses", "park"]


static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid: Array = []
	grid.resize(W * H)
	grid.fill(LOT)
	for y in H:
		for x in W:
			if x % COL_STEP == 0 or y % ROW_STEP == 0:
				grid[y * W + x] = ROAD
	_remove_some_segments(grid, rng)

	# Collect 2x2 slots: four per block.
	var slots: Array = []
	for by in range(0, H - 1, ROW_STEP):
		for bx in range(0, W - 1, COL_STEP):
			for off in [Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 3), Vector2i(4, 3)]:
				var sx: int = bx + off.x
				var sy: int = by + off.y
				if sx + 1 < W and sy + 1 < H and _slot_free(grid, sx, sy) and _touches_road(grid, sx, sy):
					slots.append(Vector2i(sx, sy))
	_shuffle(slots, rng)

	var buildings: Array = []
	var decor: Array = []
	var type_list: Array = []
	for t in Balance.BUILDINGS:
		for i in Balance.BUILDINGS[t]["count"]:
			type_list.append([t, i])
	var si := 0
	for entry in type_list:
		if si >= slots.size():
			break
		var s: Vector2i = slots[si]
		si += 1
		var t: String = entry[0]
		var names: Array = Balance.NAME_PREFIX.get(t, [Balance.BUILDINGS[t]["label"]])
		var b := {
			"id": buildings.size(), "type": t, "name": names[entry[1] % names.size()],
			"x": s.x, "y": s.y, "w": 2, "h": 2,
		}
		buildings.append(b)
		_fill(grid, s.x, s.y, BUILDING)
	while si < slots.size():
		var s2: Vector2i = slots[si]
		si += 1
		decor.append({"x": s2.x, "y": s2.y, "kind": DECOR_KINDS[rng.randi() % DECOR_KINDS.size()]})
		_fill(grid, s2.x, s2.y, DECOR)

	# Middle column of each block: trees.
	var trees: Array = []
	for y in H:
		for x in W:
			if grid[y * W + x] == LOT and rng.randf() < 0.35:
				trees.append([x, y])

	# Packed for a compact network snapshot; the rules only read it.
	return {"w": W, "h": H, "grid": PackedByteArray(grid), "buildings": buildings, "decor": decor, "trees": trees}


static func _remove_some_segments(grid: Array, rng: RandomNumberGenerator) -> void:
	# Knock out a few inner road segments for variety, keeping the network connected.
	var tries := 0
	var removed := 0
	while removed < 9 and tries < 200:
		tries += 1
		var horizontal := rng.randf() < 0.5
		var cells: Array = []
		if horizontal:
			var row: int = (1 + rng.randi() % ((H - 1) / ROW_STEP - 1)) * ROW_STEP
			var col: int = (rng.randi() % ((W - 1) / COL_STEP)) * COL_STEP
			for x in range(col + 1, col + COL_STEP):
				cells.append(Vector2i(x, row))
		else:
			var col2: int = (1 + rng.randi() % ((W - 1) / COL_STEP - 1)) * COL_STEP
			var row2: int = (rng.randi() % ((H - 1) / ROW_STEP)) * ROW_STEP
			for y in range(row2 + 1, row2 + ROW_STEP):
				cells.append(Vector2i(col2, y))
		if grid[cells[0].y * W + cells[0].x] != ROAD:
			continue
		for c in cells:
			grid[c.y * W + c.x] = LOT
		if _roads_connected(grid):
			removed += 1
		else:
			for c in cells:
				grid[c.y * W + c.x] = ROAD


static func _roads_connected(grid: Array) -> bool:
	var start := -1
	var total := 0
	for i in grid.size():
		if grid[i] == ROAD:
			total += 1
			if start < 0:
				start = i
	var seen := {start: true}
	var stack := [start]
	while stack.size() > 0:
		var i: int = stack.pop_back()
		var x := i % W
		var y := i / W
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx >= 0 and ny >= 0 and nx < W and ny < H:
				var j: int = ny * W + nx
				if grid[j] == ROAD and not seen.has(j):
					seen[j] = true
					stack.append(j)
	return seen.size() == total


static func _slot_free(grid: Array, x: int, y: int) -> bool:
	for dy in 2:
		for dx in 2:
			if grid[(y + dy) * W + x + dx] != LOT:
				return false
	return true


static func _touches_road(grid: Array, x: int, y: int) -> bool:
	for dy in range(-1, 3):
		for dx in range(-1, 3):
			var inside := dx >= 0 and dx <= 1 and dy >= 0 and dy <= 1
			var corner := (dx == -1 or dx == 2) and (dy == -1 or dy == 2)
			if inside or corner:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < W and ny < H and grid[ny * W + nx] == ROAD:
				return true
	return false


static func _fill(grid: Array, x: int, y: int, v: int) -> void:
	for dy in 2:
		for dx in 2:
			grid[(y + dy) * W + x + dx] = v


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
