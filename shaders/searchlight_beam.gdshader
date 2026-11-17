shader_type spatial;
// The visible cone of a searchlight in the fog: brightest at the lens, fading along its length and
// towards its edges so it reads as light in the air and not as a solid.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.84, 1.0);
uniform float strength = 0.15;

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);  // 1 at the lens end, 0 at the far end
	float edge = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.6);
	ALBEDO = tint.rgb;
	ALPHA = strength * pow(along, 1.3) * edge;
}
