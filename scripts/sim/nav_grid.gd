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
	for ix in size.x:
		for iy in size.y:
			var c := origin + Vector2((ix + 0.5) * CELL, (iy + 0.5) * CELL)
			var blocked := false
			for b in world.boxes:
				if c.x > b["x0"] - clearance - CELL * 0.4 and c.x < b["x1"] + clearance + CELL * 0.4 and c.y > b["y0"] - clearance - CELL * 0.4 and c.y < b["y1"] + clearance + CELL * 0.4:
					blocked = true
					break
			if not blocked:
				for p in world.posts:
					if c.distance_to(Vector2(p["x"], p["y"])) < float(p["r"]) + clearance + CELL * 0.3:
						blocked = true
						break
			if blocked:
				astar.set_point_solid(Vector2i(ix, iy), true)


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
