// Twelve coherent, incommensurate modes: swell, cross sea and wind waves.
// No packet lattice or spatial averaging. CPU mirror: ocean_spectrum.gd.
uniform float spectrum_spread : hint_range(0.0, 1.5) = 0.8;
const int OCEAN_MODES = 12;
const float OCEAN_LENGTHS[12] = {1.0,0.86,1.19,0.67,0.45,0.38,0.31,0.24,0.17,0.135,0.105,0.078};
const float OCEAN_HEIGHTS[12] = {0.72,0.42,0.32,0.28,0.24,0.19,0.15,0.12,0.09,0.065,0.045,0.03};
const float OCEAN_CHOP[12] = {0.42,0.18,0.10,0.07,0.05,0.04,0.035,0.03,0.025,0.02,0.015,0.015};
const float OCEAN_ANGLES[12] = {0.0,-0.27,0.33,-0.51,0.62,-0.73,0.91,-1.04,1.17,-1.31,1.43,-1.57};

mat3 ocean_outer(vec3 a, vec3 b) { return mat3(a*b.x,a*b.y,a*b.z); }
vec3 ocean_mode_direction(vec3 wind, int i) {
    vec3 side = normalize(cross(wind, abs(wind.y)<0.9 ? vec3(0,1,0) : vec3(1,0,0)));
    vec3 vertical = cross(wind,side);
    float angle = OCEAN_ANGLES[i]*spectrum_spread;
    // Small out-of-plane spread keeps wind detail present at the planet's poles.
    return normalize(wind*cos(angle)+side*sin(angle)+vertical*sin(float(i)*2.399)*0.28);
}
float ocean_phase(vec3 p, vec3 dir, float k, float t, int i) {
    return k*dot(p,dir)+t*wave_speed*sqrt(9.81*k)+float(i)*2.39996323;
}
float ocean_mode_gate(float wavelength, float amplitude, float min_length,
                      float ocean_weight, float depth) {
    float lod = min_length>0.0 ? smoothstep(min_length*0.5,min_length*1.5,wavelength) : 1.0;
    float chop = (1.0-smoothstep(shore_length*0.25,shore_length*0.75,wavelength))
        *clamp(depth*0.4/max(amplitude,0.01),0.0,1.0)*shore_chop;
    return max(ocean_weight,chop)*lod;
}
float ocean_horizontal(float a, float k, float steepness, float gate, int i) {
    // Total horizontal contraction is bounded below one, even if every phase aligns.
    return min(a*4.0, OCEAN_CHOP[i]/(1.1*k))*clamp(steepness,0.0,0.95)*gate;
}
struct OceanField {
    vec3 lateral;
    float height;
    mat3 derivative;
    vec3 slope;
};
OceanField ocean_field(vec3 p, vec3 wind, float t, float amplitude, float steepness,
                       float min_length, float ocean_weight, float depth) {
    OceanField field;
    field.lateral=vec3(0.0); field.height=0.0;
    field.derivative=mat3(0.0); field.slope=vec3(0.0);
    float h2=0.22*clamp(steepness,0.0,0.95);
    float h3=0.055*steepness*steepness;
    for(int i=0;i<OCEAN_MODES;i++) {
        float wavelength=max(wave_base_length*OCEAN_LENGTHS[i],1.0);
        float k=6.28318530718/wavelength;
        float gate=ocean_mode_gate(wavelength,amplitude,min_length,ocean_weight,depth);
        vec3 dir=ocean_mode_direction(wind,i);
        float phase=ocean_phase(p,dir,k,t,i);
        float s=sin(phase), c=cos(phase);
        float a=amplitude*OCEAN_HEIGHTS[i];
        float horizontal=ocean_horizontal(a,k,steepness,gate,i);
        float profile=s+h2*(2.0*s*s-1.0)+h3*(4.0*s*s*s-3.0*s);
        float derivative=c*(1.0+4.0*h2*s+h3*(12.0*s*s-3.0));
        field.height+=a*gate*profile;
        field.slope+=dir*(a*gate*k*derivative);
        field.lateral+=dir*(horizontal*c);
        field.derivative-=ocean_outer(dir,dir)*(horizontal*k*s);
    }
    return field;
}
vec3 ocean_tangent(vec3 tangent, vec3 radial, float radius, OceanField field) {
    vec3 dv=field.derivative*tangent;
    return tangent*(1.0+(field.height-dot(radial,field.lateral))/radius)
        +dv-radial*dot(radial,dv)
        +radial*(dot(field.slope,tangent)-dot(field.lateral,tangent)/radius);
}

