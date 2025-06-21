shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_add;

uniform vec3 center;
uniform vec3 atmosphere_color = vec3(0.4, 0.6, 1.0);
uniform float atmosphere_radius = 1.05;
uniform float atmosphere_density = 1.0;
uniform float atmosphere_falloff = 4.0;
uniform float atmosphere_intensity = 1.0;
uniform float horizon_fade = 2.0;
uniform float ground_fade = 4.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

void fragment() {
    // Dirección de la vista desde el punto de la atmósfera
    vec3 view_dir = normalize(-VIEW);
    
    // Ángulo entre vista y dirección solar
    float sun_dot = clamp(dot(view_dir, sun_direction), 0.0, 1.0);
    
    // Scattering más fuerte cuando el ángulo vista-sol es pequeño
    float scattering = pow(sun_dot, horizon_fade);
    
    // Altura desde el centro del planeta
    float height = length(center);
    float height_diff = max(height - 1.0, 0.0); // Suponemos radio del planeta = 1.0
    float height_factor = exp(-height_diff * atmosphere_falloff);
    
    // Fade al acercarse al terreno
    float fade_ground = smoothstep(0.0, 1.0, height_diff * ground_fade);
    
    vec3 final_color = atmosphere_color * scattering * height_factor * fade_ground * atmosphere_intensity;
    
    ALBEDO = final_color;
    ALPHA = clamp(length(final_color), 0.0, 1.0);
}
