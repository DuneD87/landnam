// =============================================================================
//  toon_light.gdshaderinc
//  Luz directa por bandas suaves (a lo BotW) para el sol, la luna y las luces locales.
//
//  Solo pasa por la rampa el factor de luz directa (N·L × sombra). El ambiente del cielo,
//  que ya es azulado, rellena el lado en sombra; la translucencia, el rim y el especular
//  siguen como estaban. Con toon_amount = 0 el resultado es exactamente Lambert × ATTENUATION,
//  la luz de siempre (consola: `toon`).
//
//  Uso desde light():
//    DIFFUSE_LIGHT += toon_direct(ndl, ATTENUATION, toon_shadow_floor, LIGHT_IS_DIRECTIONAL)
//        * LIGHT_COLOR / PI;
//  en lugar de ndl * ATTENUATION * LIGHT_COLOR / PI.
// =============================================================================
#ifndef TOON_LIGHT_INC
#define TOON_LIGHT_INC

// 0 = luz física, 1 = bandas.
global uniform float toon_amount;
// N·L en el que cae el borde luz/sombra: más alto = más superficie en sombra.
global uniform float toon_threshold;
// Ancho del borde, en N·L. También endurece la penumbra de las sombras arrojadas:
// 0.1 la deja casi como está, 0.02 la vuelve un corte.
global uniform float toon_softness;
// Cuánto del degradado de Lambert conserva la cara iluminada: 0 = plana, 1 = Lambert entero.
global uniform float toon_gradient;
// Lo que vale ATTENUATION a la sombra plena del sol (1 - shadow_opacity). Lo mantiene
// SkyLighting, que sube la opacidad a 1 bajo tierra.
global uniform float toon_shadow_floor;

// lit: N·L (o el difuso envolvente) en [0, 1]. att: ATTENUATION. att_floor: ATTENUATION a la
// sombra plena (toon_shadow_floor, o 0 si el shader ya la remapeó a [0, 1], como el terreno).
// En las luces locales ATTENUATION lleva también la caída con la distancia: escalonarla dibujaría
// anillos alrededor de las antorchas, así que solo pasa N·L por la rampa.
float toon_direct(float lit, float att, float att_floor, bool is_directional) {
	if (toon_amount <= 0.0) {
		return lit * att;
	}
	float soft = max(toon_softness, 0.001);
	float band = smoothstep(toon_threshold - soft, toon_threshold + soft, lit)
		* mix(1.0, lit, toon_gradient);
	float shadow = att;
	if (is_directional) {
		float t = clamp((att - att_floor) / max(1.0 - att_floor, 0.0001), 0.0, 1.0);
		shadow = mix(att_floor, 1.0, smoothstep(0.5 - 5.0 * soft, 0.5 + 5.0 * soft, t));
	}
	return mix(lit * att, band * shadow, toon_amount);
}

#endif // TOON_LIGHT_INC
