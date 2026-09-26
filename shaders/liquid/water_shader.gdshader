shader_type spatial;
render_mode blend_mix, depth_draw_always, shadows_disabled;

// Surface simulation is shared with buoyancy and the underwater ray marcher.
#include "res://shaders/liquid/gerstner_waves.gdshaderinc"
#include "res://shaders/liquid/underwater_fog.gdshaderinc"
#include "res://shaders/liquid/ship_interiors.gdshaderinc"
#include "res://shaders/lib/sky_reflection.gdshaderinc"
#include "res://shaders/liquid/ocean_optics.gdshaderinc"
#include "res://shaders/liquid/ocean_foam.gdshaderinc"

uniform float water_time=0.0;
uniform vec3 planet_center=vec3(0.0);
uniform vec3 waterline_point=vec3(0.0);
uniform vec3 waterline_normal=vec3(0.0,1.0,0.0);
uniform float wave_lod_start : hint_range(50.0,20000.0) = 800.0;
uniform float wave_lod_falloff : hint_range(1.0,4.0) = 1.6;
uniform sampler2D texture_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D texture_normal2 : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float normal_scale1 : hint_range(0.1,100.0) = 8.0;
uniform float normal_scale2 : hint_range(0.1,100.0) = 23.0;
uniform float normal_intensity : hint_range(0.0,4.0) = 0.65;
uniform float normal_slope_limit : hint_range(0.01,1.0) = 0.16;
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
uniform float light_diffuse_strength=1.0;
uniform float light_specular_clamp=0.65;
uniform float directional_specular_clamp=0.65;
uniform float light_roughness_floor=0.22;
uniform float directional_roughness_floor=0.08;
uniform sampler2D caustics_texture : repeat_enable, filter_linear_mipmap;
uniform float caustics_scale=0.5;
uniform float caustics_speed=0.1;
uniform float caustics_intensity=0.25;
uniform int water_debug_mode : hint_range(0,5) = 0;

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
varying float coast_depth;

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
void vertex() {
    vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    material_position=world-planet_center;
    radial_up=normalize(material_position);
    radial_up_view=(VIEW_MATRIX*vec4(radial_up,0.0)).xyz;
    float relative_distance=max(distance(CAMERA_POSITION_WORLD,world)/max(wave_lod_start,1.0),1.0);
    minimum_wavelength=pow(relative_distance,wave_lod_falloff);
    WaveContext ctx=wave_context(material_position);
    float presence_lod=smoothstep(minimum_wavelength*0.5,minimum_wavelength*1.5,shore_length);
    float presence=ctx.shore_gate*smoothstep(1.0,max(shore_length*0.25,shore_depth_fade),ctx.shore_dist)*presence_lod;
    sea_context=vec4(max(mix(wave_calm_amplitude,wave_amplitude,ctx.exposure),0.0),
        mix(wave_calm_steepness,wave_steepness,ctx.exposure),
        1.0-smoothstep(0.0,shore_handover,presence),presence);
    coast_depth=ctx.shore_depth;
    vec3 sampled_normal;
    float sampled_compression;
    vec3 displacement=gerstner_surface_ctx(material_position,radial_up,water_time,
        minimum_wavelength,ctx,sampled_normal,sampled_compression);
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
    OceanBreakers history=ocean_breaker_history(material_position,radial,wind,water_time,
        sea_context.x,sea_context.y,minimum_wavelength,sea_context.z,coast_depth);
    // Coastal family supplies its own geometric contraction through the same surface.
    history.recent.x=max(history.recent.x,geometric_compression*sea_context.w*2.0);
    history.activity=max(history.activity,smoothstep(0.01,0.1,geometric_compression*sea_context.w));
    vec4 foam_pattern=ocean_foam_pattern(material_position,radial,wind,water_time);
    vec2 caps=ocean_whitecaps(history,foam_pattern,foam_crest_amount);
    float foam=1.0-(1.0-caps.x)*(1.0-caps.y);

    float raw_depth=texture(DEPTH_TEXTURE,SCREEN_UV).r;
    vec3 scene_view=ocean_view_position(SCREEN_UV,raw_depth,INV_PROJECTION_MATRIX);
    float separation=max(surface_view.z-scene_view.z,0.0);
    float contact=(1.0-smoothstep(0.0,shore_soft_width,separation))*float(raw_depth>0.0);
    contact=ocean_foam_coverage(contact*shore_foam_amount*3.0,foam_pattern,0.45);
    float wake=ocean_foam_coverage(ocean_wake(surface_world,radial)*2.5,foam_pattern,0.7);
    foam=1.0-(1.0-foam)*(1.0-contact)*(1.0-wake);

    float detail=1.0-smoothstep(detail_fade_start,detail_fade_end,view_distance);
    vec3 slope=ocean_detail(texture_normal,material_position,macro_normal,normal_scale1,wind*water_time*0.35);
    slope+=ocean_detail(texture_normal2,material_position,macro_normal,normal_scale2,-wind*water_time*0.19)*0.55;
    slope*=normal_intensity*detail*(1.0-foam*0.8);
    slope/=sqrt(1.0+dot(slope,slope)/max(normal_slope_limit*normal_slope_limit,0.0001));
    vec3 n=normalize(macro_normal+slope);
    vec3 ndx=dFdx(n), ndy=dFdy(n);
    float filtered_roughness=clamp(sqrt(roughness*roughness+min((dot(ndx,ndx)+dot(ndy,ndy))*specular_antialiasing,0.15)),0.04,1.0);
    vec3 view_normal=normalize(mat3(VIEW_MATRIX)*n);
    float fresnel=0.02037+0.97963*pow(1.0-max(dot(n,-eye_ray),0.0),5.0);

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
    vec3 body=background*transmission+scatter*(vec3(1.0)-transmission);
    // Caustics are transmitted background light, strongest in a shallow sunlit column.
    vec3 cp=(background_world-planet_center)*caustics_scale;
    vec3 tw=pow(abs(radial),vec3(4.0)); tw/=max(tw.x+tw.y+tw.z,0.001);
    vec2 scroll=vec2(water_time*caustics_speed,-water_time*caustics_speed*0.7);
    float caustics=texture(caustics_texture,cp.yz+scroll).r*tw.x
        +texture(caustics_texture,cp.xz+scroll).r*tw.y+texture(caustics_texture,cp.xy+scroll).r*tw.z;
    caustics*=caustics*caustics_intensity*sun_level*exp(-bottom_depth*0.22)*float(sample_depth>0.0);
    body+=background*transmission*caustics;
    float backlight=pow(max(dot(eye_ray,to_sun),0.0),4.0);
    float crest=smoothstep(0.0,1.1,wave_height/max(sea_context.x,0.1));
    body+=sss_color*sss_intensity*backlight*crest*sun_level;

    vec3 reflection=calculate_sky_color(reflect(eye_ray,n),radial)*sky_influence;
    float ssr_fade=1.0-smoothstep(ssr_distance_fade*0.5,ssr_distance_fade,view_distance);
    if(ssr_enabled && ssr_fade>0.001 && foam<0.95) {
        vec4 reflected=ocean_reflection(surface_view,view_normal,PROJECTION_MATRIX,INV_PROJECTION_MATRIX,
            INV_VIEW_MATRIX,planet_center,water_radius,filtered_roughness);
        reflection=mix(reflection,reflected.rgb,reflected.a*ssr_fade);
    }
    NORMAL=view_normal;
    ALBEDO=foam_color*foam*mix(0.72,1.0,foam_pattern.y);
    EMISSION=mix(body,reflection,fresnel)*(1.0-foam);
    ROUGHNESS=mix(filtered_roughness,0.88,foam);
    SPECULAR=0.0;
    METALLIC=0.0;
    ALPHA=deep_alpha*mix(smoothstep(0.0,0.12,separation),1.0,float(raw_depth<=0.0));

    if(water_debug_mode>0) {
        ALBEDO=vec3(0.0); ROUGHNESS=1.0;
        if(water_debug_mode==1) EMISSION=macro_normal*0.5+0.5;
        if(water_debug_mode==2) EMISSION=vec3(foam);
        if(water_debug_mode==3) EMISSION=vec3(history.recent.x);
        if(water_debug_mode==5) EMISSION=vec3(history.crest);
        if(water_debug_mode==4) EMISSION=vec3(clamp(0.5+wave_height/max(sea_context.x*4.0,0.1),0.0,1.0));
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
    DIFFUSE_LIGHT+=ALBEDO*LIGHT_COLOR*ATTENUATION*((nl*0.8+0.2)*light_diffuse_strength/PI)*horizon;
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
