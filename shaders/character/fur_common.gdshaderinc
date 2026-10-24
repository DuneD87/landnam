// Shared by the fur garments' shaders (fur_card.gdshader, its fringe pass and
// fur_pelt.gdshader): the colour of hair from the maps
// tools/character/blender/render_fur_maps.py renders. They hold data, not
// colour: R how far along its strand a texel is (0 root, 1 tip), G a random
// value per strand, B the occlusion between strands, A the coverage. The
// vertex colour is the pelt's own (and the shadow the garment's layers cast
// on it, build_fur_armor.py).

// Brightness at the root and at the tip, against the middle of a hair.
uniform float root_shade = 0.45;
uniform float tip_shade = 0.6;
// How much one strand differs from the next.
uniform float strand_contrast = 0.75;
// Darkest the occlusion between strands gets.
uniform float strand_occlusion = 0.3;

vec3 fur_color(vec4 texel, vec3 tint) {
	float t = texel.r;
	float along = t < 0.55 ? mix(root_shade, 1.0, t / 0.55) : mix(1.0, tip_shade, (t - 0.55) / 0.45);
	float strand = 1.0 + strand_contrast * (texel.g - 0.5);
	return tint * along * strand * mix(strand_occlusion, 1.0, texel.b);
}
