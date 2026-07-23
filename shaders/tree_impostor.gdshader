// =============================================================================
//  tree_impostor.gdshader
//  Aspa billboard usada como LOD3 de los árboles (ver planet.gd::_bake_tree_impostor).
//  Es "unshaded" (barato de lejos) PERO respeta el terminador día/noche del
//  planeta: oscurece la cara nocturna igual que el resto de la vegetación, en
//  vez de brillar a albedo pleno de noche.
//
//  El terminador se calcula por vértice con la MISMA fórmula que
//  planet_lighting.gdshaderinc::compute_planet_vertex_light. No incluimos ese
//  archivo porque aquí no hay light() (unshaded) y solo necesitamos day_factor.
//
//  planet.gd empuja cada frame light_direction y planet_position (igual que a
//  los materiales de follaje, vía item_transparent_materials). NO renombrar.
// =============================================================================
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

// Alimentados por el planeta (mismos nombres que planet_lighting.gdshaderinc).
uniform vec3 light_direction = vec3(1.0, 0.0, 0.0);
uniform vec3 planet_position;
uniform float transition_width : hint_range(0.0, 1.0, 0.01) = 0.2;
// Cuánta luz conserva la cara nocturna (0 = negro puro). Evita que el impostor
// desaparezca de noche y aproxima el ambient del follaje cercano.
uniform float night_light : hint_range(0.0, 1.0, 0.01) = 0.2;

varying float day_factor;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 sun_dir = normalize(-light_direction);
	vec3 to_planet = normalize(planet_position - world_pos);
	day_factor = smoothstep(-transition_width, transition_width, dot(to_planet, sun_dir));
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	if (tex.a < alpha_scissor_threshold) {
		discard;
	}
	ALBEDO = tex.rgb * mix(night_light, 1.0, day_factor);
}
