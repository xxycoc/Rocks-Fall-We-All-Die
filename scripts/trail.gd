class_name Trail
extends Path3D
## The hiking trail (P2). Draw it in the editor along the middle of the trail,
## first point at the bottom, last point at the peak. Boulders and landslides
## follow it downhill, so they stay on the trail however it winds or narrows.

const TERRAIN_MASK := 1
const EDGE_STEP := 0.5
const MAX_HALF_WIDTH := 25.0
## Ground steeper than this between two samples is a wall or a drop, so the trail ends there.
## A slope (not a height limit) so trails that tilt sideways still measure their full width.
const EDGE_SLOPE := 1.0  # rise over run, 45 degrees
const RAY_REACH := 6.0


## The Trail in the current scene, or null if the level has none.
static func find(tree: SceneTree) -> Trail:
	var scene := tree.current_scene
	return scene.find_child("Trail", true, false) as Trail if scene else null


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
	var center := point_at(offset)
	var side := side_at(offset)
	var ground := ground_y(center, center.y)
	return Vector2(_edge(center, -side, ground), _edge(center, side, ground))


## A point across the trail: t = 0 is the left edge, 1 the right edge.
## `margin` keeps a body of that radius inside the edges.
func across(offset: float, t: float, margin := 0.0) -> Vector3:
	var edges := edges_at(offset)
	var left := -edges.x + margin
	var right := edges.y - margin
	var x := lerpf(left, right, t) if right > left else (edges.y - edges.x) / 2.0
	var p := point_at(offset) + side_at(offset) * x
	p.y = ground_y(p, p.y)
	return p


## A strip covering `fraction` of the trail width from one edge (side -1 = left,
## 1 = right), on the ground, with x across the trail and z pointing downhill.
## Returns {"transform": Transform3D, "width": float}.
func band(offset: float, side: float, fraction: float) -> Dictionary:
	var edges := edges_at(offset)
	var width := maxf((edges.x + edges.y) * fraction, 1.0)
	var mid := (edges.y - width / 2.0) if side > 0.0 else (-edges.x + width / 2.0)
	var across_dir := side_at(offset)
	var pos := point_at(offset) + across_dir * mid
	pos.y = ground_y(pos, pos.y)
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


func _edge(center: Vector3, dir: Vector3, ground: float) -> float:
	var d := 0.0
	var last := ground
	while d < MAX_HALF_WIDTH:
		var p := center + dir * (d + EDGE_STEP)
		p.y = last
		var y := ground_y(p, INF)
		if absf(y - last) > EDGE_STEP * EDGE_SLOPE:
			break
		last = y
		d += EDGE_STEP
	return d
