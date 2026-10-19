// Sidewalks, curbs and plazas: concrete slabs with seams.
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/noise.gdshaderinc"
uniform vec3 tint : source_color = vec3(0.58, 0.59, 0.61);
uniform float slab = 0.5;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 col = tint * (0.86 + 0.22 * fbm(wpos.xz * 4.0));
	vec2 g = fract(wpos.xz / slab);
	float seam = step(g.x, 0.03) + step(g.y, 0.03);
	col *= 1.0 - 0.18 * clamp(seam, 0.0, 1.0);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
