shader_type spatial;
// Billboards de árboles lejanos del PlanetForest: un quad por instancia
// orientado a cámara (cilíndrico alrededor del up del árbol), especie
// seleccionada en el atlas via INSTANCE_CUSTOM.r. Iluminación: la MISMA ruta
// planetaria que el follaje real (compute_planet_light + ambient de Environment
// + niebla), para quedar a juego con las mallas en cualquier clima. Los fades
// por distancia son complementarios al fade de malla de
// transparent_material_shader mediante una selección estable por árbol.
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/lib/planet_lighting.gdshaderinc"

uniform sampler2D impostor_texture : source_color, filter_linear_mipmap;
uniform float atlas_grid = 4.0;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.35; // <0.5: los mips encogen el alpha y a distancia la copa se ralea
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform bool debug_unlit = false; // true: muestra el atlas sin luz (diagnóstico)

uniform float near_cutoff = 500.0; // distancia donde el billboard cede a la malla real
uniform float near_band = 80.0;
uniform float far_cutoff = 2850.0; // horizonte del bosque
uniform float far_band = 150.0;
instance uniform float cell_fade : hint_range(0.0, 1.0) = 1.0; // fade de nacimiento por celda

varying vec2 atlas_uv;
varying vec2 atlas_uv_top;
varying vec2 quad_uv;
varying float v_fade;
varying float v_top;
varying float v_tree_random;

// Debe ser idéntica a forest_stable_tree_random() del material de hojas.
float forest_stable_tree_random(vec3 world_origin) {
	vec3 radial = normalize(world_origin - planet_position);
	vec3 tree_key = floor(radial * 32768.0 + 0.5);
	return fract(sin(dot(tree_key, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

void vertex() {
	vec3 inst_origin = MODEL_MATRIX[3].xyz;
	v_tree_random = forest_stable_tree_random(inst_origin);
	float dist = distance(inst_origin, CAMERA_POSITION_WORLD);
	float f_near = smoothstep(near_cutoff - near_band, near_cutoff, dist);
	float f_far = 1.0 - smoothstep(far_cutoff, far_cutoff + far_band, dist);
	v_fade = f_near * f_far * cell_fade;

	vec3 y_axis = MODEL_MATRIX[1].xyz;
	float bs = length(y_axis);
	vec3 up_w = y_axis / bs;
	vec3 to_cam = CAMERA_POSITION_WORLD - inst_origin;

	// Visto desde arriba el quad cilíndrico queda de canto (anillos aplastados
	// y agujero bajo la cámara). Según la elevación de la cámara, el quad se
	// inclina hacia la horizontal y la textura funde a la vista cenital que el
	// baker deja en slot + mitad del atlas (INSTANCE_CUSTOM.a = su fit; 0 = no hay).
	float elev = dot(to_cam, up_w) / max(dist, 1e-3);
	float fit_top = INSTANCE_CUSTOM.a;
	v_top = (fit_top > 0.0) ? smoothstep(0.65, 0.95, elev) : 0.0;

	// gb del custom data: fracción del slot que ocupa el contenido real (medida
	// al hornear). El quad encoge a ese rectángulo y el UV se remapea igual:
	// mismos texels en pantalla, muchos menos transparentes que descartar.
	float slot = INSTANCE_CUSTOM.r;
	vec2 fit = (INSTANCE_CUSTOM.g > 0.0) ? INSTANCE_CUSTOM.gb : vec2(1.0);
	vec2 g_fit = mix(fit, vec2(fit_top), v_top);
	vec2 tile = vec2(mod(slot, atlas_grid), floor(slot / atlas_grid));
	atlas_uv = (tile + vec2(0.5) + (UV - 0.5) * g_fit) / atlas_grid;
	float slot_top = slot + atlas_grid * atlas_grid * 0.5;
	vec2 tile_top = vec2(mod(slot_top, atlas_grid), floor(slot_top / atlas_grid));
	atlas_uv_top = (tile_top + vec2(0.5) + (UV - 0.5) * g_fit) / atlas_grid;
	quad_uv = UV;

	if (v_fade <= 0.001) {
		VERTEX = vec3(0.0); // colapsa la instancia oculta: sin coste de raster
	} else {
		// Billboard cilíndrico: gira el quad hacia la cámara alrededor del up
		// del árbol. Solo se transforma el OFFSET como vector (w=0): reconstruir
		// la posición con inverse() en coords mundo grandes pierde precisión, y
		// con base ortogonal de escala uniforme la inversa es transpuesta / bs².
		vec3 h = to_cam - up_w * dot(to_cam, up_w);
		float hl = length(h);
		vec3 fwd = (hl > 1e-3) ? h / hl : normalize(MODEL_MATRIX[2].xyz);
		vec3 right_w = normalize(cross(up_w, fwd));
		// El eje vertical del quad rota de up_w a fwd con v_top: a vista cenital
		// plena el quad yace horizontal (plano right/fwd) mostrando la copa.
		vec3 v_axis = normalize(mix(up_w, fwd, v_top));
		vec3 world_offset = right_w * (VERTEX.x * bs * g_fit.x) + v_axis * (VERTEX.y * bs * g_fit.y);
		VERTEX = (transpose(mat3(MODEL_MATRIX)) * world_offset) / (bs * bs);
	}

	vertex_position_global = inst_origin;
	planet_normal = normalize(inst_origin - planet_position);
	float day_f;
	vec3 amb;
	compute_planet_vertex_light(inst_origin, planet_normal, day_f, amb);
	planet_day_factor = day_f;
	planet_ambient = amb;
}

void fragment() {
	if (v_fade < 0.999 && v_tree_random < 1.0 - v_fade) {
		discard;
	}
	vec4 tex = texture(impostor_texture, atlas_uv);
	if (v_top > 0.001) {
		tex = mix(tex, texture(impostor_texture, atlas_uv_top), v_top);
	}
	if (tex.a < alpha_scissor_threshold) {
		discard;
	}
	ALBEDO = tex.rgb * brightness;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (debug_unlit) {
		ALBEDO = vec3(0.0);
		EMISSION = tex.rgb;
	}
	// Normal esférica falsa: la copa sombrea como volumen orientado a cámara.
	// Con normal plana (up del planeta), un sol bajo daba NdotL ~0.2 uniforme y
	// el billboard quedaba a oscuras mientras el follaje real (normales en todas
	// direcciones) seguía iluminado.
	vec3 up_view = normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz);
	vec2 c = vec2(quad_uv.x - 0.5, 0.5 - quad_uv.y) * 2.0;
	NORMAL = normalize(vec3(c.x, c.y, 1.2) + up_view * 0.5);
}

void light() {
	// Misma iluminación que transparent_material_shader (ver el include).
	vec3 d, s;
	compute_planet_light(
		NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION,
		ALBEDO, 0.0, ROUGHNESS, 0.0, 1.0,
		planet_day_factor, planet_ambient, LIGHT_IS_DIRECTIONAL, d, s);
	DIFFUSE_LIGHT += d;
}
