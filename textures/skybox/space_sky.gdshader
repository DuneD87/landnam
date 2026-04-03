shader_type sky;

// === STAR POSITION ===
uniform float sun_azimuth_deg   = 0.0;
uniform float sun_elevation_deg = 25.0;
uniform float orbit_radius : hint_range(0.1, 100.0) = 3.0;

// === STAR BODY ===
uniform float star_radius : hint_range(0.001, 20.0) = 1.0;
uniform vec3 star_core_color   = vec3(1.0, 1.0, 0.95);
uniform vec3 star_surface_color = vec3(1.0, 0.6, 0.1);
uniform vec3 star_limb_color    = vec3(0.8, 0.2, 0.0);

// === CORONA & RAYS ===
uniform vec3 star_corona_color = vec3(1.0, 0.5, 0.1);
uniform vec3 star_ray_color    = vec3(1.0, 0.85, 0.6);
uniform float corona_intensity : hint_range(0.1, 15.0) = 8.0;
uniform float corona_extent : hint_range(0.5, 5.0) = 2.5;
uniform float ray_intensity : hint_range(0.1, 5.0) = 1.2;
uniform float ray_count_bias : hint_range(1.0, 20.0) = 6.0;

// === PROMINENCES ===
uniform float prominence_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float prominence_speed : hint_range(0.1, 3.0) = 0.5;

// === SUNSPOTS ===
uniform float sunspot_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float sunspot_scale : hint_range(1.0, 20.0) = 8.0;

// === SURFACE DETAIL ===
uniform float core_intensity : hint_range(0.1, 5.0) = 2.4;
uniform float surface_intensity : hint_range(0.1, 5.0) = 2.2;
uniform float detail_level : hint_range(1.0, 5.0) = 3.0;
uniform float zoom_level : hint_range(0.1, 10.0) = 0.5;
uniform float noise_seed : hint_range(0.0, 100.0) = 83.23;

// === ANIMATION ===
uniform float animation_speed : hint_range(0.1, 10.0) = 1.0;
uniform float rotation_speed : hint_range(-5.0, 5.0) = 0.25;
uniform float rotation_angle : hint_range(-1.0, 1.0) = -0.6;
uniform float pulse_amount : hint_range(0.0, 0.1) = 0.015;
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.5;

// === SPACE BACKGROUND ===
uniform float background_star_density : hint_range(0.0, 1.0) = 0.5;
uniform float background_star_brightness : hint_range(0.0, 20.0) = 0.8;

// === BLOOM / HDR ===
uniform float bloom_strength : hint_range(1.0, 8.0) = 2.5;

// ─────────────────────────────────────────────
// NOISE UTILITIES
// ─────────────────────────────────────────────
vec4 hash4(vec4 n) { return fract(sin(n) * 1399763.5453123); }
vec3 hash3(vec3 n) { return fract(sin(n) * 1399763.5453123); }

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise4q(vec4 x) {
	vec4 n3 = vec4(0.0, 0.25, 0.5, 0.75);
	vec4 p2 = floor(x.wwww + n3);
	vec4 b = floor(x.xxxx + n3) + floor(x.yyyy + n3) * 157.0 + floor(x.zzzz + n3) * 113.0;
	vec4 p1 = b + fract(p2 * 0.00390625) * vec4(164352.0, -164352.0, 163840.0, -164352.0);
	p2 = b + fract((p2 + 1.0) * 0.00390625) * vec4(164352.0, -164352.0, 163840.0, -164352.0);
	vec4 f1 = fract(x.xxxx + n3);
	vec4 f2 = fract(x.yyyy + n3);
	f1 = f1 * f1 * (3.0 - 2.0 * f1);
	f2 = f2 * f2 * (3.0 - 2.0 * f2);
	vec4 n1 = vec4(0.0, 1.0, 157.0, 158.0);
	vec4 n2 = vec4(113.0, 114.0, 270.0, 271.0);
	vec4 vs1 = mix(hash4(p1), hash4(n1.yyyy + p1), f1);
	vec4 vs2 = mix(hash4(n1.zzzz + p1), hash4(n1.wwww + p1), f1);
	vec4 vs3 = mix(hash4(p2), hash4(n1.yyyy + p2), f1);
	vec4 vs4 = mix(hash4(n1.zzzz + p2), hash4(n1.wwww + p2), f1);
	vs1 = mix(vs1, vs2, f2);
	vs3 = mix(vs3, vs4, f2);
	vs2 = mix(hash4(n2.xxxx + p1), hash4(n2.yyyy + p1), f1);
	vs4 = mix(hash4(n2.zzzz + p1), hash4(n2.wwww + p1), f1);
	vs2 = mix(vs2, vs4, f2);
	vs4 = mix(hash4(n2.xxxx + p2), hash4(n2.yyyy + p2), f1);
	vec4 vs5 = mix(hash4(n2.zzzz + p2), hash4(n2.wwww + p2), f1);
	vs4 = mix(vs4, vs5, f2);
	f1 = fract(x.zzzz + n3);
	f2 = fract(x.wwww + n3);
	f1 = f1 * f1 * (3.0 - 2.0 * f1);
	f2 = f2 * f2 * (3.0 - 2.0 * f2);
	vs1 = mix(vs1, vs2, f1);
	vs3 = mix(vs3, vs4, f1);
	vs1 = mix(vs1, vs3, f2);
	float r = dot(vs1, vec4(0.25));
	return r * r * (3.0 - 2.0 * r);
}

// Simple 3D value noise for sunspots / prominences
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = dot(i, vec3(1.0, 157.0, 113.0));
	return mix(
		mix(mix(hash11(n + 0.0),   hash11(n + 1.0), f.x),
			mix(hash11(n + 157.0), hash11(n + 158.0), f.x), f.y),
		mix(mix(hash11(n + 113.0), hash11(n + 114.0), f.x),
			mix(hash11(n + 270.0), hash11(n + 271.0), f.x), f.y),
		f.z);
}

float fbm3(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise3(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

// ─────────────────────────────────────────────
// STAR SURFACE
// ─────────────────────────────────────────────
float noiseSpere(vec3 ray, vec3 pos, float r, mat3 mr, float zoom, vec3 subnoise, float anim) {
	float b = dot(ray, pos);
	float c = dot(pos, pos) - b * b;
	float s = 0.0;
	float d = 0.03125;
	float d2 = zoom / (d * d);
	float ar = 5.0;

	for (int i = 0; i < 3; i++) {
		float rq = r * r;
		if (c < rq) {
			float l1 = sqrt(rq - c);
			vec3 r1 = (ray * (b - l1) - pos) * mr;
			s += abs(noise4q(vec4(r1 * d2 + subnoise * ar, anim * ar)) * d);
		}
		ar -= 2.0;
		d *= 4.0;
		d2 *= 0.0625;
		r -= r * 0.02;
	}
	return s;
}

// ─────────────────────────────────────────────
// LIMB DARKENING
// ─────────────────────────────────────────────
float limbDarkening(vec3 ray, vec3 pos, float r) {
	float b = dot(ray, pos);
	float c = dot(pos, pos) - b * b;
	float rq = r * r;
	if (c >= rq) return 0.0;
	float l = sqrt(rq - c);
	vec3 hit = ray * (b - l);
	vec3 normal = normalize(hit - pos);
	float mu = max(0.0, dot(normal, -normalize(pos)));
	return 0.3 + 0.93 * mu - 0.23 * mu * mu;
}

// ─────────────────────────────────────────────
// SUNSPOTS
// ─────────────────────────────────────────────
float sunspots(vec3 ray, vec3 pos, float r, mat3 mr, float anim) {
	float b = dot(ray, pos);
	float c = dot(pos, pos) - b * b;
	float rq = r * r;
	if (c >= rq) return 0.0;
	float l = sqrt(rq - c);
	vec3 surface_pt = (ray * (b - l) - pos) * mr;
	vec3 sp = normalize(surface_pt);
	float n1 = fbm3(sp * sunspot_scale + vec3(noise_seed), 3);
	float n2 = fbm3(sp * sunspot_scale * 0.5 + vec3(noise_seed * 2.0) + anim * 0.05, 2);
	float spots = smoothstep(0.55, 0.65, n1) * smoothstep(0.4, 0.6, n2);
	return spots * sunspot_intensity;
}

// ─────────────────────────────────────────────
// GLOW RING
// ─────────────────────────────────────────────
float ring(vec3 ray, vec3 pos, float r, float size) {
	float b = dot(ray, pos);
	float c = dot(pos, pos) - b * b;
	return max(0.0, 1.0 - size * abs(r - sqrt(c)));
}

// ─────────────────────────────────────────────
// MULTI-LAYER CORONA
// ─────────────────────────────────────────────
float coronaLayer(vec3 ray, vec3 pos, float r, float falloff, mat3 mr, float anim, float freq) {
	float b = dot(ray, pos);
	float c = sqrt(max(0.0, dot(pos, pos) - b * b));
	float edge = max(0.0, c - r);
	float base = exp(-edge * falloff);
	vec3 pr = ray * b - pos;
	pr *= mr;
	vec3 dir = normalize(pr);
	float n = noise4q(vec4(dir * freq, anim * 0.3));
	n = pow(n, 1.5);
	return base * (0.4 + 0.6 * n);
}

// ─────────────────────────────────────────────
// PROMINENCES
// ─────────────────────────────────────────────
float prominences(vec3 ray, vec3 pos, float r, mat3 mr, float anim) {
	float b = dot(ray, pos);
	float c = sqrt(max(0.0, dot(pos, pos) - b * b));
	if (c < r * 0.95 || c > r * 2.0) return 0.0;

	vec3 pr = normalize((ray * b - pos) * mr);
	float height = (c - r) / r;

	float angle = atan(pr.z, pr.x);
	float n1 = noise4q(vec4(vec3(angle * 2.0, height * 3.0, pr.y * 2.0), anim * prominence_speed));
	float n2 = noise4q(vec4(vec3(angle * 4.0, height * 5.0, pr.y * 3.0), anim * prominence_speed * 0.7));
	float shape = pow(n1, 2.0) * n2;
	float hfade = exp(-height * 4.0);
	return shape * hfade * prominence_intensity;
}

// ─────────────────────────────────────────────
// STAR RAYS / STREAMERS
// ─────────────────────────────────────────────
float ringRayNoise(vec3 ray, vec3 pos, float r, float size, mat3 mr, float anim) {
	float b = dot(ray, pos);
	vec3 pr = ray * b - pos;
	float c = length(pr);
	pr *= mr;
	pr = normalize(pr);

	float s = max(0.0, 1.0 - size * abs(r - c));

	float nd = noise4q(vec4(pr * 1.0, -anim + c)) * 2.0;
	nd = pow(nd, 2.0);

	float n = 0.4;
	float ns = 1.0;
	if (c > r) {
		n = noise4q(vec4(pr * ray_count_bias, -anim + c));
		ns = noise4q(vec4(pr * ray_count_bias * 5.0, -anim * 2.5 + c * 2.0)) * 2.0;
	}
	n = n * n * nd * ns;

	float streamer = 0.0;
	if (c > r) {
		float dist = c - r;
		float angle = atan(pr.z, pr.x);
		float sn = noise4q(vec4(vec3(angle * 3.0, dist * 0.5, pr.y), anim * 0.2));
		streamer = pow(sn, 4.0) * exp(-dist * 0.8) * 0.5;
	}

	return pow(s, 4.0) + s * s * n + streamer;
}

// ─────────────────────────────────────────────
// REALISTIC BACKGROUND STAR FIELD
// ─────────────────────────────────────────────

// Approximate blackbody color from a 0..1 "temperature" parameter
// 0 = cool red/orange, 0.5 = white, 1 = hot blue-white
vec3 starColor(float temp) {
	// Red stars (M/K class)
	vec3 cool = vec3(1.0, 0.6, 0.3);
	// White stars (A/F class)
	vec3 mid = vec3(1.0, 0.98, 0.95);
	// Blue-white stars (O/B class)
	vec3 hot = vec3(0.7, 0.8, 1.0);

	if (temp < 0.5) {
		return mix(cool, mid, temp * 2.0);
	} else {
		return mix(mid, hot, (temp - 0.5) * 2.0);
	}
}

// Stable hash for star positions — no TIME dependency
float stableHash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 starField(vec3 ray) {
	vec3 col = vec3(0.0);

	// Two layers at different grid scales for depth
	// Layer 1: dense dim stars (high grid resolution)
	{
		vec3 rd = ray * 500.0;
		vec3 cell = floor(rd);
		vec3 local = fract(rd) - 0.5;

		float h = stableHash(cell.xy + cell.z * 31.7);
		if (h > (1.0 - background_star_density * 0.04)) {
		    vec3 star_pos_offset = vec3(
		        stableHash(cell.xz + 7.0),
		        stableHash(cell.yz + 17.0),
		        stableHash(cell.xy + 31.0)
		    ) - 0.5;
		    float d = length(local - star_pos_offset);
		    float size = 0.015 + stableHash(cell.xz + 43.0) * 0.025;
		    float star_val = smoothstep(size, 0.0, d);
		    float magnitude = pow(stableHash(cell.yz + 59.0), 3.0);
		    float twinkle = 0.85 + 0.15 * sin(h * 6283.0 + TIME * (0.5 + h * 2.0));
		    float temp = 0.2 + stableHash(cell.xz + 71.0) * 0.6;
		    col += starColor(temp) * star_val * magnitude * twinkle * 0.6;
		}
	}

	// Layer 2: sparse bright stars (lower grid resolution, larger)
	{
		vec3 rd = ray * 150.0;
		vec3 cell = floor(rd);
		vec3 local = fract(rd) - 0.5;

		vec3 neighbor = cell;

		float h = stableHash(neighbor.xy + neighbor.z * 53.1);

		// Very sparse — only a few bright stars
		if (h > (1.0 - background_star_density * 0.004)) {
			vec3 star_pos_offset = vec3(
				stableHash(neighbor.xz + 11.0),
				stableHash(neighbor.yz + 23.0),
				stableHash(neighbor.xy + 37.0)
			) - 0.5;
			float d = length(local - star_pos_offset);

			// Slightly larger point with soft glow
			float size = 0.03 + stableHash(neighbor.xz + 47.0) * 0.04;
			float star_val = smoothstep(size, 0.0, d);

			// Soft diffraction glow around bright stars
			float glow = exp(-d * d * 80.0) * 0.3;

			float brightness = 0.5 + stableHash(neighbor.yz + 67.0) * 0.5;

			// Subtle twinkle
			float twinkle = 0.9 + 0.1 * sin(h * 4729.0 + TIME * (0.3 + h * 1.5));

			// Spectral color
			float temp = stableHash(neighbor.xz + 83.0);
			temp = 0.15 + temp * 0.7;
			vec3 scol = starColor(temp);

			col += scol * (star_val + glow) * brightness * twinkle;
		}
	}

	return col * background_star_brightness;
}

// ─────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────
void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.005, 0.005, 0.01);
	} else {
		vec3 ray = normalize(EYEDIR);
		float time = TIME * animation_speed;

		// === Star position ===
		vec2 sun_angles = radians(vec2(sun_azimuth_deg, sun_elevation_deg));
		vec3 pos = vec3(
			cos(sun_angles.y) * sin(sun_angles.x),
			sin(sun_angles.y),
			cos(sun_angles.y) * cos(sun_angles.x)
		) * orbit_radius;

		// === Pulsation ===
		float pulse = 1.0 + sin(time * pulse_speed) * pulse_amount;
		float r = star_radius * pulse;

		// === Visibility ===
		float facing = dot(ray, normalize(pos));
		float star_visibility = step(0.0, facing);
		float glow_visibility = smoothstep(-0.3, 0.1, facing);

		// === Rotation matrix ===
		float mx = time * rotation_speed;
		float my = rotation_angle;
		vec2 sins = sin(vec2(mx, my));
		vec2 coss = cos(vec2(mx, my));
		mat3 mr = mat3(
			vec3(coss.x, 0.0, sins.x),
			vec3(0.0, 1.0, 0.0),
			vec3(-sins.x, 0.0, coss.x)
		);
		mr = mat3(
			vec3(1.0, 0.0, 0.0),
			vec3(0.0, coss.y, sins.y),
			vec3(0.0, -sins.y, coss.y)
		) * mr;

		// ────── BACKGROUND: STARS ONLY ──────
		vec3 col = starField(ray);

		// Mask background stars near the main star to avoid bleed-through
		float star_dist_from_ray = length(pos - ray * dot(ray, pos));
		float bg_mask = smoothstep(r * 1.2, r * 2.5, star_dist_from_ray);
		col *= bg_mask;

		// ────── STAR BODY ──────
		float s1 = noiseSpere(ray, pos, r, mr, zoom_level, vec3(0.0), time) * star_visibility;
		s1 = pow(min(1.0, s1 * core_intensity), 2.0);
		float s2 = noiseSpere(ray, pos, r, mr, zoom_level * 8.0,
			vec3(noise_seed, noise_seed * 0.412, noise_seed * 0.81), time) * star_visibility;
		s2 = min(1.0, s2 * surface_intensity);

		float limb = limbDarkening(ray, pos, r) * star_visibility;
		float spots = sunspots(ray, pos, r, mr, time * 0.1) * star_visibility;

		vec3 surface = vec3(0.0);
		surface += mix(star_core_color, vec3(1.0), pow(s1, 60.0)) * s1;
		surface += mix(
			mix(star_surface_color, star_limb_color, pow(s2, 2.0)),
			vec3(1.0),
			pow(s2, 10.0)
		) * s2;
		surface *= mix(1.0, limb, 0.6);
		surface *= (1.0 - spots * 0.7);

		col += surface;

		// ────── EDGE GLOW ──────
		float edge_glow = ring(ray, pos, r * 1.01, corona_intensity * 0.5) * glow_visibility;
		col += star_corona_color * edge_glow * 1.5;

		// ────── CORONA ──────
		float c1 = coronaLayer(ray, pos, r, 2.0 / corona_extent, mr, time, 4.0) * glow_visibility;
		float c2 = coronaLayer(ray, pos, r, 4.0 / corona_extent, mr, time * 1.3, 8.0) * glow_visibility;
		float c3 = coronaLayer(ray, pos, r, 1.0 / corona_extent, mr, time * 0.7, 2.0) * glow_visibility;

		vec3 corona_col = star_corona_color * c1 * 0.8;
		corona_col += mix(star_corona_color, star_ray_color, 0.5) * c2 * 0.4;
		corona_col += star_corona_color * vec3(1.0, 0.8, 0.6) * c3 * 0.3;
		col += corona_col;

		// ────── PROMINENCES ──────
		float prom = prominences(ray, pos, r, mr, time) * glow_visibility;
		col += star_corona_color * vec3(1.2, 0.6, 0.3) * prom;

		// ────── RAYS / STREAMERS ──────
		float s3 = ringRayNoise(ray, pos, r * 0.96, ray_intensity, mr, time) * glow_visibility;
		col += mix(star_corona_color, star_ray_color, pow(s3, 3.0)) * s3;

		// ────── HDR BLOOM BOOST ──────
		float bloom_dist = length(pos - ray * max(0.0, dot(ray, pos)));
		float bloom = exp(-bloom_dist / (r * 1.5)) * glow_visibility;
		col += col * bloom * (bloom_strength - 1.0);

		COLOR = max(col, vec3(0.0));
	}
}
