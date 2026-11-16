shader_type canvas_item;
// The title's weather laid over the key art: thin slanted rain, slow drifting fog, a dark left
// third for the menu, a vignette, and the fade in from black. Lightning is done on the art itself.

uniform float time_s = 0.0;
uniform float aspect = 1.7778;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float left_dark : hint_range(0.0, 1.0) = 0.8;
uniform float left_width : hint_range(0.1, 1.0) = 0.46;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// One layer of rain: columns of falling streaks, slanted, thin.
float rain(vec2 uv, float cols, float speed, float len, float slant, float seed) {
	vec2 p = vec2(uv.x * aspect + uv.y * slant, uv.y);
	float id = floor(p.x * cols);
	float lx = fract(p.x * cols);
	float h = hash(vec2(id, seed));
	float gate = step(0.55, h);
	float y = fract(p.y * 0.7 - time_s * speed * (0.8 + h * 0.5) + h * 7.0);
	float streak = smoothstep(0.0, len, y) * (1.0 - smoothstep(len, len + 0.002, y));
	streak *= smoothstep(0.0, len, y);
	float w = smoothstep(0.5, 0.5 - 0.07, abs(lx - 0.5));
	return gate * w * pow(streak, 1.6);
}

void fragment() {
	vec2 uv = UV;
	float r = rain(uv, 120.0, 1.5, 0.06, 0.18, 1.0) * 0.55
		+ rain(uv, 190.0, 2.1, 0.05, 0.2, 5.0) * 0.4
		+ rain(uv, 290.0, 2.8, 0.04, 0.22, 9.0) * 0.28;
	// Fog: two slow layers of noise drifting in opposite directions, thick near the ground.
	vec2 fp = vec2(uv.x * aspect, uv.y);
	float fog = vnoise(fp * 2.2 + vec2(time_s * 0.012, 0.0)) * 0.6 + vnoise(fp * 4.7 - vec2(time_s * 0.02, time_s * 0.004)) * 0.4;
	fog = smoothstep(0.25, 0.85, fog) * (0.04 + 0.1 * smoothstep(0.35, 1.0, uv.y));

	vec3 col = vec3(0.0);
	float a = 0.0;
	// Fog and rain as pale blue-grey light over the picture.
	vec3 pale = vec3(0.62, 0.72, 0.8);
	float light = clamp(r * 0.22 + fog, 0.0, 1.0) * (1.0 - flash * 0.5);
	col = pale;
	a = light;
	// Darkness: the left third, the edges, a flat dimming that eases off in a flash.
	float left = left_dark * (1.0 - smoothstep(0.0, left_width, uv.x));
	vec2 c = uv - 0.5;
	c.x *= 0.9;
	float vig = smoothstep(0.35, 0.85, length(c));
	float dark = clamp(0.2 * (1.0 - flash) + left + vig * 0.55 * (1.0 - flash * 0.6), 0.0, 1.0);
	// Composite: first the pale light, then the dark over it, then the fade to black.
	vec3 outc = col * a;
	float outa = a;
	outc = outc * (1.0 - dark);
	outa = 1.0 - (1.0 - outa) * (1.0 - dark);
	outc = outc * (1.0 - fade);
	outa = 1.0 - (1.0 - outa) * (1.0 - fade);
	COLOR = vec4(outc / max(outa, 0.0001), outa);
}
