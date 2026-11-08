"""A03 true cap/body seam segment versus nonadjacent posed-body witnesses.

Blender CPU only: SOURCE_CANDIDATE_POSES CANDIDATE_GLB MANIFEST REPORT.
Tests idle0 and attack24 using the exact packed candidate skin and actual source
palettes from the recorded projection, without changing the mesh or exclusions.
"""
import hashlib,json,os,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from review_kolossar_shadow_posed_scope import read_export,skin
from inspect_geometry import accessor,read_glb


def check(folder,glb,manifest,output):
    doc,meshes=read_export(folder);m=json.loads(manifest.read_text())
    assert hashlib.sha256(glb.read_bytes()).hexdigest()==m['candidate_sha256']
    gd,gb=read_glb(glb)
    for mesh,p in zip(meshes,gd['meshes'][0]['primitives']):
        gv=accessor(gd,gb,p['attributes']['POSITION']);gf=accessor(gd,gb,p['indices']).reshape(-1,3)
        assert np.array_equal(gv[gf[:,[0,2,1]]],mesh[1][mesh[2]])
    nmain=len(m['retained_source_face_ids']);ids=np.asarray(m['new_surface_source_face_ids']);cap=np.concatenate([np.zeros(nmain,bool),ids<0]);v=np.concatenate([a[1]for a in meshes]);f=np.concatenate([meshes[0][2],meshes[1][2]+len(meshes[0][1])]);welded,uid=np.unique(np.round(v,6),axis=0,return_inverse=True)
    cf=uid[f[cap]];ed=np.sort(np.concatenate([cf[:,[0,1]],cf[:,[1,2]],cf[:,[2,0]]]),1);ed,c=np.unique(ed,axis=0,return_counts=True);seam=ed[c==1]
    representative=np.full(len(welded),-1,dtype=int)
    for index in np.unique(f[cap]):representative[uid[index]]=index
    body_faces=np.flatnonzero(~cap);face_source=np.concatenate([m['retained_source_face_ids'],ids]);rows=[]
    for pose in doc['poses']:
        if (pose['action'],pose['frame'])not in [('idle',0),('attack',24)]:continue
        pv=np.concatenate([skin(mesh,pose)for mesh in meshes]).astype(float);tri=pv[f[body_faces]];low=tri.min(1);high=tri.max(1);u0=uid[f[body_faces]];witnesses=[]
        for edge in seam:
            ia,ib=representative[edge];a,b=pv[[ia,ib]];direction=b-a
            box=(low<=np.maximum(a,b)).all(1)&(high>=np.minimum(a,b)).all(1)
            adjacent=(u0==edge[0]).any(1)|(u0==edge[1]).any(1);selected=np.flatnonzero(box&~adjacent)
            if not len(selected):continue
            t=tri[selected];e1=t[:,1]-t[:,0];e2=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(direction,e2.shape),e2);det=np.einsum('ij,ij->i',e1,h);valid=abs(det)>1e-18
            invdet=np.zeros(len(det));invdet[valid]=1/det[valid];s=a-t[:,0];u=invdet*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);vv=invdet*(q@direction);distance=invdet*np.einsum('ij,ij->i',e2,q)
            hit=valid&(u>=0)&(vv>=0)&(u+vv<=1)&(distance>=0)&(distance<=1)
            for k in np.flatnonzero(hit):
                fi=int(body_faces[selected[k]]);witnesses.append({'seam_raw_endpoints':v[[ia,ib]].tolist(),'seam_posed_endpoints':pv[[ia,ib]].tolist(),'body_face':fi,'source_face':int(face_source[fi]),'body_triangle_posed':tri[selected[k]].tolist(),'segment_t':float(distance[k]),'body_barycentric':[float(1-u[k]-vv[k]),float(u[k]),float(vv[k])],'strict_interior_crossing':bool(0<distance[k]<1 and min(1-u[k]-vv[k],u[k],vv[k])>0)})
        rows.append({'action':pose['action'],'frame':pose['frame'],'seam_segment_body_intersections':len(witnesses),'strict_interior_crossings':sum(w['strict_interior_crossing']for w in witnesses),'witnesses':witnesses});print(rows[-1]['action'],rows[-1]['frame'],'seam/body',len(witnesses),'strict',rows[-1]['strict_interior_crossings'],flush=True)
    report={'candidate_sha256':m['candidate_sha256'],'true_cap_boundary_edges':len(seam),'candidate_export_kind':doc.get('export_kind','ACTUAL_GODOT_EXPORT'),'poses':rows,'scope':'Exact Moller-Trumbore segment/triangle tests after AABB pruning. Body triangles sharing either raw geometric seam endpoint are excluded. No depth tolerance or near-contact exemption. Strict crossings of fixed true boundary imply cap-interior-only changes cannot remove all contacts.'}
    output.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':
    try:check(*map(Path,sys.argv[sys.argv.index('--')+1:]));code=0
    except Exception:
        import traceback;traceback.print_exc();code=1
    sys.stdout.flush();sys.stderr.flush();os._exit(code)
