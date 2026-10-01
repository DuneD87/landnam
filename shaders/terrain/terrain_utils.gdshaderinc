

// utils.gdshaderinc
struct TriplanarUVs {
    vec2 uv_x;
    vec2 uv_y;
    vec2 uv_z;
};

vec3 safe_normalize(vec3 v, vec3 fallback) {
    float len_sq = dot(v, v);
    if (len_sq <= 0.000001) {
        return fallback;
    }
    return v * inversesqrt(len_sq);
}

vec3 triplanar_blend_weights(vec3 normal, float sharpness) {
    vec3 blend = pow(max(abs(normal), vec3(0.0001)), vec3(sharpness));
    return blend / max(blend.x + blend.y + blend.z, 0.0001);
}

float signed_axis(float v) {
    return v < 0.0 ? -1.0 : 1.0;
}

uniform bool antitiling_enabled = true;
uniform float antitiling_variation_scale = 0.06;
uniform float antitiling_blend_softness = 0.2;
uniform float antitiling_rotation_strength = 1.0;
uniform float antitiling_fade_start = 0.10;
uniform float antitiling_fade_end = 0.40;

float antitiling_hash1(vec2 p) {
    ivec2 ip = ivec2(floor(p));
    int h = ip.x * 374761393 + ip.y * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    h ^= h >> 16;
    return float(h & 0x7fffffff) / 2147483647.0;
}

vec2 antitiling_region_offset(float idx) {
    int i = int(idx);
    int h1 = i * 374761393 + 1013904223;
    h1 = (h1 ^ (h1 >> 13)) * 1274126177; h1 ^= h1 >> 16;
    int h2 = i * 668265263 + 40503;
    h2 = (h2 ^ (h2 >> 13)) * 1274126177; h2 ^= h2 >> 16;
    return vec2(float(h1 & 0x7fffffff), float(h2 & 0x7fffffff)) / 2147483647.0;
}

float antitiling_value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = antitiling_hash1(i + vec2(0.0, 0.0));
    float b = antitiling_hash1(i + vec2(1.0, 0.0));
    float c = antitiling_hash1(i + vec2(0.0, 1.0));
    float d = antitiling_hash1(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float antitiling_region_angle(float idx) {
    int i = int(idx);
    int h = i * 1274126177 + 374761397;
    h = (h ^ (h >> 13)) * 668265263; h ^= h >> 16;
    return (float(h & 0x7fffffff) / 2147483647.0) * 6.2831853;
}

mat2 antitiling_region_rot(float idx) {
    float a = antitiling_region_angle(idx) * antitiling_rotation_strength;
    float c = cos(a);
    float s = sin(a);
    return mat2(vec2(c, s), vec2(-s, c));
}

float antitiling_detile_factor(vec2 uv) {
    vec2 dx = dFdx(uv);
    vec2 dy = dFdy(uv);
    float fp = sqrt(max(dot(dx, dx), dot(dy, dy))); // UV por píxel (footprint)
    return 1.0 - smoothstep(antitiling_fade_start, antitiling_fade_end, fp);
}

// Reparto de un plano triplanar en regiones (~8 a lo largo del rango del ruido; las fronteras
// siguen sus isocurvas, así que son orgánicas y no una rejilla). Solo depende de las UV, así que
// se calcula UNA vez por plano y fragmento (notile_frame) y lo reutilizan todas las texturas que
// se muestrean a esa escala. Antes cada lectura rehacía el ruido, los hashes y los senos: con
// ~27 lecturas por fragmento era el 65 % del coste del terreno.
//
// Paridad: la región par va siempre en un hueco y la impar en el otro. Al cruzar una frontera la
// región que sigue mandando no cambia de hueco, así que sus derivadas (su mip) son continuas; la
// que entra y la que sale pesan 0 justo ahí.
struct NotilePlane {
    mat2 rot_even;
    vec2 off_even;
    mat2 rot_odd;
    vec2 off_odd;
    float w_odd;  // peso de la región impar; la par lleva 1 - w_odd
    float detile; // 1 = de-tilado completo, 0 = muestra plana (lejos o anti-tiling apagado)
};

struct NotileFrame {
    NotilePlane x;
    NotilePlane y;
    NotilePlane z;
};

NotilePlane notile_plane(vec2 uv) {
    NotilePlane p;
    p.rot_even = mat2(1.0);
    p.off_even = vec2(0.0);
    p.rot_odd = mat2(1.0);
    p.off_odd = vec2(0.0);
    p.w_odd = 0.0;
    p.detile = antitiling_enabled ? antitiling_detile_factor(uv) : 0.0;
    if (p.detile <= 0.001) {
        return p;
    }
    float l = antitiling_value_noise(uv * antitiling_variation_scale) * 8.0;
    float ia = floor(l);
    // Con más de 0.5 la mezcla no es pura en f = 0 ni en f = 1: al saltar de región una de las
    // dos copias cambia de golpe (una costura cada metro) y nunca basta una sola muestra.
    float s = clamp(antitiling_blend_softness, 0.001, 0.5);
    float w = smoothstep(0.5 - s, 0.5 + s, l - ia); // peso de la región ia + 1
    bool ia_even = mod(ia, 2.0) < 0.5;
    float even_idx = ia_even ? ia : ia + 1.0;
    float odd_idx = ia_even ? ia + 1.0 : ia;
    p.w_odd = ia_even ? w : 1.0 - w;
    p.rot_even = antitiling_region_rot(even_idx);
    p.off_even = antitiling_region_offset(even_idx);
    p.rot_odd = antitiling_region_rot(odd_idx);
    p.off_odd = antitiling_region_offset(odd_idx);
    return p;
}

// Tiene que llamarse fuera de ramas: lleva derivadas de pantalla.
NotileFrame notile_frame(vec3 pos, float scale) {
    NotileFrame f;
    f.x = notile_plane(pos.yz * scale);
    f.y = notile_plane(pos.xz * scale);
    f.z = notile_plane(pos.xy * scale);
    return f;
}

// Siempre las dos regiones, sin ramas. Saltarse la que pesa 0 (o un plano triplanar sin peso)
// salía MÁS caro: con las lecturas dentro de ramas la GPU ya no las lanza juntas y espera a cada
// una. Y donde los cuatro píxeles de un quad no tomaban la misma rama las derivadas implícitas
// salían mal: puntos sueltos con el mip equivocado a lo largo de las fronteras de región.
// Las ramas de 'detile' sí se quedan: siguen la distancia (zonas enteras de pantalla) y en su
// frontera lo que cambia de rama pesa ~0.
vec4 notile_sample(sampler2D tex, vec2 uv, NotilePlane p) {
    if (p.detile <= 0.001) {
        return texture(tex, uv); // lejos: 1 muestra plana
    }
    vec2 uv_even = p.rot_even * uv + p.off_even;
    vec2 uv_odd = p.rot_odd * uv + p.off_odd;
    vec4 d = mix(texture(tex, uv_even), texture(tex, uv_odd), p.w_odd);
    if (p.detile >= 0.999) {
        return d; // cerca: solo de-tilado
    }
    return mix(texture(tex, uv), d, p.detile); // banda de distancia: plano <-> de-tilado
}

// Igual para normal maps (-1..1): la normal de cada región se gira de vuelta a las UV sin rotar.
// n.xy * R == transpose(R) * n.xy
vec3 notile_normal(sampler2D tex, vec2 uv, NotilePlane p) {
    if (p.detile <= 0.001) {
        return texture(tex, uv).rgb * 2.0 - 1.0;
    }
    vec2 uv_even = p.rot_even * uv + p.off_even;
    vec2 uv_odd = p.rot_odd * uv + p.off_odd;
    vec3 n_even = texture(tex, uv_even).rgb * 2.0 - 1.0;
    vec3 n_odd = texture(tex, uv_odd).rgb * 2.0 - 1.0;
    n_even.xy = n_even.xy * p.rot_even;
    n_odd.xy = n_odd.xy * p.rot_odd;
    vec3 d = mix(n_even, n_odd, p.w_odd);
    if (p.detile >= 0.999) {
        return d;
    }
    return mix(texture(tex, uv).rgb * 2.0 - 1.0, d, p.detile);
}

// Versiones sueltas, para lo que se muestrea a otra escala (el hielo glaciar): calculan su propio
// reparto en cada llamada, así que no las uses donde valga el marco compartido.
vec4 tex_notile(sampler2D tex, vec2 uv) {
    return notile_sample(tex, uv, notile_plane(uv));
}

vec3 antitiling_normal_notile(sampler2D tex, vec2 uv) {
    return notile_normal(tex, uv, notile_plane(uv));
}

TriplanarUVs compute_triplanar_uvs(vec3 pos, float scale) {
    TriplanarUVs r;
    r.uv_x = pos.yz * scale;
    r.uv_y = pos.xz * scale;
    r.uv_z = pos.xy * scale;
    return r;
}

vec2 limited_parallax_offset(vec2 view_tangent, float view_axis, float height, float height_scale, float min_view_dot) {
    float view_denom = max(abs(view_axis), min_view_dot);
    vec2 offset = (view_tangent / view_denom) * height * height_scale;
    float max_offset = max(abs(height_scale) * 2.0, 0.0001);
    return clamp(offset, vec2(-max_offset), vec2(max_offset));
}

TriplanarUVs compute_parallax_uvs(
    sampler2D height_tex,
    vec3 pos, vec3 surface_normal, vec3 view_world,
    float scale, float height_scale
) {
    TriplanarUVs r = compute_triplanar_uvs(pos, scale);

    if (height_scale <= 0.0001) return r;

    // Identifica el plano dominante (el que más contribuye al blend)
    vec3 abs_n = abs(surface_normal);
    int dominant = 0;
    if (abs_n.y > abs_n.x && abs_n.y > abs_n.z) dominant = 1;
    else if (abs_n.z > abs_n.x) dominant = 2;

    // Parallax solo en el dominante. Offset Limited (sin dividir por view.n)
    // — más estable y suficiente para superficies de terreno.
    if (dominant == 0) {
        float h = texture(height_tex, r.uv_x).r - 0.5;
        vec2 view_tan = view_world.yz * sign(surface_normal.x);
        vec2 offset = view_tan * h * height_scale;
        r.uv_x -= offset;
        // Aplica un offset proporcional a los otros planos para que el blend
        // no introduzca discontinuidades en la transición:
        r.uv_y -= vec2(0.0, offset.y);  // comparten Z
        r.uv_z -= vec2(0.0, offset.x);  // comparten Y
    } else if (dominant == 1) {
        float h = texture(height_tex, r.uv_y).r - 0.5;
        vec2 view_tan = view_world.xz * sign(surface_normal.y);
        vec2 offset = view_tan * h * height_scale;
        r.uv_y -= offset;
        r.uv_x -= vec2(0.0, offset.y);
        r.uv_z -= vec2(offset.x, 0.0);
    } else {
        float h = texture(height_tex, r.uv_z).r - 0.5;
        vec2 view_tan = view_world.xy * sign(surface_normal.z);
        vec2 offset = view_tan * h * height_scale;
        r.uv_z -= offset;
        r.uv_x -= vec2(offset.y, 0.0);
        r.uv_y -= vec2(offset.x, 0.0);
    }
    return r;
}

TriplanarUVs compute_parallax_uvs_limited(
    sampler2D height_tex,
    vec3 pos, vec3 surface_normal, vec3 view_world,
    float scale, float height_scale,
    float height_center, float height_contrast, float min_view_dot
) {
    TriplanarUVs r = compute_triplanar_uvs(pos, scale);

    float uv_height_scale = height_scale * scale;
    if (uv_height_scale <= 0.00001) {
        return r;
    }

    vec3 n = safe_normalize(surface_normal, vec3(0.0, 1.0, 0.0));
    vec3 v = safe_normalize(view_world, n);
    vec3 abs_n = abs(n);

    float mask_x = smoothstep(0.20, 0.85, abs_n.x);
    float mask_y = smoothstep(0.20, 0.85, abs_n.y);
    float mask_z = smoothstep(0.20, 0.85, abs_n.z);

    float sx = signed_axis(n.x);
    float sy = signed_axis(n.y);
    float sz = signed_axis(n.z);

    float hx = (texture(height_tex, r.uv_x).r - height_center) * height_contrast;
    float hy = (texture(height_tex, r.uv_y).r - height_center) * height_contrast;
    float hz = (texture(height_tex, r.uv_z).r - height_center) * height_contrast;

    r.uv_x -= limited_parallax_offset(v.yz * sx, v.x * sx, hx, uv_height_scale, min_view_dot) * mask_x;
    r.uv_y -= limited_parallax_offset(v.xz * sy, v.y * sy, hy, uv_height_scale, min_view_dot) * mask_y;
    r.uv_z -= limited_parallax_offset(v.xy * sz, v.z * sz, hz, uv_height_scale, min_view_dot) * mask_z;

    return r;
}

// Versiones de sample que aceptan UVs precomputados. Las _nt usan el reparto de anti-tiling
// compartido (notile_frame), calculado con las mismas UV base.
vec3 triplanar_sample_nt(sampler2D tex, TriplanarUVs uvs, vec3 normal, NotileFrame nt) {
    vec3 col_x = notile_sample(tex, uvs.uv_x, nt.x).rgb;
    vec3 col_y = notile_sample(tex, uvs.uv_y, nt.y).rgb;
    vec3 col_z = notile_sample(tex, uvs.uv_z, nt.z).rgb;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

vec3 triplanar_sample_uvs(sampler2D tex, TriplanarUVs uvs, vec3 normal) {
    vec3 col_x = tex_notile(tex, uvs.uv_x).rgb;
    vec3 col_y = tex_notile(tex, uvs.uv_y).rgb;
    vec3 col_z = tex_notile(tex, uvs.uv_z).rgb;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

// Sin anti-tiling: para la capa lejana, cuya repetición (~12 m) ya no se distingue a la
// distancia a la que manda.
vec3 triplanar_sample_plain(sampler2D tex, TriplanarUVs uvs, vec3 normal) {
    vec3 col_x = texture(tex, uvs.uv_x).rgb;
    vec3 col_y = texture(tex, uvs.uv_y).rgb;
    vec3 col_z = texture(tex, uvs.uv_z).rgb;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

// Factor de brillo de una capa de la misma textura a otra escala (el detalle de cerca, la capa
// lejana), normalizado por la media real de la textura (mip 1x1). Devuelve 1.0 donde la capa vale
// lo que la media, así que la mezcla no cambia la luminancia de la textura sea clara u oscura
// (el clásico *2.0 solo era neutro con media 0.5, y en lineal la hierba está en ~0.05).
float layer_blend_factor(sampler2D tex, vec3 layer_color, float weight) {
    const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
    vec3 avg = textureLod(tex, vec2(0.5), 20.0).rgb; // mip más bajo = media de la textura
    float ratio = dot(layer_color, LUMA) / max(dot(avg, LUMA), 0.002);
    return mix(1.0, clamp(ratio, 0.25, 3.0), weight);
}

// Mapas escalares (roughness/AO/height): muestreo PLANO (sin anti-tiling). La repetición
// de roughness/AO/height es prácticamente imperceptible frente a la del albedo, pero
// de-tilarlos cuesta lo mismo. Aquí solo albedo y normal pasan por el anti-tiling; esto
// recorta ~la mitad de las muestras de-tiladas en todos los píxeles. (Si ves tiling en el
// reparto hierba/tierra por el height bias, bajar height_blend_strength o de-tilar height.)
float triplanar_scalar_sample_uvs(sampler2D tex, TriplanarUVs uvs, vec3 normal) {
    float r = texture(tex, uvs.uv_x).r;
    float g = texture(tex, uvs.uv_y).r;
    float b = texture(tex, uvs.uv_z).r;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return r * blend.x + g * blend.y + b * blend.z;
}



// Función para obtener el factor secundario de transvoxel
float get_transvoxel_secondary_factor(int idata, int transition_mask) {
    int cell_border_mask = idata & 63;
    int vertex_border_mask = (idata >> 8) & 63;
    int m = transition_mask & cell_border_mask;
    float t = float(m != 0);
    t *= float((vertex_border_mask & ~transition_mask) == 0);
    return t;
}

// Función para obtener la posición transvoxel
vec3 get_transvoxel_position(vec3 vertex_pos, vec4 fdata, int transition_mask) {
    int idata = floatBitsToInt(fdata.a);
    float secondary_factor = get_transvoxel_secondary_factor(idata, transition_mask);
    vec3 secondary_position = fdata.xyz;
    vec3 pos = mix(vertex_pos, secondary_position, secondary_factor);
    int itransition = (idata >> 16) & 0xff;
    float transition_cull = float(itransition == 0 || (itransition & transition_mask) != 0);
    pos *= transition_cull;
    return pos;
}

// Interruptor del fundido de LOD. Descomentar para activarlo, y emparejarlo con
// lod_fade_duration del VoxelLodTerrain (0 = apagado). Cuesta caro y DE FORMA CONSTANTE,
// haya fundido en curso o no: un shader con discard pierde el early-Z y deja de poder usar
// el material de sombra compartido, asi que el terreno ejecuta fragment() tambien en el
// prepass de profundidad y en las 4 cascadas del sol. Es el shader con mas overdraw del
// juego, asi que el peaje se nota en todo el frame.
//#define LOD_FADE_ENABLED

// Fundido de LOD. Con VoxelLodTerrain.lod_fade_duration > 0 el modulo escribe u_lod_fade
// en el material de cada bloque: x = progreso 0..1 del fundido, y = 1 mientras el bloque
// aparece y 0 mientras desaparece. Con el fundido apagado nadie lo escribe y el cero por
// defecto (y = 0, x = 0) deja el bloque entero visible.
uniform vec2 u_lod_fade;
// 0 = off, 1 = tinta los bloques en fundido (verde aparece, rojo desaparece) sin recortar.
uniform int debug_lod_fade : hint_range(0, 1) = 0;

// Umbral ordenado 4x4 (Bayer) en pixeles de pantalla, 16 escalones en [0,1).
float lod_fade_dither(vec2 frag_coord) {
    vec2 a = floor(frag_coord);
    vec2 b = floor(frag_coord * 0.5);
    float fine = fract(a.x * 0.5 + a.y * a.y * 0.75);
    float coarse = fract(b.x * 0.5 + b.y * b.y * 0.75);
    return coarse * 0.25 + fine;
}

// true si este pixel le toca al bloque hermano del otro LOD. Los dos bloques comparten
// umbral y comparan al reves, asi que se reparten la pantalla sin huecos ni solapes.
bool lod_fade_discards(vec2 frag_coord) {
    float threshold = lod_fade_dither(frag_coord);
    bool appearing = u_lod_fade.y > 0.5;
    return appearing ? (threshold >= u_lod_fade.x) : (threshold < u_lod_fade.x);
}

// Función de hash
float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Función de ruido procedural
float noise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f); // Interpolación suave
    return mix(
        mix(
            mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
            mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x),
            f.y
        ),
        mix(
            mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
            mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x),
            f.y
        ),
        f.z
    );
}

// Función para muestrear texturas con mapeo triplanar
float signed_fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float amplitude_sum = 0.0;

    for (int i = 0; i < 4; i++) {
        value += (noise(p) * 2.0 - 1.0) * amplitude;
        amplitude_sum += amplitude;
        p = p * 2.03 + vec3(17.13, 31.71, 11.47);
        amplitude *= 0.5;
    }

    return value / max(amplitude_sum, 0.0001);
}

vec4 open_simplex2_permute(vec4 t) {
    return t * (t * 34.0 + 133.0);
}

vec3 open_simplex2_grad(float hash) {
    vec3 cube = mod(floor(hash / vec3(1.0, 2.0, 4.0)), 2.0) * 2.0 - 1.0;
    vec3 cuboct = cube;
    float edge = floor(hash / 16.0);
    if (edge < 0.5) {
        cuboct.x = 0.0;
    } else if (edge < 1.5) {
        cuboct.y = 0.0;
    } else {
        cuboct.z = 0.0;
    }

    float type = mod(floor(hash / 8.0), 2.0);
    vec3 rhomb = mix(cube, cuboct + cross(cube, cuboct), type);
    vec3 grad = cuboct * 1.22474487139 + rhomb;
    return grad * (1.0 - 0.042942436724648037 * type) * 32.80201376986577;
}

float open_simplex2_base(vec3 x) {
    vec3 v1 = floor(x + vec3(0.5));
    vec3 d1 = x - v1;
    vec3 score1 = abs(d1);
    vec3 dir1 = step(max(score1.yzx, score1.zxy), score1);
    vec3 v2 = v1 + dir1 * sign(d1);
    vec3 d2 = x - v2;

    vec3 x2 = x + vec3(144.5);
    vec3 v3 = floor(x2 + vec3(0.5));
    vec3 d3 = x2 - v3;
    vec3 score2 = abs(d3);
    vec3 dir2 = step(max(score2.yzx, score2.zxy), score2);
    vec3 v4 = v3 + dir2 * sign(d3);
    vec3 d4 = x2 - v4;

    vec4 hashes = open_simplex2_permute(mod(vec4(v1.x, v2.x, v3.x, v4.x), 289.0));
    hashes = open_simplex2_permute(mod(hashes + vec4(v1.y, v2.y, v3.y, v4.y), 289.0));
    hashes = mod(open_simplex2_permute(mod(hashes + vec4(v1.z, v2.z, v3.z, v4.z), 289.0)), 48.0);

    vec4 a = max(0.5 - vec4(dot(d1, d1), dot(d2, d2), dot(d3, d3), dot(d4, d4)), 0.0);
    vec4 a2 = a * a;
    vec4 a4 = a2 * a2;
    vec4 extrapolations = vec4(
        dot(d1, open_simplex2_grad(hashes.x)),
        dot(d2, open_simplex2_grad(hashes.y)),
        dot(d3, open_simplex2_grad(hashes.z)),
        dot(d4, open_simplex2_grad(hashes.w))
    );

    return dot(a4, extrapolations);
}

float open_simplex2_3d(vec3 p) {
    vec3 rotated = vec3(dot(p, vec3(2.0 / 3.0))) - p;
    return open_simplex2_base(rotated);
}

#include "res://shaders/lib/fnl_simplex.gdshaderinc"


vec3 triplanar_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;
    vec3 col_x = texture(tex, uv_x).rgb;
    vec3 col_y = texture(tex, uv_y).rgb;
    vec3 col_z = texture(tex, uv_z).rgb;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

// Convierte el normal map en un vector de normales en espacio tangente
vec3 unpack_normal(vec3 n) {
    return normalize(n * 2.0 - 1.0);
}

vec3 apply_normal_strength(vec3 base_normal, vec3 detail_normal, float strength) {
    float s = clamp(strength, 0.0, 4.0);
    return safe_normalize(mix(base_normal, detail_normal, s), base_normal);
}

// Whiteout blend de las tres muestras crudas (-1..1) de un normal map triplanar. w = tightness:
// 1.0 = sin promediado de mip, <1.0 = el mip promedió perturbaciones (lo usa la specular AA).
vec4 triplanar_normal_combine(vec3 raw_x, vec3 raw_y, vec3 raw_z, vec3 blend, vec3 surface_normal) {
    float avg_len = length(raw_x) * blend.x
                  + length(raw_y) * blend.y
                  + length(raw_z) * blend.z;

    vec3 tn_x = safe_normalize(raw_x, vec3(0.0, 0.0, 1.0));
    vec3 tn_y = safe_normalize(raw_y, vec3(0.0, 0.0, 1.0));
    vec3 tn_z = safe_normalize(raw_z, vec3(0.0, 0.0, 1.0));
    tn_x.xy = tn_x.yx;

    tn_x = vec3(tn_x.xy + surface_normal.zy, abs(tn_x.z) * surface_normal.x);
    tn_y = vec3(tn_y.xy + surface_normal.xz, abs(tn_y.z) * surface_normal.y);
    tn_z = vec3(tn_z.xy + surface_normal.xy, abs(tn_z.z) * surface_normal.z);

    vec3 n = safe_normalize(
        tn_x.zyx * blend.x + tn_y.xzy * blend.y + tn_z.xyz * blend.z,
        surface_normal
    );

    return vec4(n, avg_len);
}

vec4 triplanar_normal_sample_nt_v(sampler2D tex, TriplanarUVs uvs, vec3 surface_normal, NotileFrame nt) {
    vec3 blend = triplanar_blend_weights(surface_normal, 4.0);
    return triplanar_normal_combine(
        notile_normal(tex, uvs.uv_x, nt.x),
        notile_normal(tex, uvs.uv_y, nt.y),
        notile_normal(tex, uvs.uv_z, nt.z),
        blend, surface_normal);
}

vec4 triplanar_normal_sample_uvs_v(sampler2D tex, TriplanarUVs uvs, vec3 surface_normal) {
    vec3 blend = triplanar_blend_weights(surface_normal, 4.0);
    return triplanar_normal_combine(
        antitiling_normal_notile(tex, uvs.uv_x),
        antitiling_normal_notile(tex, uvs.uv_y),
        antitiling_normal_notile(tex, uvs.uv_z),
        blend, surface_normal);
}

vec3 triplanar_normal_sample(sampler2D tex, vec3 pos, vec3 surface_normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;

    // Muestreo en tangente (-1..1)
    vec3 tn_x = unpack_normal(texture(tex, uv_x).rgb);
    vec3 tn_y = unpack_normal(texture(tex, uv_y).rgb);
    vec3 tn_z = unpack_normal(texture(tex, uv_z).rgb);
	tn_x.xy = tn_x.yx;
    // Whiteout blend: cada muestra perturba la normal en su plano,
    // y el componente "Z" del normal map se alinea con la normal real
    tn_x = vec3(tn_x.xy + surface_normal.zy, abs(tn_x.z) * surface_normal.x);
    tn_y = vec3(tn_y.xy + surface_normal.xz, abs(tn_y.z) * surface_normal.y);
    tn_z = vec3(tn_z.xy + surface_normal.xy, abs(tn_z.z) * surface_normal.z);

    // Pesos
    vec3 blend = triplanar_blend_weights(surface_normal, 4.0);

    // Swizzle para devolver al espacio mundo y mezclar
    return safe_normalize(
        tn_x.zyx * blend.x +
        tn_y.xzy * blend.y +
        tn_z.xyz * blend.z,
        surface_normal
    );
}

// Versiones con LOD bias explícito — para eliminar seams en transiciones de mesh LOD.
// En VoxelLodTerrain con mesh_block_size=16, los bloques gruesos tienen triángulos más
// grandes: el GPU selecciona automáticamente un mip más bajo → textura diferente en cada
// lado del seam. Un bias negativo compensa, haciendo que todos los bloques usen el mismo
// nivel de mip que el LOD 0.
vec3 triplanar_sample_uvs_bias(sampler2D tex, TriplanarUVs uvs, vec3 normal, float bias) {
    vec3 col_x = texture(tex, uvs.uv_x, bias).rgb;
    vec3 col_y = texture(tex, uvs.uv_y, bias).rgb;
    vec3 col_z = texture(tex, uvs.uv_z, bias).rgb;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

float triplanar_scalar_sample_uvs_bias(sampler2D tex, TriplanarUVs uvs, vec3 normal, float bias) {
    float r = texture(tex, uvs.uv_x, bias).r;
    float g = texture(tex, uvs.uv_y, bias).r;
    float b = texture(tex, uvs.uv_z, bias).r;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return r * blend.x + g * blend.y + b * blend.z;
}

// Función para muestrear roughness maps con mapeo triplanar (escala de grises)
float triplanar_roughness_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;
    float rough_x = texture(tex, uv_x).r;
    float rough_y = texture(tex, uv_y).r;
    float rough_z = texture(tex, uv_z).r;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return rough_x * blend.x + rough_y * blend.y + rough_z * blend.z;
}
