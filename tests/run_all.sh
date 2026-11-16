#!/bin/sh
# Import the project, then run the headless checks. Needs Godot on PATH (or GODOT=/path/to/godot).
# Run it from anywhere; it stops at the first failure.
set -e
GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
"$GODOT" --headless --path "$HERE" --import
"$GODOT" --headless --path "$HERE" res://tests/car_test.tscn
"$GODOT" --headless --path "$HERE" res://tests/pack_test.tscn
"$GODOT" --headless --path "$HERE" res://tests/settings_test.tscn
"$GODOT" --headless --path "$HERE" --script res://tests/menu_nav_test.gd
"$GODOT" --headless --path "$HERE" res://tests/mission_test.tscn
"$GODOT" --headless --path "$HERE" res://tests/presenter_test.tscn
