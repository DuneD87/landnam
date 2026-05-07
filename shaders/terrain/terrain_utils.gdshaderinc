

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
    vec3 col_x = texture(tex, uvs.uv_x).rgb;
    vec3 col_y = texture(tex, uvs.uv_y).rgb;
    vec3 col_z = texture(tex, uvs.uv_z).rgb;
    vec3 blend = triplanar_blend_weights(normal, 3.0);
    return col_x * blend.x + col_y * blend.y + col_z * blend.z;
}

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

// Whiteout blending (lo que vimos antes) con UVs precomputados
vec3 triplanar_normal_sample_uvs(sampler2D tex, TriplanarUVs uvs, vec3 surface_normal) {
    vec3 tn_x = unpack_normal(texture(tex, uvs.uv_x).rgb);
    vec3 tn_y = unpack_normal(texture(tex, uvs.uv_y).rgb);
    vec3 tn_z = unpack_normal(texture(tex, uvs.uv_z).rgb);

    tn_x = vec3(tn_x.xy + surface_normal.zy, abs(tn_x.z) * surface_normal.x);
    tn_y = vec3(tn_y.xy + surface_normal.xz, abs(tn_y.z) * surface_normal.y);
    tn_z = vec3(tn_z.xy + surface_normal.xy, abs(tn_z.z) * surface_normal.z);

    vec3 blend = triplanar_blend_weights(surface_normal, 4.0);

    return safe_normalize(
        tn_x.zyx * blend.x +
        tn_y.xzy * blend.y +
        tn_z.xyz * blend.z,
        surface_normal
    );
}

vec3 triplanar_normal_sample(sampler2D tex, vec3 pos, vec3 surface_normal, float scale) {
    vec2 uv_x = pos.yz * scale;
    vec2 uv_y = pos.xz * scale;
    vec2 uv_z = pos.xy * scale;

    // Muestreo en tangente (-1..1)
    vec3 tn_x = unpack_normal(texture(tex, uv_x).rgb);
    vec3 tn_y = unpack_normal(texture(tex, uv_y).rgb);
    vec3 tn_z = unpack_normal(texture(tex, uv_z).rgb);

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
