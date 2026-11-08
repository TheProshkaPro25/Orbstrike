"""A03 local sloped shoulder graft geometry (Blender exact Boolean, CPU only).

blender -b --factory-startup -P tools/models/export_kolossar_shadow_graft.py -- SOURCE OUTPUT_NPZ
All global Boolean side effects are discarded by build_kolossar_shadow_graft.py.
"""
import sys,json,os,time,numpy as np
from pathlib import Path
import bpy,bmesh
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'tools/models'))
import hashlib
args=sys.argv[sys.argv.index('--')+1:];source,output=map(Path,args[:2]);left_intercept=float(args[2])if len(args)>2 else .445
from remove_kolossar_shadow_smoke import BASE_SHA
assert hashlib.sha256(source.read_bytes()).hexdigest()==BASE_SHA
assert not output.resolve().is_relative_to((root/'assets/creatures_hd').resolve()), 'Candidate geometry output required'
from inspect_geometry import read_glb,accessor
try:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 d,b=read_glb(source);p=d['meshes'][0]['primitives'][0];v=accessor(d,b,p['attributes']['POSITION']);f=accessor(d,b,p['indices']).reshape(-1,3)
 # Source weld uses exact coincident coordinates. No position quantization.
 w,iv=np.unique(v,axis=0,return_inverse=True);mesh=bpy.data.meshes.new('A03 local surgery');mesh.from_pydata(w.tolist(),[],iv[f].tolist());mesh.update();o=bpy.data.objects.new('source',mesh);bpy.context.collection.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True)
 for name in ['retained','cap']:mesh.materials.append(bpy.data.materials.new(name))
 attr=mesh.attributes.new('source_face','INT','FACE')
 for i,a in enumerate(attr.data):a.value=i
 for label,lo,hi in [('left',[-.6,.205,.06],[-.13,.8,.5]),('right',[.225,.205,-.5],[.6,.8,.06])]:
  xs=[lo[0],hi[0]];zs=[lo[2],hi[2]]
  def floor(x,z):return left_intercept+.6*x-.5*z if label=='left' else .42-.6*x+.5*z
  bottom=[[x,floor(x,z),z]for x,z in [(xs[0],zs[0]),(xs[1],zs[0]),(xs[1],zs[1]),(xs[0],zs[1])]]
  vertices=bottom+[[p[0],.8,p[2]]for p in bottom]
  cm=bpy.data.meshes.new('sloping cutter');cm.from_pydata(vertices,[],[[0,1,2,3],[7,6,5,4],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]]);cm.update()
  bm=bmesh.new();bm.from_mesh(cm);geom=list(bm.verts)+list(bm.edges)+list(bm.faces);bmesh.ops.bisect_plane(bm,geom=geom,dist=1e-9,plane_co=(0,.205,0),plane_no=(0,1,0),clear_inner=True);bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if len(e.link_faces)==1],sides=0);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(cm);bm.free()
  cube=bpy.data.objects.new('cutter_'+label,cm);bpy.context.collection.objects.link(cube)
  cube.data.materials.append(mesh.materials[0]);cube.data.materials.append(mesh.materials[1])
  for poly in cube.data.polygons:poly.material_index=1
  ca=cube.data.attributes.new('source_face','INT','FACE')
  for a in ca.data:a.value=-1
  bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('exact_'+label,'BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cube
  mod.use_self=True;mod.use_hole_tolerant=True
  t=time.time();bpy.ops.object.modifier_apply(modifier=mod.name);print('BOOLEAN',label,len(o.data.polygons),'sec',time.time()-t,flush=True);bpy.data.objects.remove(cube,do_unlink=True)
 # Triangulate only Boolean ngons. Original triangles are left intact.
 bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.triangulate(bm,faces=[p for p in bm.faces if len(p.verts)>3],quad_method='BEAUTY',ngon_method='BEAUTY');bm.to_mesh(o.data);bm.free()
 ov=np.array([v.co[:]for v in o.data.vertices]);of=np.array([p.vertices[:]for p in o.data.polygons]);ids=np.array([a.value for a in o.data.attributes['source_face'].data]);mat=np.array([p.material_index for p in o.data.polygons]);output.parent.mkdir(parents=True,exist_ok=True);np.savez(output,v=ov,f=of,source_face=ids,material=mat)
 print('EXPORT',len(ov),len(of),'cap',sum(mat==1),'source ids',np.unique(ids,return_counts=True)[0].shape,flush=True)
 code=0
except Exception:
 import traceback;traceback.print_exc();code=1
sys.stdout.flush();sys.stderr.flush();os._exit(code)
