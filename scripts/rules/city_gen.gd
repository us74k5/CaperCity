class_name CityGen
## Builds the town from the original map (CityMap) and holds the rules for moving through it.
##
## Grid cells: 0 = lot/grass, 1 = road, 2 = building, 3 = decor, 4 = water, 5 = paving.
## Roads keep the original piece codes (city.roads), so routes are the original's: a piece only
## joins its neighbours on the sides it opens to. The motorway has one lane per direction, needs a
## car and costs half a step per cell; junctions can be crossed on foot.

const W := CityMap.W
const H := CityMap.H

const LOT := 0
const ROAD := 1
const BUILDING := 2
const DECOR := 3
const WATER := 4
const PAVED := 5

const N := 1
const E := 2
const S := 4
const WEST := 8
const DIR_BIT := {"N": N, "E": E, "S": S, "W": WEST}
const OPPOSITE := {"N": "S", "S": "N", "E": "W", "W": "E"}
const DIR_VEC := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}

## Sides each road code opens to (index = code). 12-15 are one-way motorway lanes, 16 a junction.
const EXITS := [0, N | E, N | WEST, E | S, S | WEST, E | WEST, N | S, 15, N | E | WEST, E | S | WEST, N | E | S,
	N | S | WEST, WEST, E, S, N, 15]
const MOTORWAY := 12
const JUNCTION := 16

## step_cost() results that aren't a cost.
const BLOCKED := -1
const NEEDS_CAR := -2
const ONE_WAY := -3


static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid := PackedByteArray()
	grid.resize(W * H)
	var roads := PackedByteArray()
	roads.resize(W * H)
	var terrain := PackedByteArray()
	terrain.resize(W * H)
	var trees: Array = []
	for y in H:
		var rrow: String = CityMap.ROADS[y]
		var trow: String = CityMap.TERRAIN[y]
		for x in W:
			var i := y * W + x
			roads[i] = "0123456789abcdefg".find(rrow[x].replace(".", "0"))
			terrain[i] = trow.unicode_at(x)
			match trow[x]:
				"r":
					grid[i] = ROAD
				"B":
					grid[i] = BUILDING
				"w", "c", "o":
					grid[i] = WATER if trow[x] != "o" else DECOR
				"p":
					grid[i] = PAVED
				"T":
					trees.append([x, y])
					trees.append([x, y])
				"t", "b":
					if rng.randf() < 0.6:
						trees.append([x, y])
	var buildings: Array = []
	var seen := {}
	for entry in CityMap.BUILDINGS:
		var t: String = entry[0]
		var n: int = seen.get(t, 0)
		seen[t] = n + 1
		var names: Array = Balance.NAME_PREFIX.get(t, [Balance.BUILDINGS[t]["label"]])
		var b := {"id": buildings.size(), "type": t, "name": names[n % names.size()],
			"x": entry[1], "y": entry[2], "w": entry[3], "h": entry[4]}
		if not entry[5].is_empty():
			b["cells"] = entry[5]   # not a full box (the airport wraps around its access road)
		buildings.append(b)
	# Packed for a compact network snapshot; the rules only read it.
	return {"w": W, "h": H, "grid": grid, "roads": roads, "terrain": terrain, "buildings": buildings,
		"decor": [], "trees": trees}


static func is_motorway(code: int) -> bool:
	return code >= MOTORWAY


## Cost in half steps of moving one cell from `from` in direction `dir` (2 = a step, 1 = half a
## step on the motorway), or BLOCKED / NEEDS_CAR / ONE_WAY. Moving into a building cell means
## walking in, which works from any ordinary road beside it.
static func step_cost(city: Dictionary, from: Vector2i, dir: String, has_car: bool) -> int:
	var to: Vector2i = from + DIR_VEC[dir]
	var w: int = city.w
	if to.x < 0 or to.y < 0 or to.x >= w or to.y >= int(city.h):
		return BLOCKED
	var roads: PackedByteArray = city.roads
	var from_code: int = roads[from.y * w + from.x]
	var cell: int = city.grid[to.y * w + to.x]
	if cell == BUILDING:
		return 2 if from_code > 0 and not is_motorway(from_code) else BLOCKED
	if cell != ROAD or from_code == 0:
		return BLOCKED
	var to_code: int = roads[to.y * w + to.x]
	if EXITS[from_code] & DIR_BIT[dir] == 0:
		# On a lane: backwards is against the traffic, sideways is changing lanes between exits.
		return ONE_WAY if from_code >= MOTORWAY and from_code < JUNCTION and EXITS[from_code] == DIR_BIT[OPPOSITE[dir]] else BLOCKED
	if to_code >= MOTORWAY and to_code < JUNCTION:
		if not has_car:
			return NEEDS_CAR
		if EXITS[to_code] != DIR_BIT[dir]:
			return ONE_WAY
	elif to_code < MOTORWAY and EXITS[to_code] & DIR_BIT[OPPOSITE[dir]] == 0:
		return BLOCKED
	return 1 if has_car and is_motorway(to_code) else 2


## The building covering a cell, if any.
static func building_at(city: Dictionary, x: int, y: int) -> Dictionary:
	if x < 0 or y < 0 or x >= int(city.w) or y >= int(city.h) or city.grid[y * int(city.w) + x] != BUILDING:
		return {}
	for b in city.buildings:
		if x >= int(b.x) and x < int(b.x) + int(b.w) and y >= int(b.y) and y < int(b.y) + int(b.h):
			return b
	return {}


## Where you stand outside a building: an ordinary road cell beside it (never a motorway lane).
static func entrance(city: Dictionary, b: Dictionary) -> Array:
	var w: int = city.w
	var roads: PackedByteArray = city.roads
	for y in range(int(b.y), int(b.y) + int(b.h)):
		for x in range(int(b.x), int(b.x) + int(b.w)):
			if city.grid[y * w + x] != BUILDING:
				continue
			for d in ["S", "E", "W", "N"]:
				var c: Vector2i = Vector2i(x, y) + DIR_VEC[d]
				if c.x >= 0 and c.y >= 0 and c.x < w and c.y < int(city.h):
					var code: int = roads[c.y * w + c.x]
					if code > 0 and code < MOTORWAY:
						return [c.x, c.y]
	return [int(b.x), int(b.y)]
