shader_type spatial;
// Horneado de billboards del PlanetForest: albedo plano sin iluminación, con
// alpha scissor, para capturar cada especie de árbol a su slot del atlas.
render_mode unshaded, cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_linear_mipmap;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 tex = texture(texture_albedo, UV) * albedo;
	if (tex.a < alpha_scissor_threshold) {
		discard;
	}
	ALBEDO = tex.rgb;
}
