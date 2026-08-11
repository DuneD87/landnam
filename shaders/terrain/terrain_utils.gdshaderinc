

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

vec4 antitiling_region_color(sampler2D tex, vec2 uv, float idx) {
    mat2 R = antitiling_region_rot(idx);
    vec2 o = antitiling_region_offset(idx);
    return texture(tex, R * uv + o);
}

vec3 antitiling_region_normal(sampler2D tex, vec2 uv, float idx) {
    mat2 R = antitiling_region_rot(idx);
    vec2 o = antitiling_region_offset(idx);
    vec3 n = texture(tex, R * uv + o).rgb * 2.0 - 1.0;
    n.xy = n.xy * R; // n.xy * R == transpose(R) * n.xy
    return n;
}

vec3 antitiling_region_weights(vec2 uv) {
    // ~8 regiones a lo largo del rango del ruido; las transiciones siguen las
    // isocurvas del ruido → fronteras orgánicas, no una rejilla recta.
    float l  = antitiling_value_noise(uv * antitiling_variation_scale) * 8.0;
    float ia = floor(l);
    float f  = l - ia;
    float s = max(antitiling_blend_softness, 0.001);
    float w = smoothstep(0.5 - s, 0.5 + s, f);
    return vec3(ia, ia + 1.0, w);
}

float antitiling_detile_factor(vec2 uv) {
    vec2 dx = dFdx(uv);
    vec2 dy = dFdy(uv);
    float fp = sqrt(max(dot(dx, dx), dot(dy, dy))); // UV por píxel (footprint)
    return 1.0 - smoothstep(antitiling_fade_start, antitiling_fade_end, fp);
}

vec4 tex_notile(sampler2D tex, vec2 uv) {
    if (!antitiling_enabled) {
        return texture(tex, uv);
    }
    float detile = antitiling_detile_factor(uv);
    if (detile <= 0.001) {
        return texture(tex, uv); // lejos: 1 muestra plana
    }

    vec3 rw = antitiling_region_weights(uv);
    vec4 d;
    if (rw.z <= 0.001) {
        d = antitiling_region_color(tex, uv, rw.x);
    } else if (rw.z >= 0.999) {
        d = antitiling_region_color(tex, uv, rw.y);
    } else {
        d = mix(
            antitiling_region_color(tex, uv, rw.x),
            antitiling_region_color(tex, uv, rw.y),
            rw.z
        );
    }

    if (detile >= 0.999) {
        return d; // cerca: solo de-tilado
    }
    return mix(texture(tex, uv), d, detile); // banda de distancia: plano <-> de-tilado
}


vec3 antitiling_normal_notile(sampler2D tex, vec2 uv) {
    if (!antitiling_enabled) {
        return texture(tex, uv).rgb * 2.0 - 1.0;
    }
    float detile = antitiling_detile_factor(uv);
    if (detile <= 0.001) {
        return texture(tex, uv).rgb * 2.0 - 1.0; // lejos: 1 muestra plana
    }

    vec3 rw = antitiling_region_weights(uv);
    vec3 d;
    if (rw.z <= 0.001) {
        d = antitiling_region_normal(tex, uv, rw.x);
    } else if (rw.z >= 0.999) {
        d = antitiling_region_normal(tex, uv, rw.y);
    } else {
        d = mix(
            antitiling_region_normal(tex, uv, rw.x),
            antitiling_region_normal(tex, uv, rw.y),
            rw.z
        );
    }

    if (detile >= 0.999) {
        return d; // cerca: solo de-tilado
    }
    return mix(texture(tex, uv).rgb * 2.0 - 1.0, d, detile);
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

// Versiones de sample que aceptan UVs precomputados
vec3 triplanar_sample_uvs(sampler2D tex, TriplanarUVs uvs, vec3 normal) {
    vec3 col_x = tex_notile(tex, uvs.uv_x).rgb;
    vec3 col_y = tex_notile(tex, uvs.uv_y).rgb;
    vec3 col_z = tex_notile(tex, uvs.uv_z).rgb;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

// Factor de brillo del detail blend, normalizado por la media real de la textura (mip 1x1).
// Devuelve 1.0 donde el detalle vale lo que la media, así que la mezcla no cambia la
// luminancia de la textura sea clara u oscura (el clásico *2.0 solo era neutro con media 0.5,
// y en lineal la hierba está en ~0.05: perdía el 45% de brillo).
float detail_blend_factor(sampler2D tex, TriplanarUVs uvs_detail, vec3 axis, float weight) {
    const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
    vec3 detail = triplanar_sample_uvs(tex, uvs_detail, axis);
    vec3 avg = textureLod(tex, vec2(0.5), 20.0).rgb; // mip más bajo = media de la textura
    float ratio = dot(detail, LUMA) / max(dot(avg, LUMA), 0.002);
    return mix(1.0, clamp(ratio, 0.25, 3.0), weight);
}

// Mapas escalares (roughness/AO/height): muestreo PLANO (sin anti-tiling). La repetición
// de roughness/AO/height es prácticamente imperceptible frente a la del albedo, pero
// de-tilarlos cuesta lo mismo. Aquí solo albedo y normal pasan por tex_notile; esto
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

const int FNL_PRIME_X = 501125321;
const int FNL_PRIME_Y = 1136930381;
const int FNL_PRIME_Z = 1720413743;

int fnl_hash_3d(int seed, int x_primed, int y_primed, int z_primed) {
    int h = seed ^ x_primed ^ y_primed ^ z_primed;
    h *= 668265261; // 0x27d4eb2d — constante exacta de FastNoiseLite
    return h;
}

vec3 fnl_gradient_3d(int hash) {
    hash ^= hash >> 15;
    int index = (hash & 252) >> 2;

    if (index >= 60) {
        if (index == 60) return vec3(1.0, 1.0, 0.0);
        if (index == 61) return vec3(0.0, -1.0, 1.0);
        if (index == 62) return vec3(-1.0, 1.0, 0.0);
        return vec3(0.0, -1.0, -1.0);
    }

    int g = index % 12;
    if (g == 0) return vec3(0.0, 1.0, 1.0);
    if (g == 1) return vec3(0.0, -1.0, 1.0);
    if (g == 2) return vec3(0.0, 1.0, -1.0);
    if (g == 3) return vec3(0.0, -1.0, -1.0);
    if (g == 4) return vec3(1.0, 0.0, 1.0);
    if (g == 5) return vec3(-1.0, 0.0, 1.0);
    if (g == 6) return vec3(1.0, 0.0, -1.0);
    if (g == 7) return vec3(-1.0, 0.0, -1.0);
    if (g == 8) return vec3(1.0, 1.0, 0.0);
    if (g == 9) return vec3(-1.0, 1.0, 0.0);
    if (g == 10) return vec3(1.0, -1.0, 0.0);
    return vec3(-1.0, -1.0, 0.0);
}

float fnl_grad_coord_3d(int seed, int x_primed, int y_primed, int z_primed, float xd, float yd, float zd) {
    vec3 g = fnl_gradient_3d(fnl_hash_3d(seed, x_primed, y_primed, z_primed));
    return dot(g, vec3(xd, yd, zd));
}

float fast_noise_lite_open_simplex2_single_3d(int seed, float x, float y, float z) {
    int i = int(round(x));
    int j = int(round(y));
    int k = int(round(z));
    float x0 = x - float(i);
    float y0 = y - float(j);
    float z0 = z - float(k);

    int x_nsign = int(-1.0 - x0) | 1;
    int y_nsign = int(-1.0 - y0) | 1;
    int z_nsign = int(-1.0 - z0) | 1;

    float ax0 = float(x_nsign) * -x0;
    float ay0 = float(y_nsign) * -y0;
    float az0 = float(z_nsign) * -z0;

    i *= FNL_PRIME_X;
    j *= FNL_PRIME_Y;
    k *= FNL_PRIME_Z;

    float value = 0.0;
    float a = (0.6 - x0 * x0) - (y0 * y0 + z0 * z0);

    for (int l = 0; l < 2; l++) {
        if (a > 0.0) {
            value += (a * a) * (a * a) * fnl_grad_coord_3d(seed, i, j, k, x0, y0, z0);
        }

        float b = a + 1.0;
        int i1 = i;
        int j1 = j;
        int k1 = k;
        float x1 = x0;
        float y1 = y0;
        float z1 = z0;
        if (ax0 >= ay0 && ax0 >= az0) {
            x1 += float(x_nsign);
            b -= float(x_nsign) * 2.0 * x1;
            i1 -= x_nsign * FNL_PRIME_X;
        } else if (ay0 > ax0 && ay0 >= az0) {
            y1 += float(y_nsign);
            b -= float(y_nsign) * 2.0 * y1;
            j1 -= y_nsign * FNL_PRIME_Y;
        } else {
            z1 += float(z_nsign);
            b -= float(z_nsign) * 2.0 * z1;
            k1 -= z_nsign * FNL_PRIME_Z;
        }

        if (b > 0.0) {
            // FastNoiseLite canónico: ambas muestras de la iteración usan el mismo seed
            value += (b * b) * (b * b) * fnl_grad_coord_3d(seed, i1, j1, k1, x1, y1, z1);
        }

        if (l == 1) {
            break;
        }

        ax0 = 0.5 - ax0;
        ay0 = 0.5 - ay0;
        az0 = 0.5 - az0;

        x0 = float(x_nsign) * ax0;
        y0 = float(y_nsign) * ay0;
        z0 = float(z_nsign) * az0;

        a += (0.75 - ax0) - (ay0 + az0);

        i += (x_nsign >> 1) & FNL_PRIME_X;
        j += (y_nsign >> 1) & FNL_PRIME_Y;
        k += (z_nsign >> 1) & FNL_PRIME_Z;

        x_nsign = -x_nsign;
        y_nsign = -y_nsign;
        z_nsign = -z_nsign;

        seed = ~seed;
    }

    return value * 32.69428253173828125;
}
float fast_noise_lite_open_simplex2_ridged_3d(
    vec3 p, float frequency, int seed,
    int octaves, float lacunarity, float gain, float weighted_strength
) {
    // Frequency + rotación R3 una sola vez (igual que el wrapper single).
    // Las octavas siguientes solo escalan por lacunarity en el espacio ya rotado,
    // tal como hace GenFractalRidged en FastNoiseLite.
    vec3 q = p * frequency;
    float r = (q.x + q.y + q.z) * (2.0 / 3.0);
    q = vec3(r) - q;

    // fractal_bounding = 1 / sum(gain^i) para i en [0, octaves-1].
    // Normaliza la suma final a ~[-1, 1] independientemente del número de octavas.
    float amp_iter = gain;
    float amp_fractal = 1.0;
    for (int i = 1; i < octaves; i++) {
        amp_fractal += amp_iter;
        amp_iter *= gain;
    }
    float fractal_bounding = 1.0 / amp_fractal;

    float sum = 0.0;
    float amp = fractal_bounding;

    for (int i = 0; i < octaves; i++) {
        float n = abs(fast_noise_lite_open_simplex2_single_3d(seed, q.x, q.y, q.z));
        // (noise * -2 + 1): convierte |n| en [0,1] → [-1,1] con ridges en los picos
        sum += (n * -2.0 + 1.0) * amp;
        // weighted_strength atenúa las octavas siguientes cerca de los valles
        amp *= mix(1.0, 1.0 - n, weighted_strength);

        q *= lacunarity;
        amp *= gain;
        seed += 1;  // seed++ post-incremento, igual que FNL
    }

    return sum;
}
float fast_noise_lite_open_simplex2_3d(vec3 p, float frequency, int seed) {
    vec3 q = p * frequency;
    float r = (q.x + q.y + q.z) * (2.0 / 3.0);
    q = vec3(r) - q;
    return fast_noise_lite_open_simplex2_single_3d(seed, q.x, q.y, q.z);
}

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

vec4 triplanar_normal_sample_uvs_v(sampler2D tex, TriplanarUVs uvs, vec3 surface_normal) {

    vec3 raw_x = antitiling_normal_notile(tex, uvs.uv_x);
    vec3 raw_y = antitiling_normal_notile(tex, uvs.uv_y);
    vec3 raw_z = antitiling_normal_notile(tex, uvs.uv_z);

    vec3 blend = triplanar_blend_weights(surface_normal, 4.0);

    // Tightness: 1.0 = sin promediado de mip, <1.0 = mip promedió perturbaciones
    float avg_len = length(raw_x) * blend.x
                  + length(raw_y) * blend.y
                  + length(raw_z) * blend.z;

    // Whiteout blend igual que antes, pero con los samples ya normalizados
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
