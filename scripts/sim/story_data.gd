class_name StoryData
extends RefCounted
## The story as constant data: the places, the radio script and the three missions. Tuning a
## timer, a hold or a line never touches logic; MissionSim reads this and nothing else.
##
## A step has a `kind`, one of:
##   reach   {place}                 drive into the place's marker
##   hold    {place, seconds}        stay in the marker under 2 m/s; progress pauses when you leave
##   kill    {count, place?}         run down `count` Gaunts (run-downs and fatal throws since the step began)
##   survive {seconds}               stay alive
##   gate    {place}                 reach the gate's trigger while it is open: the escape
## and optionally `text` (the objective line), `radius` (instead of the place's), and the effects
## `begin`, `during` ([{t, ...}], t in seconds into a hold or survive, else into the step) and `end`.
##
## An effect is a dictionary with any of:
##   lines [id]                      radio lines to play
##   pack n                          the pack's size from now on
##   alert {place, radius} | {all}   alert every Gaunt within radius of a place, or all of them
##   spawn [{place, count, ring}]    Gaunts placed `ring` metres from a place, already hunting
##   timer {id, seconds, reason, label}   start a timer; it fails the mission with `reason` at zero
##   stop_timer id
##   gate "open"
##   checkpoint true                 (end only) the next step is a checkpoint
##   escape true                     (end only) the car drives out through the gate
##
## Places are map metres read from the city layout; tests/mission_test.gd is the arbiter (inside
## the arena, clear of everything, reachable on the path grid).

const SPEAKERS := {
	"vera": {"name": "Vera", "color": Color(0.21, 1.0, 0.88)},
	"teo": {"name": "Teo", "color": Color(1.0, 0.65, 0.11)},
	"ruck": {"name": "Ruck", "color": Color(0.72, 0.5, 0.5)},
}

## `label` is the name on the full map; `angle` is the heading a car placed there faces. A place
## with `marker: false` is only a name on the map.
const PLACES := {
	"safe_start": {"name": "the safe start", "pos": Vector2(-30.0, -2.5), "radius": 5.0, "angle": 0.0, "label": "", "marker": false},
	"shop": {"name": "the 24-hour shop", "pos": Vector2(46.0, 7.0), "radius": 5.0, "angle": -PI / 2.0, "label": "24H", "marker": true},
	"hotel": {"name": "the hotel's east door", "pos": Vector2(60.0, -16.0), "radius": 5.0, "angle": PI / 2.0, "label": "Hotel", "marker": true},
	"hut": {"name": "the park hut", "pos": Vector2(-32.0, -9.0), "radius": 5.0, "angle": PI / 2.0, "label": "Park", "marker": true},
	"pharmacy": {"name": "the pharmacy", "pos": Vector2(-44.0, 4.0), "radius": 5.0, "angle": 0.0, "label": "Pharmacy", "marker": true},
	"west_gate": {"name": "the west gate", "pos": Vector2(-70.0, 0.0), "radius": 6.0, "angle": PI, "label": "West Gate", "marker": true},
	"diner": {"name": "the diner", "pos": Vector2(-20.5, 16.0), "radius": 0.0, "angle": 0.0, "label": "Diner", "marker": false},
	"motel": {"name": "the motel", "pos": Vector2(-20.5, 31.5), "radius": 0.0, "angle": 0.0, "label": "Motel", "marker": false},
	"bar": {"name": "the bar", "pos": Vector2(19.0, -24.0), "radius": 0.0, "angle": 0.0, "label": "Bar", "marker": false},
	"pawn": {"name": "the pawn shop", "pos": Vector2(42.5, -32.0), "radius": 0.0, "angle": 0.0, "label": "Pawn", "marker": false},
}

## The radio script, 21 lines. `text` carries the cue words in square brackets (they steer the
## voice and are neither spoken nor shown); subtitle() strips them.
const LINES := {
	"bat_call_1": {"speaker": "vera", "text": "[low, steady voice] Red car on the avenue. Yes, you. Keep moving. They come for anything that sits still."},
	"bat_call_2": {"speaker": "vera", "text": "I'm on the hotel roof and my radio's dying. The all-night shop at the gas station has a box of batteries. Bring it to me."},
	"bat_shop": {"speaker": "vera", "text": "Pull up to the south door and hold still. Count to four."},
	"bat_alarm": {"speaker": "vera", "text": "[urgent] That's the door alarm. Sorry. Hold on, hold on!"},
	"bat_loaded": {"speaker": "vera", "text": "Got it. Hotel, east door. I'll lower a rope."},
	"bat_done": {"speaker": "vera", "text": "[relieved] Lights are back. And Red, someone else is on this band, near the park hut. Get close and I'll patch them through."},
	"ph_call_1": {"speaker": "teo", "text": "[whispering, scared] Hello? This is Teo, at the pharmacy. They're scratching at the shutter. It won't hold long."},
	"ph_call_2": {"speaker": "vera", "text": "Hang on, Teo. Red, the pharmacy tower, north side of the avenue. Hurry."},
	"ph_door": {"speaker": "teo", "text": "[shouting] Two of them at the shutter! Run them down!"},
	"ph_cleared": {"speaker": "teo", "text": "Okay, okay. Stop by the door, I'm coming out."},
	"ph_aboard": {"speaker": "teo", "text": "[breathless] I'm in. Drive!"},
	"ph_done": {"speaker": "vera", "text": "Teo's safe up here. If anyone outside can hear us, it's through the gas station's aerial."},
	"ph_failed": {"speaker": "teo", "text": "[screaming] They're through the shutter!"},
	"gate_call_1": {"speaker": "ruck", "text": "[flat, tired voice] Unknown vehicle, this is the cordon. We open the west gate once, at the end of the avenue. At first light we burn the quarter."},
	"gate_call_2": {"speaker": "vera", "text": "We're coming with you. Hotel, east door. Both of us."},
	"gate_aboard": {"speaker": "ruck", "text": "Gate opens in sixty seconds. Keep moving. The whole quarter can hear you now."},
	"gate_open": {"speaker": "ruck", "text": "Gate's open. Twenty seconds."},
	"gate_failed": {"speaker": "ruck", "text": "Gate's shut. I'm sorry."},
	"end_vera": {"speaker": "vera", "text": "[quiet] Look at that, Red. First light."},
	"end_ruck": {"speaker": "ruck", "text": "Vehicle is out. Seal it."},
	"wrecked": {"speaker": "vera", "text": "[afraid] Red? Red, answer me."},
}

## Why a mission can fail: the text on the fail screen and the line that plays.
const REASONS := {
	"wrecked": {"text": "The car was wrecked.", "line": "wrecked"},
	"shutter": {"text": "The shutter gave way before Teo was in the car.", "line": "ph_failed"},
	"gate": {"text": "The gate closed before you reached it.", "line": "gate_failed"},
}

const MISSIONS := [
	{
		"id": "batteries", "title": "BATTERIES", "start": "", "dawn": 0.0,
		"begin": {"lines": ["bat_call_1", "bat_call_2"], "pack": 3},
		"end": {"lines": ["bat_done"]},
		"steps": [
			{"id": "reach_shop", "kind": "reach", "place": "shop", "text": "Drive to the 24-hour shop at the gas station"},
			{
				"id": "load", "kind": "hold", "place": "shop", "seconds": 4.0,
				"text": "Hold still at the shop's south door while the box is loaded",
				"begin": {"lines": ["bat_shop"]},
				"during": [{"t": 1.0, "lines": ["bat_alarm"], "alert": {"place": "shop", "radius": 90.0}, "pack": 4}],
				"end": {"lines": ["bat_loaded"], "checkpoint": true},
			},
			{"id": "deliver", "kind": "hold", "place": "hotel", "seconds": 3.0, "text": "Take the box to the hotel's east door and hold still"},
		],
	},
	{
		"id": "pharmacist", "title": "THE PHARMACIST", "start": "hut", "dawn": 0.1,
		"begin": {
			"lines": ["ph_call_1", "ph_call_2"], "pack": 4,
			"timer": {"id": "shutter", "seconds": 120.0, "reason": "shutter", "label": "SHUTTER"},
		},
		"end": {"lines": ["ph_done"]},
		"steps": [
			{"id": "reach_pharmacy", "kind": "reach", "place": "pharmacy", "text": "Drive to the pharmacy tower on the avenue"},
			{
				"id": "clear", "kind": "kill", "count": 2, "place": "pharmacy", "text": "Run down the Gaunts at the shutter",
				"begin": {"lines": ["ph_door"], "spawn": [{"place": "pharmacy", "count": 2, "ring": 8.0}]},
			},
			{
				"id": "load_teo", "kind": "hold", "place": "pharmacy", "seconds": 3.0, "text": "Stop at the door while Teo gets in",
				"begin": {"lines": ["ph_cleared"]},
				"end": {"lines": ["ph_aboard"], "stop_timer": "shutter", "checkpoint": true},
			},
			{"id": "deliver", "kind": "hold", "place": "hotel", "seconds": 3.0, "text": "Take Teo to the hotel's east door"},
		],
	},
	{
		"id": "west_gate", "title": "WEST GATE", "start": "shop", "dawn": 0.2,
		"begin": {"lines": ["gate_call_1", "gate_call_2"], "pack": 4},
		"end": {},
		"steps": [
			{
				"id": "pickup", "kind": "hold", "place": "hotel", "seconds": 4.0, "text": "Pick up Vera and Teo at the hotel's east door",
				"end": {"lines": ["gate_aboard"], "pack": 6, "alert": {"all": true}, "checkpoint": true},
			},
			{"id": "hold_out", "kind": "survive", "seconds": 60.0, "text": "Stay alive until the gate opens"},
			{
				"id": "run", "kind": "gate", "place": "west_gate", "text": "Reach the west gate",
				"begin": {
					"lines": ["gate_open"], "gate": "open",
					"timer": {"id": "gate", "seconds": 20.0, "reason": "gate", "label": "GATE"},
				},
				"end": {"lines": ["end_vera", "end_ruck"], "stop_timer": "gate", "escape": true},
			},
		],
	},
]

## The sky's lightening once the story is over, for free roam after the last mission.
const ENDING_DAWN := 0.3


static func mission_index(id: String) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i]["id"] == id:
			return i
	return -1


static func place_pos(id: String) -> Vector2:
	return PLACES[id]["pos"]


static func place_radius(id: String) -> float:
	return float(PLACES[id]["radius"])


## What is spoken and shown: the text without its [cue words].
static func subtitle(id: String) -> String:
	var text: String = LINES[id]["text"]
	var out := ""
	var depth := 0
	for ch in text:
		if ch == "[":
			depth += 1
		elif ch == "]":
			depth = maxi(0, depth - 1)
		elif depth == 0:
			out += ch
	return out.strip_edges()


## How long a subtitle stays up when its audio does not exist yet (14 characters a second, at least 2).
static func reading_time(id: String) -> float:
	return maxf(2.0, float(subtitle(id).length()) / 14.0)


## Every line id a mission, step or effect names, for the test that none is missing.
static func line_ids_used() -> Array:
	var out: Array = []
	for m in MISSIONS:
		_collect_lines(m.get("begin", {}), out)
		_collect_lines(m.get("end", {}), out)
		for s in m["steps"]:
			_collect_lines(s.get("begin", {}), out)
			_collect_lines(s.get("end", {}), out)
			for d in s.get("during", []):
				_collect_lines(d, out)
	for r in REASONS.values():
		out.append(r["line"])
	return out


static func _collect_lines(fx: Dictionary, out: Array) -> void:
	for id in fx.get("lines", []):
		out.append(id)
