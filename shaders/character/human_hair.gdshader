shader_type spatial;
render_mode cull_disabled;

// Hair, eyebrow and eyelash cards of the MakeHuman assets. The texture's
// strands are recoloured with hair_color relative to the texture's own mean
// tone (texture_tone), so one colour looks alike on every style. Alpha is cut
// with alpha to coverage, which keeps soft strand edges under MSAA without
// sorting.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 texture_tone : source_color = vec3(0.3, 0.24, 0.2);
uniform vec3 hair_color : source_color = vec3(0.23, 0.16, 0.11);
uniform float roughness : hint_range(0.0, 1.0) = 0.55;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	float tone_luma = to_srgb(vec3(dot(texture_tone, LUMA))).r;
	float relative = to_srgb(vec3(dot(texel.rgb, LUMA))).r / max(tone_luma, 0.02);
	// Near-black textures (eyelashes) carry no shading to keep, and the RGB
	// of half-transparent texels is unreliable: fall back to the flat tint.
	relative = mix(1.0, relative, smoothstep(0.05, 0.1, tone_luma) * smoothstep(0.3, 0.8, texel.a));
	ALBEDO = to_linear(to_srgb(hair_color) * clamp(relative, 0.0, 1.8));
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
}
