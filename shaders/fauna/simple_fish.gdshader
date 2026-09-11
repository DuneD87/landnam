shader_type spatial;
render_mode cull_disabled;

instance uniform vec4 fish_color : source_color = vec4(1.0);
instance uniform int fish_type = 0;
instance uniform float swim_phase = 0.0;
instance uniform float swim_frequency = 6.0;

void vertex() {
    float phase = TIME * swim_frequency + swim_phase;
    float tail = UV2.y;
    VERTEX.x += sin(phase - VERTEX.z * 3.0) * 0.07 * tail;
    if (UV2.x > 0.5 && UV2.x < 1.5) {
        VERTEX.x += sin(phase * 1.3 + VERTEX.z * 7.0) * 0.007;
    }
}

float band(float position, float center, float width) {
    return 1.0 - smoothstep(width, width + 0.008, abs(position - center));
}

void fragment() {
    if (UV2.x > 0.5 && UV2.x < 1.5 && dot(NORMAL, VIEW) < 0.0) {
        NORMAL = -NORMAL;
    }
    vec3 color = COLOR.rgb;
    if (UV2.x < 0.5) {
        float u = UV.x;
        float v = UV.y;
        if (fish_type == 0) {
            // Silver flank and a fine blue lateral line.
            color = mix(color, vec3(0.12, 0.32, 0.43), band(v, 0.54, 0.012) * 0.45);
        } else if (fish_type == 1) {
            float lines = pow(0.5 + 0.5 * sin(v * 72.0), 10.0);
            color *= 1.0 - 0.12 * lines;
            color = mix(color, vec3(0.83, 0.57, 0.12), band(u, 0.15, 0.033) * smoothstep(0.57, 0.78, v));
        } else if (fish_type == 2) {
            float p = u + 0.025 * sin(v * 10.0);
            float edge = max(band(p, 0.20, 0.058), max(band(p, 0.52, 0.078), band(p, 0.87, 0.052)));
            float white = max(band(p, 0.20, 0.038), max(band(p, 0.52, 0.056), band(p, 0.87, 0.034)));
            color = mix(color, vec3(0.035, 0.055, 0.065), edge);
            color = mix(color, vec3(0.91, 0.94, 0.85), white);
        } else if (fish_type == 3) {
            float stripes = pow(0.5 + 0.5 * sin((u + abs(v - 0.5) * 0.65) * 90.0), 10.0);
            color *= 1.0 - stripes * 0.17;
            color = mix(color, vec3(0.045, 0.065, 0.075), band(u + 0.045 * (v - 0.5), 0.18, 0.055));
            vec2 spot = (UV - vec2(0.77, 0.61)) * vec2(1.0, 0.85);
            color = mix(color, vec3(0.10, 0.14, 0.16), 1.0 - smoothstep(0.053, 0.065, length(spot)));
        } else if (fish_type == 4) {
            float curve = 0.52 + sin(u * 3.14159) * 0.19;
            float marking = band(v, curve, 0.050) * smoothstep(0.22, 0.33, u);
            marking = max(marking, smoothstep(0.56, 0.72, u) * band(v, 0.52, 0.085));
            color = mix(color, vec3(0.025, 0.050, 0.11), marking);
        } else if (fish_type == 5) {
            float stripes = smoothstep(0.60, 0.78, sin(v * 32.0 + sin(u * 9.0) * 0.5));
            color = mix(color, vec3(0.76, 0.20, 0.43), stripes * 0.88);
        }
    }
    ALBEDO = color * (UV2.x < 1.5 ? fish_color.rgb : vec3(1.0));
    ROUGHNESS = UV2.x > 1.5 ? 0.25 : 0.48;
    SPECULAR = 0.4;
}
