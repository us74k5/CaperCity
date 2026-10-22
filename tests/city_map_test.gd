extends SceneTree
## The town is the original map, and moving through it follows the original's rules.
## Run: godot --headless --path . --script res://tests/city_map_test.gd

var fails := 0


func _init() -> void:
	var city := CityGen.generate(1)
	_check(city.w == 45 and city.h == 40, "map is 45 x 40")
	_check(city.buildings.size() == 64, "64 buildings (got %d)" % city.buildings.size())
	var per_type := {}
	for b in city.buildings:
		per_type[b.type] = per_type.get(b.type, 0) + 1
	for t in Balance.BUILDINGS:
		_check(per_type.get(t, 0) == Balance.BUILDINGS[t].count, "%s: %d on the map, Balance says %d" % [t, per_type.get(t, 0), Balance.BUILDINGS[t].count])

	# Every building can be walked into from the start, on foot (junctions can be crossed on foot).
	var start := Vector2i(22, 16)
	_check(city.grid[start.y * city.w + start.x] == CityGen.ROAD, "start cell is a road")
	var on_foot := _reach(city, start, false)
	var by_car := _reach(city, start, true)
	for b in city.buildings:
		_check(on_foot.has(b.id), "%s (%s at %d,%d) can be walked to" % [b.name, b.type, b.x, b.y])
	_check(by_car.size() == city.buildings.size(), "every building can be driven to")

	# Pieces only join on their open sides: car dealer 1's road (12,5) is an E-W straight, so no turning north off it
	# except into the building itself, and (9,4) "1" (NE) doesn't open west.
	_check(CityGen.step_cost(city, Vector2i(9, 4), "W", false) == CityGen.BLOCKED, "a NE bend doesn't open west")
	_check(CityGen.step_cost(city, Vector2i(9, 4), "E", false) == 2, "a NE bend opens east")
	_check(CityGen.step_cost(city, Vector2i(12, 5), "N", false) == 2, "walk into the car dealer from the street")

	# The motorway: lanes need a car, run one way, and cost half a step; junctions can be crossed on foot.
	_check(CityGen.step_cost(city, Vector2i(1, 14), "E", false) == 2, "walk onto a junction")
	_check(CityGen.step_cost(city, Vector2i(2, 14), "N", false) == CityGen.NEEDS_CAR, "no walking on a lane")
	_check(CityGen.step_cost(city, Vector2i(2, 14), "S", true) == 1, "drive south on the left lane: half a step")
	_check(CityGen.step_cost(city, Vector2i(2, 14), "N", true) == CityGen.ONE_WAY, "no driving north on the southbound lane")
	_check(CityGen.step_cost(city, Vector2i(2, 15), "N", true) == CityGen.ONE_WAY, "no reversing on a lane")
	_check(CityGen.step_cost(city, Vector2i(2, 15), "E", true) == CityGen.BLOCKED, "no changing lanes between exits")
	_check(CityGen.step_cost(city, Vector2i(3, 14), "N", true) == 1, "the right lane runs north")
	_check(CityGen.step_cost(city, Vector2i(5, 10), "E", true) == 1, "the lower lane runs east")
	_check(CityGen.step_cost(city, Vector2i(5, 9), "W", true) == 1, "the upper lane runs west")

	# The server banks half steps.
	var gs := GameServer.new(1)
	gs.handle(1, {"t": "join", "name": "A", "crew": ""})
	gs.handle(1, {"t": "start", "target": 20})
	var p: Dictionary = gs.state.players.values()[0]
	p.car = 1
	p.pos = [2, 14]
	p.steps = 10
	p.inside = -1
	gs.state.pending = {}
	gs.handle(1, {"t": "move", "dir": "S"})
	_check(int(p.steps) == 10 and p.half_step, "first motorway cell is free (half banked)")
	gs.state.pending = {}
	gs.handle(1, {"t": "move", "dir": "S"})
	_check(int(p.steps) == 9 and not p.half_step, "second motorway cell costs the step")
	_check(gs.handle(1, {"t": "move", "dir": "N"}) != "" or not gs.state.pending.is_empty(), "reversing is refused")

	print("city map: %s" % ("ok" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


## Building ids you can get into from `start`.
func _reach(city: Dictionary, start: Vector2i, car: bool) -> Dictionary:
	var seen := {start: true}
	var stack: Array = [start]
	var found := {}
	while stack.size() > 0:
		var cur: Vector2i = stack.pop_back()
		for d in CityGen.DIR_VEC:
			if CityGen.step_cost(city, cur, d, car) <= 0:
				continue
			var nxt: Vector2i = cur + CityGen.DIR_VEC[d]
			if city.grid[nxt.y * city.w + nxt.x] == CityGen.BUILDING:
				found[CityGen.building_at(city, nxt.x, nxt.y).id] = true
			elif not seen.has(nxt):
				seen[nxt] = true
				stack.append(nxt)
	return found


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)
