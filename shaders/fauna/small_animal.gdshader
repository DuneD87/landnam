shader_type spatial;

instance uniform int species = 0;
instance uniform float animation_time = 0.0;
instance uniform float gait_phase = 0.0;
instance uniform float movement = 0.0;
instance uniform float run_blend = 0.0;
instance uniform float airborne = 0.0;
instance uniform float vertical_speed = 0.0;
instance uniform float turn_amount = 0.0;
instance uniform float landing = 0.0;
varying vec3 rest_position;

mat3 rotate_x(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(1,0,0),vec3(0,c,s),vec3(0,-s,c));
}

mat3 rotate_y(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(c,0,-s),vec3(0,1,0),vec3(s,0,c));
}

// The stance foot travels backwards against forward body motion at constant speed.
// Only the recovery phase lifts the paw; its endpoints have zero vertical speed.
vec2 foot_cycle(float phase, float stance, float reach, float lift) {
	float t = fract(phase);
	if (t < stance) {
		return vec2(0.0, mix(-reach, reach, t / stance));
	}
	float swing = (t - stance) / (1.0 - stance);
	float ease = swing * swing * (3.0 - 2.0 * swing);
	return vec2(pow(sin(PI * swing), 2.0) * lift, mix(reach, -reach, ease));
}

// Two-link leg bending in the sagittal plane. The rest hock shape is retained in
// the lower link. Blended rotations and normals keep the continuous skin joined.
void pose_leg(inout vec3 p, inout vec3 n, vec3 hip, vec3 knee, vec3 foot,
		vec3 target, float bend, float weight) {
	float upper = length(knee.yz - hip.yz);
	float lower = length(foot.yz - knee.yz);
	vec2 offset = target.yz - hip.yz;
	float distance = clamp(length(offset), abs(upper - lower) + 0.001, (upper + lower) * 0.998);
	vec2 direction = normalize(offset);
	float along = (upper * upper - lower * lower + distance * distance) / (2.0 * distance);
	float height = sqrt(max(0.0, upper * upper - along * along));
	vec2 joint = hip.yz + direction * along + vec2(-direction.y, direction.x) * height * bend;
	vec3 new_knee = vec3(knee.x, joint);
	vec3 reachable = vec3(foot.x, hip.yz + direction * distance);
	float a = atan(new_knee.z - hip.z, new_knee.y - hip.y) - atan(knee.z - hip.z, knee.y - hip.y);
	float b = atan(reachable.z - new_knee.z, reachable.y - new_knee.y) - atan(foot.z - knee.z, foot.y - knee.y);
	mat3 top_rotation = rotate_x(a);
	mat3 bottom_rotation = rotate_x(b);
	float lower_weight = 1.0 - smoothstep(knee.y - 0.025, knee.y + 0.040, p.y);
	vec3 top = hip + top_rotation * (p - hip);
	vec3 bottom = new_knee + bottom_rotation * (p - knee);
	p = mix(p, mix(top, bottom, lower_weight), weight);
	n = normalize(mix(n, mix(top_rotation * n, bottom_rotation * n, lower_weight), weight));
}

void vertex() {
	rest_position = VERTEX;
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	int part = int(UV.x + 0.5);
	float weight = UV.y;
	float beat = gait_phase * 2.0 * PI;
	float idle = 1.0 - movement;
	if (part >= 1 && part <= 4) {
		bool rear = part > 2;
		float side = (part == 1 || part == 3) ? -1.0 : 1.0;
		if (species == 1) {
			float trot_offset = (part == 1 || part == 4) ? 0.0 : 0.5;
			float gallop_offset = part == 1 ? 0.0 : (part == 2 ? 0.12 : (part == 3 ? 0.53 : 0.65));
			float phase = gait_phase + mix(trot_offset, gallop_offset, run_blend);
			vec2 cycle = foot_cycle(phase, mix(0.58, 0.42, run_blend), mix(0.085, 0.115, run_blend), mix(0.045, 0.095, run_blend));
			vec3 hip = rear ? vec3(side * 0.084, 0.320, 0.190) : vec3(side * 0.071, 0.339, -0.188);
			vec3 knee = rear ? vec3(side * 0.098, 0.195, 0.105) : vec3(side * 0.078, 0.190, -0.125);
			vec3 foot = rear ? vec3(side * 0.103, 0.023, 0.182) : vec3(side * 0.079, 0.024, -0.224);
			vec3 target = foot + vec3(0.0, cycle.x, cycle.y) * movement;
			pose_leg(p, n, hip, knee, foot, target, rear ? 1.0 : -1.0, weight * movement);
		} else if (species == 0) {
			// Flight pose is driven by the physical hop, not a separate sine-wave clock.
			float rising = smoothstep(-0.8, 1.6, vertical_speed);
			float tuck = airborne * movement;
			vec3 pivot = rear ? vec3(side * 0.11, 0.10, 0.10) : vec3(side * 0.073, 0.16, -0.11);
			float angle = rear ? mix(0.36, -0.60, rising) : mix(-0.28, 0.52, rising);
			mat3 rotation = rotate_x(angle * tuck);
			p = mix(p, pivot + rotation * (p - pivot), weight);
			n = normalize(mix(n, rotation * n, weight));
			p.y += (rear ? 0.025 : 0.016) * tuck * weight;
		} else {
			float phase = gait_phase + ((part == 1 || part == 4) ? 0.0 : 0.5);
			vec2 cycle = foot_cycle(phase, 0.56, 0.017, 0.014);
			vec3 pivot = vec3(side * 0.038, 0.055, rear ? 0.065 : -0.050);
			mat3 rotation = rotate_x(cycle.y * 11.0 * movement);
			p = mix(p, pivot + rotation * (p - pivot), weight);
			p.y += cycle.x * movement * weight;
			n = normalize(mix(n, rotation * n, weight));
		}
	} else if (part == 5) {
		float amount = species == 1 ? 0.16 : (species == 2 ? 0.08 : 0.04);
		float yaw = (sin(animation_time * 1.3 - weight * 2.0) * amount + turn_amount * 0.20) * weight;
		vec3 root = species == 1 ? vec3(0,0.328,0.285) : (species == 2 ? vec3(0,0.057,0.133) : vec3(0,0.186,0.25));
		mat3 rotation = rotate_y(yaw);
		p = root + rotation * (p - root);
		n = rotation * n;
		if (species == 1) {
			p.y += (0.060 * run_blend + sin(beat - weight) * 0.009 * movement) * weight;
		}
	} else if (part >= 6) {
		// Brief asynchronous ear flicks with a long rest between them.
		float flick = pow(max(0.0, sin(animation_time * 0.78 + float(part) * 2.1)), 12.0);
		p.z += (flick * 0.017 * idle - movement * run_blend * 0.012) * weight;
	}
	float body_weight = smoothstep(species == 2 ? 0.02 : 0.10, species == 2 ? 0.065 : 0.29, rest_position.y);
	float bob = species == 1 ? (cos(beat * 2.0) * 0.004 + sin(beat) * 0.012 * run_blend) : (species == 2 ? sin(beat * 2.0) * 0.0015 : 0.0);
	p.y += bob * movement * body_weight;
	if (species == 0) {
		p.y -= landing * 0.010 * body_weight;
	}
	// The muzzle and its eyes share the same head transform while observing/sniffing.
	float head = (1.0 - smoothstep(species == 2 ? -0.10 : -0.34, species == 2 ? -0.05 : -0.22, rest_position.z));
	vec3 neck = species == 1 ? vec3(0,0.41,-0.25) : (species == 2 ? vec3(0,0.077,-0.055) : vec3(0,0.29,-0.15));
	float look = (sin(animation_time * 0.63) * 0.10 * idle + turn_amount * 0.08) * head;
	float sniff = sin(animation_time * (species == 2 ? 4.5 : 1.7)) * 0.025 * idle * head;
	mat3 head_rotation = rotate_y(look) * rotate_x(sniff);
	p = neck + head_rotation * (p - neck);
	n = head_rotation * n;
	p.x *= 1.0 + sin(animation_time * 2.3) * idle * body_weight * 0.004;
	VERTEX = p;
	NORMAL = normalize(n);
}

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}

void fragment() {
	vec3 color = COLOR.rgb;
	float fur = smoothstep(0.7, 0.95, COLOR.a);
	float scale = species == 2 ? 3.0 : 1.0;
	vec3 p = rest_position * scale;
	vec3 grain_position = p * vec3(380.0, 330.0, 75.0);
	float footprint = max(length(dFdx(grain_position)), length(dFdy(grain_position)));
	float fade = 1.0 - smoothstep(0.5, 2.0, footprint);
	float grain = noise3(grain_position);
	float undercoat = noise3(p * 95.0);
	color *= 1.0 + fur * ((grain - 0.5) * 0.30 * fade + (undercoat - 0.5) * 0.10);
	ALBEDO = color;
	ROUGHNESS = mix(0.17, 0.87, fur);
	SPECULAR = mix(0.65, 0.26, fur);
	RIM = fur * 0.13;
	RIM_TINT = 0.45;
}
