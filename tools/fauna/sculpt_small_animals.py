"""Bake continuous wildlife surfaces. Run in the build/fauna_tools Python venv.

The editable anatomy is a smooth signed-distance field. Marching cubes and
quadric simplification are offline only; the game loads the resulting meshes.
Coordinates are Godot's metres, Y up, nose toward -Z.
"""
from pathlib import Path
import json
import numpy as np
from scipy.spatial.transform import Rotation
from skimage.measure import marching_cubes
import trimesh

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/fauna/sculpted'
OUT.mkdir(parents=True, exist_ok=True)


def smooth(a, b, k):
    h = np.maximum(k - np.abs(a - b), 0) / k
    return np.minimum(a, b) - h * h * k * .25


def ss(a, b, x):
    t = np.clip((x-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def rgb(h):
    return np.array([int(h[i:i+2], 16)/255 for i in (0, 2, 4)])


class Sculpt:
    def __init__(self, kind, lo, hi, step, blend):
        self.kind, self.lo, self.step, self.blend = kind, np.array(lo), step, blend
        axes = [np.arange(lo[i], hi[i]+step, step, dtype=np.float32) for i in range(3)]
        self.grid = np.stack(np.meshgrid(*axes, indexing='ij'), axis=-1)
        self.parts = []
        self.cuts = []
        self.field = np.full(self.grid.shape[:-1], 100, dtype=np.float32)

    @staticmethod
    def distance(p, center, radii, rotation):
        q = (p-np.asarray(center, dtype=np.float32)) @ rotation
        r = np.asarray(radii, dtype=np.float32)
        k0 = np.linalg.norm(q/r, axis=-1)
        k1 = np.linalg.norm(q/(r*r), axis=-1)
        return k0*(k0-1)/np.maximum(k1, 1e-8)

    def ell(self, c, r, angle=(0,0,0), blend=None, cut=False):
        rot = Rotation.from_euler('xyz', angle, degrees=True).as_matrix().astype(np.float32)
        part = (c, r, rot, self.blend if blend is None else blend)
        d = self.distance(self.grid, c, r, rot)
        if cut:
            self.field = -smooth(-self.field, d, part[3])
            self.cuts.append(part)
        else:
            self.field = smooth(self.field, d, part[3])
            self.parts.append(part)

    def rod(self, a, b, width, thickness=None, blend=None):
        a, b = np.array(a), np.array(b)
        axis = b-a
        axis /= np.linalg.norm(axis)
        rot, _ = Rotation.align_vectors([axis], [[0,1,0]])
        self.ell((a+b)/2, (width, np.linalg.norm(b-a)*.5+width, thickness or width),
                 rot.as_euler('xyz', degrees=True), blend)

    def at(self, p):
        f = np.full(np.asarray(p).shape[:-1], 100.)
        for c, r, rot, k in self.parts:
            f = smooth(f, self.distance(p, c, r, rot), k)
        for c, r, rot, k in self.cuts:
            f = -smooth(-f, self.distance(p, c, r, rot), k)
        return f

    def surface(self, point, normal):
        p, n = np.array(point), np.array(normal)
        n = n/np.linalg.norm(n)
        lo, hi = -.05, .05
        for _ in range(24):
            mid = (lo+hi)*.5
            if self.at(p+n*mid) > 0:
                hi = mid
            else:
                lo = mid
        return p+n*(lo+hi)*.5, n

    def mesh(self):
        v, f, _, _ = marching_cubes(self.field, 0, spacing=(self.step,)*3, gradient_direction='ascent')
        v += self.lo
        m = trimesh.Trimesh(v, f, process=True)
        m.fix_normals()
        m = m.simplify_quadric_decimation(face_count=18000, aggression=5)
        # Smooth voxel-scale sampling artifacts, preserving volume and anatomical creases.
        trimesh.smoothing.filter_taubin(m, lamb=.4, nu=.41, iterations=3)
        m.fix_normals()
        return m


def anatomy(kind):
    if kind == 0:
        s = Sculpt(kind, (-.23,-.035,-.43), (.23,.73,.39), .0038, .022)
        # Low crouch: large pelvis, sloping back, narrow forequarters and an elongated face.
        for c,r,a in [((0,.215,.09),(.139,.171,.219),(8,0,0)),
                      ((0,.183,-.070),(.099,.128,.160),(20,0,0)),
                      ((0,.285,-.150),(.080,.115,.098),(-20,0,0)),
                      ((0,.327,-.210),(.080,.084,.105),(8,0,0)),
                      ((0,.292,-.280),(.055,.051,.079),(-8,0,0))]:
            s.ell(c,r,a)
        for side in (-1,1):
            s.ell((side*.092,.136,.133),(.078,.119,.124), (16,0,side*8))
            s.rod((side*.073,.218,-.091),(side*.073,.068,-.141),.030,.035)
            s.rod((side*.073,.072,-.139),(side*.073,.027,-.181),.020,.023)
            s.ell((side*.073,.021,-.199),(.028,.023,.059),blend=.010)
            s.rod((side*.113,.088,.133),(side*.112,.036,.043),.033,.040)
            s.ell((side*.111,.025,-.004),(.040,.026,.087),blend=.012)
            s.ell((side*.047,.496,-.180),(.028,.157,.016),(-12,0,-side*12),blend=.012)
        s.ell((0,.186,.289),(.047,.049,.055),blend=.01)
        for side in (-1,1):
            s.ell((side*.048,.508,-.192),(.017,.113,.011),(-12,0,-side*12),blend=.004,cut=True)
    elif kind == 1:
        s = Sculpt(kind, (-.23,-.035,-.65), (.23,.79,.87), .0048, .025)
        for c,r,a in [((0,.343,.002),(.092,.108,.289),(0,0,0)),
                      ((0,.336,.185),(.098,.114,.151),(-8,0,0)),
                      ((0,.350,-.186),(.098,.131,.146),(-18,0,0)),
                      ((0,.421,-.274),(.066,.094,.101),(-27,0,0)),
                      ((0,.470,-.345),(.069,.067,.105),(14,0,0)),
                      ((0,.442,-.427),(.049,.040,.103),(-8,0,0)),
                      ((0,.436,-.507),(.027,.024,.071),(-3,0,0))]:
            s.ell(c,r,a)
        for side in (-1,1):
            # Foreleg: shoulder, elbow, narrow wrist, slightly forward paw.
            s.rod((side*.071,.339,-.188),(side*.078,.190,-.125),.030,.037)
            s.rod((side*.078,.190,-.125),(side*.079,.047,-.195),.017,.019,blend=.010)
            s.ell((side*.079,.024,-.224),(.026,.025,.053),blend=.009)
            # Digitigrade rear leg: thigh forward, hock back, toes under the body.
            s.rod((side*.084,.320,.190),(side*.098,.195,.105),.044,.051)
            s.rod((side*.098,.195,.105),(side*.102,.098,.233),.021,.026,blend=.012)
            s.rod((side*.102,.105,.231),(side*.103,.038,.213),.015,.019,blend=.010)
            s.ell((side*.103,.023,.182),(.026,.024,.050),blend=.010)
            # Cheek ruff broadens behind the jaw while the muzzle stays fine.
            s.ell((side*.056,.442,-.318),(.036,.045,.066),(0,side*18,0),blend=.015)
            # Compact triangular pinnae: broad lower fold and a narrow upright tip.
            for t in np.linspace(0,1,10):
                w=.048*(1-t)+.003
                s.ell((side*(.052+t*.033),.520+t*.127,-.318+t*.012),
                      (w,.022,.021*(1-t)+.004),blend=.006)
        # Dense tapered sweep follows the actual centreline, avoiding segmented lobes.
        for t in np.linspace(0,1,33):
            radius=.035*(1-t)+.051*np.sin(np.pi*t)**.85+.002
            s.ell((.018*np.sin(t*4),.328-.167*np.sin(t*np.pi*.75),.285+t*.475),
                  (radius,radius,radius),blend=.010)
        for side in (-1,1):
            s.ell((side*.064,.574,-.338),(.026,.049,.012),(-7,0,-side*15),blend=.003,cut=True)
    else:
        s = Sculpt(kind, (-.125,-.018,-.215), (.125,.22,.41), .0018, .008)
        for c,r,a in [((0,.076,.032),(.056,.066,.112),(8,0,0)),
                      ((0,.070,-.049),(.043,.047,.077),(-12,0,0)),
                      ((0,.086,-.093),(.037,.040,.055),(12,0,0)),
                      ((0,.064,-.139),(.024,.021,.042),(-8,0,0))]:
            s.ell(c,r,a)
        for side in (-1,1):
            s.rod((side*.032,.067,-.051),(side*.039,.019,-.065),.010,.013,blend=.005)
            s.ell((side*.041,.009,-.081),(.013,.010,.025),blend=.004)
            s.ell((side*.043,.049,.070),(.028,.041,.043),blend=.005)
            s.rod((side*.048,.035,.073),(side*.048,.012,.035),.011,.015,blend=.004)
            s.ell((side*.051,.009,.017),(.015,.009,.031),blend=.004)
            s.ell((side*.038,.131,-.074),(.030,.034,.011),(-12,side*22,-side*17),blend=.004)
        previous = np.array((0,.057,.133))
        for i in range(1,21):
            t = i/20
            point = np.array((.035*np.sin(t*4), .050-.039*np.sin(t*np.pi*.65), .133+t*.245))
            s.rod(previous,point,.0065*(1-t)+.0012,blend=.003)
            previous=point
        for side in (-1,1):
            s.ell((side*.039,.134,-.083),(.022,.025,.008),(-12,side*22,-side*17),blend=.002,cut=True)
    return s


def coat(kind, v, normals):
    x,y,z = v.T
    if kind == 0:
        color=np.tile(rgb('83705a'),(len(v),1))
        light=rgb('c6b69b')
        belly=ss(.16,.07,y)*(1-ss(.12,.17,np.abs(x)))
        chin=ss(-.22,-.30,z)*ss(.31,.26,y)
        tail=ss(.254,.30,z)
        mask=np.maximum.reduce([belly,chin,tail])
        color=color*(1-mask[:,None])+light*mask[:,None]
        # Dark guard hairs over the back and ear tips; ear interior muted rather than pink plastic.
        saddle=ss(.20,.34,y)*(1-ss(-.10,-.20,z))
        color*=1-.17*saddle[:,None]
        ear=ss(.397,.425,y)*ss(-.16,-.195,z)*(1-ss(.60,.65,y))
        color=color*(1-ear[:,None]*.80)+rgb('ac8575')*ear[:,None]*.80
        color*=1-.30*ss(.60,.66,y)[:,None]
    elif kind == 1:
        color=np.tile(rgb('a85527'),(len(v),1))
        cream=rgb('d8cbb0')
        belly=ss(.32,.245,y)*(1-ss(.105,.15,np.abs(x)))*(1-ss(.25,.32,z))
        chest=ss(-.17,-.28,z)*ss(.20,.28,y)*(1-ss(.392,.438,y))
        cheek=ss(-.29,-.35,z)*ss(.468,.440,y)*(1-ss(-.52,-.57,z))
        tail=ss(.635,.690,z)
        mask=np.maximum.reduce([belly,chest,cheek,tail])
        color=color*(1-mask[:,None])+cream*mask[:,None]
        dark=ss(.145,.095,y)*(1-ss(.27,.32,z))
        color=color*(1-dark[:,None])+rgb('302a27')*dark[:,None]
        ear=ss(.527,.55,y)*ss(-.31,-.335,z)
        color=color*(1-ear[:,None]*.9)+rgb('bdab96')*ear[:,None]*.9
        tips=ss(.609,.653,y)
        color=color*(1-tips[:,None]*.9)+rgb('342e27')*tips[:,None]*.9
        saddle=ss(.405,.475,y)*ss(-.22,-.06,z)*(1-ss(.30,.37,z))
        color*=1-.22*saddle[:,None]
        # Malar tear markings follow the angle below the eyes rather than a circular patch.
        tear=np.exp(-((np.abs(x)-.056)/.016)**2-((y-(.468+.28*(z+.39)))/.009)**2-((z+.397)/.044)**2)
        color=color*(1-tear[:,None]*.55)+rgb('483626')*tear[:,None]*.55
    else:
        color=np.tile(rgb('827461'),(len(v),1))
        belly=ss(.065,.033,y)*(1-ss(.13,.16,z))
        color=color*(1-belly[:,None])+rgb('d0c1a3')*belly[:,None]
        skin=np.maximum.reduce([ss(.131,.16,z),ss(.025,.015,y),ss(.108,.132,y)*ss(-.063,-.085,z)])
        color=color*(1-skin[:,None])+rgb('b38a7d')*skin[:,None]
    # Deterministic low-amplitude pigmentation; finer fur is shaded at runtime.
    grain=(np.sin(x*227+y*171+z*193)+np.sin(x*413-y*307+z*229))*.017
    color=np.clip(color*(1+grain[:,None]),0,1)
    return np.column_stack((color,np.ones(len(v))))


def detail_sphere(center, scale, normal, color, surface=0):
    m=trimesh.creation.uv_sphere(count=[12,20])
    n=np.array(normal); n=n/np.linalg.norm(n)
    right=np.cross([0,1,0],n)
    if np.linalg.norm(right)<.01: right=np.array([1,0,0])
    right/=np.linalg.norm(right)
    up=np.cross(n,right)
    m.vertices=(m.vertices*np.asarray(scale))@np.column_stack((right,up,n)).T+center
    colors=np.tile(np.r_[rgb(color),surface],(len(m.vertices),1))
    return m,colors


def weights(kind,v):
    x,y,z=v.T
    uv=np.zeros((len(v),2))
    # Smooth deformation weights vanish before reaching the torso.
    hips=[(.15,-.13,.075,.13),(.32,-.19,.084,.18),(.060,-.06,.035,.07)][kind]
    h,front,width,back=hips
    leg=(1-ss(h*.36,h,y))*ss(width*.32,width*.75,np.abs(x))
    if kind == 1:
        leg=(1-ss(.26,.36,y))*ss(.026,.060,np.abs(x))
    # Bring weights to zero between joints, so a triangle cannot switch abruptly
    # from one leg's motion to the opposite leg or the tail.
    leg*=ss(0,[.04,.07,.017][kind],np.abs(z-(front+back)*.5))
    tailstart=[.25,.29,.131][kind]
    leg*=1-ss(tailstart-[.04,.05,.025][kind],tailstart,z)
    uv[:,0]=1+(x>0).astype(float)+2*(z>(front+back)*.5).astype(float)
    uv[:,1]=leg
    tail=ss(tailstart,tailstart+[.07,.23,.12][kind],z)
    choose=tail>leg
    uv[choose,0]=5; uv[choose,1]=tail[choose]
    earbase=[.395,.54,.112][kind]
    ear=ss(earbase,earbase+[.18,.14,.045][kind],y)
    choose=ear>uv[:,1]
    uv[choose,0]=6+(x[choose]>0).astype(float); uv[choose,1]=ear[choose]
    return uv


def bake(kind):
    names=['rabbit','fox','mouse']
    s=anatomy(kind)
    main=s.mesh()
    meshes=[main]; colors=[coat(kind,main.vertices,main.vertex_normals)]
    eye_pos=[(.063,.341,-.257),(.060,.483,-.387),(.030,.096,-.119)][kind]
    eye_size=[.012,.014,.009][kind]
    for side in (-1,1):
        p,n=s.surface((side*eye_pos[0],eye_pos[1],eye_pos[2]),(side*.82,.15,-.55))
        # Lens lies against the skin, with iris aligned to the outward surface normal.
        for c,sc,col,surf in [(p-n*eye_size*.15,(eye_size,eye_size*.83,eye_size*.42),'171713',0),
                              (p+n*eye_size*.30,(eye_size*.65,eye_size*.62,eye_size*.12),'967342' if kind==1 else '3a2c20',0),
                              (p+n*eye_size*.40,(eye_size*.32,eye_size*.45,eye_size*.07),'090d10',0)]:
            m,c=detail_sphere(c,sc,n,col,surf);meshes.append(m);colors.append(c)
        # A restrained catchlight, not a separate bulging eye.
        m,c=detail_sphere(p+n*eye_size*.46+np.array((0,eye_size*.22,0)),(eye_size*.10,)*3,n,'ede3cd',0)
        meshes.append(m);colors.append(c)
    nose=[((0,.289,-.351),(.014,.010,.009),'725249'),((0,.436,-.570),(.017,.011,.012),'232421'),((0,.064,-.178),(.007,.005,.006),'b7837b')][kind]
    m,c=detail_sphere(nose[0],nose[1],(0,0,-1),nose[2],.25);meshes.append(m);colors.append(c)
    # Fine whiskers, curved and tapered, grouped into the same draw surface.
    if kind in (0,2):
        root=np.array([(.029,.284,-.326),(.015,.065,-.158)][0 if kind==0 else 1])
        length=.072 if kind==0 else .050
        for side in (-1,1):
            for strand in (-1,0,1):
                start=root*np.array((side,1,1))
                for t in range(4):
                    a=t/4; b=(t+1)/4
                    def point(q): return start+np.array((side*length*q,strand*length*.13*q-length*.08*q*q,strand*length*.25*q))
                    a1,b1=point(a),point(b)
                    radius=(.00065 if kind==0 else .00035)*(1-a*.7)
                    m=trimesh.creation.cylinder(radius=radius,segment=np.array([a1,b1]),sections=5)
                    meshes.append(m);colors.append(np.tile(np.r_[rgb('b9ac94'),.4],(len(m.vertices),1)))
    mesh=trimesh.util.concatenate(meshes)
    color=np.concatenate(colors)
    uv=weights(kind,mesh.vertices)
    # Godot uses clockwise front faces. Trimesh supplies outward CCW normals.
    output={'vertices':np.round(mesh.vertices,6).tolist(), 'normals':np.round(mesh.vertex_normals,6).tolist(),
            'colors':np.round(color,5).tolist(), 'uv':np.round(uv,5).tolist(),
            'indices':mesh.faces[:,::-1].reshape(-1).tolist()}
    (OUT/(names[kind]+'.json')).write_text(json.dumps(output,separators=(',',':')))
    print(f'{names[kind]}: {len(mesh.faces)} triangles, body watertight={main.is_watertight}, {len(main.split())} body components',flush=True)


if __name__=='__main__':
    import sys
    for kind in ([int(sys.argv[1])] if len(sys.argv)>1 else range(3)):
        bake(kind)
