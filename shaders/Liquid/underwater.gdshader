// Parameter carrier for UnderwaterRenderPass. Never attached to geometry.
shader_type spatial;
render_mode unshaded, depth_draw_never;

#include "res://shaders/liquid/gerstner_waves.gdshaderinc"
#include "res://shaders/liquid/underwater_fog.gdshaderinc"
#include "res://shaders/liquid/ship_interiors.gdshaderinc"

uniform vec3 planet_center;
uniform float water_time = 0.0;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);

uniform vec3 absorption_coefficients = vec3(0.45, 0.18, 0.06);
// Extinction separates absorption from suspended-particle scattering.
uniform float absorption_scale = 0.4;
uniform vec3 scattering_coefficients = vec3(0.015, 0.022, 0.020);
uniform float surface_exposure = 0.95;
uniform float surface_saturation = 0.65;
uniform float fog_density : hint_range(0.0, 4.0) = 1.0;
uniform float sun_glow_intensity : hint_range(0.0, 2.0) = 0.35;
uniform float sun_glow_power : hint_range(1.0, 32.0) = 8.0;
uniform float tir_reflection_depth = 60.0;
uniform float scatter_vertical_range = 40.0;
uniform float distance_depth_gain : hint_range(0.0, 3.0) = 0.7;
uniform float distance_depth_max = 120.0;
uniform float meniscus_width = 0.25;
uniform float meniscus_strength = 0.3;
uniform float waterline_seal_distance = 3.0;
uniform float waterline_seal_band = 0.06;

uniform float surface_search_distance = 80.0;
uniform float underside_refraction : hint_range(0.0, 8.0) = 4.5;
// Metres along the underwater view ray at which surface projection falls to 1/e.
uniform float surface_projection_distance : hint_range(1.0, 100.0) = 18.0;
uniform float surface_reflection_strength : hint_range(0.0, 1.0) = 1.0;
// Tamaño en metros de la ondulación del techo, relativo al detalle del material exterior.
// Por encima de 1 el techo es más liso que el mar visto desde arriba; por debajo, más picado.
uniform float surface_ripple_scale : hint_range(0.05, 6.0) = 1.0;
// Fuerza de esa ondulación, independiente de normal_intensity, que la comparte el exterior.
uniform float surface_ripple_strength : hint_range(0.0, 6.0) = 4.0;
// 0 reproduce la transición ancha anterior; 1 es el ángulo crítico real de Snell.
uniform float surface_window_sharpness : hint_range(0.0, 1.0) = 0.8;
// The same animated detail maps used by the visible ocean surface.
uniform sampler2D texture_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D texture_normal2 : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float normal_scale1 = 8.0;
uniform float normal_scale2 = 23.0;
uniform float normal_intensity = 0.65;
uniform float normal_slope_limit = 0.16;

uniform float godray_intensity : hint_range(0.0, 8.0) = 1.0;
uniform int godray_samples : hint_range(4, 32) = 24;
uniform float godray_max_distance = 40.0;
// Multiplicador del tamaño de celda respecto a caustics_scale. Toca escala y scroll a la
// vez, así que cambia el grano sin cambiar la velocidad en metros por segundo.
uniform float godray_pattern_scale = 1.0;
// Sesgo sobre la velocidad de las cáusticas: 1.0 = exactamente su mismo movimiento.
uniform float godray_pattern_speed = 1.0;
uniform float godray_sharpness : hint_range(0.5, 16.0) = 6.0;
uniform float godray_phase_power : hint_range(1.0, 32.0) = 6.0;
uniform float godray_min_phase : hint_range(0.0, 1.0) = 0.15;
// Ata los haces a la ola: la faceta encarada al sol transmite y la de canto no. Queda a 0
// por defecto porque los ata TAMBIÉN a su velocidad, y una ola de 60 m viaja a ~10 m/s. Con
// esto encendido no hay forma de que los haces se muevan despacio: o van a velocidad de ola,
// o el patrón de la textura se desliza contra ellos y eso es lo que se percibe como
// parpadeo. Las cuchillas ya las dibuja la textura a godray_pattern_scale 0.15.
uniform float godray_surface_focus : hint_range(0.0, 64.0) = 0.0;

uniform sampler2D caustics_texture : filter_linear_mipmap, repeat_enable;
uniform float caustics_scale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float caustics_speed : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float caustics_intensity : hint_range(0.0, 2.0, 0.1) = 0.8;
// 0.7 apagaba las cáusticas en 1.4 m de profundidad; la superficie usa 0.22.
uniform float caustics_depth_fade : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float caustics_near_fade : hint_range(0.0, 10.0, 0.1) = 1.5;

uniform int debug_mode : hint_range(0, 8) = 0;
uniform float debug_scale = 20.0;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform vec3 waterline_point;
uniform vec3 waterline_normal;

void vertex() {}
void fragment() { ALBEDO = vec3(0.0); }
