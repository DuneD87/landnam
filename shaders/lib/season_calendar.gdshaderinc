// =============================================================================
//  season_calendar.gdshaderinc
//  La fecha del calendario (sun_controller.gd la empuja en season_state) y la estación de cada
//  sitio: el norte y el sur van al revés y la franja del ecuador no tiene estaciones. Lo incluye
//  climate.gdshaderinc (el invierno enfría: baja la cota de nieve) y, a través de él,
//  season.gdshaderinc (árboles, hierba, sotobosque). scripts/planet/seasons.gd es la réplica en CPU.
// =============================================================================
#ifndef SEASON_CALENDAR_INC
#define SEASON_CALENDAR_INC

// x = fase del año (0 = equinoccio de primavera del norte, 0,25 = solsticio de verano del norte),
// y = declinación del sol (grados), z = inclinación del eje (grados), w = 1 con estaciones.
// Con w = 0 (herramientas, horneado) todo se queda en verano.
global uniform vec4 season_state;

// Franja del ecuador sin estaciones: el ciclo entra entre estas dos latitudes (grados). Estrecha a
// propósito: los bosques caducos llegan casi al ecuador y el punto de partida está a 17°.
#define SEASON_TROPIC_START 3.0
#define SEASON_TROPIC_END 12.0
// Frío del invierno pleno, en grados de latitud equivalente (los de climate_coldness): baja la cota
// de nieve. El verano no suma nada: la calibración del clima es la del verano.
#define SEASON_WINTER_COLD 14.0
// Retraso térmico: lo más cálido llega este tanto de fase después del solsticio de verano (y lo más
// frío, después del de invierno). La primavera sale así más fría que el otoño.
#define SEASON_THERMAL_LAG 0.05

// |latitud| en grados.
float season_abs_latitude(vec3 local) {
	return degrees(asin(clamp(abs(local.y) / max(length(local), 0.001), 0.0, 1.0)));
}

float season_local_phase(vec3 local) {
	return local.y >= 0.0 ? season_state.x : fract(season_state.x + 0.5);
}

// 0 sin estaciones (calendario apagado, ecuador) .. 1 ciclo completo.
float season_strength(vec3 local) {
	if (season_state.w < 0.5 || length(local) < 1.0) {
		return 0.0;
	}
	return smoothstep(SEASON_TROPIC_START, SEASON_TROPIC_END, season_abs_latitude(local));
}

// Frío de la estación: 0 en lo más cálido del verano .. 1 en lo más frío del invierno.
float season_chill(vec3 local) {
	float p = season_local_phase(local);
	return (1.0 - cos(TAU * (p - 0.25 - SEASON_THERMAL_LAG))) * 0.5 * season_strength(local);
}

#endif
