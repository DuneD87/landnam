// =============================================================================
//  grass_patch_impostor.gdshader
//  Tarjeta que sustituye a un PARCHE ENTERO de hierba a distancia (ver
//  planet.gd::_bake_grass_patch). Una instancia vale por decenas de matas, que es
//  lo que compensa que las bandas de LOD altas den menos instancias por m².
//
//  Geometría: aspa vertical (silueta contra el horizonte) + quad horizontal (la
//  alfombra vista en picado). COLOR.r elige la capa del Texture2DArray horneado:
//  0 = vista lateral para el aspa, 1 = vista cenital para el horizontal.
//
//  Iluminación: la textura horneada es albedo PURO (grass_patch_bake la pinta sin
//  luz), y aquí se ilumina con el mismo planet_lighting.gdshaderinc que
//  grass_wind.gdshader, para que el relevo entre hierba real y tarjeta no cambie
//  de color. Va iluminado y no unshaded a propósito: un material unshaded no
//  recibe sombras ni difuso, y a media tarde quedaba de un verde plano que no
//  pertenecía al paisaje.
//
//  La normal es el "arriba" radial y no la del quad: el parche se comporta como el
//  suelo que cubre, no como dos cartones. En espacio local de la instancia ese
//  arriba es +Y (el instancer las coloca con up_mode SPHERE).
//
//  Cerca de la cámara la tarjeta se colapsa a un punto (VERTEX *= grow): ahí ya
//  está la hierba real de LOD0/LOD1 y así no paga fill ninguno. fade_start debe
//  solaparse con el fade_start/fade_end de grass_wind.gdshader o se verá un hueco
//  sin hierba en la banda intermedia.
//
//  planet.gd empuja cada frame light_direction y planet_position (vía
//  item_transparent_materials). NO renombrar.
// =============================================================================
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

#include "res://shaders/lib/planet_lighting.gdshaderinc"

uniform sampler2DArray patch_atlas : source_color, filter_linear_mipmap;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.01) = 0.25;

// Aparición por distancia: por debajo de fade_start la tarjeta no existe.
uniform float fade_start : hint_range(0.0, 3000.0, 1.0) = 70.0;
uniform float fade_width : hint_range(1.0, 1000.0, 1.0) = 40.0;

// El quad horizontal solo funciona si se mira desde arriba: rasante se ve de canto,
// la textura cenital se comprime en pantalla y queda un borrón horizontal. Se apaga
// por ángulo (|cos| entre la vista y el "arriba" radial) y deja el trabajo al aspa.
uniform float ground_fade_min : hint_range(0.0, 1.0, 0.01) = 0.10;
uniform float ground_fade_max : hint_range(0.0, 1.0, 0.01) = 0.35;

// Translucencia y rim del include: 0 los salta enteros (son view-dependent y caros).
// Subirlo acerca el tono al de la hierba cercana a contraluz, a cambio de fragmento.
uniform float light_detail : hint_range(0.0, 1.0, 0.01) = 0.0;

// Suelo de luz ambiente propio. El include multiplica SU ambient por ATTENUATION, que
// ya lleva dentro el término de sombra, así que una tarjeta a la sombra se quedaba sin
// difuso Y sin ambiente: negro puro. Este se suma al margen de la sombra, solo con el
// sol, para que quede oscura pero perteneciendo al paisaje. 0 = comportamiento anterior.
uniform float ambient_floor : hint_range(0.0, 2.0, 0.01) = 1.0;

// Diagnóstico: apagar un quad para ver cuál sostiene realmente la imagen.
uniform float cross_enabled : hint_range(0.0, 1.0, 1.0) = 1.0;
uniform float ground_enabled : hint_range(0.0, 1.0, 1.0) = 1.0;
// 0 = normal | 1 = aspa roja / suelo azul | 2 = UV en color (rojo=u, verde=v):
// si el mapeo estuviera deformado, el degradado saldría comprimido en un eje |
// 3 = sin recorte de alfa: enseña el rectángulo entero que ocupa la textura.
// Los modos 1 y 2 salen por EMISSION, sin iluminar, para que se lean a cualquier hora.
uniform int debug_mode : hint_range(0, 3, 1) = 0;

varying float atlas_layer;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	atlas_layer = step(0.5, COLOR.r);

	vec3 to_cam = CAMERA_POSITION_WORLD - base;
	// "Arriba" de ESTA instancia, desde el centro del planeta que la lleva.
	vec3 up = normalize(base - planet_position);
	float ground_w = smoothstep(ground_fade_min, ground_fade_max, abs(dot(normalize(to_cam), up)));

	// max() en el borde: con fade_width 0 los dos bordes coinciden y smoothstep queda
	// indefinido en GLSL (puede salir NaN y llevarse la tarjeta por delante).
	float grow = smoothstep(fade_start, fade_start + max(fade_width, 0.001), length(to_cam));
	VERTEX *= grow * mix(cross_enabled, ground_enabled * ground_w, atlas_layer);

	NORMAL = vec3(0.0, 1.0, 0.0);

	vertex_position_global = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	planet_normal = up;
	float day_f;
	vec3 amb;
	compute_planet_vertex_light(vertex_position_global, planet_normal, day_f, amb);
	planet_day_factor = day_f;
	planet_ambient = amb;
}

void fragment() {
	vec4 tex = texture(patch_atlas, vec3(UV, atlas_layer));
	// Los modos 2 y 3 quieren ver el quad entero, así que se saltan el recorte.
	if (tex.a < alpha_scissor_threshold && debug_mode < 2) {
		discard;
	}

	vec3 debug_col = vec3(0.0);
	if (debug_mode == 1) {
		debug_col = mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.3, 1.0), atlas_layer);
	} else if (debug_mode == 2) {
		debug_col = vec3(UV, 0.0);
	}
	bool is_debug = debug_mode == 1 || debug_mode == 2;

	ALBEDO = is_debug ? vec3(0.0) : tex.rgb;
	EMISSION = debug_col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// Mismos parámetros que grass_wind.gdshader (specular y ao a 0) para que el
	// relevo no se note; detail 0 salta translucencia/rim, que a esta distancia no
	// se aprecian y cuestan 3 pow por fragmento.
	vec3 d, s;
	compute_planet_light(
		NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
		ALBEDO, METALLIC, ROUGHNESS, 0.0, 0.0,
		planet_day_factor, planet_ambient, LIGHT_IS_DIRECTIONAL, light_detail, d, s);
	DIFFUSE_LIGHT += d;

	// Solo con el sol: en light() por luz, sumarlo sin condición lo contaría una vez
	// por antorcha.
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += planet_ambient * mix(0.3, 1.0, planet_day_factor) * ambient_floor;
	}
}
