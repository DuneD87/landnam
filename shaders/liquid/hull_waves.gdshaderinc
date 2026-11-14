// Olas que levantan los barcos al moverse y anillos de los golpes de proa (HullWaves los empuja).
// Solo dibujo: la flotación de CPU no las ve. Van en el marco del barco, quietas respecto a él:
//   - bigote de proa: el agua se amontona en la roda y abre en dos brazos en V que se separan del
//     casco y se quedan atrás, cada vez más anchos y más bajos;
//   - seno a media eslora: el casco aparta el agua y a sus costados baja;
//   - brazos de popa, más flojos, y las ondas transversales de la estela dentro de la cuña de Kelvin;
//   - anillos: un golpe de proa deja una onda que se abre desde la roda y se apaga.

const int MAX_HULLS=8;
const int MAX_HULL_RINGS=16;
// Ángulo de la cuña de Kelvin (19,47°): tangente.
const float KELVIN_TAN=0.3536;
// Ángulo de los brazos de la ola de proa respecto a la marcha: algo más abiertos que la cuña.
const float BOW_ARM_TAN=0.42;

uniform int hull_count=0;
// xyz = centro del casco (mundo), w = semieslora en el sentido de la marcha (m).
uniform vec4 hull_frame[MAX_HULLS];
// xyz = sentido de la marcha (mundo, unitario), w = semimanga (m).
uniform vec4 hull_axis[MAX_HULLS];
// x = velocidad respecto al agua (m/s), y = altura de la ola de proa (m), z = radio de culling (m).
uniform vec4 hull_params[MAX_HULLS];
uniform int hull_ring_count=0;
// xyz = centro (mundo), w = edad (s).
uniform vec4 hull_rings[MAX_HULL_RINGS];
// x = altura (m), y = radio inicial (m), z = velocidad de la onda (m/s), w = vida (s).
uniform vec4 hull_ring_params[MAX_HULL_RINGS];

// Cresta con un seno a cada lado y media nula: la forma de una onda suelta (sombrero mexicano).
float hull_crest(float q,float w) {
    float u=q/max(w,0.05);
    return (1.0-2.0*u*u)*exp(-u*u);
}

// Altura extra del agua en [p] (mundo) y en [foam] la espuma que levanta (0..1).
// [min_wavelength]: lo más corto que la malla resuelve ahí; lo que no cabe se apaga.
float hull_wave_height(vec3 p,vec3 radial,float min_wavelength,out float foam) {
    float h=0.0;
    foam=0.0;
    for(int i=0;i<MAX_HULLS;i++) {
        if(i>=hull_count) break;
        vec3 d=p-hull_frame[i].xyz;
        float reach=hull_params[i].z;
        if(dot(d,d)>reach*reach) continue;
        vec3 fwd=normalize(hull_axis[i].xyz-radial*dot(hull_axis[i].xyz,radial));
        vec3 side=cross(radial,fwd);
        float L=hull_frame[i].w, B=hull_axis[i].w;
        float U=hull_params[i].x, A=hull_params[i].y;
        float s=dot(d,fwd), y=abs(dot(d,side));
        float n=y-B;
        // Lo que la malla no puede dibujar no se dibuja: un brazo más estrecho que dos vértices
        // sale como dientes de sierra.
        float w0=0.45+0.3*B;
        float res=smoothstep(min_wavelength*0.35,min_wavelength*0.8,w0);
        if(res<=0.0) continue;
        float hi=0.0;

        // Brazos de proa, con el vértice algo por delante de la roda.
        float x=L+0.3*B-s;
        float q;
        float w=w0*(1.0+max(x,0.0)/(2.5*L));
        if(x>=0.0) {
            float yc=B*(1.0-exp(-x/(0.8*B+0.5)))+x*BOW_ARM_TAN;
            q=y-yc;
        } else {
            q=length(vec2(x*1.6,y));
        }
        // Brazos cortos: van rígidos con el casco, y una V larga girando en bloque al virar se ve rara.
        // La estela de espuma ya hace de rastro largo.
        float decay=inversesqrt(1.0+max(x,0.0)/L)*(1.0-smoothstep(2.0*L,5.0*L+10.0,x));
        float arm=hull_crest(q,w)*decay*(w0/w);
        hi+=A*arm;
        // Rompe en la roda: blanco en la cresta del bigote, que se deshace al quedarse atrás.
        foam=max(foam,clamp(A/0.45,0.0,1.0)*0.85*max(arm,0.0)*exp(-max(x,0.0)/(L+1.8))*res);
        // Una franja de espuma pegada al costado, donde el casco corta el agua.
        float side_cut=(1.0-smoothstep(0.0,0.6+0.15*B,abs(n)))*step(abs(s),L)*smoothstep(-L,L*0.2,s);
        foam=max(foam,clamp(A/0.6,0.0,1.0)*side_cut*0.5*res);

        // Brazos de popa: arrancan en la popa, más flojos.
        float xs=-L-s;
        float ws=w0*(1.0+max(xs,0.0)/(2.5*L));
        float qs=xs>=0.0 ? y-(B*0.8+xs*KELVIN_TAN) : length(vec2(xs*2.0,max(n,0.0)));
        hi+=0.38*A*hull_crest(qs,ws)*inversesqrt(1.0+max(xs,0.0)/L)*(1.0-smoothstep(1.0*L,2.5*L+5.0,xs))*(w0/ws);

        // Seno a los costados: el casco aparta el agua a media eslora.
        hi-=0.48*A*exp(-(s*s)/(0.45*L*L))*exp(-max(n,0.0)/(0.5*B+0.4));

        // Ondas transversales tras la popa, dentro de la cuña. Su longitud es la de una ola que
        // corre a la velocidad del barco: 2πU²/g.
        float k=9.8/max(U*U,0.01);
        float lambda=6.2832/k;
        if(xs>0.0 && lambda>min_wavelength*0.6) {
            float wedge=1.0-smoothstep(B+xs*KELVIN_TAN*0.6,B+xs*KELVIN_TAN,y);
            float fade=smoothstep(min_wavelength*0.6,min_wavelength*1.4,lambda);
            hi+=0.2*A*cos(k*xs)*wedge*exp(-xs/(2.0*lambda+L))*smoothstep(0.0,lambda*0.5,xs)*fade;
        }

        // Dentro de la huella del casco nada sube: en un barco abierto el agua asomaría por la bodega.
        if(abs(s)<L && n<0.0) {
            hi=min(hi,hi*exp(-(n*n)/(0.09*B*B+0.04)));
        }
        h+=hi*res;
    }
    for(int r=0;r<MAX_HULL_RINGS;r++) {
        if(r>=hull_ring_count) break;
        vec4 ring=hull_rings[r];
        vec4 rp=hull_ring_params[r];
        float age=ring.w;
        float life=max(rp.w,0.01);
        if(age>=life) continue;
        float front=rp.y+rp.z*age;
        float w=0.35+0.15*age+rp.y*0.3;
        vec3 d=p-ring.xyz;
        d-=radial*dot(d,radial);
        float dist=length(d);
        if(dist>front+3.0*w) continue;
        float res=smoothstep(min_wavelength*0.3,min_wavelength*0.7,w);
        float life_fade=1.0-smoothstep(0.0,life,age);
        float amp=rp.x*life_fade*life_fade*sqrt(rp.y/max(front,rp.y));
        float c=hull_crest(dist-front,w);
        h+=amp*c*res;
        // El golpe deja una mancha blanca en el centro y la cresta del anillo, recién nacido.
        float spot=exp(-dist*dist/(rp.y*rp.y+0.5))*(1.0-smoothstep(0.0,life*0.8,age));
        foam=max(foam,clamp(rp.x/0.3,0.0,1.0)*0.8*max(max(c,0.0)*(1.0-smoothstep(0.0,life*0.5,age)),spot));
    }
    return h;
}

// Altura y pendiente de las olas de casco, por diferencias finitas en el plano tangente.
// Devuelve el gradiente (mundo, tangente) en [gradient] y la espuma en [foam].
float hull_wave_sample(vec3 p,vec3 radial,float min_wavelength,out vec3 gradient,out float foam) {
    gradient=vec3(0.0);
    foam=0.0;
    if(hull_count==0 && hull_ring_count==0) return 0.0;
    vec3 e1=normalize(cross(radial,abs(radial.y)<0.9 ? vec3(0,1,0) : vec3(1,0,0)));
    vec3 e2=cross(radial,e1);
    float delta=max(0.25,min_wavelength*0.15);
    float unused;
    float h=hull_wave_height(p,radial,min_wavelength,foam);
    if(h==0.0 && foam==0.0) return 0.0;
    float hx=hull_wave_height(p+e1*delta,radial,min_wavelength,unused);
    float hy=hull_wave_height(p+e2*delta,radial,min_wavelength,unused);
    gradient=(e1*(hx-h)+e2*(hy-h))/delta;
    return h;
}
