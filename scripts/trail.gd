@tool
class_name Trail
extends Path3D
## The hiking trail (P2). Draw it in the editor along the middle of the trail,
## first point at the bottom, last point at the peak. Boulders and landslides
## follow it downhill, so they stay on the trail however it winds or narrows.
## Place points roughly, then press "Snap points to ground" in the Inspector.

const TERRAIN_MASK := 1
const EDGE_STEP := 0.5
const MAX_HALF_WIDTH := 25.0
## Ground steeper than this between two samples is a wall or a drop, so the trail ends there.
## A slope (not a height limit) so trails that tilt sideways still measure their full width.
const EDGE_SLOPE := 1.0  # rise over run, 45 degrees
const RAY_REACH := 6.0
## Rock closer than this above the ground is an overhang, so the trail ends there.
const HEADROOM := 3.0
## How high above the ground "Snap points to ground" puts each point.
const SNAP_LIFT := 0.3

@export_tool_button("Snap points to ground") var snap_action := snap_to_ground


## The Trail in the current scene, or null if the level has none.
static func find(tree: SceneTree) -> Trail:
	var scene := tree.current_scene
	return scene.find_child("Trail", true, false) as Trail if scene else null


## Drops every curve point onto the terrain below it (the surface within
## RAY_REACH of the point first, so points under an overhang stay there).
func snap_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	for i in curve.point_count:
		var p := to_global(curve.get_point_position(i))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				p + Vector3.UP * RAY_REACH, p + Vector3.DOWN * RAY_REACH, TERRAIN_MASK))
		if hit.is_empty():
			hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(
					p + Vector3.UP * 500.0, p + Vector3.DOWN * 500.0, TERRAIN_MASK))
		if hit:
			curve.set_point_position(i, to_local(hit.position + Vector3.UP * SNAP_LIFT))
			curve.set_point_in(i, Vector3.ZERO)
			curve.set_point_out(i, Vector3.ZERO)


func length() -> float:
	return curve.get_baked_length()


## Distance along the trail (0 = bottom) of the trail point closest to `world_pos`.
func offset_of(world_pos: Vector3) -> float:
	return curve.get_closest_offset(to_local(world_pos))


func point_at(offset: float) -> Vector3:
	return to_global(curve.sample_baked(clampf(offset, 0.0, length())))


## Flat direction pointing up the trail.
func uphill_at(offset: float) -> Vector3:
	var dir := point_at(offset + 1.0) - point_at(offset - 1.0)
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD


## Flat direction pointing to the right when facing up the trail.
func side_at(offset: float) -> Vector3:
	return uphill_at(offset).cross(Vector3.UP)


## How far the trail reaches to the left and right of the trail line, in metres.
func edges_at(offset: float) -> Vector2:
	var m := _measure(offset)
	return Vector2(m.left, m.right)


## A point across the trail: t = 0 is the left edge, 1 the right edge.
## `margin` keeps a body of that radius inside the edges.
func across(offset: float, t: float, margin := 0.0) -> Vector3:
	var m := _measure(offset)
	var left: float = -m.left + margin
	var right: float = m.right - margin
	var x: float = lerpf(left, right, t) if right > left else (m.right - m.left) / 2.0
	return _ground_across(offset, m, x)


## A strip covering `fraction` of the trail width from one edge (side -1 = left,
## 1 = right), on the ground, with x across the trail and z pointing downhill.
## Returns {"transform": Transform3D, "width": float}.
func band(offset: float, side: float, fraction: float) -> Dictionary:
	var m := _measure(offset)
	var width := maxf((m.left + m.right) * fraction, 1.0)
	var mid: float = (m.right - width / 2.0) if side > 0.0 else (-m.left + width / 2.0)
	var across_dir := side_at(offset)
	var pos := _ground_across(offset, m, mid)
	return {"transform": Transform3D(Basis(across_dir, Vector3.UP, across_dir.cross(Vector3.UP)), pos), "width": width}


## Where `world_pos` sits across the trail, from 0 (left edge) to 1 (right edge).
func t_of(world_pos: Vector3, offset: float) -> float:
	var edges := edges_at(offset)
	var x := (world_pos - point_at(offset)).dot(side_at(offset))
	return clampf((x + edges.x) / maxf(edges.x + edges.y, 0.01), 0.0, 1.0)


## Height of the terrain under `p`, or `fallback` if there is none.
func ground_y(p: Vector3, fallback: float) -> float:
	var from := Vector3(p.x, p.y + RAY_REACH, p.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_REACH * 2.0, TERRAIN_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else fallback


## Ground heights every EDGE_STEP from the line out to each edge (index 0 is on the line).
## The trail width each side is (samples - 1) * EDGE_STEP.
func _measure(offset: float) -> Dictionary:
	var center := point_at(offset)
	var side := side_at(offset)
	var ground := ground_y(center, center.y)
	var l := _edge(center, -side, ground)
	var r := _edge(center, side, ground)
	return {"left": (l.size() - 1) * EDGE_STEP, "right": (r.size() - 1) * EDGE_STEP, "left_h": l, "right_h": r}


## Ground point `x` metres across the trail (negative = left). On a wide trail on a
## slope the ground there can be far above or below the line, so the ray starts
## from the height the edge walk found there.
func _ground_across(offset: float, m: Dictionary, x: float) -> Vector3:
	var p := point_at(offset) + side_at(offset) * x
	var heights: PackedFloat32Array = m.right_h if x > 0.0 else m.left_h
	var guess := heights[clampi(roundi(absf(x) / EDGE_STEP), 0, heights.size() - 1)]
	p.y = ground_y(Vector3(p.x, guess, p.z), guess)
	return p


## Walks from the line in `dir` until the ground turns into a wall or a drop, or
## rock overhangs it, and returns the ground heights it passed.
func _edge(center: Vector3, dir: Vector3, ground: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array([ground])
	var space := get_world_3d().direct_space_state
	var d := 0.0
	var last := ground
	while d < MAX_HALF_WIDTH:
		var p := center + dir * (d + EDGE_STEP)
		p.y = last
		var y := ground_y(p, INF)
		if absf(y - last) > EDGE_STEP * EDGE_SLOPE:
			break
		p.y = y + 0.1
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * HEADROOM, TERRAIN_MASK)):
			break
		last = y
		d += EDGE_STEP
		heights.append(y)
	return heights
