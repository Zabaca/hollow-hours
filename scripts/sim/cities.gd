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
