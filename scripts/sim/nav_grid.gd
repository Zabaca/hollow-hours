class_name NavGrid
extends RefCounted
## A coarse A* grid over the city (2 m cells) so the creatures path around buildings instead of
## pressing against them. Cells a creature's body cannot fit through are solid.

const CELL := 2.0

var astar := AStarGrid2D.new()
var origin := Vector2.ZERO
var size := Vector2i.ZERO


func _init(world: SimWorld, clearance: float = 0.75) -> void:
	var a: Dictionary = world.arena
	origin = Vector2(a["left"], a["bottom"])
	size = Vector2i(int(ceil((a["right"] - a["left"]) / CELL)), int(ceil((a["top"] - a["bottom"]) / CELL)))
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = origin + Vector2(CELL, CELL) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	# Each box and post marks only the cells it can reach (the box grown by the clearance and 0.4 of a
	# cell, the post's circle by the clearance and 0.3), not every cell of the city: the same solid cells
	# the test of every cell against every box gave, found in time that follows the obstacles.
	var reach := clearance + CELL * 0.4
	for b in world.boxes:
		var ix0 := _index((b["x0"] - reach - origin.x) / CELL - 0.5, size.x) - 1
		var ix1 := _index((b["x1"] + reach - origin.x) / CELL - 0.5, size.x) + 1
		var iy0 := _index((b["y0"] - reach - origin.y) / CELL - 0.5, size.y) - 1
		var iy1 := _index((b["y1"] + reach - origin.y) / CELL - 0.5, size.y) + 1
		for ix in range(maxi(ix0, 0), mini(ix1, size.x - 1) + 1):
			var cx := origin.x + (ix + 0.5) * CELL
			if not (cx > b["x0"] - clearance - CELL * 0.4 and cx < b["x1"] + clearance + CELL * 0.4):
				continue
			for iy in range(maxi(iy0, 0), mini(iy1, size.y - 1) + 1):
				var cy := origin.y + (iy + 0.5) * CELL
				if cy > b["y0"] - clearance - CELL * 0.4 and cy < b["y1"] + clearance + CELL * 0.4:
					astar.set_point_solid(Vector2i(ix, iy), true)
	for p in world.posts:
		var lim: float = float(p["r"]) + clearance + CELL * 0.3
		var at := Vector2(p["x"], p["y"])
		var ix0 := _index((at.x - lim - origin.x) / CELL - 0.5, size.x) - 1
		var ix1 := _index((at.x + lim - origin.x) / CELL - 0.5, size.x) + 1
		var iy0 := _index((at.y - lim - origin.y) / CELL - 0.5, size.y) - 1
		var iy1 := _index((at.y + lim - origin.y) / CELL - 0.5, size.y) + 1
		for ix in range(maxi(ix0, 0), mini(ix1, size.x - 1) + 1):
			for iy in range(maxi(iy0, 0), mini(iy1, size.y - 1) + 1):
				var c := origin + Vector2((ix + 0.5) * CELL, (iy + 0.5) * CELL)
				if c.distance_to(at) < lim:
					astar.set_point_solid(Vector2i(ix, iy), true)


## The cell index a cell-space coordinate falls in, clamped to the grid (floor, so a negative one is not
## rounded toward zero).
func _index(u: float, count: int) -> int:
	return clampi(int(floor(u)), -1, count)


func cell_of(p: Vector2) -> Vector2i:
	var rel := (p - origin) / CELL
	return Vector2i(clampi(int(floor(rel.x)), 0, size.x - 1), clampi(int(floor(rel.y)), 0, size.y - 1))


## The nearest walkable cell to `c` within a small ring, or `c` itself.
func _free_cell(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 5):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n := Vector2i(clampi(c.x + dx, 0, size.x - 1), clampi(c.y + dy, 0, size.y - 1))
				if not astar.is_point_solid(n):
					return n
	return c


## Waypoints (cell centres) from `a` to `b`; empty when there is no route.
func path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca := _free_cell(cell_of(a))
	var cb := _free_cell(cell_of(b))
	if astar.is_point_solid(ca) or astar.is_point_solid(cb):
		return PackedVector2Array()
	return astar.get_point_path(ca, cb)
