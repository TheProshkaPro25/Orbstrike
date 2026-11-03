"""Project-authored anime costume and body proportions, Blender Z-up.
Garments have actual silhouettes, seams, collars, cuffs and layered panels.
No source clothing or human torso is used in the exported actor.
"""
import bpy, math, bmesh
from mathutils import Vector
from anime_head import material

class Part:
    def __init__(self,name,role,color):
        self.name=name;self.role=role;self.color=color;self.v=[];self.f=[];self.uv=[];self.bones=[]
    def vertex(self,p,bone,uv=(0,0)):
        self.v.append(tuple(p));self.bones.append(bone);self.uv.append(uv)
        return len(self.v)-1
    def rings(self,rings,bone,segments=32,arc=(0,math.tau),cap=False):
        # rings: center, local horizontal radius, depth radius. Arc 0 faces forward.
        start=len(self.v);closed=abs(arc[1]-arc[0]-math.tau)<.001
        n=segments if closed else segments+1
        for i,(c,rx,ry) in enumerate(rings):
            for j in range(n):
                a=arc[0]+(arc[1]-arc[0])*j/segments
                self.vertex((c[0]+rx*math.sin(a),c[1]-ry*math.cos(a),c[2]),bone,(j/segments,i/(len(rings)-1)))
        for i in range(len(rings)-1):
            for j in range(segments):
                a=start+i*n+j;b=start+i*n+(j+1)%n
                self.f.append((a,b,b+n,a+n))
        if cap:
            self.f.append(tuple(start+j for j in reversed(range(n))))
            self.f.append(tuple(start+(len(rings)-1)*n+j for j in range(n)))
    def tube(self,points,radii,bone,segments=24):
        samples=[];sizes=[]
        for k in range(len(points)-1):
            for j in range(5):
                t=j/5
                values=[]
                for dim in range(5):
                    controls=[(*points[h],*radii[h])[dim] for h in [max(0,k-1),k,k+1,min(len(points)-1,k+2)]]
                    a,b,c,d=controls
                    values.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
                samples.append(values[:3]);sizes.append(values[3:])
        points=samples+[points[-1]];radii=sizes+[radii[-1]]
        start=len(self.v)
        for i,p in enumerate(points):
            p=Vector(p);tangent=(Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])).normalized()
            a=Vector((0,-1,0));a=(a-tangent*a.dot(tangent)).normalized();b=tangent.cross(a)
            rx,ry=radii[i]
            for j in range(segments):
                t=math.tau*j/segments
                self.vertex(p+a*(math.cos(t)*ry)+b*(math.sin(t)*rx),bone,(j/segments,i/(len(points)-1)))
        for i in range(len(points)-1):
            for j in range(segments):
                a=start+i*segments+j;b=start+i*segments+(j+1)%segments;self.f.append((a,b,b+segments,a+segments))
        self.f.append(tuple(start+j for j in reversed(range(segments))))
        self.f.append(tuple(start+(len(points)-1)*segments+j for j in range(segments)))
    def panel(self,points,bone):
        ids=[self.vertex(p,bone,((p[0]+.4)/.8,p[2]/1.8)) for p in points]
        self.f.append(tuple(ids))
    def box(self,c,size,bone):
        start=len(self.v)
        for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:
            self.vertex((c[0]+x*size[0]/2,c[1]+y*size[1]/2,c[2]+z*size[2]/2),bone,((x+1)/2,(z+1)/2))
        for face in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]:self.f.append(tuple(start+i for i in face))
    def finish(self,rig):
        mesh=bpy.data.meshes.new(self.name);mesh.from_pydata(self.v,[],self.f);mesh.update()
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
        layer=mesh.uv_layers.new(name='AvatarUV')
        for loop in mesh.loops:layer.data[loop.index].uv=self.uv[loop.vertex_index]
        obj=bpy.data.objects.new(self.name,mesh);bpy.context.collection.objects.link(obj);obj.parent=rig
        for name in set(self.bones):
            group=obj.vertex_groups.new(name=name);group.add([i for i,b in enumerate(self.bones) if b==name],1,'REPLACE')
        mod=obj.modifiers.new('FighterSkinning','ARMATURE');mod.object=rig
        obj.data.materials.append(material(self.role,self.color))
        for p in mesh.polygons:p.use_smooth=len(p.vertices)==4
        return obj

def create_anime_body(rig):
    skin=Part('FighterArms','Skin',(.95,.77,.62))
    jacket=Part('FighterJacket','Outfit',(.62,.05,.07))
    dark=Part('FighterPanels','ClothDark',(.024,.034,.064))
    trim=Part('FighterTrim','ClothLight',(.83,.84,.79))
    accent=Part('FighterAccent','Accent',(.95,.57,.13))
    pants=Part('FighterPants','Pants',(.045,.065,.115))
    shoes=Part('FighterShoes','Shoes',(.035,.05,.09))
    glove=Part('FighterBracers','Gloves',(.035,.065,.12))
    # Sleeveless inner layer; tailored torso, distinctly narrower than shoulders.
    dark.rings([((0,.005,z),x,y) for z,x,y in [(.905,.119,.073),(.97,.117,.079),(1.08,.124,.082),(1.18,.154,.088),(1.265,.174,.08),(1.304,.078,.047)]],'spine02',cap=True)
    # Open front jacket, separate side silhouettes; the dark undershirt remains visible.
    coat=[(.94,.139,.083),(1.00,.136,.087),(1.12,.144,.096),(1.235,.174,.094),(1.291,.188,.080),(1.309,.071,.049)]
    jacket.rings([((0,.01,z),x,y) for z,x,y in coat],'spine02',arc=(.24,math.tau-.24))
    # Broad shoulder yoke and sculpted standing collar are geometric, not a painted zip.
    for s in [-1,1]:
        def mirror(points):return [(s*x,y,z) for x,y,z in points]
        jacket.panel(mirror([(.045,-.072,1.279),(.085,-.067,1.333),(.095,-.012,1.341),(.184,.005,1.291),(.177,-.047,1.255)]),'spine02')
        dark.panel(mirror([(.05,-.076,1.278),(.085,-.070,1.329),(.096,-.015,1.336),(.102,-.016,1.307),(.066,-.080,1.256)]),'spine02')
        # Front opening piping follows the torso surface.
        trim.panel(mirror([(.034,-.078, .945),(.040,-.077,.945),(.047,-.080,1.20),(.064,-.070,1.276),(.057,-.072,1.279),(.040,-.083,1.20)]),'spine02')
        dark.panel(mirror([(.133,-.039,.95),(.15,-.035,1.12),(.133,-.066,1.18),(.111,-.071,.96)]),'spine02')
        # Chest pocket with flap and luminous small crest.
        dark.panel(mirror([(.075,-.091,1.16),(.122,-.070,1.16),(.124,-.072,1.215),(.075,-.094,1.215)]),'spine02')
        trim.panel(mirror([(.074,-.095,1.21),(.125,-.074,1.21),(.125,-.074,1.218),(.074,-.095,1.218)]),'spine02')
    accent.panel([(-.021,-.095,1.19),(0,-.098,1.21),(.021,-.095,1.19),(0,-.098,1.166)],'spine02')
    # Hem, visible belt and rectangular silver buckle.
    dark.rings([((0,.01,z),.141,.085) for z in [.93,.948]],'spine03')
    dark.rings([((0,.006,z),.127,.076) for z in [.88,.915]],'spine03')
    trim.box((0,-.077,.897),(.048,.009,.038),'spine03')
    dark.box((0,-.084,.897),(.027,.006,.022),'spine03')
    for x in [-.095,-.06,.06,.095]: accent.box((x,-.069,.897),(.008,.008,.012),'spine03')
    for s,side in [(-1,'R'),(1,'L')]:
        upper='upperarm01.'+side;lower='lowerarm01.'+side;wrist='wrist.'+side
        # Source hands sit at these wrists. The articulated arms are neither cylinders nor spheres.
        points=[(s*.177,-.012,1.287),(s*.205,-.018,1.24),(s*.232,-.022,1.16),(s*.256,-.022,1.08),(s*.286,-.096,1.008),(s*.327,-.189,.922)]
        skin.tube([points[2],points[3],(s*.282,-.083,1.023)],[(.043,.043),(.035,.035),(.035,.036)],upper)
        jacket.tube([(s*.133,-.01,1.277),(s*.174,-.013,1.28),points[1],(s*.222,-.021,1.19),points[2]],[(.024,.028),(.060,.058),(.063,.061),(.059,.058),(.053,.052)],upper)
        dark.tube([(s*.227,-.021,1.174),(s*.234,-.023,1.153)],[(.055,.054),(.053,.053)],upper)
        trim.tube([(s*.229,-.023,1.17),(s*.232,-.024,1.162)],[(.0555,.0545),(.055,.054)],upper)
        glove.tube([(s*.282,-.083,1.023),(s*.30,-.128,.976),(s*.327,-.189,.922)],[(.041,.042),(.036,.036),(.03,.029)],lower)
        accent.tube([(s*.282,-.083,1.023),(s*.286,-.091,1.013)],[(.043,.044),(.042,.043)],lower)
        # Leg shape: separated thighs, readable knees, taper to a substantial shoe.
        leg='upperleg01.'+side
        pants.rings([((s*x,y,z),rx,ry) for z,x,y,rx,ry in [(.10,.177,-.005,.048,.052),(.22,.172,.002,.050,.058),(.39,.156,-.014,.059,.067),(.435,.152,-.027,.063,.071),(.48,.148,-.022,.063,.07),(.52,.142,-.013,.066,.071),(.59,.134,.002,.071,.077),(.74,.116,.007,.080,.079),(.88,.085,.006,.087,.08),(.92,.078,.008,.081,.072)]],leg,cap=True)
        # Thigh pocket and angular knee overlay / side stripes.
        dark.panel([(s*x,y,z) for x,y,z in [(.149,-.068,.64),(.20,-.047,.65),(.202,-.046,.75),(.155,-.073,.765)]],leg)
        trim.panel([(s*x,y,z) for x,y,z in [(.147,-.070,.755),(.203,-.049,.74),(.203,-.049,.749),(.148,-.070,.764)]],leg)
        dark.panel([(s*x,y,z) for x,y,z in [(.11,-.093,.42),(.17,-.103,.415),(.199,-.084,.48),(.171,-.103,.535),(.117,-.101,.525),(.096,-.086,.48)]],leg)
        accent.panel([(s*x,y,z) for x,y,z in [(.166,-.109,.517),(.191,-.095,.482),(.186,-.098,.476),(.159,-.111,.512)]],leg)
        # High-top sneaker, shoe upper/sole/toe panels, tongue and actual laces.
        foot='foot.'+side
        shoes.rings([((s*.18,y,z),rx,ry) for z,y,rx,ry in [(.018,-.057,.061,.118),(.043,-.06,.064,.121),(.07,-.062,.061,.114),(.115,-.021,.052,.07),(.19,-.004,.05,.058)]],foot,cap=True)
        trim.rings([((s*.18,-.058,z),.064,.122) for z in [.014,.031]],foot,cap=True)
        jacket.rings([((s*.18,-.005,z),.052,.060) for z in [.145,.178]],foot)
        trim.panel([(s*(.18+x),y,z) for x,y,z in [(-.043,-.097,.073),(.043,-.097,.073),(.04,-.055,.126),(-.04,-.055,.126)]],foot)
        for z,y in [(.09,-.088),(.106,-.073),(.122,-.059)]:dark.box((s*.18,y,z),(.058,.005,.004),foot)
    return [p.finish(rig) for p in [skin,jacket,dark,trim,accent,pants,shoes,glove]]

def add_body_morphs(objects):
    # Coherent deformation for all parts, including sleeves, hands, footwear and seams.
    # Height/head unchanged; no per-frame mesh rebuilding or skeleton scaling.
    for obj in objects:
        if not obj.data.shape_keys:obj.shape_key_add(name='Basis')
        for name,sx,sy in [('BodyLean',.87,.94),('BodyAthletic',1.12,1.07)]:
            shape=obj.shape_key_add(name=name)
            for v in shape.data:
                w=max(0,min(1,(1.43-v.co.z)/.11))
                v.co.x*=1+(sx-1)*w;v.co.y*=1+(sy-1)*w
