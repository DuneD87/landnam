shader_type spatial;
render_mode cull_disabled;

// Animal marino grande de un pack, con esqueleto (SkinnedMarineModel): la textura tal cual y un
// fundido de aparecer y de irse con tramado, como marine_animal.gdshader, para que el cuerpo siga
// en la pasada opaca mientras aparece cerca de la cámara.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float specular : hint_range(0.0, 1.0) = 0.45;

// 0 oculto, 1 opaco.
instance uniform float fade = 1.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	if (fade < 1.0) {
		ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
		if ((BAYER[cell.x + cell.y * 4] + 0.5) / 16.0 > fade) {
			discard;
		}
	}
	ALBEDO = texture(albedo_texture, UV).rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
