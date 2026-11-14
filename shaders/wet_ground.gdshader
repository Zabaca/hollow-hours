shader_type spatial;
// Wet asphalt and sidewalk: puddles from world-space noise (smooth and mirror-like), a darker
// wet colour in them, rain ripples that perturb the normal, and fine roughness grain. The
// reflections themselves come from the environment's screen-space reflections.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 base_color : source_color = vec3(0.07, 0.075, 0.085);
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.6;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.7;
uniform float base_rough : hint_range(0.0, 1.0) = 0.55;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = wpos.xz;
	float big = texture(noise_tex, w * 0.035).r;
	float mid = texture(noise_tex, w * 0.12 + vec2(3.7, 1.3)).r;
	float fine = texture(noise_tex, w * 1.1).r;
	float field = big * 0.65 + mid * 0.35;
	float thresh = mix(0.62, 0.44, puddle_amount);
	float puddle = smoothstep(thresh, thresh + 0.06, field);

	// Rain ripples: one ring per jittered cell, expanding and fading, only inside puddles.
	vec2 g = w * 1.7;
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash12(cell);
	vec2 centre = (vec2(hash12(cell + 3.1), hash12(cell + 7.7)) - 0.5) * 0.5;
	float phase = fract(TIME * (0.55 + h * 0.5) + h * 7.0);
	vec2 dv = f - centre;
	float d = length(dv);
	float ring = sin(d * 42.0 - phase * 16.0) * exp(-d * 6.0) * (1.0 - phase) * step(0.45, h);
	vec2 push = normalize(dv + vec2(1e-4)) * ring * ripple_strength * puddle * 0.45;

	vec3 n_w = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	n_w.xz += push;
	n_w = normalize(n_w);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_w, 0.0)).xyz);

	ALBEDO = base_color * (0.75 + fine * 0.5) * (1.0 - 0.45 * puddle);
	ROUGHNESS = mix(base_rough * (0.7 + fine * 0.6), 0.04, clamp(puddle + wetness * 0.35, 0.0, 1.0));
	SPECULAR = 0.55 + puddle * 0.45;
	METALLIC = 0.0;
}
