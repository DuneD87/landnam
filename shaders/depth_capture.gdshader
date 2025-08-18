shader_type spatial;

render_mode unshaded;

uniform float cam_near = 0.05;
uniform float cam_far = 1000.0;

varying float vertex_depth;

void vertex() {
    vertex_depth = -(VIEW_MATRIX * MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
    float normalized_depth = (vertex_depth - cam_near) / (cam_far - cam_near);
    ALBEDO = vec3(clamp(normalized_depth, 0.0, 1.0));
}