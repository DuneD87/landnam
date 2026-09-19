// Whitecaps, residual wash and boat wakes. Coverage is independent of reflections.
uniform vec3 foam_color : source_color = vec3(0.96,0.98,1.0);
uniform float foam_crest_threshold : hint_range(0.0,1.0) = 0.55;
uniform float foam_crest_softness : hint_range(0.01,0.5) = 0.18;
uniform float foam_crest_amount : hint_range(0.0,10.0) = 1.4;
uniform float foam_trail_strength : hint_range(0.0,1.0) = 0.65;
uniform sampler2D foam_density_texture : hint_default_black, repeat_disable, filter_linear_mipmap_anisotropic;
uniform float foam_scale : hint_range(0.1,8.0) = 1.2;
uniform float foam_edge_breakup : hint_range(0.0,1.0) = 0.65;
uniform float foam_crest_width : hint_range(0.1,0.8) = 0.65;
uniform float shore_foam_amount : hint_range(0.0,1.0) = 0.8;
uniform float shore_soft_width : hint_range(0.01,10.0) = 1.2;
const int MAX_WAKES=8;
const int MAX_WAKE_POINTS=512;
uniform int wake_count=0;
uniform vec4 wake_bounds[MAX_WAKES];
uniform vec2 wake_ranges[MAX_WAKES];
uniform vec4 wake_points[MAX_WAKE_POINTS];
uniform float wake_alphas[MAX_WAKE_POINTS];

// Seconds of finite analytic history; changing it never changes the waves.
uniform float foam_lifetime : hint_range(1.0,10.0) = 5.0;

struct OceanBreakers {
    vec3 recent;
    vec3 older;
    float activity;
    float crest;
};
OceanBreakers ocean_breaker_history(vec3 p, vec3 radial, vec3 wind, float t,
        float amplitude, float steepness, float min_length, float ocean_weight, float depth) {
    OceanBreakers b;
    b.recent=vec3(0.0); b.older=vec3(0.0);
    float variance=0.0, slope_variance=0.0;
    float carrier_height=0.0,height_energy=0.0;
    float h2=0.22*clamp(steepness,0.0,0.95);
    float h3=0.055*steepness*steepness;
    for(int i=0;i<OCEAN_MODES;i++) {
        float wavelength=max(wave_base_length*OCEAN_LENGTHS[i],1.0);
        float k=6.28318530718/wavelength;
        float gate=ocean_mode_gate(wavelength,amplitude,min_length,ocean_weight,depth);
        vec3 dir=ocean_mode_direction(wind,i);
        float tangent_weight=max(1.0-pow(dot(dir,radial),2.0),0.0);
        float a=amplitude*OCEAN_HEIGHTS[i];
        float q=k*ocean_horizontal(a,k,steepness,gate,i)*tangent_weight;
        variance+=q*q*0.5;
        slope_variance+=pow(a*k*gate,2.0)*tangent_weight*0.5;
        float phase=ocean_phase(p,dir,k,t,i);
        // Height of the actual wave profile, used only to weight deposition.
        // Zero-slope contours of the short modes made artificial serpentine bands.
        float s=sin(phase);
        float profile=s+h2*(2.0*s*s-1.0)+h3*(4.0*s*s*s-3.0*s);
        carrier_height+=a*gate*profile;
        height_energy+=pow(a*gate,2.0)*0.5;
        float omega=wave_speed*sqrt(9.81*k)*foam_lifetime;
        b.recent+=q*sin(vec3(phase)-omega*vec3(0.0,0.13,0.28));
        b.older+=q*sin(vec3(phase)-omega*vec3(0.46,0.69,1.0));
    }
    // Normalize by local spectral energy: rotating around the sphere must not
    // silently change the meaning of the threshold. The floor and activity gate
    // prevent tiny ripples / zero displacement from producing storm whitecaps.
    float scale=max(2.5*sqrt(variance),0.03);
    b.recent=max(b.recent/scale,vec3(0.0));
    b.older=max(b.older/scale,vec3(0.0));
    b.activity=smoothstep(0.025,0.10,sqrt(slope_variance));
    float relative_height=carrier_height/max(sqrt(height_energy),0.01);
    float width=clamp(foam_crest_width,0.1,0.8);
    b.crest=smoothstep(1.6-width,1.9+width*0.2,relative_height);
    return b;
}
float ocean_hash(vec3 p) {
    uvec3 q=uvec3(ivec3(p));
    q=(q^(q>>16u))*uvec3(1597334677u,3812015801u,2798796415u);
    uint h=q.x^q.y^q.z;
    h=(h^(h>>16u))*2246822519u;
    return float(h^(h>>13u))/4294967295.0;
}
float ocean_noise(vec3 p) {
    vec3 cell=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(mix(ocean_hash(cell),ocean_hash(cell+vec3(1,0,0)),f.x),
                   mix(ocean_hash(cell+vec3(0,1,0)),ocean_hash(cell+vec3(1,1,0)),f.x),f.y),
               mix(mix(ocean_hash(cell+vec3(0,0,1)),ocean_hash(cell+vec3(1,0,1)),f.x),
                   mix(ocean_hash(cell+vec3(0,1,1)),ocean_hash(cell+vec3(1,1,1)),f.x),f.y),f.z);
}
float ocean_filtered_noise(vec3 p, float footprint) {
    return mix(ocean_noise(p),0.5,smoothstep(0.35,1.2,footprint));
}
// Blend interior texture patches with random rotations and offsets. The source
// does not need perfectly matching edges: samples stay inside [0.06, 0.94].
// Patch weights and their first derivatives vanish at each grid boundary.
vec2 ocean_foam_rotate(vec2 p, int rotation) {
    if(rotation==1) return vec2(-p.y,p.x);
    if(rotation==2) return -p;
    if(rotation==3) return vec2(p.y,-p.x);
    return p;
}
float ocean_foam_patch(vec2 uv, vec2 cell, vec2 dx, vec2 dy) {
    float seed=ocean_hash(vec3(cell,7.0));
    int rotation=int(seed*3.999);
    vec2 offset=vec2(ocean_hash(vec3(cell,31.0)),ocean_hash(vec3(cell,97.0)))-0.5;
    vec2 sample_uv=vec2(0.5)+ocean_foam_rotate(uv-cell,rotation)*0.35+offset*0.18;
    return textureGrad(foam_density_texture,sample_uv,
        ocean_foam_rotate(dx,rotation)*0.35,ocean_foam_rotate(dy,rotation)*0.35).r;
}
float ocean_foam_texture(vec2 uv, vec2 dx, vec2 dy) {
    vec2 cell=floor(uv), f=fract(uv);
    vec2 weights=f*f*f*(f*(f*6.0-15.0)+10.0);
    float a=ocean_foam_patch(uv,cell,dx,dy);
    float b=ocean_foam_patch(uv,cell+vec2(1,0),dx,dy);
    float c=ocean_foam_patch(uv,cell+vec2(0,1),dx,dy);
    float d=ocean_foam_patch(uv,cell+vec2(1,1),dx,dy);
    return mix(mix(a,b,weights.x),mix(c,d,weights.x),weights.y);
}
float ocean_foam_triplanar(vec3 p,vec3 weights,vec3 dx,vec3 dy) {
    return ocean_foam_texture(p.yz,dx.yz,dy.yz)*weights.x
        +ocean_foam_texture(p.xz,dx.xz,dy.xz)*weights.y
        +ocean_foam_texture(p.xy,dx.xy,dy.xy)*weights.z;
}
vec4 ocean_foam_pattern(vec3 material_pos,vec3 radial,vec3 wind,float time) {
    vec3 p=material_pos*foam_scale;
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    vec3 drift=wind*time*0.045;
    float rafts=ocean_filtered_noise(p*0.075-drift,footprint*0.075);
    vec3 weights=pow(abs(radial),vec3(8.0));
    weights/=max(weights.x+weights.y+weights.z,0.001);
    vec3 uv=(p-wind*time*0.12)/28.0;
    vec3 dx=dFdx(uv),dy=dFdy(uv);
    float broad=ocean_foam_triplanar(uv,weights,dx,dy);
    float fine=ocean_foam_triplanar(uv*3.71+vec3(17.3),weights,dx*3.71,dy*3.71);
    // Broad rafts keep their ragged outline; fine froth gives them internal
    // density variation. Preserve grayscale instead of outlining / thresholding it.
    float density=broad*mix(0.68,1.15,fine);
    // Vary the breaking contour itself, at several scales. Eroding only the
    // texture leaves every raft clipped against the same wave isocontour.
    float edge=ocean_filtered_noise(p*0.09-drift+vec3(41.0),footprint*0.09)*0.55;
    edge+=ocean_filtered_noise(p*0.27-drift+vec3(13.0),footprint*0.27)*0.30;
    edge+=ocean_filtered_noise(p*0.73-drift,footprint*0.73)*0.15;
    edge=clamp(0.5+(edge-0.5)*2.0,0.0,1.0);
    return vec4(rafts,fine,clamp(density,0.0,1.0),edge);
}
float ocean_foam_coverage(float mass, vec4 pattern, float erosion) {
    // Sparse parts of a raft also receive less foam: the breaking front dissolves
    // into fragments instead of cutting the texture along a continuous contour.
    float local_mass=mass*mix(0.35,1.25,smoothstep(0.05,0.65,pattern.z));
    float density=1.0-exp(-max(local_mass,0.0)*1.8);
    float cutoff=erosion*(1.0-density)*0.32;
    float texture_density=max((pattern.z-cutoff)/max(1.0-cutoff,0.01),0.0);
    // Fresh froth is opaque and particulate; residual foam thins and loses its
    // sparse edges first. Texture mipmaps retain density when detail is subpixel.
    return pow(texture_density,mix(1.6,0.55,density))*density*smoothstep(0.28,0.9,local_mass);
}
vec2 ocean_whitecaps(OceanBreakers b, vec4 pattern, float amount) {
    float threshold=max(0.02,foam_crest_threshold+(pattern.x-0.5)*0.30
        +(pattern.w-0.5)*foam_edge_breakup);
    float softness=max(foam_crest_softness,0.02);
    threshold+=(1.0-pattern.z)*softness*foam_edge_breakup;
    vec3 recent=smoothstep(vec3(threshold),vec3(threshold+softness),b.recent);
    vec3 older=smoothstep(vec3(threshold),vec3(threshold+softness),b.older);
    float deposition=log(1.0+max(amount,0.0))*1.5*b.activity;
    // A crest adds density to existing froth. Never fill texture holes or
    // union an opaque geometric strip with the mask: that paints white ribbons.
    float crown=clamp(b.crest+(pattern.w-0.5)*foam_edge_breakup*1.6*b.crest*(1.0-b.crest),0.0,1.0);
    float core=crown*smoothstep(max(foam_crest_threshold,0.15),
        max(foam_crest_threshold,0.15)+softness,b.recent.x);
    float buildup=1.0+1.5*smoothstep(1.0,4.0,amount);
    deposition*=mix(0.2,1.0,smoothstep(0.22,0.72,pattern.x));
    float fresh=recent.x*deposition*(0.55+core*buildup);
    float aged=dot(recent.yz,vec2(0.30,0.24))+dot(older,vec3(0.20,0.15,0.08));
    aged*=deposition*foam_trail_strength*0.7;
    return vec2(ocean_foam_coverage(fresh,pattern,0.0),
        ocean_foam_coverage(aged,pattern,1.0));
}
float ocean_wake(vec3 world, vec3 radial) {
    float wake=0.0;
    for(int w=0;w<MAX_WAKES;w++) {
        if(w>=wake_count) break;
        vec3 bd=world-wake_bounds[w].xyz;
        if(dot(bd,bd)>wake_bounds[w].w*wake_bounds[w].w) continue;
        int start=int(wake_ranges[w].x), end=start+int(wake_ranges[w].y);
        for(int i=start;i<end-1;i++) {
            vec4 a=wake_points[i], b=wake_points[i+1];
            vec3 ab=b.xyz-a.xyz, ap=world-a.xyz;
            float t=clamp(dot(ap,ab)/max(dot(ab,ab),0.0001),0.0,1.0);
            vec3 d=ap-ab*t;
            float r=max(mix(a.w,b.w,t),0.01);
            float distance_to_wake=length(d-radial*dot(d,radial));
            wake=max(wake,(1.0-smoothstep(r*0.2,r,distance_to_wake))*mix(wake_alphas[i],wake_alphas[i+1],t));
        }
    }
    return clamp(wake,0.0,1.0);
}
