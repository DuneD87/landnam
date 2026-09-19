uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform bool ssr_enabled=true;
uniform int ssr_max_steps : hint_range(8,48) = 24;
uniform float ssr_distance_fade : hint_range(10.0,1000.0) = 200.0;
uniform float ssr_thickness : hint_range(0.05,2.0) = 0.2;
uniform float refraction_strength : hint_range(0.0,1.0) = 0.18;
uniform float refraction_max_offset : hint_range(0.001,0.05) = 0.012;
uniform float refraction_blur : hint_range(0.0,3.0) = 0.6;
uniform vec3 absorption_coefficients=vec3(0.32,0.095,0.055);
uniform vec4 color_deep : source_color = vec4(0.025,0.16,0.21,1.0);
uniform vec4 color_shallow : source_color = vec4(0.13,0.48,0.39,1.0);
uniform float sky_influence : hint_range(0.0,2.0) = 0.85;
uniform float deep_alpha : hint_range(0.0,1.0) = 1.0;

vec3 ocean_view_position(vec2 uv,float depth,mat4 inverse_projection) {
    vec3 ndc=vec3(uv*2.0-1.0,depth);
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    ndc.z=depth*2.0-1.0;
    #endif
    vec4 p=inverse_projection*vec4(ndc,1.0);
    return p.xyz/p.w;
}
vec2 ocean_project(vec3 p,mat4 projection) {
    vec4 clip=projection*vec4(p,1.0);
    return clip.xy/clip.w*0.5+0.5;
}
vec4 ocean_reflection(vec3 surface,vec3 normal,mat4 projection,mat4 inverse_projection,
                       mat4 inverse_view,vec3 center,float radius,float surface_roughness) {
    vec3 direction=reflect(normalize(surface),normal);
    vec3 p=surface+normal*0.15;
    float stride=0.5;
    float previous_difference=-1.0;
    for(int i=0;i<ssr_max_steps;i++) {
        vec3 previous=p;
        p+=direction*stride;
        if(p.z>=-0.1) break;
        vec2 uv=ocean_project(p,projection);
        if(any(lessThan(uv,vec2(0.002))) || any(greaterThan(uv,vec2(0.998)))) break;
        float depth=textureLod(DEPTH_TEXTURE,uv,0.0).r;
        vec3 scene=ocean_view_position(uv,depth,inverse_projection);
        float difference=scene.z-p.z;
        if(depth>0.0 && difference>0.0 && previous_difference<=0.0) {
            vec3 lo=previous, hi=p;
            for(int j=0;j<5;j++) {
                vec3 mid=(lo+hi)*0.5;
                vec2 mid_uv=ocean_project(mid,projection);
                float mid_depth=textureLod(DEPTH_TEXTURE,mid_uv,0.0).r;
                vec3 mid_scene=ocean_view_position(mid_uv,mid_depth,inverse_projection);
                if(mid_depth>0.0 && mid_scene.z>mid.z) hi=mid; else lo=mid;
            }
            uv=ocean_project(hi,projection);
            depth=textureLod(DEPTH_TEXTURE,uv,0.0).r;
            scene=ocean_view_position(uv,depth,inverse_projection);
            vec3 world=(inverse_view*vec4(scene,1.0)).xyz;
            difference=scene.z-hi.z;
            if(depth<=0.0 || difference<0.0 || difference>ssr_thickness || length(world-center)<radius) break;
            float edge=1.0-smoothstep(0.7,1.0,max(abs(uv.x*2.0-1.0),abs(uv.y*2.0-1.0)));
            float confidence=edge*(1.0-smoothstep(0.0,ssr_thickness,difference));
            return vec4(textureLod(SCREEN_TEXTURE,uv,surface_roughness*3.0).rgb,confidence);
        }
        previous_difference=depth>0.0 ? difference : -1.0;
        stride*=1.16;
    }
    return vec4(0.0);
}
