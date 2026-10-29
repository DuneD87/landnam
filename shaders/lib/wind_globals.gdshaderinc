// =============================================================================
//  wind_globals.gdshaderinc
//  Viento global de la vegetación, lo empuja planet.gd (_advance_wind_clock) cada frame:
//    wind_gain   multiplicador del clima con sus rachas (1 sin clima). Escala la amplitud.
//    wind_clock  integral de wind_gain en segundos. Sustituye a TIME en las fases que deben
//                acelerar con el viento: TIME * wind_speed salta de fase al cambiar la intensidad.
//  Fuera del juego (previews, tests) wind_clock queda en 0: usar wind_time(), que cae a TIME.
// =============================================================================
#ifndef WIND_GLOBALS_INC
#define WIND_GLOBALS_INC

global uniform float wind_gain;
global uniform float wind_clock;

float wind_time() {
	return wind_clock > 0.0 ? wind_clock : TIME * wind_gain;
}

#endif
