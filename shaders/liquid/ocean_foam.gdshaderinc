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
// --- Rompiente ---------------------------------------------------------------------------------
// La ola de orilla rompe a unos surf_zone_width metros del litoral y llega rota hasta la playa: del frente de la cresta sale
// un rodillo de espuma densa que avanza con ella y deja detrás una cola que se abre en encaje
// (surf_tail = lo deprisa que se apaga; más alto, cola más corta).
uniform float surf_foam_amount : hint_range(0.0,3.0) = 1.2;
uniform float surf_zone_width : hint_range(5.0,200.0) = 70.0;
uniform float surf_tail : hint_range(1.0,12.0) = 4.5;
// Vaivén de la espuma en la línea de playa: cada ola la empuja tierra adentro y al retirarse deja
// un encaje que se deshace. 0 = la franja fija de antes.
uniform float swash_strength : hint_range(0.0,1.0) = 0.8;
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
    // Varianza de pendiente de todo el espectro en este punto, y la parte que el LOD de distancia ya
    // no dibuja: el píxel la recupera como rugosidad y borreguillos estadísticos (ver far_* en
    // water_shader.gdshader).
    float slopes;
    float hidden;
    // Pendiente de las olas que la malla no dibuja pero el píxel sí resuelve (se suma a la normal),
    // y contracción de la superficie aquí (positiva en la cresta): afila lo que cabalga encima.
    vec3 detail;
    float pinch;
};
// Deriva común a las olas que solo dibuja la normal: cuatro ondulaciones fijas que desplazan el punto
// donde se evalúa la fase. A la ola larga no le hacen nada; a la corta le doblan la cresta y le
// cambian la longitud a trozos. La suma de sus gradientes no pasa de 0,8: deforma, no pliega.
vec3 ocean_ripple_warp(vec3 p) {
    return vec3(0.83,-0.28,0.48)*(0.25*sin(dot(p,vec3(-0.37,0.62,0.69))*0.9+1.3))
        +vec3(-0.31,0.88,0.36)*(0.08*sin(dot(p,vec3(0.73,0.21,0.65))*2.3+4.1))
        +vec3(0.29,0.75,-0.60)*(0.03*sin(dot(p,vec3(0.71,-0.41,0.57))*5.9))
        +vec3(0.62,0.11,0.78)*(0.011*sin(dot(p,vec3(-0.52,0.80,0.30))*14.0+2.2));
}
// Cresta corta: la amplitud de una ola sube y baja A LO LARGO de su cresta, en tramos de unas tres
// longitudes de onda. Un tren de ondas planas tiene crestas rectas de horizonte a horizonte y,
// visto de punta, raya el mar hacia el punto de fuga.
// Los dos ejes son perpendiculares a la ola y FIJOS en el marco del planeta. No sirve el eje natural
// (cresta = dir x vertical local): la posición es paralela a la vertical local, así que su producto
// con ese eje es cero en todas partes y solo queda ruido de redondeo. Con dos, al menos uno corre a
// lo largo de la cresta en cualquier punto del planeta. La media cuadrática del factor es 1.
float ocean_short_crest(vec3 p, vec3 dir, float k, int i) {
    vec3 e1=normalize(cross(dir,vec3(0.36,0.48,0.8)));
    vec3 e2=cross(dir,e1);
    float phase=float(i)*1.9;
    return (0.62+0.27*sin(dot(p,e1)*k*0.33+phase)+0.27*sin(dot(p,e2)*k*0.29+phase*1.7))*1.45;
}
// 'min_length' es el LOD de la MALLA (lo que el vértice ya desplaza); 'dpx' y 'dpy' son las derivadas
// de pantalla de 'p'. El píxel decide por su cuenta qué olas resuelve según cuánto mide sobre el agua.
OceanBreakers ocean_breaker_history(vec3 p, vec3 radial, vec3 wind, float t,
        float amplitude, float steepness, float min_length, float ocean_weight, float depth,
        float inland, vec3 dpx, vec3 dpy) {
    OceanBreakers b;
    b.recent=vec3(0.0); b.older=vec3(0.0); b.detail=vec3(0.0);
    float variance=0.0, slope_variance=0.0, full_slopes=0.0;
    float carrier_height=0.0,height_energy=0.0;
    float h2=0.22*clamp(steepness,0.0,0.95);
    float h3=0.055*steepness*steepness;
    float major=max(length(dpx),length(dpy));
    vec3 warp=ocean_ripple_warp(p);
    for(int i=0;i<OCEAN_MODES;i++) {
        float wavelength=max(wave_base_length*OCEAN_LENGTHS[i],1.0);
        float k=6.28318530718/wavelength;
        float full_gate=ocean_mode_gate(wavelength,amplitude,0.0,ocean_weight,depth,inland);
        vec3 dir=ocean_mode_direction(wind,i);
        // Entera con más de 4,5 píxeles por longitud de onda, nada con menos de 2,2. El píxel se mide
        // a lo largo de la ola, pero con un suelo de tres cuartos de su lado largo: filtrando solo
        // por dirección, a ras de agua sobreviven nada más que las olas que corren hacia la cámara y
        // el mar queda peinado en rayas hacia el punto de fuga.
        float pixel=1.0-smoothstep(0.22,0.45,max(max(abs(dot(dpx,dir)),abs(dot(dpy,dir))),major*0.75)/wavelength);
        float mesh=min_length>0.0 ? smoothstep(min_length*0.5,min_length*1.5,wavelength) : 1.0;
        float gate=full_gate*pixel;
        vec3 tangent_dir=dir-radial*dot(dir,radial);
        float tangent_weight=dot(tangent_dir,tangent_dir);
        float a=amplitude*OCEAN_HEIGHTS[i];
        float q=k*ocean_horizontal(a,k,steepness,gate,i)*tangent_weight;
        variance+=q*q*0.5;
        float mode_slopes=pow(a*k*full_gate,2.0)*tangent_weight*0.5;
        full_slopes+=mode_slopes;
        slope_variance+=mode_slopes*pixel*pixel;
        float phase=ocean_phase(p,dir,k,t,i);
        // Height of the actual wave profile, used only to weight deposition.
        // Zero-slope contours of the short modes made artificial serpentine bands.
        float s=sin(phase), c=cos(phase);
        float profile=s+h2*(2.0*s*s-1.0)+h3*(4.0*s*s*s-3.0*s);
        carrier_height+=a*gate*profile;
        height_energy+=pow(a*gate,2.0)*0.5;
        // Gradiente de altura de la parte de esta ola que el píxel ve y la malla no lleva, con la
        // cresta doblada y cortada en tramos (la malla sí lleva la ola entera y recta).
        float unseen=max(pixel-mesh,0.0);
        if(unseen>0.001) {
            float bent=phase+k*dot(warp,dir);
            float bs=sin(bent);
            b.detail+=tangent_dir*(a*full_gate*k*cos(bent)*(1.0+4.0*h2*bs+h3*(12.0*bs*bs-3.0))
                *unseen*ocean_short_crest(p,dir,k,i));
        }
        float omega=wave_speed*sqrt(9.81*k)*foam_lifetime;
        b.recent+=q*sin(vec3(phase)-omega*vec3(0.0,0.13,0.28));
        b.older+=q*sin(vec3(phase)-omega*vec3(0.46,0.69,1.0));
    }
    b.pinch=b.recent.x;
    // Normalize by local spectral energy: rotating around the sphere must not
    // silently change the meaning of the threshold. The floor and activity gate
    // prevent tiny ripples / zero displacement from producing storm whitecaps.
    float scale=max(2.5*sqrt(variance),0.03);
    b.recent=max(b.recent/scale,vec3(0.0));
    b.older=max(b.older/scale,vec3(0.0));
    b.activity=smoothstep(0.025,0.10,sqrt(slope_variance));
    b.slopes=full_slopes;
    b.hidden=max(full_slopes-slope_variance,0.0);
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
// Cada celda enseña una ventana de ±0,2 de la textura, con el centro en cualquier punto de ±0,24,
// girada y a veces reflejada. Con la ventana anterior (±0,35) el centro solo podía moverse ±0,09
// sin salirse de la imagen: todas las celdas enseñaban casi el mismo trozo y la espuma se repetía
// como un azulejo girado.
float ocean_foam_patch(vec2 uv, vec2 cell, vec2 dx, vec2 dy) {
    float seed=ocean_hash(vec3(cell,7.0));
    int rotation=int(seed*3.999);
    float flip=ocean_hash(vec3(cell,53.0))<0.5 ? -1.0 : 1.0;
    vec2 offset=vec2(ocean_hash(vec3(cell,31.0)),ocean_hash(vec3(cell,97.0)))-0.5;
    vec2 mirror=vec2(flip,1.0);
    vec2 sample_uv=vec2(0.5)+ocean_foam_rotate((uv-cell)*mirror,rotation)*0.2+offset*0.48;
    return textureGrad(foam_density_texture,sample_uv,
        ocean_foam_rotate(dx*mirror,rotation)*0.2,ocean_foam_rotate(dy*mirror,rotation)*0.2).r;
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
    // 16 m por celda: con la ventana de ±0,2 la textura conserva su tamaño en el mundo (80 m).
    vec3 uv=(p-wind*time*0.12)/16.0;
    vec3 dx=dFdx(uv),dy=dFdy(uv);
    // A ras de agua el píxel es decenas de veces más largo que ancho y el filtro anisótropo no llega:
    // lo que sobra se emborrona en hebras que apuntan a la cámara. Se engorda el lado corto hasta
    // 4:1, que sí cubre: la espuma lejana queda suave en vez de peinada.
    float lx=length(dx), ly=length(dy), major=max(lx,ly);
    dx*=max(1.0,major/(4.0*max(lx,0.0000001)));
    dy*=max(1.0,major/(4.0*max(ly,0.0000001)));
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
// 'churn' recibe la masa de espuma antes de recortarla con la textura, para el agua batida.
vec2 ocean_whitecaps(OceanBreakers b, vec4 pattern, float amount, out vec2 churn) {
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
    // Dos escalas: x = la misma masa que la espuma (el agua batida justo bajo las balsas), y = la
    // rompiente con el umbral abierto y sin el recorte fino del dibujo (el halo ancho alrededor).
    float base=max(foam_crest_threshold,0.02);
    vec3 wide_recent=smoothstep(vec3(base),vec3(base+softness*4.0),b.recent);
    vec3 wide_older=smoothstep(vec3(base),vec3(base+softness*4.0),b.older);
    churn=vec2(fresh+aged,(wide_recent.x*(0.55+core*buildup)+dot(wide_recent.yz,vec2(0.30,0.24))
        +dot(wide_older,vec3(0.20,0.15,0.08))*foam_trail_strength)*deposition);
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

// Rodillo de la rompiente a partir de shore_wave_signal: x = masa de espuma, y = su edad dentro
// de la ola (0 en el frente que rompe, 1 justo antes de que llegue la siguiente).
vec2 ocean_surf(vec3 signal, vec4 pattern) {
    // El frente va 0.6 rad por delante del paso por cero: al pie de la cara que mira a tierra. El
    // dibujo de la espuma lo mella para que no sea la isolínea exacta de la fase.
    float age=fract((signal.x-0.6)/6.28318530718-(pattern.w-0.5)*0.035);
    float zone=1.0-smoothstep(surf_zone_width*0.7,surf_zone_width*1.3,signal.z);
    float roller=smoothstep(0.0,0.02,age)*exp(-age*surf_tail);
    return vec2(roller*zone*signal.y,age);
}
// Labio de la rompiente: la línea blanca y densa del frente que rompe. A diferencia del resto de
// la espuma casi no depende del dibujo: es agua batida, no balsas. La cortan los tramos flojos de
// la ola (el peso), no la textura.
float ocean_surf_lip(vec3 signal, vec4 pattern, float age) {
    float zone=1.0-smoothstep(surf_zone_width*0.7,surf_zone_width*1.3,signal.z);
    float lip=smoothstep(0.0,0.012,age)*(1.0-smoothstep(0.035,0.11,age));
    return lip*zone*smoothstep(0.22,0.5,signal.y)*mix(0.6,1.0,pattern.z);
}
// Alcance del vaivén en la playa según la edad de la ola: sube deprisa al llegar, baja despacio.
float ocean_swash_reach(float age) {
    return smoothstep(0.0,0.12,age)*(1.0-smoothstep(0.15,0.85,age));
}
