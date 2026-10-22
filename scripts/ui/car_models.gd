class_name CarModels
extends RefCounted
## The cars, from Kenney's Car Kit (CC0): one model per car in Balance.CARS, plus the squad car and
## a few for traffic. The lot, the city map and the building scenes all use these, so a car looks
## the same wherever it is. Every car comes centered on its wheels with its nose toward +Z.

const DIR := "res://assets/models/cars/"
# Balance.CARS index -> [model, tint, length stretch]
const LOOKS := {
	1: ["hatchback-sports", Color.WHITE, 1.0],
	2: ["sedan", Color.WHITE, 1.0],
	3: ["sedan-sports", Color.WHITE, 1.0],
	4: ["van", Color.WHITE, 1.0],
	5: ["suv", Color.WHITE, 1.0],
	6: ["suv-luxury", Color.WHITE, 1.0],
	7: ["sedan", Color(0.32, 0.32, 0.36), 1.45],
	8: ["sedan-sports", Color(0.45, 0.47, 0.55), 1.0],
	9: ["race-future", Color.WHITE, 1.0],
	10: ["race", Color.WHITE, 1.0],
}
const TRAFFIC := ["sedan", "hatchback-sports", "suv", "taxi", "van", "suv-luxury"]


## Car `ci` (a Balance.CARS index), `length` long.
static func car(ci: int, length: float) -> Node3D:
	var look: Array = LOOKS.get(ci, LOOKS[2])
	var node := model(str(look[0]), length, float(look[2]))
	if look[1] != Color.WHITE:
		tint(node, look[1])
	return node


## Any model in the kit by name ("police", "taxi", "delivery"...), `length` long.
static func model(name: String, length: float, stretch := 1.0) -> Node3D:
	var inner: Node3D = load(DIR + name + ".glb").instantiate()
	var bb := aabb(inner)
	var k: float = length / maxf(bb.size.z * stretch, 0.01)
	var scale := Vector3(k, k, k * stretch)
	inner.scale = scale
	inner.position = -Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * scale
	var holder := Node3D.new()
	holder.add_child(inner)
	return holder


## Bounds of a model's meshes, in its own space.
static func aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		var xf := Transform3D()
		var n: Node = mi
		while n != node and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var bb: AABB = xf * mi.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


## Darkens a model's paint (and everything else) by `col`: the limo and the Stiletto are black.
static func tint(node: Node3D, col: Color) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var dup: StandardMaterial3D = mat.duplicate()
				dup.albedo_color = dup.albedo_color * col
				dup.metallic = 0.5
				dup.roughness = 0.25
				mi.set_surface_override_material(s, dup)
