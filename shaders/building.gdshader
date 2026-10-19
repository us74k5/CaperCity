// Procedural building: window grid on the walls, parapet and gravel on the roof.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"
uniform vec3 wall_color : source_color = vec3(0.6, 0.55, 0.5);
uniform vec3 roof_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 size = vec3(3.4, 4.0, 3.4);
uniform float floor_h = 0.95;
uniform float bay_w = 0.62;
uniform float seed = 0.0;
uniform float lit = 0.35;
varying vec3 lpos;
varying vec3 lnorm;
void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}
void fragment() {
	if (lnorm.y > 0.5) {
		vec2 p = lpos.xz + size.xz * 0.5;
		float edge = min(min(p.x, size.x - p.x), min(p.y, size.z - p.y));
		vec3 c = roof_color * (0.82 + 0.3 * fbm(p * 5.0 + seed));
		c *= 0.92 + 0.12 * hash12(floor(p * 25.0));
		if (edge < 0.16) {
			c = roof_color * 0.55;
		} else if (edge < 0.24) {
			c *= 0.75;
		}
		ALBEDO = c;
		ROUGHNESS = 0.95;
	} else if (lnorm.y < -0.5) {
		ALBEDO = vec3(0.05);
	} else {
		float u = abs(lnorm.x) > 0.5 ? lpos.z : lpos.x;
		float h = lpos.y + size.y * 0.5;
		float fl = floor(h / floor_h);
		float fy = fract(h / floor_h);
		float bay = floor(u / bay_w);
		float wx = fract(u / bay_w);
		vec3 c = wall_color * (0.8 + 0.16 * fbm(vec2(u, h) * 3.0 + seed));
		if (fy < 0.06) c *= 0.8;
		bool window = fy > 0.32 && fy < 0.82 && wx > 0.18 && wx < 0.82 && h > 0.45 && h < size.y - 0.3;
		if (window) {
			float r = hash12(vec2(bay, fl) + seed);
			vec3 glass = vec3(0.10, 0.13, 0.19) + 0.08 * vec3(fy);
			if (r < lit) {
				glass = mix(vec3(1.0, 0.80, 0.48), vec3(0.85, 0.92, 1.0), step(0.5, hash12(vec2(fl, bay) + 3.0)));
				EMISSION = glass * 0.75;
			}
			c = glass;
			ROUGHNESS = 0.2;
		} else {
			ROUGHNESS = 0.9;
		}
		// darker band at street level
		if (h < 0.45) c *= 0.7;
		ALBEDO = c;
	}
}
