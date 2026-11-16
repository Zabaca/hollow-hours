class_name MarkerView
extends Node3D
## The markers in the world: a ring on the ground and a faint column of light rising through the fog
## for each blip the story shows, amber for an objective and teal for a mission start. The glow is
## only a picture: it does not keep the Gaunts off, as the street lamps do.

const BEAM := preload("res://shaders/marker_beam.gdshader")
const HEIGHT := 46.0

var _nodes := {}  # "place:kind" -> Node3D
var _time := 0.0


## Show exactly these blips: [{kind, place, pos}].
func show_blips(blips: Array) -> void:
	var wanted := {}
	for bl in blips:
		var key := "%s:%s" % [bl["place"], bl["kind"]]
		wanted[key] = true
		if not _nodes.has(key):
			var n := _make(bl)
			add_child(n)
			_nodes[key] = n
	for key in _nodes.keys():
		if not wanted.has(key):
			_nodes[key].queue_free()
			_nodes.erase(key)


func shown() -> int:
	return _nodes.size()


func _make(bl: Dictionary) -> Node3D:
	var col: Color = MapView.TEAL if bl["kind"] == "start" else MapView.AMBER
	var root := Node3D.new()
	root.position = GM.to3(bl["pos"])
	var radius := StoryData.place_radius(bl["place"])
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.09
	torus.outer_radius = radius
	torus.rings = 56
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.14
	ring.scale.y = 0.2
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(col, 0.5)
	rm.disable_receive_shadows = true
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.5
	cyl.bottom_radius = 1.5
	cyl.height = HEIGHT
	cyl.radial_segments = 20
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	beam.position.y = HEIGHT * 0.5
	var bm := ShaderMaterial.new()
	bm.shader = BEAM
	bm.set_shader_parameter("tint", col)
	bm.set_shader_parameter("strength", 0.5)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	return root


func _process(delta: float) -> void:
	_time += delta
	for n in _nodes.values():
		var ring: MeshInstance3D = n.get_child(0)
		var m: StandardMaterial3D = ring.material_override
		m.albedo_color.a = 0.38 + 0.16 * sin(_time * 2.2)
