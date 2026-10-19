// Grass and dirt patches for the ground plane.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = fbm(wpos.xz * 0.7);
	vec3 grass = mix(vec3(0.20, 0.38, 0.19), vec3(0.30, 0.50, 0.24), n);
	grass *= 0.9 + 0.2 * hash12(floor(wpos.xz * 20.0));
	float dirt = smoothstep(0.62, 0.7, fbm(wpos.xz * 0.35 + 17.0));
	ALBEDO = mix(grass, vec3(0.42, 0.36, 0.26), dirt * 0.6);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
