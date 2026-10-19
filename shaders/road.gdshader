// Asphalt with lane markings. Vertex COLOR = connectivity (r=N, g=E, b=S, a=W).
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/noise.gdshaderinc"

varying vec4 conn;
varying vec3 wpos;

void vertex() {
	conn = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	vec3 asphalt = vec3(0.16, 0.17, 0.19) * (0.82 + 0.32 * fbm(wpos.xz * 3.0));
	asphalt += (hash12(floor(wpos.xz * 30.0)) - 0.5) * 0.035;
	vec3 col = asphalt;
	vec3 yellow = vec3(0.92, 0.72, 0.16);
	vec3 white = vec3(0.86, 0.87, 0.88);
	vec3 curb = vec3(0.50, 0.51, 0.53);
	float n = conn.r, e = conn.g, s = conn.b, w = conn.a;
	float cnt = n + e + s + w;
	if (cnt > 2.5) {
		// zebra crossings on each connected arm
		float zx = step(0.5, fract(uv.x * 7.0));
		float zy = step(0.5, fract(uv.y * 7.0));
		if (n > 0.5 && uv.y < 0.17 && uv.y > 0.03 && uv.x > 0.08 && uv.x < 0.92) col = mix(col, white, zx);
		if (s > 0.5 && uv.y > 0.83 && uv.y < 0.97 && uv.x > 0.08 && uv.x < 0.92) col = mix(col, white, zx);
		if (w > 0.5 && uv.x < 0.17 && uv.x > 0.03 && uv.y > 0.08 && uv.y < 0.92) col = mix(col, white, zy);
		if (e > 0.5 && uv.x > 0.83 && uv.x < 0.97 && uv.y > 0.08 && uv.y < 0.92) col = mix(col, white, zy);
	} else if (e + w > 1.5) {
		float d = abs(uv.y - 0.5);
		if (d > 0.012 && d < 0.036) col = yellow;
		if (abs(d - 0.25) < 0.008 && fract(uv.x * 2.0) < 0.55) col = mix(col, white, 0.55);
	} else if (n + s > 1.5) {
		float d = abs(uv.x - 0.5);
		if (d > 0.012 && d < 0.036) col = yellow;
		if (abs(d - 0.25) < 0.008 && fract(uv.y * 2.0) < 0.55) col = mix(col, white, 0.55);
	} else if (cnt > 1.5) {
		// corner: centre line is a quarter circle around the shared corner
		vec2 c = vec2(e > 0.5 ? 1.0 : 0.0, s > 0.5 ? 1.0 : 0.0);
		float r = length(uv - c);
		float d = abs(r - 0.5);
		if (d > 0.012 && d < 0.036) col = yellow;
		if (r > 1.0) col = curb * (0.9 + 0.2 * vnoise(wpos.xz * 8.0));
	}
	// tyre wear in the lanes
	col *= 1.0 - 0.06 * smoothstep(0.3, 0.0, abs(fract(uv.x * 2.0 + 0.25) - 0.5)) * step(1.5, e + w);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
