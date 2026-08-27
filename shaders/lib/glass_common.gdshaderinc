// Común a las dos pasadas del cristal (transmisión multiplicativa + reflejo). El test de sumergido
// tiene que dar lo MISMO en las dos: si divergen, una pinta cristal donde la otra pinta niebla.

uniform vec3 planet_center = vec3(0.0);
uniform float water_radius = 0.0;

// Profundidad del panel bajo la superficie del mar en reposo; <= 0 es aire.
float glass_pane_depth(vec3 world_pos) {
	return water_radius > 0.0 ? water_radius - length(world_pos - planet_center) : -1.0;
}
