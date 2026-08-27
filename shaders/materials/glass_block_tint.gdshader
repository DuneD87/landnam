shader_type spatial;
render_mode blend_mul, depth_draw_never, cull_back, unshaded;

// Pasada 1 del cristal: la transmisión. Multiplica el framebuffer por el tinte del vidrio, que es
// la única forma de que el panel QUITE luz en vez de sumarla; el reflejo lo suma después
// glass_block.gdshader.

#include "res://shaders/lib/glass_common.gdshaderinc"

uniform vec3 glass_tint : source_color = vec3(0.78, 0.90, 0.85);

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Blanco es la identidad en multiplicativo. Sumergido no se toca: manda la otra pasada, que
	// sustituye el píxel por la niebla compuesta.
	vec3 tint = vec3(1.0);
	if (glass_pane_depth(v_world_pos) <= 0.0) {
		// Beer-Lambert por el grosor recorrido: a rasante se atraviesa más vidrio y tiñe más, que
		// es el verde de canto del vidrio real.
		float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		tint = pow(glass_tint, vec3(1.0 / max(ndv, 0.15)));
	}
	ALBEDO = tint;
	ALPHA = 1.0;
}
