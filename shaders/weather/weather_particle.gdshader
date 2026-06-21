shader_type spatial;
// Dibujo de las partículas de precipitación: billboard a cámara + descarte por partícula de las
// que quedan bajo el techo del terreno (rejilla de WeatherOcclusionField). Da "fuera sí, dentro
// no". El movimiento lo lleva el ParticleProcessMaterial; esto solo dibuja/oculta.
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform sampler2D albedo_tex : source_color, filter_linear;

// Rejilla de oclusión radial (la empuja WeatherFX cada frame).
uniform sampler2D occ_height_tex : filter_nearest;
uniform vec3 occ_center;
uniform vec3 occ_x;
uniform vec3 occ_z;
uniform vec3 occ_up;
uniform float occ_half_size = 50.0;
uniform float occ_span = 140.0;
uniform float occ_below = 60.0;
uniform float occ_enabled = 0.0;
// Oculta también una franja por encima del techo (roca): absorbe techo irregular + cuantización.
uniform float occ_margin = 4.0;

varying float v_hidden;

void vertex() {
	vec3 particle_pos = MODEL_MATRIX[3].xyz;
	v_hidden = 0.0;
	if (occ_enabled > 0.5) {
		vec3 rel = particle_pos - occ_center;
		float u = dot(rel, occ_x) / occ_half_size;
		float w = dot(rel, occ_z) / occ_half_size;
		if (abs(u) <= 1.0 && abs(w) <= 1.0) {   // fuera de la rejilla = sin dato = visible
			vec2 uv = vec2(u, w) * 0.5 + 0.5;
			// Dilatación 5-tap: techo más alto del vecindario, para tapar fugas en bordes (paredes).
			vec2 texel = 1.0 / vec2(textureSize(occ_height_tex, 0));
			float hn = textureLod(occ_height_tex, uv, 0.0).r;
			hn = max(hn, textureLod(occ_height_tex, uv + vec2(texel.x, 0.0), 0.0).r);
			hn = max(hn, textureLod(occ_height_tex, uv - vec2(texel.x, 0.0), 0.0).r);
			hn = max(hn, textureLod(occ_height_tex, uv + vec2(0.0, texel.y), 0.0).r);
			hn = max(hn, textureLod(occ_height_tex, uv - vec2(0.0, texel.y), 0.0).r);
			float terrain_h = hn * occ_span - occ_below;
			if (dot(rel, occ_up) < terrain_h + occ_margin) {
				v_hidden = 1.0;
			}
		}
	}

	// Billboard a cámara conservando la escala por partícula (snippet estándar Godot).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	if (v_hidden > 0.5) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ALPHA = texture(albedo_tex, UV).a * COLOR.a;
}
