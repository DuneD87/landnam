// =============================================================================
//  grass_patch_bake.gdshader
//  Material temporal de horneado: solo se usa dentro del SubViewport de
//  planet.gd::_bake_grass_patch, nunca en la escena real.
//
//  Reproduce el degradado base->punta de grass_wind.gdshader pero SIN luz de
//  escena: la textura horneada guarda albedo puro y es la tarjeta
//  (grass_patch_impostor) la que aplica el terminador día/noche en tiempo real.
//  Si se horneara con luz, el parche llevaría un sol fijo pintado encima.
// =============================================================================
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.06, 0.30, 0.04, 1.0); // raíz, más oscuro
uniform vec4 tip_color  : source_color = vec4(0.20, 0.65, 0.10, 1.0); // punta, más claro
uniform float grass_height : hint_range(0.05, 5.0, 0.01) = 1.0;
// Oscurece la base para fingir la oclusión del interior del parche, que un
// render plano no tiene.
uniform float ao_strength : hint_range(0.0, 1.0, 0.01) = 0.35;

varying float height_factor;

void vertex() {
	// En el horneado el clúster está apoyado en y=0, así que la altura mundo
	// equivale a la altura sobre la base de la brizna.
	float h = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	height_factor = clamp(h / grass_height, 0.0, 1.0);
}

void fragment() {
	vec3 c = mix(base_color.rgb, tip_color.rgb, height_factor);
	ALBEDO = c * mix(1.0 - ao_strength, 1.0, height_factor);
}
