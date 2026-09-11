shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

instance uniform vec3 planet_center = vec3(0.0);
instance uniform float water_radius = 1.0;
varying vec3 world_position;

void vertex() {
    // Face the camera but preserve the particle's growth scale.
    mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    billboard[0].xyz *= length(MODEL_MATRIX[0].xyz);
    billboard[1].xyz *= length(MODEL_MATRIX[1].xyz);
    billboard[2].xyz *= length(MODEL_MATRIX[2].xyz);
    MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
    world_position = (billboard * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    if (length(world_position - planet_center) >= water_radius) discard;
    vec2 p = UV * 2.0 - 1.0;
    float fringe = 0.10 * sin(p.x * 12.0 + TIME * 0.7) * sin(p.y * 10.0 - TIME * 0.4);
    float density = 1.0 - smoothstep(0.12, 1.0, dot(p, p) + fringe);
    // Transparent particles render after underwater fog: attenuate their tint with
    // distance too, so a remote puff doesn't appear bright red through the whole sea.
    float distance_m = length(world_position - INV_VIEW_MATRIX[3].xyz);
    ALBEDO = mix(vec3(0.28, 0.006, 0.018), vec3(0.0, 0.12, 0.16), 1.0 - exp(-distance_m * 0.06));
    ALPHA = density * COLOR.a * exp(-distance_m * 0.015);
}
