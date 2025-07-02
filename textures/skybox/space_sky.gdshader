shader_type sky;


uniform float sun_azimuth_deg   = 0.0;   // –180 ° … 180 °
uniform float sun_elevation_deg = 25.0;  // –10 ° …  90 °

// Parámetros configurables
uniform float star_radius : hint_range(0.1, 2.0) = 1.0;
uniform vec3 star_core_color  = vec3(1.0, 1.0, 0.0);
uniform vec3 star_surface_color  = vec3(1.0, 0.0, 0.0);
uniform vec3 star_corona_color = vec3(1.0, 0.6, 0.1);
uniform vec3 star_ray_color = vec3(1.0, 0.95, 1.0);
uniform vec3 space_color1 = vec3(1.0, 0.0, 0.0);
uniform vec3 space_color2 = vec3(0.0, 0.0, 1.0);
uniform vec3 space_color3  = vec3(0.9, 1.0, 0.1);

// Nueva variable para la posición de la estrella
uniform vec3 star_position = vec3(0.0, 0.0, 3.0);
uniform float orbit_radius : hint_range(0.1, 10.0) = 3.0; // Radio de la órbita
uniform float orbit_speed : hint_range(-5.0, 5.0) = 1.0; // Velocidad de rotación
uniform vec3 orbit_axis = vec3(0.0, 1.0, 0.0); // Eje de rotación (normalizado)
uniform float orbit_inclination : hint_range(0.0, 3.1416) = 0.5; // Inclinación de la órbita

uniform float animation_speed : hint_range(0.1, 10.0) = 1.0;
uniform float rotation_speed : hint_range(-5.0, 5.0) = 0.25;
uniform float rotation_angle : hint_range(-1.0, 1.0) = -0.6;

uniform float core_intensity : hint_range(0.1, 5.0) = 2.4;
uniform float surface_intensity : hint_range(0.1, 5.0) = 2.2;
uniform float corona_intensity : hint_range(0.1, 10.0) = 11.0;
uniform float ray_intensity : hint_range(0.1, 5.0) = 1.0;

uniform float detail_level : hint_range(1.0, 5.0) = 3.0;
uniform float zoom_level : hint_range(0.1, 10.0) = 0.5;
uniform float noise_seed : hint_range(0.0, 100.0) = 83.23;

// Noise functions
vec4 hash4(vec4 n) { return fract(sin(n)*1399763.5453123); }
vec3 hash3(vec3 n) { return fract(sin(n)*1399763.5453123); }
vec3 hpos(vec3 n) { return hash3(vec3(dot(n,vec3(157.0,113.0,271.0)), dot(n,vec3(271.0,157.0,113.0)), dot(n,vec3(113.0,271.0,157.0)))); }

float noise4q(vec4 x) {
	vec4 n3 = vec4(0,0.25,0.5,0.75);
	vec4 p2 = floor(x.wwww+n3);
	vec4 b = floor(x.xxxx+n3) + floor(x.yyyy+n3)*157.0 + floor(x.zzzz +n3)*113.0;
	vec4 p1 = b + fract(p2*0.00390625)*vec4(164352.0, -164352.0, 163840.0, -164352.0);
	p2 = b + fract((p2+1.0)*0.00390625)*vec4(164352.0, -164352.0, 163840.0, -164352.0);
	vec4 f1 = fract(x.xxxx+n3);
	vec4 f2 = fract(x.yyyy+n3);
	f1=f1*f1*(3.0-2.0*f1);
	f2=f2*f2*(3.0-2.0*f2);
	vec4 n1 = vec4(0,1.0,157.0,158.0);
	vec4 n2 = vec4(113.0,114.0,270.0,271.0);
	vec4 vs1 = mix(hash4(p1), hash4(n1.yyyy+p1), f1);
	vec4 vs2 = mix(hash4(n1.zzzz+p1), hash4(n1.wwww+p1), f1);
	vec4 vs3 = mix(hash4(p2), hash4(n1.yyyy+p2), f1);
	vec4 vs4 = mix(hash4(n1.zzzz+p2), hash4(n1.wwww+p2), f1);
	vs1 = mix(vs1, vs2, f2);
	vs3 = mix(vs3, vs4, f2);
	vs2 = mix(hash4(n2.xxxx+p1), hash4(n2.yyyy+p1), f1);
	vs4 = mix(hash4(n2.zzzz+p1), hash4(n2.wwww+p1), f1);
	vs2 = mix(vs2, vs4, f2);
	vs4 = mix(hash4(n2.xxxx+p2), hash4(n2.yyyy+p2), f1);
	vec4 vs5 = mix(hash4(n2.zzzz+p2), hash4(n2.wwww+p2), f1);
	vs4 = mix(vs4, vs5, f2);
	f1 = fract(x.zzzz+n3);
	f2 = fract(x.wwww+n3);
	f1=f1*f1*(3.0-2.0*f1);
	f2=f2*f2*(3.0-2.0*f2);
	vs1 = mix(vs1, vs2, f1);
	vs3 = mix(vs3, vs4, f1);
	vs1 = mix(vs1, vs3, f2);
	float r=dot(vs1,vec4(0.25));
	return r*r*(3.0-2.0*r);
}

// Star body
float noiseSpere(vec3 ray, vec3 pos, float r, mat3 mr, float zoom, vec3 subnoise, float anim) {
	float b = dot(ray,pos);
	float c = dot(pos,pos) - b*b;

	vec3 r1=vec3(0.0);
	float s=0.0;
	float d=0.03125;
	float d2=zoom/(d*d);
	float ar=5.0;

	for (int i=0;i<3;i++) {
		float rq=r*r;
		if(c <rq) {
			float l1=sqrt(rq-c);
			r1= ray*(b-l1)-pos;
			r1=r1*mr;
			s+=abs(noise4q(vec4(r1*d2+subnoise*ar,anim*ar))*d);
		}
		ar-=2.0;
		d*=4.0;
		d2*=0.0625;
		r=r-r*0.02;
	}
	return s;
}

// Glow ring
float ring(vec3 ray, vec3 pos, float r, float size) {
	float b = dot(ray,pos);
	float c = dot(pos,pos) - b*b;
	float s=max(0.0,(1.0-size*abs(r-sqrt(c))));
	return s;
}

// Star rays
float ringRayNoise(vec3 ray, vec3 pos, float r, float size, mat3 mr, float anim) {
	float b = dot(ray,pos);
	vec3 pr=ray*b-pos;
	float c=length(pr);
	pr*=mr;
	pr=normalize(pr);
	float s=max(0.0,(1.0-size*abs(r-c)));
	float nd=noise4q(vec4(pr*1.0,-anim+c))*2.0;
	nd=pow(nd,2.0);
	float n=0.4;
	float ns=1.0;
	if (c>r) {
		n=noise4q(vec4(pr*10.0,-anim+c));
		ns=noise4q(vec4(pr*50.0,-anim*2.5+c*2.0))*2.0;
	}
	n=n*n*nd*ns;
	return pow(s,4.0)+s*s*n;
}

// Space noise
vec4 noiseSpace(vec3 ray, vec3 pos, float r, mat3 mr, float zoom, vec3 subnoise, float anim) {
	float b = dot(ray,pos);
	float c = dot(pos,pos) - b*b;
	vec3 r1=vec3(0.0);
	float s=0.0;
	float d=0.0625*1.5;
	float d2=zoom/d;

	float rq=r*r;
	float l1=sqrt(abs(rq-c));
	r1= (ray*(b-l1)-pos)*mr;
	r1*=d2;
	s+=abs(noise4q(vec4(r1+subnoise,anim))*d);
	s+=abs(noise4q(vec4(r1*0.5+subnoise,anim))*d*2.0);
	s+=abs(noise4q(vec4(r1*0.25+subnoise,anim))*d*4.0);
	return vec4(s*2.0,abs(noise4q(vec4(r1*0.1+subnoise,anim))),abs(noise4q(vec4(r1*0.1+subnoise*6.0,anim))),abs(noise4q(vec4(r1*0.1+subnoise*13.0,anim))));
}

float sphereZero(vec3 ray, vec3 pos, float r) {
	float b = dot(ray,pos);
	float c = dot(pos,pos) - b*b;
	float s=1.0;
	if (c<r*r) s=0.0;
	return s;
}

void sky() {
    if (AT_CUBEMAP_PASS) {
        COLOR = vec3(0.2f, 0.6f, 1.0f);
    } else {
        vec3 ray = normalize(EYEDIR);
        float time = TIME * animation_speed;


        vec2 sun_angles = radians(vec2(sun_azimuth_deg, sun_elevation_deg));

		vec3 pos = vec3(
		    cos(sun_angles.y) * sin(sun_angles.x),   // X
		    sin(sun_angles.y),                       // Y
		    cos(sun_angles.y) * cos(sun_angles.x)    // Z
		) * orbit_radius;                            // usa tu mismo radio

        float star_visibility = step(0.0, dot(ray, pos)); // 1.0 frente, 0.0 atrás

        // --- Rotación local de la estrella ---
        float mx = time * rotation_speed;
        float my = rotation_angle;
        vec2 rotate = vec2(mx, my);
        vec2 sins = sin(rotate);
        vec2 coss = cos(rotate);
        mat3 mr = mat3(vec3(coss.x, 0.0, sins.x), vec3(0.0, 1.0, 0.0), vec3(-sins.x, 0.0, coss.x));
        mr = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, coss.y, sins.y), vec3(0.0, -sins.y, coss.y)) * mr;

        // --- Renderizado de la estrella (solo en el hemisferio frontal) ---
        float s1 = noiseSpere(ray, pos, star_radius, mr, zoom_level, vec3(0.0), time) * star_visibility;
        s1 = pow(min(1.0, s1 * core_intensity), 2.0);
        float s2 = noiseSpere(ray, pos, star_radius, mr, zoom_level * 8.0, vec3(noise_seed, noise_seed * 0.412, noise_seed * 0.81), time) * star_visibility;
        s2 = min(1.0, s2 * surface_intensity);

        vec3 col = mix(star_core_color, vec3(1.0), pow(s1, 60.0)) * s1;
        col += mix(mix(star_surface_color, star_surface_color * vec3(1.0, 0.0, 1.0), pow(s2, 2.0)), vec3(1.0), pow(s2, 10.0)) * s2;

        col -= vec3(ring(ray, pos, star_radius * 1.03, corona_intensity)) * 2.0 * star_visibility;
        col = max(vec3(0.0), col);

        float s3 = ringRayNoise(ray, pos, star_radius * 0.96, ray_intensity, mr, time) * star_visibility;
        col += mix(star_corona_color, star_ray_color, pow(s3, 3.0)) * s3;

        // --- Fondo de galaxias (sin restricción de sphereZero) ---
        // Eliminamos sphereZero y usamos una transición suave
        float star_distance = length(pos - ray * dot(ray, pos));
        float background_mask = smoothstep(star_radius * 1.5, star_radius * 3.5, star_distance);

        vec4 s4 = noiseSpace(ray, pos, 100.0, mr, zoom_level * 0.1, vec3(1.0, 2.0, 4.0), 0.0);
        s4.x = pow(s4.x, 3.0);
        col += mix(mix(space_color1, space_color2, s4.y * 1.9), space_color3, s4.w * 0.75) * s4.x * pow(s4.z * 2.5, 3.0) * 0.2 * background_mask;

        COLOR = clamp(col, 0.0, 1.0);
    }
}