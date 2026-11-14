class_name GM
extends RefCounted
## Small helpers shared by the presentation scripts.

## Map (x, y) metres to a 3D position: map y points up the screen, which is -Z in Godot.
static func to3(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x, h, -p.y)


static func from3(v: Vector3) -> Vector2:
	return Vector2(v.x, -v.z)


## Set a batch of properties on any object by name. Used for the rendering settings, where a
## property renamed in some engine version should log an error rather than stop the game.
static func apply(obj: Object, props: Dictionary) -> void:
	for k in props:
		obj.set(k, props[k])


static func damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


## A WAV stream set to loop over its whole length (imported WAVs default to no loop).
static func loop_wav(path: String) -> AudioStream:
	var s: AudioStream = load(path)
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = s
		var bytes := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
		var channels := 2 if w.stereo else 1
		var samples := w.data.size() / (bytes * channels)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples
	return s
