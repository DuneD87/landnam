// Cielo reflejado, compartido. Aquí no hay ningún cubemap que reflejar: el cielo que se ve lo
// pinta un CompositorEffect POST_TRANSPARENT y el Sky del Environment es el espacio exterior, así
// que cualquier superficie que quiera reflejar cielo tiene que sintetizarlo. Esta es la
// aproximación que usa el agua desde siempre, ahora compartida con los bloques traslúcidos.
//
// Los colores los calcula SkyLighting cada frame con el mismo modelo de dispersión que pinta el
// cielo visible, en el marco del observador: siguen la hora, el lugar del planeta, la luna y el
// clima (antes eran dos paletas fijas, día y noche, y el agua reflejaba cielo azul al atardecer).
global uniform vec3 sky_zenith_radiance;
global uniform vec3 sky_horizon_sun_radiance;
global uniform vec3 sky_horizon_side_radiance;
global uniform vec3 sky_horizon_anti_radiance;
// Halo alrededor del sol (la corona que pinta el cielo): naranja al ponerse, casi blanco alto.
global uniform vec3 sky_sun_glow_radiance;
global uniform vec3 sky_sun_direction;
uniform float sky_gradient_power : hint_range(0.1, 50.0) = 2.5;

// Degradado horizonte→cenit del cielo reflejado. `up` es la radial del planeta: usar el eje Y
// del mundo daba por hecho un mundo plano, y el rayo en view-space ataba el degradado al eje
// vertical de la CÁMARA (giraba al mover la vista). En el horizonte se funde del lado del sol
// (naranja al ponerse) al lado opuesto según el azimut del rayo.
vec3 calculate_sky_color(vec3 view_direction, vec3 up) {
    float vertical_angle = clamp(dot(view_direction, up) * 0.5 + 0.5, 0.0, 1.0);
    vertical_angle = pow(vertical_angle, sky_gradient_power);
    vec3 view_flat = view_direction - up * dot(view_direction, up);
    vec3 sun_flat = sky_sun_direction - up * dot(sky_sun_direction, up);
    float toward_sun = dot(view_flat, sun_flat)
        * inversesqrt(max(dot(view_flat, view_flat) * dot(sun_flat, sun_flat), 1e-8));
    // Tres muestras en azimut, como el ambiente: lado del sol, de costado y opuesto. Con solo las
    // dos puntas, a media vuelta del sol el reflejo mezclaba el rosa de junto al sol con el marrón
    // del lado opuesto y el agua salía lavanda bajo un cielo naranja.
    vec3 horizon = toward_sun >= 0.0
        ? mix(sky_horizon_side_radiance, sky_horizon_sun_radiance, toward_sun)
        : mix(sky_horizon_side_radiance, sky_horizon_anti_radiance, -toward_sun);
    // El halo solo existe donde el sol está sobre el horizonte de ESTE punto: desde órbita el sol
    // no está filtrado y el agua del lado nocturno lo reflejaba en manchas blancas sobre el oleaje.
    float glow = pow(max(dot(view_direction, sky_sun_direction), 0.0), 8.0)
        * smoothstep(-0.1, 0.02, dot(up, sky_sun_direction));
    return mix(horizon, sky_zenith_radiance, vertical_angle) + sky_sun_glow_radiance * glow;
}
