class_name Cities
extends RefCounted
## The cities the game has, by id: each one's layout (the data SimWorld reads; its shape is written at
## the top of scripts/sim/sim_world.gd) and its model. One city is loaded at a time. The story's places
## and missions name their city by these ids (StoryData), and the game scene loads the one the story is
## in. A new city is one more branch in each function here, one id in IDS, and its own generated
## layout and model.

const QUARTER := "quarter"
const HARBOUR := "harbour"
const IDS := [QUARTER, HARBOUR]


static func has(id: String) -> bool:
	return id in IDS


## The city's layout dictionary (CityLayout.DATA for the quarter).
static func layout(id: String) -> Dictionary:
	match id:
		QUARTER:
			return CityLayout.DATA
		HARBOUR:
			return HarbourLayout.DATA
	push_error("Cities.layout: no city called '%s'" % id)
	return {}


## The city's model, a glTF scene.
static func model_path(id: String) -> String:
	match id:
		QUARTER:
			return "res://assets/models/city.glb"
		HARBOUR:
			return "res://assets/cities/harbour_city.glb"
	push_error("Cities.model_path: no city called '%s'" % id)
	return ""


## The cities that show a route to the objective on the radar and the full map, and widen the radar with speed (the
## quarter is too small for either, and chapter 1 stays as it was), with the car's own path grid for each: 1 m cells, the car's
## half width plus a hand's breadth, and a halo that keeps a route to the middle of a gap (a 2 m grid with a wide berth
## cannot see a 4 m squeeze). {} for a city with none.
const ROUTE_GRIDS := {
	"harbour": {"clearance": 1.0, "cell": 1.0, "halo": 3.0},
}


static func route_grid(id: String) -> Dictionary:
	return ROUTE_GRIDS.get(id, {})
