"""Original game-anime head. Broad face, compact features and sculpted almond eyes.
Blender coordinates: Z up, -Y forward. Does not modify any creature model.
"""
import bpy
import math
from mathutils import Vector

PROFILE=[(1.390,.006,.035),(1.410,.039,.062),(1.440,.073,.084),(1.480,.106,.099),(1.530,.129,.109),(1.585,.133,.114),(1.650,.125,.109),(1.705,.087,.078),(1.735,.002,.002)]
CENTER_Y=-.016

def profile(z):
    for i in range(len(PROFILE)-1):
        a,b=PROFILE[i:i+2]
        if z<=b[0]:
            t=max(0,min(1,(z-a[0])/(b[0]-a[0])))
            # Catmull-Rom avoids horizontal ridges in the sculpted cheek.
            prev=PROFILE[max(i-1,0)];nxt=PROFILE[min(i+2,len(PROFILE)-1)]
            def cubic(k):
                m0=(b[k]-prev[k])/(b[0]-prev[0])*(b[0]-a[0])
                m1=(nxt[k]-a[k])/(nxt[0]-a[0])*(b[0]-a[0])
                return (2*t**3-3*t*t+1)*a[k]+(t**3-2*t*t+t)*m0+(-2*t**3+3*t*t)*b[k]+(t**3-t*t)*m1
            return max(.002,cubic(1)),max(.002,cubic(2))
    return PROFILE[-1][1:]

def face_y(x,z):
    radius,depth=profile(z)
    y=CENTER_Y-depth*math.sqrt(max(.001,1-abs(x/radius)**3.2))
    # Tiny anime nose: one smooth plane change, no nostrils or human lip volume.
    y-=.023*math.exp(-(x/.014)**2-((z-1.505)/.019)**2)
    return y

def material(name,color):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.65
    return mat

def mesh_object(name,verts,faces,rig,mat,uvs=None):
    # Compact anime lower face, then seat the whole head above the collar.
    verts=[(v[0]*1.055,v[1],(1.568+(v[2]-1.568)*.76 if v[2]<1.568 else v[2])-.090) for v in verts]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    import bmesh
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    layer=mesh.uv_layers.new(name='AvatarUV')
    for loop in mesh.loops:
        p=mesh.vertices[loop.vertex_index].co
        layer.data[loop.index].uv=uvs[loop.vertex_index] if uvs else ((p.x+.15)/.3,(p.z-1.35)/.45)
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    obj.parent=rig
    group=obj.vertex_groups.new(name='head');group.add(list(range(len(verts))),1,'REPLACE')
    modifier=obj.modifiers.new('HeadBind','ARMATURE');modifier.object=rig
    obj.data.materials.append(mat)
    for polygon in mesh.polygons: polygon.use_smooth=True
    return obj

def stroke_geometry(points,width,verts,faces):
    start=len(verts)
    for i,p in enumerate(points):
        p=Vector(p)
        tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        across=Vector((-tangent.z,0,tangent.x)).normalized()
        taper=math.sin(math.pi*(.04+.92*i/(len(points)-1)))**.4
        for sign in [-1,1]: verts.append(tuple(p+across*(width*sign*taper)))
    for i in range(len(points)-1):
        a=start+i*2;faces.append((a,a+1,a+3,a+2))

def create_anime_head(rig):
    skin=material('SkinFace',(.95,.77,.62));ink=material('Brows',(.028,.018,.020))
    # Dense continuous skull; ears are part of the same skinned mesh.
    verts=[];faces=[];n=64;rows=64
    for row in range(rows+1):
        z=1.39+.345*row/rows;radius,depth=profile(z)
        for j in range(n):
            a=j/n*math.tau;x=radius*math.sin(a)
            y=CENTER_Y-depth*math.cos(a)
            if math.cos(a)>0: y=face_y(x,z)
            verts.append((x,y,z))
    for row in range(rows):
        for j in range(n):
            a=row*n+j;b=row*n+(j+1)%n;faces.append((a,b,b+n,a+n))
    for side in [-1,1]:
        start=len(verts)
        for row in range(13):
            p=math.pi*row/12
            for j in range(20):
                a=j/20*math.tau
                verts.append((side*(.130+.018*math.sin(p)*math.cos(a)),-.002+.012*math.sin(p)*math.sin(a),1.505+.031*math.cos(p)))
        for row in range(12):
            for j in range(20):
                a=start+row*20+j;b=start+row*20+(j+1)%20;faces.append((a,b,b+20,a+20))
    # Short neck behind the pointed chin, overlapping the body's collar seam.
    start=len(verts)
    for row in range(5):
        z=1.30+row*.040
        for j in range(32):
            a=j/32*math.tau
            verts.append((.039*math.sin(a),.012-.038*math.cos(a),z))
    for row in range(4):
        for j in range(32):
            a=start+row*32+j;b=start+row*32+(j+1)%32;faces.append((a,b,b+32,a+32))
    faces.append(tuple(start+4*32+j for j in range(32)))
    head=mesh_object('FighterHead',verts,faces,rig,skin)
    head.shape_key_add(name='Basis')
    for name,scale in [('FaceNarrow',-.05),('FaceBroad',.05)]:
        shape=head.shape_key_add(name=name)
        for v in shape.data:
            weight=max(0,1-abs(v.co.z-1.39)/.055)
            v.co.x*=1+scale*weight
    # Almond-shaped patches follow the actual face, with a slight corneal bulge.
    ev=[];ef=[];uv=[];upper=[];brows=[]
    for side in [-1,1]:
        cx=side*.057;cz=1.568;w=.041
        start=len(ev);radial=10;segments=64
        for row in range(radial+1):
            r=max(.0001,row/radial)
            for j in range(segments):
                a=j/segments*math.tau
                dx=math.cos(a)*w*r
                height=.029 if math.sin(a)>0 else .023
                dz=math.sin(a)*height*r+side*dx*.20
                x=cx+dx;z=cz+dz
                ev.append((x,face_y(x,z)-.0018-.003*(1-r*r),z))
                uv.append((.5+dx/(2*w),.5+dz/.055))
        for row in range(radial):
            for j in range(segments):
                a=start+row*segments+j;b=start+row*segments+(j+1)%segments;ef.append((a,b,b+segments,a+segments))
        line=[]
        for j in range(33):
            a=math.pi*j/32;dx=math.cos(a)*w;dz=math.sin(a)*.029+side*dx*.20
            x=cx+dx;z=cz+dz;line.append((x,face_y(x,z)-.003,z))
        upper.append(line)
        points=[]
        for j in range(20):
            t=j/19;x=cx+(t-.5)*.077
            z=1.611+side*(t-.5)*.022+.003*math.sin(t*math.pi)
            points.append((x,face_y(x,z)-.003,z))
        brows.append(points)
    eyes=mesh_object('FighterEyes',ev,ef,rig,material('Eyes',(1,1,1)),uv)
    lv=[];lf=[];bv=[];bf=[]
    for line in upper: stroke_geometry(line,.0031,lv,lf)
    for side in [-1,1]:
        line=[]
        for j in range(25):
            a=math.pi+math.pi*j/24;dx=math.cos(a)*.041;dz=math.sin(a)*.023+side*dx*.20
            x=side*.057+dx;z=1.568+dz;line.append((x,face_y(x,z)-.0028,z))
        stroke_geometry(line,.00065,lv,lf)
    for line in brows: stroke_geometry(line,.0030,bv,bf)
    lashes=mesh_object('FighterLashes',lv,lf,rig,material('Lashes',(.018,.012,.018)))
    brow=mesh_object('FighterBrows',bv,bf,rig,ink)
    mv=[];mf=[];line=[]
    for i in range(25):
        x=(i/24-.5)*.044;z=1.452+.0015*(1-(x/.023)**2)
        line.append((x,face_y(x,z)-.0015,z))
    stroke_geometry(line,.0010,mv,mf)
    mouth=mesh_object('FighterMouth',mv,mf,rig,material('Mouth',(.19,.09,.08)))
    return head,eyes,brow,lashes,mouth
