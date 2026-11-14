shader_type spatial;
render_mode blend_mix, depth_draw_always;

// Surface simulation is shared with buoyancy and the underwater ray marcher.
#include "res://shaders/liquid/gerstner_waves.gdshaderinc"
#include "res://shaders/liquid/underwater_fog.gdshaderinc"
#include "res://shaders/liquid/ship_interiors.gdshaderinc"
#include "res://shaders/lib/sky_reflection.gdshaderinc"
#include "res://shaders/liquid/ocean_optics.gdshaderinc"
#include "res://shaders/liquid/ocean_foam.gdshaderinc"
#include "res://shaders/liquid/ocean_chop.gdshaderinc"
#include "res://shaders/liquid/hull_waves.gdshaderinc"

uniform float water_time=0.0;
uniform vec3 planet_center=vec3(0.0);
uniform vec3 waterline_point=vec3(0.0);
uniform vec3 waterline_normal=vec3(0.0,1.0,0.0);
uniform float wave_lod_start : hint_range(50.0,20000.0) = 800.0;
uniform float wave_lod_falloff : hint_range(1.0,4.0) = 1.6;
// La malla del agua: separación entre vértices del nivel más fino (m) y cuánto crece por metro de
// distancia a la cámara (los pone OceanSystem a partir del quadtree). Una ola con menos de unos
// tres vértices por longitud de onda no se puede desplazar: sale un zigzag que baila al moverse la
// malla y, de lejos, una rejilla. Esas olas se quedan sin desplazamiento y las dibuja la normal por
// píxel (ocean_breaker_history).
uniform float mesh_min_spacing = 0.9;
uniform float mesh_spacing_rate = 0.016;
uniform float mesh_wave_samples : hint_range(1.0,8.0) = 3.2;
uniform sampler2D texture_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D texture_normal2 : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float normal_scale1 : hint_range(0.1,100.0) = 8.0;
uniform float normal_scale2 : hint_range(0.1,100.0) = 23.0;
uniform float normal_intensity : hint_range(0.0,4.0) = 0.65;
uniform float normal_slope_limit : hint_range(0.01,1.0) = 0.16;
// Parte del rizado de textura (texture_normal/2) que se conserva. A 0 desde que el mar de viento lo
// dibujan ondas de verdad (ocean_chop): el ruido es una textura que se repite cada 8 m y cada 23 m
// y se veía como un grano uniforme, en azulejo; además escarchaba el agua a ras de superficie.
uniform float texture_ripple : hint_range(0.0,1.0) = 0.0;
uniform float roughness : hint_range(0.02,1.0) = 0.12;
uniform float specular_antialiasing : hint_range(0.0,1.0) = 0.4;
uniform float detail_fade_start=150.0;
uniform float detail_fade_end=1200.0;
uniform vec3 sun_direction=vec3(0.4,-0.7,0.3);
// Luz de la escena (SkyLighting): radiancia efectiva del sol y de la luna (color × energía, con la
// hora, la extinción y el clima ya aplicados) y la del cielo que baña el agua. Antes el agua tenía
// su propio sol blanco fijo y una paleta día/noche: al atardecer seguía iluminada a pleno día.
global uniform vec3 sky_sun_radiance;
global uniform vec3 sky_moon_radiance;
global uniform vec3 sky_moon_direction;
global uniform vec3 sky_ambient_radiance;
uniform vec3 sss_color : source_color = vec3(0.08,0.46,0.32);
uniform float sss_intensity : hint_range(0.0,3.0) = 0.7;
// Luz que el agua devuelve desde dentro en las caras que miran a la cámara, y la que devuelve hacia
// todas partes (como un difuso tenue). Sin ellas el agua es de un solo color y la ola no tiene
// volumen: solo se distingue por lo que refleja.
uniform float sss_view : hint_range(0.0,1.0) = 0.1;
uniform float sss_lambert : hint_range(0.0,1.0) = 0.05;
// Agua batida: bajo la espuma y a su alrededor el agua está llena de burbujas y se ve turquesa
// lechoso. Es lo que hace que una mancha blanca se lea como espuma y no como algo posado encima.
uniform vec3 churn_color : source_color = vec3(0.17,0.44,0.42);
uniform float churn_strength : hint_range(0.0,1.0) = 0.6;
// Luz del cielo sobre la espuma, como fracción del cielo que refleja el agua. El ambiente del motor
// es mucho más oscuro que ese cielo: sin esto una espuma fina sobre agua que refleja el horizonte la
// OSCURECE (tapa un reflejo brillante con un blanco mal iluminado) y se lee como una costra gris.
uniform float foam_skylight : hint_range(0.0,1.5) = 0.6;
// Cuánto del reflejo que apunta bajo el horizonte se sustituye por agua (da en otra ola, no en el
// cielo). 0 = todo cielo, como antes.
uniform float reflection_occlusion : hint_range(0.0,1.0) = 0.85;
uniform float light_diffuse_strength=1.0;
uniform float light_specular_clamp=0.65;
uniform float directional_specular_clamp=0.65;
uniform float light_roughness_floor=0.22;
uniform float directional_roughness_floor=0.08;
uniform sampler2D caustics_texture : repeat_enable, filter_linear_mipmap;
uniform float caustics_scale=0.5;
uniform float caustics_speed=0.1;
uniform float caustics_intensity=0.25;
uniform int water_debug_mode : hint_range(0,8) = 0;

// --- El mar de lejos ---------------------------------------------------------------------------
// Con la distancia el LOD apaga las olas cortas y las normales de detalle se funden: sin más, lo
// que queda es un espejo liso que refleja el cielo entero en el horizonte y el sol en un punto. Un
// mar de verdad sigue rizado aunque no se le vean las olas, y eso se nota en tres cosas: el reflejo
// del sol se abre en un camino ancho de destellos, el horizonte refleja MENOS cielo (las facetas
// miran al observador) y deja ver el color del agua, y las rompientes siguen blanqueando. Aquí la
// pendiente que ya no se dibuja se devuelve como estadística: rugosidad, Fresnel medio y cobertura.
// Escala de esa rugosidad; 0 = el mar lejano liso de antes.
uniform float far_roughness : hint_range(0.0,2.0) = 0.6;
// Varianza de pendiente del rizado fino (lo que dibujan texture_normal/2 de cerca).
uniform float far_detail_variance : hint_range(0.0,0.05) = 0.004;
// Rachas: manchas de viento de far_gust_size metros que rizan más o menos el agua. Rompen la
// uniformidad del mar visto desde un monte o desde el barco.
uniform float far_gust_strength : hint_range(0.0,1.0) = 0.55;
uniform float far_gust_size : hint_range(50.0,2000.0) = 380.0;
// Fracción del mar que blanquea con temporal pleno cuando las crestas ya no caben en el píxel.
uniform float far_whitecaps : hint_range(0.0,1.0) = 0.15;

// --- Banquisa (hielo marino, ver sea_ice_fraction en gerstner_waves.gdshaderinc) ---------------
// En el borde del hielo el mar se rompe en témpanos (celdas de Voronoi que se sueldan al enfriar);
// dentro, una placa continua con grietas recongeladas, ventisqueros de nieve y hielo azul desnudo.
uniform vec3 ice_snow_color : source_color = vec3(0.90, 0.93, 0.97);
uniform vec3 ice_bare_color : source_color = vec3(0.50, 0.66, 0.78);
uniform float ice_floe_size : hint_range(4.0, 200.0) = 38.0;
uniform float ice_crack_width : hint_range(0.0, 2.0) = 0.35;
// Témpanos con volumen (SeaIceFloes) hasta esta distancia de la cámara: ahí el agua solo pone la
// placa cerrada entre ellos, y los sueltos los dibuja a partir de ice_geometry_start → end, mientras
// los de verdad encogen. 0 = sin témpanos 3D (todo dibujado aquí).
uniform float ice_geometry_start = 0.0;
uniform float ice_geometry_end = 0.0;

varying vec3 surface_world;
varying vec3 material_position;
varying vec3 radial_up;
// Vertical del planeta en espacio de vista, para el horizonte de cada luz en light() (como el
// terreno: se calcula en vertex()).
varying vec3 radial_up_view;
varying vec3 geometry_normal;
varying float wave_height;
varying float geometric_compression;
varying float minimum_wavelength;
varying vec4 sea_context;
varying float sea_inland;
varying float coast_depth;
// Ola de orilla en el vértice: fase, peso y distancia al litoral (shore_wave_signal).
varying vec3 shore_surf;
// Hielo marino del vértice (0..1).
varying float sea_ice;
// Banquisa que cubre el píxel (0..1): light() la ilumina como un sólido difuso.
varying float ice_cover;
// Espuma de las olas de casco (bigote de proa, costados, golpes): ver hull_waves.gdshaderinc.
varying float hull_foam;

vec3 ocean_wind() {
    vec3 pole=length(wave_pole)>0.0001 ? normalize(wave_pole) : vec3(0,1,0);
    vec3 gx=normalize(cross(pole,abs(pole.x)<0.9 ? vec3(1,0,0) : vec3(0,0,1)));
    vec3 gy=cross(pole,gx);
    vec2 d=dot(wave_direction,wave_direction)>0.0001 ? normalize(wave_direction) : vec2(1,0);
    return gx*d.x+gy*d.y;
}
vec3 ocean_detail(sampler2D map,vec3 p,vec3 normal,float scale,vec3 scroll) {
    vec3 weights=pow(abs(normal),vec3(4.0));
    weights/=max(weights.x+weights.y+weights.z,0.001);
    vec2 x=texture(map,(p.yz+scroll.yz)/scale).rg*2.0-1.0;
    vec2 y=texture(map,(p.xz+scroll.xz)/scale).rg*2.0-1.0;
    vec2 z=texture(map,(p.xy+scroll.xy)/scale).rg*2.0-1.0;
    vec3 slope=vec3(0,x.y,x.x)*weights.x+vec3(y.x,0,y.y)*weights.y+vec3(z.x,z.y,0)*weights.z;
    return slope-normal*dot(slope,normal);
}
float ice_hash(vec3 p) {
    p=fract(p*0.1031);
    p+=dot(p,p.zyx+31.32);
    return fract((p.x+p.y)*p.z);
}
// Giro fijo para que la rejilla del ruido de valor no se alinee con los ejes: sin él la banquisa
// enseñaba cuadros regulares vista desde lejos.
const mat3 ICE_ROTATION=mat3(vec3(0.8,0.6,0.0),vec3(-0.48,0.64,0.6),vec3(0.36,-0.48,0.8));
float ice_value_noise(vec3 p) {
    p=ICE_ROTATION*p;
    vec3 i=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(mix(ice_hash(i),ice_hash(i+vec3(1,0,0)),f.x),mix(ice_hash(i+vec3(0,1,0)),ice_hash(i+vec3(1,1,0)),f.x),f.y),
        mix(mix(ice_hash(i+vec3(0,0,1)),ice_hash(i+vec3(1,0,1)),f.x),mix(ice_hash(i+vec3(0,1,1)),ice_hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
// Voronoi 3D: x = distancia al borde de la celda (m), y = azar de la celda.
vec2 ice_cells(vec3 p, float size) {
    vec3 q=p/size;
    vec3 base=floor(q);
    float best=1e9, second=1e9, id=0.0;
    for(int x=-1;x<=1;x++) for(int y=-1;y<=1;y++) for(int z=-1;z<=1;z++) {
        vec3 c=base+vec3(float(x),float(y),float(z));
        vec3 o=c+vec3(ice_hash(c),ice_hash(c+vec3(17.1)),ice_hash(c+vec3(31.7)))*0.9;
        float d=length(q-o);
        if(d<best) { second=best; best=d; id=ice_hash(c+vec3(5.3)); }
        else if(d<second) { second=d; }
    }
    return vec2((second-best)*0.5*size,id);
}

void vertex() {
    vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    material_position=world-planet_center;
    radial_up=normalize(material_position);
    radial_up_view=(VIEW_MATRIX*vec4(radial_up,0.0)).xyz;
    float camera_distance=distance(CAMERA_POSITION_WORLD,world);
    float relative_distance=max(camera_distance/max(wave_lod_start,1.0),1.0);
    float spacing=max(mesh_min_spacing,camera_distance*mesh_spacing_rate);
    minimum_wavelength=max(pow(relative_distance,wave_lod_falloff),spacing*mesh_wave_samples);
    WaveContext ctx=wave_context(material_position);
    float presence_lod=smoothstep(minimum_wavelength*0.5,minimum_wavelength*1.5,shore_length);
    float presence=ctx.shore_gate*smoothstep(1.0,max(shore_length*0.25,shore_depth_fade),ctx.shore_dist)*presence_lod;
    sea_context=vec4(max(mix(wave_calm_amplitude,wave_amplitude,ctx.exposure),0.0),
        mix(wave_calm_steepness,wave_steepness,ctx.exposure),
        1.0-smoothstep(0.0,shore_handover,presence),presence);
    coast_depth=ctx.shore_depth;
    sea_inland=ctx.inland;
    sea_ice=ctx.ice;
    // Sin el LOD de la malla: la fase se interpola bien entre vértices lejanos, y la espuma de la
    // rompiente se tiene que ver desde un monte aunque la ola ya no levante la malla.
    shore_surf=shore_wave_signal(material_position,radial_up,water_time,0.0,ctx);
    vec3 sampled_normal;
    float sampled_compression;
    vec3 displacement=gerstner_surface_ctx(material_position,radial_up,water_time,
        minimum_wavelength,ctx,sampled_normal,sampled_compression);
    // Olas de los barcos, en el plano de la superficie ya desplazada en horizontal: van pegadas al
    // casco, que flota sobre esa superficie.
    vec3 hull_gradient;
    float hull_white;
    vec3 hull_p=world+displacement-radial_up*dot(displacement,radial_up);
    float hull_h=hull_wave_sample(hull_p,radial_up,minimum_wavelength,hull_gradient,hull_white);
    hull_foam=hull_white;
    displacement+=radial_up*hull_h;
    sampled_normal=normalize(sampled_normal-hull_gradient);
    geometry_normal=sampled_normal;
    geometric_compression=sampled_compression;
    wave_height=dot(displacement,radial_up);
    VERTEX+=inverse(mat3(MODEL_MATRIX))*displacement;
    surface_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    if(inside_ship_interior(surface_world)) discard;
    vec3 near_view=ocean_view_position(SCREEN_UV,1.0,INV_PROJECTION_MATRIX);
    vec3 near_offset=mat3(INV_VIEW_MATRIX)*near_view;
    if(waterline_signed_relative(CAMERA_POSITION_WORLD,near_offset,waterline_point,waterline_normal)<0.0) discard;

    vec3 radial=normalize(radial_up);
    vec3 macro_normal=normalize(geometry_normal);
    vec3 eye_ray=normalize(surface_world-CAMERA_POSITION_WORLD);
    vec3 surface_view=(VIEW_MATRIX*vec4(surface_world,1.0)).xyz;
    float view_distance=length(surface_view);
    vec3 wind=ocean_wind();
    // Derivadas de pantalla de la posición en reposo: la huella del píxel sobre el agua.
    vec3 dpx=dFdx(material_position), dpy=dFdy(material_position);
    float footprint=max(length(dpx),length(dpy));
    OceanBreakers history=ocean_breaker_history(material_position+wave_shift,radial,wind,water_time+wave_time_offset,
        sea_context.x,sea_context.y,minimum_wavelength,sea_context.z,coast_depth,sea_inland,dpx,dpy);
    // Coastal family supplies its own geometric contraction through the same surface.
    history.recent.x=max(history.recent.x,geometric_compression*sea_context.w*2.0);
    history.activity=max(history.activity,smoothstep(0.01,0.1,geometric_compression*sea_context.w));
    vec4 foam_pattern=ocean_foam_pattern(material_position,radial,wind,water_time);
    vec2 churn_mass;
    // Las rachas agrupan las rompientes: con todas las crestas rompiendo por igual, de lejos los
    // borreguillos caen en la rejilla que dibuja el cruce de las olas dominantes.
    vec3 gust_p=material_position/far_gust_size-wind*water_time*(6.0/far_gust_size);
    float gust=ocean_noise(gust_p)*0.65+ocean_noise(gust_p*2.9+vec3(7.0))*0.35;
    vec2 caps=ocean_whitecaps(history,foam_pattern,foam_crest_amount*mix(0.3,1.35,smoothstep(0.25,0.75,gust)),churn_mass);
    float foam=1.0-(1.0-caps.x)*(1.0-caps.y);
    // Rodilla suave: una película de espuma al 10-20 % no se lee como espuma sino como una costra
    // sobre el agua. Por debajo de un tercio de cobertura se desvanece; por encima no cambia.
    foam*=smoothstep(0.0,0.33,foam);

    // Mar de viento por píxel. Tierra adentro y bajo el hielo riza menos.
    float chop_hidden;
    vec3 chop=ocean_chop(material_position,radial,dpx,dpy,
        chop_strength*(1.0-sea_ice)*mix(1.0,0.6,sea_inland),chop_hidden);

    // Lo que el píxel ya no resuelve se queda como estadística: las olas del espectro y del mar de
    // viento que no le caben, y el rizado de textura fundido o más pequeño que su huella.
    float detail=1.0-smoothstep(detail_fade_start,detail_fade_end,view_distance);
    float detail_seen=detail*(1.0-smoothstep(0.3,2.0,footprint));
    float lost_slopes=(history.hidden+chop_hidden+far_detail_variance*(1.0-detail_seen))*far_roughness
        *mix(1.0,0.35+1.3*gust,far_gust_strength);
    float sigma=min(sqrt(lost_slopes),0.36);
    // Borreguillos que ya no caben en el píxel: solo su media, sin dibujo (un dibujo de manchas a
    // esa distancia se lee como rocas).
    float far_foam=far_whitecaps*smoothstep(0.18,0.7,sqrt(history.slopes))
        *min(log(1.0+max(foam_crest_amount,0.0))/2.24,1.3)*mix(0.5,1.5,gust)
        *smoothstep(0.25,0.85,history.hidden/max(history.slopes,0.00001));
    foam=1.0-(1.0-foam)*(1.0-far_foam);

    float raw_depth=texture(DEPTH_TEXTURE,SCREEN_UV).r;
    vec3 scene_view=ocean_view_position(SCREEN_UV,raw_depth,INV_PROJECTION_MATRIX);
    float separation=max(surface_view.z-scene_view.z,0.0);
    // Rompiente: el rodillo que sale del frente de la ola de orilla y su cola de encaje.
    // La ola de orilla también tiene que caber en el píxel (por su lado estrecho: desde lo alto
    // las crestas se ven de través).
    vec3 shore_signal=shore_surf;
    shore_signal.y*=1.0-smoothstep(0.3,0.6,min(length(dpx),length(dpy))/max(shore_length,1.0));
    vec2 surf=ocean_surf(shore_signal,foam_pattern);
    float surf_scale=surf_foam_amount*clamp(shore_amplitude,0.4,1.6);
    float surf_foam=ocean_foam_coverage(surf.x*surf_scale*5.0,foam_pattern,smoothstep(0.08,0.5,surf.y));
    surf_foam=max(surf_foam,ocean_surf_lip(shore_signal,foam_pattern,surf.y)*min(surf_scale,1.0));
    foam=1.0-(1.0-foam)*(1.0-surf_foam);
    // Línea de playa: la franja de espuma avanza con cada ola y al retirarse deja su encaje.
    float swash=swash_strength*clamp(shore_signal.y*2.5,0.0,1.0);
    float shore_width=shore_soft_width*mix(1.0,mix(0.45,2.8,ocean_swash_reach(surf.y)),swash);
    float wet=float(raw_depth>0.0);
    float contact=(1.0-smoothstep(0.0,shore_width,separation))*wet;
    float lace=(1.0-smoothstep(0.0,shore_soft_width*2.8,separation))*wet*swash*(1.0-surf.y)*0.6;
    contact=max(ocean_foam_coverage(contact*shore_foam_amount*3.0,foam_pattern,0.45),
        ocean_foam_coverage(lace*shore_foam_amount*3.0,foam_pattern,1.0));
    float wake_mass=ocean_wake(surface_world,radial);
    float wake=ocean_foam_coverage(wake_mass*2.5,foam_pattern,0.7);
    float hull_white=ocean_foam_coverage(hull_foam*2.2,foam_pattern,0.85);
    foam=1.0-(1.0-foam)*(1.0-contact)*(1.0-wake)*(1.0-hull_white);
    // Solo donde de verdad rompe: la masa de rompiente es pequeña pero no nula en casi toda la
    // superficie de un temporal, y sin umbral el mar entero se vuelve turquesa.
    float churn=clamp(smoothstep(0.2,1.3,churn_mass.x)*0.6+smoothstep(0.7,3.0,churn_mass.y)*0.7,0.0,1.0);
    churn=max(churn,1.0-exp(-(surf.x*surf_scale*3.0+wake_mass*1.2+hull_foam*1.5)))*churn_strength;

    vec3 slope=vec3(0.0);
    if(texture_ripple>0.001) {
        slope=ocean_detail(texture_normal,material_position,macro_normal,normal_scale1,wind*water_time*0.35);
        slope+=ocean_detail(texture_normal2,material_position,macro_normal,normal_scale2,-wind*water_time*0.19)*0.55;
        slope*=normal_intensity*texture_ripple*detail*(1.0-foam*0.8);
        slope/=sqrt(1.0+dot(slope,slope)/max(normal_slope_limit*normal_slope_limit,0.0001));
    }
    // Olas por píxel: las del espectro que la malla no lleva y el mar de viento. Cabalgan sobre la
    // superficie, así que donde ésta se contrae (la cresta) se aprietan y se empinan, y en el seno se
    // tienden. La normal es la vertical menos el gradiente de altura.
    vec3 wave_slope=(history.detail+chop)*(1.0-foam*0.8)/max(1.0-history.pinch,0.4);
    wave_slope/=sqrt(1.0+dot(wave_slope,wave_slope)/0.81);
    vec3 n=normalize(macro_normal-wave_slope+slope);
    vec3 ndx=dFdx(n), ndy=dFdy(n);
    float filtered_roughness=clamp(sqrt(roughness*roughness+min((dot(ndx,ndx)+dot(ndy,ndy))*specular_antialiasing,0.15)),0.04,1.0);
    // La pendiente perdida ensancha el lóbulo: alfa de Beckmann² = 2·sigma², y aquí alfa = rugosidad².
    filtered_roughness=clamp(pow(pow(filtered_roughness,4.0)+2.0*sigma*sigma,0.25),0.04,1.0);
    vec3 view_normal=normalize(mat3(VIEW_MATRIX)*n);
    // Fresnel medio sobre una superficie rizada (ajuste de Bruneton 2010): con sigma 0 es Schlick.
    // A ras de agua un mar liso refleja el 100 %; uno rizado se queda en un 20-40 %.
    float fresnel=0.02037+0.97963*pow(1.0-max(dot(n,-eye_ray),0.0),5.0*exp(-2.69*sigma))
        /(1.0+22.7*pow(sigma,1.5));

    // Snell refraction, projected to the opaque background depth. Validate the
    // proposed sample before using it so foreground rocks cannot smear into water.
    vec3 refracted_direction=mat3(VIEW_MATRIX)*refract(eye_ray,n,1.0/1.333);
    float travel=min(separation/max(-refracted_direction.z,0.1),30.0);
    vec2 refracted_uv=ocean_project(surface_view+refracted_direction*travel,PROJECTION_MATRIX);
    float border=smoothstep(0.0,0.04,min(min(SCREEN_UV.x,SCREEN_UV.y),min(1.0-SCREEN_UV.x,1.0-SCREEN_UV.y)));
    refracted_uv=mix(SCREEN_UV,refracted_uv,refraction_strength*border*(1.0-foam));
    // A screen buffer cannot recover surfaces hidden behind an object. Bound the
    // distortion footprint instead of stretching those missing pixels into large patches.
    vec2 refracted_offset=refracted_uv-SCREEN_UV;
    refracted_offset*=min(1.0,refraction_max_offset/max(length(refracted_offset),0.00001));
    refracted_uv=SCREEN_UV+refracted_offset;
    refracted_uv=clamp(refracted_uv,vec2(0.001),vec2(0.999));
    vec2 sample_uv=SCREEN_UV;
    if(raw_depth>0.0 && refraction_strength>0.0) {
        // Validate the UV actually used, not just the end of an offset. Blending
        // valid/invalid endpoints can land on a foreground silhouette in between.
        for(int attempt=0;attempt<4;attempt++) {
            float candidate_depth=textureLod(DEPTH_TEXTURE,refracted_uv,0.0).r;
            vec3 candidate_view=ocean_view_position(refracted_uv,candidate_depth,INV_PROJECTION_MATRIX);
            vec3 candidate_world=(INV_VIEW_MATRIX*vec4(candidate_view,1.0)).xyz;
            if(candidate_depth>0.0 && surface_view.z-candidate_view.z>0.05
                    && dot(candidate_world-surface_world,radial)<-0.02) {
                sample_uv=refracted_uv;
                break;
            }
            refracted_uv=mix(SCREEN_UV,refracted_uv,0.5);
        }
    }
    float sample_depth=texture(DEPTH_TEXTURE,sample_uv).r;
    vec3 background_view=ocean_view_position(sample_uv,sample_depth,INV_PROJECTION_MATRIX);
    // The refracted endpoint lies on another screen ray. Its camera-Z difference
    // can be almost zero despite meters of water: use the actual segment length.
    float optical_depth=sample_depth>0.0 ? length(background_view-surface_view) : 160.0;
    vec3 background_world=(INV_VIEW_MATRIX*vec4(background_view,1.0)).xyz;
    float bottom_depth=sample_depth>0.0 ? max(water_radius-length(background_world-planet_center),0.0) : 160.0;
    vec3 transmission=exp(-max(absorption_coefficients,vec3(0.0))*optical_depth);
    vec3 background=textureLod(SCREEN_TEXTURE,sample_uv,refraction_blur*(1.0-exp(-optical_depth*0.08))).rgb;
    vec3 to_sun=normalize(length(sun_direction)>0.001 ? -sun_direction : vec3(-0.4,0.7,-0.3));
    // Terminador estrecho: la radiancia ya se apaga con el sol en el horizonte del observador;
    // esto solo separa el agua lejana que queda al otro lado de la línea día/noche.
    float daylight=smoothstep(-0.05,0.05,dot(radial,to_sun));
    float moonlight=smoothstep(-0.05,0.05,dot(radial,sky_moon_direction));
    float sun_level=dot(sky_sun_radiance,vec3(0.2126,0.7152,0.0722))*daylight;
    vec3 illumination=sky_ambient_radiance+(sky_sun_radiance*daylight+sky_moon_radiance*moonlight)*0.8;
    vec3 scatter=mix(color_shallow.rgb,color_deep.rgb,1.0-exp(-optical_depth*0.13))*illumination;
    // Luz devuelta desde dentro del agua, según cómo mira cada faceta: a contraluz la que cruza la
    // cresta (más en lo alto de la ola y en las caras de espaldas al sol), la que vuelve por las
    // caras que miran a la cámara y un difuso tenue de las que miran al sol.
    vec3 direct_light=sky_sun_radiance*daylight+sky_moon_radiance*moonlight;
    float crest=smoothstep(0.0,1.1,wave_height/max(sea_context.x,0.1));
    float facing=max(dot(n,-eye_ray),0.0);
    float through=pow(max(dot(eye_ray,to_sun),0.0),4.0)*pow(clamp(0.5-0.5*dot(to_sun,n),0.0,1.0),1.5);
    scatter+=sss_color*(direct_light*(sss_intensity*3.0*crest*through+sss_lambert*max(dot(n,to_sun),0.0))
        +illumination*(sss_view*facing*facing*(0.6+0.8*crest)));
    // Agua batida, encima del color del agua y antes de mezclar con el fondo que se transparenta.
    scatter=mix(scatter,churn_color*illumination,churn);
    transmission*=1.0-churn;
    vec3 body=background*transmission+scatter*(vec3(1.0)-transmission);
    // Caustics are transmitted background light, strongest in a shallow sunlit column.
    vec3 cp=(background_world-planet_center)*caustics_scale;
    vec3 tw=pow(abs(radial),vec3(4.0)); tw/=max(tw.x+tw.y+tw.z,0.001);
    vec2 scroll=vec2(water_time*caustics_speed,-water_time*caustics_speed*0.7);
    float caustics=texture(caustics_texture,cp.yz+scroll).r*tw.x
        +texture(caustics_texture,cp.xz+scroll).r*tw.y+texture(caustics_texture,cp.xy+scroll).r*tw.z;
    caustics*=caustics*caustics_intensity*sun_level*exp(-bottom_depth*0.22)*float(sample_depth>0.0);
    body+=background*transmission*caustics;

    // Las facetas que se ven a ras de agua son las que miran hacia arriba y hacia el observador:
    // el reflejo medio sale de más alto en el cielo que el del espejo.
    vec3 mirror=reflect(eye_ray,n);
    mirror=normalize(mirror+radial*sigma*(1.0-max(dot(mirror,radial),0.0)));
    vec3 reflection=calculate_sky_color(mirror,radial)*sky_influence;
    // El rayo reflejado que baja del horizonte no da en el cielo sino en otra ola: se ve agua. Sin
    // esto las caras que miran hacia abajo reflejan el blanco del horizonte, y cada cresta lleva una
    // raya de tiza por detrás. Solo donde hay oleaje resuelto: el mar lejano y liso sigue de espejo.
    float occluded=(1.0-smoothstep(-0.45,0.12,dot(mirror,radial)))
        *smoothstep(0.05,0.2,sqrt(max(history.slopes-history.hidden,0.0)))*reflection_occlusion;
    reflection=mix(reflection,scatter,occluded);
    float ssr_fade=1.0-smoothstep(ssr_distance_fade*0.5,ssr_distance_fade,view_distance);
    if(ssr_enabled && ssr_fade>0.001 && foam<0.95) {
        vec4 reflected=ocean_reflection(surface_view,view_normal,PROJECTION_MATRIX,INV_PROJECTION_MATRIX,
            INV_VIEW_MATRIX,planet_center,water_radius,filtered_roughness);
        reflection=mix(reflection,reflected.rgb,reflected.a*ssr_fade);
    }
    NORMAL=view_normal;
    ALBEDO=foam_color*foam*mix(0.72,1.0,foam_pattern.y);
    vec3 foam_sky=(sky_zenith_radiance+sky_horizon_side_radiance)*(0.5*foam_skylight*sky_influence);
    EMISSION=mix(body,reflection,fresnel)*(1.0-foam)+foam_color*foam_sky*(foam*mix(0.72,1.0,foam_pattern.y));
    ROUGHNESS=mix(filtered_roughness,0.88,foam);
    SPECULAR=0.0;
    METALLIC=0.0;
    ALPHA=deep_alpha*mix(smoothstep(0.0,0.12,separation),1.0,float(raw_depth<=0.0));

    // Banquisa. Cada témpano es una celda que se hiela cuando el hielo del sitio supera su umbral:
    // al enfriar se juntan y la placa se cierra, con las grietas entre celdas ya soldadas.
    ice_cover=0.0;
    if(sea_ice>0.002) {
        vec2 cell=ice_cells(material_position,ice_floe_size);
        float threshold=0.08+cell.y*0.84;
        float floe=smoothstep(threshold-0.04,threshold+0.04,sea_ice);
        // Canal abierto entre témpanos mientras el hielo no está cerrado; grieta fina después.
        float lead=mix(ice_crack_width*6.0+2.5,ice_crack_width,smoothstep(0.85,1.0,sea_ice));
        float pixel=max(fwidth(cell.x),0.02);
        float edge=smoothstep(lead-pixel,lead+pixel,cell.x);
        // Con el hielo cerrado las grietas quedan soldadas del todo: ni una fracción del agua (su
        // normal y su reflejo aliasean en un rayado fino a esta distancia).
        float closed=smoothstep(0.9,0.98,sea_ice);
        float cover=floe*mix(edge,1.0,closed);
        if(ice_geometry_end>0.0) {
            // Cerca, los témpanos sueltos son geometría: aquí solo el hielo nuevo que suelda las
            // grietas de la banquisa cerrada.
            float geometry=1.0-smoothstep(ice_geometry_start,ice_geometry_end,view_distance);
            cover=mix(cover,floe*closed,geometry);
        }
        // Metros por píxel: cada octava de ruido se apaga antes de caber en un píxel, o de lejos la
        // banquisa se llena de moiré en cuadrícula.
        float footprint=length(fwidth(material_position));
        float fine_fade=1.0-smoothstep(0.2,0.5,footprint*1.3);
        float mid_fade=1.0-smoothstep(0.2,0.5,footprint*0.3);
        // Nieve venteada a manchas; el hielo desnudo es azul y liso.
        float drift=ice_value_noise(material_position*0.045)*0.6
            +mix(0.5,ice_value_noise(material_position*0.19+vec3(5.0)),1.0-smoothstep(0.2,0.5,footprint*0.19))*0.4;
        float snowy=smoothstep(0.42,0.58,drift+cell.y*0.2);
        // Crestas de presión en los bordes de las placas grandes: hielo roto y amontonado.
        vec2 plate=ice_cells(material_position+vec3(97.0),ice_floe_size*5.0);
        float ridge=(1.0-smoothstep(0.0,3.5,plate.x))*smoothstep(0.9,1.0,sea_ice);
        vec3 ice_albedo=mix(ice_bare_color,ice_snow_color,max(snowy,ridge*0.8));
        ice_albedo*=mix(1.0,mix(0.9,1.04,ice_value_noise(material_position*1.3)),fine_fade);
        // Grietas recongeladas: hielo nuevo, más oscuro y liso, en el borde de las celdas.
        float refrozen=(1.0-smoothstep(ice_crack_width,ice_crack_width*4.0+0.3,cell.x))*smoothstep(0.9,0.98,sea_ice);
        ice_albedo=mix(ice_albedo,ice_bare_color*0.7,refrozen*(1.0-ridge));
        // Relieve: el gradiente de un solo ruido (diferencias finitas), más marcado en las crestas.
        float h0=ice_value_noise(material_position*0.3);
        vec3 slope=vec3(ice_value_noise(material_position*0.3+vec3(0.08,0,0)),
            ice_value_noise(material_position*0.3+vec3(0,0.08,0)),ice_value_noise(material_position*0.3+vec3(0,0,0.08)))-h0;
        slope=(slope-radial*dot(slope,radial))*(2.2*snowy+6.0*ridge)*mid_fade;
        vec3 ice_normal=normalize(radial-slope);
        ALBEDO=mix(ALBEDO,ice_albedo,cover);
        EMISSION*=1.0-cover;
        NORMAL=normalize(mix(NORMAL,normalize(mat3(VIEW_MATRIX)*ice_normal),cover));
        ROUGHNESS=mix(ROUGHNESS,mix(0.3,0.8,max(snowy,ridge)),cover);
        ALPHA=mix(ALPHA,1.0,cover);
        ice_cover=cover;
    }

    if(water_debug_mode>0) {
        ALBEDO=vec3(0.0); ROUGHNESS=1.0;
        if(water_debug_mode==1) EMISSION=macro_normal*0.5+0.5;
        if(water_debug_mode==2) EMISSION=vec3(foam);
        if(water_debug_mode==3) EMISSION=vec3(history.recent.x);
        if(water_debug_mode==5) EMISSION=vec3(history.crest);
        if(water_debug_mode==4) EMISSION=vec3(clamp(0.5+wave_height/max(sea_context.x*4.0,0.1),0.0,1.0));
        if(water_debug_mode==6) EMISSION=vec3(sigma*2.5);
        if(water_debug_mode==7) EMISSION=vec3(far_foam);
        if(water_debug_mode==8) EMISSION=vec3(surf.y,shore_surf.y,surf_foam);
        ALPHA=1.0;
    }
    if(shore_debug_mode>0) {
        ALBEDO=vec3(0.0); EMISSION=shore_debug_color(material_position,water_time); ALPHA=1.0;
    }
}
void light() {
    if(water_debug_mode==0 && shore_debug_mode==0) {
    float nl=max(dot(NORMAL,LIGHT),0.0);
    float nv=max(dot(NORMAL,VIEW),0.001);
    // El sol y la luna solo alumbran el agua que los tiene sobre su horizonte: sin esto la espuma
    // del lado nocturno se llevaba el 20% envolvente del sol (se veía desde órbita). El margen va
    // por debajo del horizonte: la puesta ya la apaga la energía del sol, esto solo corta el agua
    // lejana del otro lado del terminador.
    float horizon=1.0;
    if(LIGHT_IS_DIRECTIONAL) {
        horizon=smoothstep(-0.15,-0.02,dot(normalize(radial_up_view),LIGHT));
    }
    // La espuma lleva el albedo aquí además del que aplica el motor, y un 35 % envolvente (la espuma dispersa la luz por dentro: su cara en sombra no es gris roca); la
    // banquisa es un sólido: Lambert normal, con su albedo una sola vez.
    float wrap=mix(0.35,0.0,ice_cover);
    DIFFUSE_LIGHT+=mix(ALBEDO,vec3(1.0),ice_cover)*LIGHT_COLOR*ATTENUATION
        *((nl*(1.0-wrap)+wrap)*light_diffuse_strength/PI)*horizon;
    vec3 h=normalize(LIGHT+VIEW);
    float nh=max(dot(NORMAL,h),0.0);
    float r=max(ROUGHNESS,LIGHT_IS_DIRECTIONAL ? directional_roughness_floor : light_roughness_floor);
    float a2=pow(r,4.0);
    float denominator=nh*nh*(a2-1.0)+1.0;
    float d=a2/max(PI*denominator*denominator,0.00000001);
    float gv=2.0*nv/(nv+sqrt(a2+(1.0-a2)*nv*nv));
    float gl=2.0*nl/max(nl+sqrt(a2+(1.0-a2)*nl*nl),0.001);
    float f=0.02037+0.97963*pow(1.0-max(dot(VIEW,h),0.0),5.0);
    float spec=min(d*gv*gl*f/(4.0*nv),LIGHT_IS_DIRECTIONAL ? directional_specular_clamp : light_specular_clamp);
    SPECULAR_LIGHT+=spec*LIGHT_COLOR*ATTENUATION*SPECULAR_AMOUNT*horizon;
    }
}
