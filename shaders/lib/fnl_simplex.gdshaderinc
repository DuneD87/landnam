// =============================================================================
//  fnl_simplex.gdshaderinc
//  Réplica exacta del OpenSimplex2 3D de FastNoiseLite (ZN_FastNoiseLite del módulo de vóxeles):
//  lo que decide un grafo de vegetación en CPU se puede reproducir píxel a píxel en un shader.
//  Lo usan el terreno (máscaras de ruido de bioma) y el campo de clima (climate.gdshaderinc).
// =============================================================================
#ifndef FNL_SIMPLEX_INC
#define FNL_SIMPLEX_INC

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

    // Los primeros 60 índices repiten 12 gradientes. Solo 60 y 62 rompen
    // el ciclo: corresponden a los gradientes 8 y 9; 61 y 63 ya dan 1 y 3.
    // Reconstruye la misma tabla sin recorrer ramas distintas por muestra.
    int g = index % 12 + 8 * int(index == 60) + 7 * int(index == 62);
    float a = 1.0 - 2.0 * float(g & 1);
    float b = 1.0 - 2.0 * float((g >> 1) & 1);
    return vec3(a * float(g >= 4),
        mix(b, a, float(g < 8)) * float(g < 4 || g >= 8),
        b * float(g < 8));
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

#endif
