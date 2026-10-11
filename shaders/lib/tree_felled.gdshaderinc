// =============================================================================
//  tree_felled.gdshaderinc
//  Árbol talado (FallingTree), en la corteza y el follaje de los Branching. El bosque los
//  dibuja en MultiMesh con los valores por defecto, que no cambian nada; el árbol que cae los
//  fija en su propia instancia.
//    fell_base        xyz: base del árbol en pie respecto al centro del planeta; w = 1 si está
//                     talado. Al caer gira sobre la bisagra del corte y su origen se mueve: sin
//                     esto cambiaban a media caída el tinte, la estación de la hoja y la fase del
//                     viento, que salen de la posición de la base.
//    fell_cut_height  altura local del corte: la madera de debajo se queda en el tocón.
//    fell_sway        inclinación del tronco con el viento (0 tumbado).
// =============================================================================
#ifndef TREE_FELLED_INC
#define TREE_FELLED_INC

instance uniform vec4 fell_base = vec4(0.0);
instance uniform float fell_cut_height = -1000.0;
instance uniform float fell_sway = 1.0;

// Base del árbol respecto al centro del planeta: la de su modelo o, talado ([felled] es
// fell_base, que se lee en vertex()), la que tenía en pie.
vec3 tree_relative_base(mat4 model, vec3 planet_center, vec4 felled) {
	return felled.w > 0.5 ? felled.xyz : model[3].xyz - planet_center;
}

#endif // TREE_FELLED_INC
