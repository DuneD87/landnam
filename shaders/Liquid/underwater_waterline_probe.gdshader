// GPU regression probe for the same outside-water discard used by the ocean.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
#include "res://shaders/liquid/underwater_fog.gdshaderinc"
uniform vec3 waterline_point;
uniform vec3 waterline_normal;
void vertex() { POSITION = vec4(VERTEX.xy, 0.0, 1.0); }
void fragment() {
    vec4 near_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
    vec3 near_offset = mat3(INV_VIEW_MATRIX) * (near_view.xyz / near_view.w);
    if (waterline_signed_relative(CAMERA_POSITION_WORLD, near_offset, waterline_point, waterline_normal) < 0.0) discard;
    ALBEDO = vec3(1.0, 0.0, 0.0);
}
