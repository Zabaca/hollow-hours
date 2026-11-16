shader_type spatial;
// A faint column of light for a mission marker: brightest at the ground, gone at the top.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0, 0.68, 0.2, 1.0);
uniform float strength = 0.4;

void fragment() {
	float up = clamp(1.0 - UV.y, 0.0, 1.0);
	// It thins out close to the camera, so a car sitting in the marker is not looking through a wall of light.
	float near = smoothstep(6.0, 26.0, -VERTEX.z);
	ALBEDO = tint.rgb;
	ALPHA = strength * pow(1.0 - up, 1.8) * near;
}
