// =============================================================================
//  octahedral.gdshaderinc
//  Codificación octaédrica compartida por el horneado de impostores de árbol
//  (tree_impostor_bake.gdshader) y su render (tree_octa_impostor.gdshader). Las mismas
//  fórmulas están en scripts/planet/tree_octa_impostor.gd para colocar las cámaras.
//  Eje Y arriba.
// =============================================================================
#ifndef OCTAHEDRAL_INC
#define OCTAHEDRAL_INC

// Dirección del hemisferio superior (y >= 0) -> [0,1]².
vec2 hemi_oct_encode(vec3 d) {
	d /= abs(d.x) + abs(d.y) + abs(d.z);
	return vec2(d.x + d.z, d.x - d.z) * 0.5 + 0.5;
}

vec3 hemi_oct_decode(vec2 uv) {
	vec2 e = uv * 2.0 - 1.0;
	vec3 d = vec3((e.x + e.y) * 0.5, 0.0, (e.x - e.y) * 0.5);
	d.y = 1.0 - abs(d.x) - abs(d.z);
	return normalize(d);
}

vec2 oct_sign(vec2 v) {
	return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

// Normal de la esfera completa -> [0,1]².
vec2 oct_normal_encode(vec3 n) {
	n /= abs(n.x) + abs(n.y) + abs(n.z);
	vec2 e = n.y >= 0.0 ? n.xz : (1.0 - abs(n.zx)) * oct_sign(n.xz);
	return e * 0.5 + 0.5;
}

vec3 oct_normal_decode(vec2 uv) {
	vec2 e = uv * 2.0 - 1.0;
	vec3 n = vec3(e.x, 1.0 - abs(e.x) - abs(e.y), e.y);
	if (n.y < 0.0) {
		n.xz = (1.0 - abs(n.zx)) * oct_sign(n.xz);
	}
	return normalize(n);
}

// Base de una vista: la cámara mira hacia -d; x a la derecha, y hacia arriba en la imagen.
void oct_frame_basis(vec3 d, out vec3 right, out vec3 up) {
	vec3 ref = abs(d.y) > 0.999 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
	right = normalize(cross(ref, d));
	up = cross(d, right);
}

#endif // OCTAHEDRAL_INC
