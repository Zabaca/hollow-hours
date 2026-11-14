shader_type canvas_item;
// Full-screen post effects drawn over the 3D view: vignette, chromatic aberration, a red wash
// when the car is hurt, claw scratches when a creature lands, desaturation and film grain.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette : hint_range(0.0, 1.0) = 0.45;
uniform float red : hint_range(0.0, 1.0) = 0.0;
uniform float chroma : hint_range(0.0, 1.0) = 0.0;
uniform float scratches : hint_range(0.0, 1.0) = 0.0;
uniform float desat : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float dawn : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	float ca = chroma * 0.018 * (0.4 + r2 * 3.0) + 0.0008;
	vec3 col;
	col.r = texture(screen_tex, uv + c * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * ca).b;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desat);

	float edge = length(c * vec2(1.0, 0.9));
	float vig = smoothstep(0.85, 0.25, edge);
	col *= mix(1.0, vig, vignette);

	// The red wash is heaviest at the edges, like blood in the corner of the eye.
	float wash = red * (0.25 + smoothstep(0.15, 0.75, edge));
	col = mix(col, col * vec3(1.5, 0.3, 0.3) + vec3(0.1, 0.0, 0.0), clamp(wash, 0.0, 1.0));

	// Four claw streaks, curved a little, drawn once per landing (seed picks the fan's side).
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 o = vec2(0.22 + fi * 0.15 + seed * 0.2, 0.05);
		vec2 d = normalize(vec2(0.33 + seed * 0.1, 1.0));
		vec2 q = uv - o;
		float along = dot(q, d);
		float across = dot(q, vec2(-d.y, d.x)) + 0.035 * sin(along * 8.0 + fi * 1.7);
		float wd = 0.0035 + 0.0025 * sin(fi * 2.3 + 1.0);
		s += smoothstep(wd, 0.0, abs(across)) * step(0.0, along) * smoothstep(0.0, 0.12, along) * smoothstep(1.2, 0.6, along);
	}
	s = clamp(s, 0.0, 1.0);
	col = mix(col, vec3(0.015, 0.0, 0.0), s * scratches);
	col += vec3(0.35, 0.02, 0.02) * s * scratches * 0.35;

	col += (hash(uv * 1013.0 + TIME) - 0.5) * grain;
	col = mix(col, col * vec3(1.15, 1.02, 0.9) + vec3(0.04, 0.03, 0.02), dawn);
	col = mix(col, vec3(0.0), fade);
	COLOR = vec4(col, 1.0);
}
