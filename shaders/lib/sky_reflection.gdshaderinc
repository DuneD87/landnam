// Cielo reflejado, compartido. Aquí no hay ningún cubemap que reflejar: el cielo que se ve lo
// pinta un CompositorEffect POST_TRANSPARENT y el Sky del Environment es el espacio exterior, así
// que cualquier superficie que quiera reflejar cielo tiene que sintetizarlo. Esta es la
// aproximación que usa el agua desde siempre, ahora compartida con los bloques traslúcidos.

uniform vec3 sky_color_horizon : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 sky_color_zenith : source_color = vec3(0.30, 0.55, 0.85);
// Mismo degradado con el sol bajo el horizonte: sin esto se reflejaba cielo de día 24 h.
uniform vec3 sky_color_horizon_night : source_color = vec3(0.03, 0.04, 0.07);
uniform vec3 sky_color_zenith_night : source_color = vec3(0.01, 0.015, 0.035);
uniform float sky_gradient_power : hint_range(0.1, 50.0) = 2.5;

// Degradado horizonte→cenit del cielo reflejado. `up` es la radial del planeta: usar el eje Y
// del mundo daba por hecho un mundo plano, y el rayo en view-space ataba el degradado al eje
// vertical de la CÁMARA (giraba al mover la vista). `day` funde al cielo nocturno.
vec3 calculate_sky_color(vec3 view_direction, vec3 up, float day) {
    float vertical_angle = clamp(dot(view_direction, up) * 0.5 + 0.5, 0.0, 1.0);
    vertical_angle = pow(vertical_angle, sky_gradient_power);
    vec3 horizon = mix(sky_color_horizon_night, sky_color_horizon, day);
    vec3 zenith = mix(sky_color_zenith_night, sky_color_zenith, day);
    return mix(horizon, zenith, vertical_angle);
}
