// Compartimentos SECOS de los barcos como OBBs: dentro no existe el agua (water_shader
// descarta superficie; underwater se descarta con la cámara dentro). GridManager los empuja
// por frame; underwater.gd los replica vía _SYNCED_WATER_PARAMS (el corte debe ir síncrono).

const int MAX_INTERIORS = 64;
uniform int interior_count = 0;
uniform vec4 interior_center[MAX_INTERIORS]; // xyz = centro de la caja en world
uniform vec4 interior_axis_x[MAX_INTERIORS]; // xyz = eje local X del casco, w = semieje
uniform vec4 interior_axis_y[MAX_INTERIORS];
uniform vec4 interior_axis_z[MAX_INTERIORS];

// true si el punto world cae dentro de algún compartimento seco.
bool inside_ship_interior(vec3 p) {
    for (int i = 0; i < MAX_INTERIORS; i++) {
        if (i >= interior_count) {
            break;
        }
        vec3 d = p - interior_center[i].xyz;
        if (abs(dot(d, interior_axis_x[i].xyz)) < interior_axis_x[i].w
            && abs(dot(d, interior_axis_y[i].xyz)) < interior_axis_y[i].w
            && abs(dot(d, interior_axis_z[i].xyz)) < interior_axis_z[i].w) {
            return true;
        }
    }
    return false;
}
