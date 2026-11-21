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
##   spawn [{place, count, ring, clear?, bearings?}]   Gaunts placed `ring` metres from a place, already
##                                   hunting, at least `clear` (default 6) metres from the car. `bearings`
##                                   (radians, map angle) says where round the place each one stands; the
##                                   pharmacy's two are down the avenue to its west, so a car arriving from
##                                   the east has a straight run at them
##   sound "name"                    a sound effect (assets/audio/<name>) played when the effect runs
##   ambush {route: [a, b], max?}    arm the layout's ambush spots beside the car's route from place a to place b
##                                   (at most `max`, default AMBUSH_MAX, kept apart along it, none at its ends): two or
##                                   three creatures wait in the dark and are placed, hunting, when the car comes within
##                                   AMBUSH_RELEASE metres. Cities with no route grid (the quarter) have none.
##   stalled true                    arm the city layout's stalled-car hunters: each waits in its car and is
##                                   placed, already hunting, when the car comes within its `release` distance
##   timer {id, seconds, reason, label}   start a timer; it fails the mission with `reason` at zero
##   stop_timer id
##   bridge "down"                   lower the harbour city's lift bridge (its colliders leave the world; it rises again, and
##                                   the colliders return, when a mission starts or fails)
##   gate "open"
##   checkpoint true                 (end only) the next step is a checkpoint
##   escape true                     (end only) the car drives out through the gate
##
## Places are map metres read from the city layout; tests/mission_test.gd is the arbiter (inside
## the arena, clear of everything, reachable on the path grid).
##
## Cities. Every place and every mission names its city (`city`, an id Cities knows), and a mission's
## places are all in its own city. A chapter is a run of missions in one city; `safe: true` marks a
## city's safe start (where a New Game, a Continue or a restart puts the car when the mission names no
## start place of its own). The functions below read missions through a `missions` argument that
## defaults to MISSIONS, so tests can hold a longer story (chapter 2) up against the same code.

const SPEAKERS := {
	"vera": {"name": "Vera", "color": Color(0.21, 1.0, 0.88)},
	"teo": {"name": "Teo", "color": Color(1.0, 0.65, 0.11)},
	"ruck": {"name": "Ruck", "color": Color(0.72, 0.5, 0.5)},
}

## `label` is the name on the full map; `angle` is the heading a car placed there faces. A place
## with `marker: false` is only a name on the map (the diner, bar and pawn shop sit at their
## buildings' centres in tools/blender/city.py).
##
## Every leg of the story is a cross-town drive, 90 m or more in a straight line, the start of each
## mission to its first step included (the hotel in the east and the pharmacy and gate in the west
## fix the geometry, so each mission alternates sides; tests/mission_test.gd pins it):
##   1 BATTERIES      safe start (64, 0) -> motel office 94 m -> hotel 99 m
##   2 THE PHARMACIST gas station 90 m -> pharmacy 106 m -> hotel
##   3 WEST GATE      park hut 92 m -> hotel 92 m -> west gate 131 m
## Between missions the lit start is 27 m from the hotel after mission 1 (the gas station) and 92 m after
## mission 2 (the park hut): the pharmacy and the hotel are buildings, so the gap cannot be wider.
const PLACES := {
	"safe_start": {"name": "the safe start", "pos": Vector2(64.0, 0.0), "radius": 5.0, "angle": PI, "label": "", "city": "quarter", "marker": false, "safe": true},
	"shop": {"name": "the gas station", "pos": Vector2(46.0, 7.0), "radius": 5.0, "angle": -PI / 2.0, "label": "24H", "city": "quarter", "marker": true},
	"hotel": {"name": "the hotel's east door", "pos": Vector2(60.0, -16.0), "radius": 5.0, "angle": PI / 2.0, "label": "Hotel", "city": "quarter", "marker": true},
	"hut": {"name": "the park hut", "pos": Vector2(-32.0, -9.0), "radius": 5.0, "angle": PI / 2.0, "label": "Park", "city": "quarter", "marker": true},
	"pharmacy": {"name": "the pharmacy", "pos": Vector2(-44.0, 4.0), "radius": 5.0, "angle": 0.0, "label": "Pharmacy", "city": "quarter", "marker": true},
	"west_gate": {"name": "the west gate", "pos": Vector2(-70.0, 0.0), "radius": 6.0, "angle": PI, "label": "West Gate", "city": "quarter", "marker": true},
	"diner": {"name": "the diner", "pos": Vector2(-20.5, 16.0), "radius": 0.0, "angle": 0.0, "label": "Diner", "city": "quarter", "marker": false},
	"motel": {"name": "the motel office", "pos": Vector2(-20.5, 41.5), "radius": 5.0, "angle": PI, "label": "Motel", "city": "quarter", "marker": true},
	"bar": {"name": "the bar", "pos": Vector2(19.0, -24.0), "radius": 0.0, "angle": 0.0, "label": "Bar", "city": "quarter", "marker": false},
	"pawn": {"name": "the pawn shop", "pos": Vector2(42.5, -32.0), "radius": 0.0, "angle": 0.0, "label": "Pawn", "city": "quarter", "marker": false},
	# The harbour city (chapter 2). Its map is one rectangle: the city in the west and, running out of its east
	# side, the divided highway the chapter opens on. `highway_start` is the cordon's checkpoint at the far end
	# (the layout's player start). tests/harbour_test.gd measures every leg on the path grid.
	"highway_start": {"name": "the highway checkpoint", "pos": Vector2(1379.0, 11.5), "radius": 8.0, "angle": PI, "label": "", "city": "harbour", "marker": false, "safe": true},
	"toll_plaza": {"name": "the toll plaza", "pos": Vector2(1244.5, 8.5), "radius": 16.0, "angle": PI, "label": "Toll Plaza", "city": "harbour", "marker": true},
	"jam": {"name": "the stalled traffic", "pos": Vector2(1127.5, 8.5), "radius": 18.0, "angle": PI, "label": "Traffic", "city": "harbour", "marker": true},
	"truck_stop": {"name": "the truck stop", "pos": Vector2(650.5, 20.5), "radius": 28.0, "angle": PI, "label": "Truck Stop", "city": "harbour", "marker": true},
	"convoy_call": {"name": "the east ring road", "pos": Vector2(171.5, -3.5), "radius": 12.0, "angle": PI, "label": "East Ring", "city": "harbour", "marker": true},
	# Chapter 2's other places, at the coordinates tools/blender/harbour_plan.py plans them (the layout's `places` agree;
	# tests/harbour_test.gd checks each is clear and reachable and measures every leg by road).
	"ruck_truck": {"name": "Ruck's truck", "pos": Vector2(-180.0, 140.0), "radius": 10.0, "angle": 0.0, "label": "Ruck", "city": "harbour", "marker": true},
	"field_hospital": {"name": "the field hospital", "pos": Vector2(190.0, -91.5), "radius": 12.0, "angle": PI, "label": "Hospital", "city": "harbour", "marker": true},
	"fuel_depot": {"name": "the fuel depot", "pos": Vector2(-170.0, -92.5), "radius": 10.0, "angle": 0.0, "label": "Depot", "city": "harbour", "marker": true},
	"post_north": {"name": "the north generator post", "pos": Vector2(148.0, 140.5), "radius": 9.0, "angle": PI, "label": "North Post", "city": "harbour", "marker": true},
	"post_centre_west": {"name": "the west generator post", "pos": Vector2(-160.0, 3.5), "radius": 9.0, "angle": 0.0, "label": "West Post", "city": "harbour", "marker": true},
	"post_east": {"name": "the east generator post", "pos": Vector2(190.0, -36.0), "radius": 9.0, "angle": -PI / 2.0, "label": "East Post", "city": "harbour", "marker": true},
	"lift_gate": {"name": "the far bank", "pos": Vector2(-199.0, -144.0), "radius": 6.0, "angle": PI, "label": "Lift Bridge", "city": "harbour", "marker": true, "needs_bridge": true},
	"control_house": {"name": "the lift bridge's control house", "pos": Vector2(-112.0, -140.5), "radius": 10.0, "angle": PI, "label": "Control House", "city": "harbour", "marker": true},
}

## The radio script, 21 lines. `text` carries the cue words in square brackets (they steer the
## voice and are neither spoken nor shown); subtitle() strips them.
const LINES := {
	"bat_call_1": {"speaker": "vera", "text": "[low, steady voice] Red car on the avenue. Yes, you. Keep moving. They come for anything that sits still."},
	"bat_call_2": {"speaker": "vera", "text": "I'm on the hotel roof and my radio's dying. The motel office has a box of batteries. Bring it to me."},
	"bat_shop": {"speaker": "vera", "text": "Pull up to the office door and hold still. Count to four."},
	"bat_alarm": {"speaker": "vera", "text": "[urgent] That's the door alarm. Sorry. Hold on, hold on!"},
	"bat_loaded": {"speaker": "vera", "text": "Got it. Hotel, east door. I'll lower a rope."},
	"bat_done": {"speaker": "vera", "text": "[relieved] Lights are back. And Red, someone else is on this band, near the gas station. Get close and I'll patch them through."},
	"ph_call_1": {"speaker": "teo", "text": "[whispering, scared] Hello? This is Teo, at the pharmacy. They're scratching at the shutter. It won't hold long."},
	"ph_call_2": {"speaker": "vera", "text": "Hang on, Teo. Red, the pharmacy tower, north side of the avenue. Hurry."},
	"ph_door": {"speaker": "teo", "text": "[shouting] Two of them at the shutter! Run them down!"},
	"ph_cleared": {"speaker": "teo", "text": "Okay, okay. Stop by the door, I'm coming out."},
	"ph_aboard": {"speaker": "teo", "text": "[breathless] I'm in. Drive!"},
	"ph_done": {"speaker": "vera", "text": "Teo's safe up here. If anyone outside can hear us, it's through the park hut's aerial."},
	"ph_failed": {"speaker": "teo", "text": "[screaming] They're through the shutter!"},
	"gate_call_1": {"speaker": "ruck", "text": "[flat, tired voice] Unknown vehicle, this is the cordon. We open the west gate once, at the end of the avenue. At first light we burn the quarter."},
	"gate_call_2": {"speaker": "vera", "text": "We're coming with you. Hotel, east door. Both of us."},
	"gate_aboard": {"speaker": "ruck", "text": "Gate opens in sixty seconds. Keep moving. The whole quarter can hear you now."},
	"gate_open": {"speaker": "ruck", "text": "Gate's open. Twenty seconds."},
	"gate_failed": {"speaker": "ruck", "text": "Gate's shut. I'm sorry."},
	"end_vera": {"speaker": "vera", "text": "[quiet] Look at that, Red. First light."},
	"end_ruck": {"speaker": "ruck", "text": "Vehicle is out. Seal it."},
	"wrecked": {"speaker": "vera", "text": "[afraid] Red? Red, answer me."},
	# Chapter 2, The Long Road.
	"lr_call_1": {"speaker": "vera", "text": "[urgent] Red, the checkpoint's falling. Don't stop for anything. Drive the highway into the city, the convoy's last call came from the east ring road."},
	"lr_call_2": {"speaker": "teo", "text": "[whispering] Something is moving in the stalled cars. Please keep your lights on the road."},
	"lr_jam": {"speaker": "vera", "text": "Dead traffic ahead, both ways. There's a gap in it. Slow down and find it."},
	"lr_overpass": {"speaker": "teo", "text": "[afraid] The overpass came down across the road. There's a truck stop beside it. Go round through the lot."},
	"lr_done": {"speaker": "ruck", "text": "[flat, tired voice] I see headlights on the ring road. Is that you, Red? Stay where you are. Do not stop for anyone but us."},
	# Chapter 2, Dead Convoy.
	"dc_call_1": {"speaker": "vera", "text": "[tired, steady] Red, you made it. Ruck's truck went off the north ring road at dusk, on the far side of the river. He's alive, on a dying handset."},
	"dc_call_2": {"speaker": "ruck", "text": "[hoarse, in pain] On my side by the north wall. Take a bridge and mind the barricades. They wait beside the barricades, Red."},
	"dc_hold": {"speaker": "ruck", "text": "[grunting] I see your lights. Stay still. My leg is under the cab."},
	"dc_aboard": {"speaker": "ruck", "text": "[breathless] I'm in. The school, south-east. Teo will be at the door. Drive."},
	"dc_done": {"speaker": "vera", "text": "[relieved] Teo has him. Stay close to the school, Red. The floodlights are all that keeps them off us."},
	# Floodlights.
	"fl_call_1": {"speaker": "vera", "text": "[urgent] The generators under the floodlights are failing. When the lights go out, the pack comes in through the school door."},
	"fl_call_2": {"speaker": "teo", "text": "[quick, quiet] There are drums at the fuel depot on the west docks. Then three generator posts: north, west of the centre, and the east ring. Please hurry."},
	"fl_load": {"speaker": "vera", "text": "[low] Stop at the depot gate and wait. The drums are by the tanks. Don't leave the engine running long."},
	"fl_loaded": {"speaker": "vera", "text": "[steady] The drums are in. Three posts, the north ring first. I can see the lights from the roof, Red, and they are getting yellow."},
	"fl_post_1": {"speaker": "teo", "text": "[breathless] The north generator's running. The one west of the centre next."},
	"fl_post_2": {"speaker": "vera", "text": "[tight] Two of three. The last post is on the east ring, by the corner."},
	"fl_done": {"speaker": "vera", "text": "[relieved] All three are burning. The school is lit like a ship. Come back for us."},
	"fl_failed": {"speaker": "teo", "text": "[screaming] The lights have gone out! They're at the door!"},
	# The Lift Bridge, up to the control house.
	"lb_call_1": {"speaker": "vera", "text": "[heavy] Red. The only road out is the lift bridge at the harbour mouth, and it is raised. Ruck says the control house is on the east bank."},
	"lb_call_2": {"speaker": "ruck", "text": "[flat, tired voice] Bring the car to the school door. All of us go, or none. Teo can work the lift."},
	"lb_aboard": {"speaker": "teo", "text": "[breathless] We're in, all three of us. South-west, along the harbour. Mind the bridges."},
	"lb_arrive": {"speaker": "ruck", "text": "[flat] That's the control house. Stop at the door and hold. Teo's going in."},
	"lb_work": {"speaker": "teo", "text": "[muffled, strained] The motor is dead. I'm on the manual lever. Don't move the car."},
	"lb_end": {"speaker": "teo", "text": "[panting] It's turning. Stay exactly where you are, Red. It takes a minute."},
	"lb_hold": {"speaker": "vera", "text": "[urgent] They heard the motor. Hold still, Red. We can't move until it's down."},
	"lb_down": {"speaker": "teo", "text": "[shouting over a motor] It's coming down! Go the moment it touches, I can't keep it there!"},
	"lb_failed": {"speaker": "ruck", "text": "[flat] It's rising. We don't cross tonight."},
	"lb_end_1": {"speaker": "vera", "text": "[quiet] Look at that, Red. First light, on the far bank."},
	"lb_end_2": {"speaker": "ruck", "text": "[flat, then softer] Vehicle is across. Nobody tell the cordon. Stop the engine and let the sun find us."},
}

## Lines that have no audio file yet: the radio shows their subtitles for their reading time. Empty now that every line is
## voiced; a line added without its voice goes here until it is bought (radio_test wants every other line to have its file).
const UNVOICED := []

## Why a mission can fail: the text on the fail screen and the line that plays.
const REASONS := {
	"wrecked": {"text": "The car was wrecked.", "line": "wrecked"},
	"shutter": {"text": "The shutter gave way before Teo was in the car.", "line": "ph_failed"},
	"gate": {"text": "The gate closed before you reached it.", "line": "gate_failed"},
	"floodlights": {"text": "The floodlights went out before the last generator was fuelled.", "line": "fl_failed"},
	"bridge": {"text": "The bridge lifted before you were across.", "line": "lb_failed"},
}

const MISSIONS := [
	{
		"id": "batteries", "title": "BATTERIES", "city": "quarter", "start": "", "dawn": 0.0,
		"begin": {"lines": ["bat_call_1", "bat_call_2"], "pack": 3},
		"end": {"lines": ["bat_done"]},
		"steps": [
			{"id": "reach_motel", "kind": "reach", "place": "motel", "text": "Drive to the motel office on the north road"},
			{
				"id": "load", "kind": "hold", "place": "motel", "seconds": 4.0,
				"text": "Hold still at the motel office door while the box is loaded",
				"begin": {"lines": ["bat_shop"]},
				"during": [{"t": 1.0, "lines": ["bat_alarm"], "alert": {"place": "motel", "radius": 90.0}, "pack": 4}],
				"end": {"lines": ["bat_loaded"], "checkpoint": true},
			},
			{"id": "deliver", "kind": "hold", "place": "hotel", "seconds": 3.0, "text": "Take the box to the hotel's east door and hold still"},
		],
	},
	{
		"id": "pharmacist", "title": "THE PHARMACIST", "city": "quarter", "start": "shop", "dawn": 0.1,
		"begin": {
			"lines": ["ph_call_1", "ph_call_2"], "pack": 4,
			"timer": {"id": "shutter", "seconds": SHUTTER_SECONDS, "reason": "shutter", "label": "SHUTTER"},
		},
		"end": {"lines": ["ph_done"]},
		"steps": [
			{"id": "reach_pharmacy", "kind": "reach", "place": "pharmacy", "text": "Drive to the pharmacy tower on the avenue"},
			{
				"id": "clear", "kind": "kill", "count": 2, "place": "pharmacy", "text": "Run down the Gaunts at the shutter",
				"begin": {"lines": ["ph_door"], "spawn": [{"place": "pharmacy", "count": 1, "ring": 13.0, "bearings": [3.4]}]},
				"during": [{"t": 9.0, "spawn": [{"place": "pharmacy", "count": 1, "ring": 13.0, "bearings": [2.9]}]}],
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
		"id": "west_gate", "title": "WEST GATE", "city": "quarter", "start": "hut", "dawn": 0.2,
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
	# Chapter 2. `closes_story: false` keeps the story going in free roam when this is the last mission in the list
	# (the rest of the chapter is built in later slices).
	{
		"id": "long_road", "title": "THE LONG ROAD", "city": "harbour", "start": "", "dawn": 0.0, "closes_story": false,
		"begin": {"lines": ["lr_call_1", "lr_call_2"], "pack": 2, "stalled": true},
		"end": {"lines": ["lr_done"]},
		"steps": [
			{"id": "toll", "kind": "reach", "place": "toll_plaza", "text": "Drive the highway into the city: through the toll plaza", "end": {"lines": ["lr_jam"]}},
			{"id": "jam", "kind": "reach", "place": "jam", "text": "Find the gap in the stalled traffic", "end": {"lines": ["lr_overpass"]}},
			{"id": "overpass", "kind": "reach", "place": "truck_stop", "text": "The overpass is down: go round through the truck stop"},
			{"id": "city", "kind": "reach", "place": "convoy_call", "text": "Drive on to the east ring road"},
		],
	},
	{
		"id": "dead_convoy", "title": "DEAD CONVOY", "city": "harbour", "start": "convoy_call", "resume_at": "convoy_call", "dawn": 0.0,
		"begin": {"lines": ["dc_call_1", "dc_call_2"], "pack": 3, "ambush": {"route": ["convoy_call", "ruck_truck"]}},
		"end": {"lines": ["dc_done"]},
		"steps": [
			{"id": "reach_truck", "kind": "reach", "place": "ruck_truck", "text": "Drive to Ruck's truck on the north ring road"},
			{
				"id": "drag", "kind": "hold", "place": "ruck_truck", "seconds": 5.0, "text": "Hold still while Ruck drags himself in",
				"begin": {"lines": ["dc_hold"]},
				"end": {"lines": ["dc_aboard"], "checkpoint": true, "ambush": {"route": ["ruck_truck", "field_hospital"]}},
			},
			{"id": "deliver", "kind": "hold", "place": "field_hospital", "seconds": 3.0, "text": "Bring Ruck to the field hospital"},
		],
	},
	{
		"id": "floodlights", "title": "FLOODLIGHTS", "city": "harbour", "start": "field_hospital", "resume_at": "field_hospital", "dawn": 0.05,
		"begin": {
			"lines": ["fl_call_1", "fl_call_2"], "pack": 3, "ambush": {"route": ["field_hospital", "fuel_depot"]},
			"timer": {"id": "floodlights", "seconds": FLOODLIGHT_SECONDS, "reason": "floodlights", "label": "FLOODLIGHTS"},
		},
		"end": {"lines": ["fl_done"]},
		"steps": [
			{"id": "reach_depot", "kind": "reach", "place": "fuel_depot", "text": "Drive to the fuel depot on the west docks"},
			{
				"id": "load", "kind": "hold", "place": "fuel_depot", "seconds": 4.0, "text": "Hold still at the depot gate while the drums are loaded",
				"begin": {"lines": ["fl_load"]},
				"end": {"lines": ["fl_loaded"], "checkpoint": true, "ambush": {"route": ["fuel_depot", "post_north"]}},
			},
			{
				"id": "post_1", "kind": "hold", "place": "post_north", "seconds": 3.0, "text": "Fuel the generator at the north post",
				"begin": {"sound": "generator_start"},
				"end": {"lines": ["fl_post_1"], "ambush": {"route": ["post_north", "post_centre_west"]}},
			},
			{
				"id": "post_2", "kind": "hold", "place": "post_centre_west", "seconds": 3.0, "text": "Fuel the generator west of the centre",
				"begin": {"sound": "generator_start"},
				"end": {"lines": ["fl_post_2"], "ambush": {"route": ["post_centre_west", "post_east"]}},
			},
			{
				"id": "post_3", "kind": "hold", "place": "post_east", "seconds": 3.0, "text": "Fuel the generator at the east post",
				"begin": {"sound": "generator_start"}, "end": {"stop_timer": "floodlights"},
			},
		],
	},
	# The Lift Bridge: pick up the others, drive to the control house, hold out while Teo brings the bridge down, cross it
	# before it lifts again and drive out of the far bank's gate into first light. The last mission: it closes the story.
	{
		"id": "lift_bridge", "title": "THE LIFT BRIDGE", "city": "harbour", "start": "field_hospital", "resume_at": "field_hospital", "dawn": 0.1,
		"begin": {"lines": ["lb_call_1", "lb_call_2"], "pack": 4},
		"end": {},
		"steps": [
			{
				"id": "pickup", "kind": "hold", "place": "field_hospital", "seconds": 4.0, "text": "Pick up Vera, Teo and Ruck at the hospital door",
				"end": {"lines": ["lb_aboard"], "checkpoint": true, "ambush": {"route": ["field_hospital", "control_house"]}},
			},
			{"id": "drive", "kind": "reach", "place": "control_house", "text": "Drive to the lift bridge's control house on the harbour road"},
			{
				"id": "work", "kind": "hold", "place": "control_house", "seconds": BRIDGE_HOLD_SECONDS, "text": "Hold out while Teo works the lift",
				"begin": {"lines": ["lb_arrive"]},
				"during": [{"t": 2.0, "lines": ["lb_work"]}, {"t": 5.0, "lines": ["lb_hold"], "alert": {"all": true}, "pack": 5}],
				"end": {"lines": ["lb_end"], "checkpoint": true},
			},
			{
				"id": "cross", "kind": "gate", "place": "lift_gate", "text": "Cross the bridge before it rises",
				"begin": {
					"lines": ["lb_down"], "bridge": "down", "gate": "open",
					"timer": {"id": "bridge", "seconds": BRIDGE_SECONDS, "reason": "bridge", "label": "BRIDGE"},
				},
				"end": {"lines": ["lb_end_1", "lb_end_2"], "stop_timer": "bridge", "escape": true},
			},
		],
	},
]

## The card shown at the start of each chapter after the first: "Chapter N" over its title.
const CHAPTER_TITLES := ["The quarter", "The next night"]

## Tuning numbers MissionSim reads.
## How long Teo can hold the shutter, from the call until he is in the car: long enough for a driver to run down
## two creatures that fight back and still have time to spare (tests/mission_test.gd drives it with creatures live).
const SHUTTER_SECONDS := 180.0
## How long the floodlights hold, from the call to the last generator: the legs run 1.8 km by road (tests/harbour_test.gd
## drives it with the autopilot and wants spare time).
const FLOODLIGHT_SECONDS := 360.0
## The Lift Bridge: how long the car holds still at the control house while Teo works the lift, and how long the bridge
## stays down once it is (the way to the gate from the control house is 83 m).
const BRIDGE_HOLD_SECONDS := 14.0
const BRIDGE_SECONDS := 45.0
## Ambushes (effect `ambush`): at most this many on a leg, placed when the car comes this close; and how many spots are
## armed at random in free roam so that a known route is not a safe one.
const AMBUSH_MAX := 2
const AMBUSH_RELEASE := 35.0
const AMBUSH_ROAM := 3
const RETRY_MIN_HULL := 60.0  # a retry from a checkpoint brings the car back with at least this hull
const HOLD_SPEED := 2.0  # m/s: a hold fills only below this
const ROAM_PACK := 3  # the pack's size in free roam

## The closing lines of the last mission, spoken once the car has stopped outside the gate (the presenter holds them).
const ENDING_LINES := ["end_vera", "end_ruck"]
## The closing lines of the story, spoken once the car has stopped on the far bank.
const ENDING_LINES_2 := ["lb_end_1", "lb_end_2"]


## Is this one of the lines the presenter holds until the car has stopped (the closing lines of a chapter or the story)?
static func is_ending_line(id: String) -> bool:
	return id in ENDING_LINES or id in ENDING_LINES_2

## The sky's lightening once the story is over, for free roam after the last mission.
const ENDING_DAWN := 0.3


## Which city a place is in.
static func place_city(id: String) -> String:
	return str(PLACES[id]["city"])


## Which city mission `i` is in.
static func mission_city(i: int, missions: Array = MISSIONS) -> String:
	return str(missions[i]["city"])


## The story's chapters in order: [{city, first, last}], one per run of missions in the same city
## (first and last are mission indices).
static func chapters(missions: Array = MISSIONS) -> Array:
	var out: Array = []
	for i in missions.size():
		var city := str(missions[i]["city"])
		if out.is_empty() or out[-1]["city"] != city:
			out.append({"city": city, "first": i, "last": i})
		else:
			out[-1]["last"] = i
	return out


## Is mission `i` the last of its chapter (the story's last mission included)?
static func ends_chapter(i: int, missions: Array = MISSIONS) -> bool:
	return i + 1 >= missions.size() or str(missions[i + 1]["city"]) != str(missions[i]["city"])


## Does finishing mission `i` end the story (the credits)? The last mission does, unless it says `closes_story: false`.
static func closes_story(i: int, missions: Array = MISSIONS) -> bool:
	return i + 1 >= missions.size() and bool(missions[i].get("closes_story", true))


## The city the player is in with `done_count` missions finished: the next mission's, or the last
## one's when the story is over.
static func city_after(done_count: int, missions: Array = MISSIONS) -> String:
	if missions.is_empty():
		return Cities.QUARTER
	return str(missions[mini(done_count, missions.size() - 1)]["city"])


## A city's safe start: the place marked `safe` that is in it ("" when it has none).
static func safe_start_id(city: String) -> String:
	for id in PLACES:
		if PLACES[id].get("safe", false) and PLACES[id]["city"] == city:
			return id
	return ""


## Where a mission begins: its own start place, else its city's safe start.
static func start_place_id(mission: Dictionary) -> String:
	var start: String = mission["start"]
	return start if start != "" else safe_start_id(str(mission["city"]))


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
