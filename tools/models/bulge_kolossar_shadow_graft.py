"""Add a small convex interior to A03 caps; preserve every true body/cap seam.

Only internal cap edges and face interiors gain vertices. Outer cap edges and all
existing vertices/weights remain exact. Writes a separate candidate and manifest.
python tools/models/bulge_kolossar_shadow_graft.py INPUT MANIFEST OUTPUT [MAX_BULGE]
"""
import copy,hashlib,json,sys
from pathlib import Path
import numpy as np
from inspect_geometry import accessor,read_glb
from upgrade_rigs import Writer


def bulge(source,manifest_file,output,amount=.002):
    assert source.resolve()!=output.resolve()
    root=Path(__file__).resolve().parents[2];assert not output.resolve().is_relative_to((root/'assets/creatures_hd').resolve())
    m=json.loads(manifest_file.read_text());assert hashlib.sha256(source.read_bytes()).hexdigest()==m['candidate_sha256']
    d,b=read_glb(source);d=copy.deepcopy(d);p=d['meshes'][0]['primitives'][1];a={k:accessor(d,b,i)for k,i in p['attributes'].items()};v=a['POSITION'];f=accessor(d,b,p['indices']).reshape(-1,3);ids=np.asarray(m['new_surface_source_face_ids']);cap_ids=np.flatnonzero(ids<0)
    welded,inv=np.unique(v,axis=0,return_inverse=True);cf=inv[f[cap_ids]];edges=np.sort(np.concatenate([cf[:,[0,1]],cf[:,[1,2]],cf[:,[2,0]]]),1);unique,counts=np.unique(edges,axis=0,return_counts=True);assert counts.max()==2
    seam=unique[counts==1];internal={tuple(edge)for edge in unique[counts==2]};segments=welded[seam].astype(float);e=segments[:,1]-segments[:,0];den=np.maximum((e*e).sum(1),1e-30)
    normals=np.cross(v[f[:,1]]-v[f[:,0]],v[f[:,2]]-v[f[:,0]]);normals=normals/np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-20)
    edge_normals={}
    for fi in cap_ids:
        for va,vb in zip(inv[f[fi]],np.roll(inv[f[fi]],-1)):
            key=tuple(sorted((int(va),int(vb))))
            if key in internal:edge_normals.setdefault(key,[]).append(normals[fi])
    nj=len(d['skins'][0]['joints']);records={k:[row.copy()for row in values]for k,values in a.items()};new_faces=[];new_sources=[];parents=[];midpoints={};diagnostics=[]
    def decoded(index):
        w=np.zeros(nj)
        for slot in (0,1):np.add.at(w,a[f'JOINTS_{slot}'][index],a[f'WEIGHTS_{slot}'][index])
        return w
    def add(point,normal,source_indices):
        point=np.asarray(point,float);normal=np.asarray(normal,float);normal/=max(np.linalg.norm(normal),1e-20)
        t=np.clip(((point-segments[:,0])*e).sum(1)/den,0,1);dist=float(np.linalg.norm(point-segments[:,0]-t[:,None]*e,axis=1).min())
        lift=min(amount,.75*dist);pos=(point+normal*lift).astype(np.float32)
        weights=sum((decoded(int(index))for index in source_indices),start=np.zeros(nj))/len(source_indices);j=np.argsort(-weights,kind='stable')[:8];w=weights[j];w/=max(w.sum(),1e-20)
        record={key:a[key][source_indices].mean(0)for key in a};record.update(POSITION=pos,NORMAL=normal,TEXCOORD_0=a['TEXCOORD_0'][source_indices[0]],JOINTS_0=j[:4],JOINTS_1=j[4:],WEIGHTS_0=w[:4],WEIGHTS_1=w[4:])
        index=len(records['POSITION'])
        for key in records:records[key].append(record[key])
        diagnostics.append({'vertex':index,'seam_distance':dist,'outward_lift':lift})
        return index
    for fi,tri in enumerate(f):
        if ids[fi]>=0:new_faces.append(tri.tolist());new_sources.append(int(ids[fi]));parents.append(fi);continue
        polygon=[]
        for va,vb in zip(tri,np.roll(tri,-1)):
            polygon.append(int(va));key=tuple(sorted((int(inv[va]),int(inv[vb]))))
            if key in internal:
                if key not in midpoints:midpoints[key]=add((v[va]+v[vb])*.5,np.sum(edge_normals[key],axis=0),np.array([va,vb]))
                polygon.append(midpoints[key])
        center=add(v[tri].mean(0),normals[fi],tri)
        for va,vb in zip(polygon,np.roll(polygon,-1)):
            new_faces.append([int(va),int(vb),center]);new_sources.append(-1);parents.append(fi)
    writer=Writer(d,b)
    for key,values in records.items():
        meta=d['accessors'][p['attributes'][key]];p['attributes'][key]=writer.add(np.asarray(values),meta['type'],meta['componentType'])
    p['indices']=writer.add(np.asarray(new_faces,dtype=np.uint32).ravel()[:,None],'SCALAR',5125)
    output.parent.mkdir(parents=True,exist_ok=True);writer.save(output)
    m['previous_candidate_sha256']=m['candidate_sha256'];m['candidate_sha256']=hashlib.sha256(output.read_bytes()).hexdigest();m['new_surface_source_face_ids']=new_sources;m['new_surface_triangles']=len(new_faces);m['new_cap_triangles']=int(sum(i<0 for i in new_sources));m['cap_subdivision_parent_face_ids']=parents;m['cap_interior_sculpt']={'max_outward_lift':amount,'distance_limit_factor':.75,'new_interior_vertices':len(diagnostics),'new_internal_edge_midpoints':len(midpoints),'true_seam_edges_unchanged':len(seam),'all_existing_vertices_weights_preserved':True,'vertices':diagnostics};m['scope']='Local convex cap-interior retessellation. Outside body and every original body/cap seam vertex/edge/8weights exact; no global remesh.'
    output.with_suffix('.graft.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps({k:v for k,v in m.items()if k in ('candidate_sha256','previous_candidate_sha256','new_surface_triangles','new_cap_triangles','clipped_source_triangles')},indent=2));print('new interiors',len(diagnostics),'seam edges unchanged',len(seam))
if __name__=='__main__':bulge(*map(Path,sys.argv[1:4]),float(sys.argv[4])if len(sys.argv)>4 else .002)
