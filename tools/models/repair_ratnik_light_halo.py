"""A04 SHA-locked local disc replacement; writes uninstalled candidate only.

CPU/source candidate, not Godot/GPU acceptance. Only a bounded source helmet
collar changes POSITION/NORMAL; source skin/UV, cloth, images, animation and
nodes remain exact. New crown patches close the disc boundaries; a separate
thin closed ring follows the head bone.
"""
import argparse, copy, hashlib, io, json
from pathlib import Path
import numpy as np
from PIL import Image
from inspect_geometry import read_glb, accessor
from remove_grifalon_gale_wind import components, boundary_edges, loops_of, triangulate
from upgrade_rigs import Writer
from ratnik_light_crown_patch import crown_patch,smooth_collar
BASE_SHA='454e8442b83fe7fd618d0bc0338dfc8b51b1daabaa49b4a5237dcb669598f727'

def select(doc,binary):
    prim=doc['meshes'][0]['primitives'][0]
    arrays={k:accessor(doc,binary,i) for k,i in prim['attributes'].items()}
    v=arrays['POSITION']; f=accessor(doc,binary,prim['indices']).reshape(-1,3)
    view=doc['bufferViews'][doc['images'][doc['textures'][doc['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]['bufferView']]
    start=view.get('byteOffset',0)
    tex=np.asarray(Image.open(io.BytesIO(binary[start:start+view['byteLength']])).convert('RGB'))
    uv=arrays['TEXCOORD_0'][f].mean(1);pix=(np.clip(uv,0,1)*np.array([tex.shape[1]-1,tex.shape[0]-1])).astype(int)
    rgb=tex[pix[:,1],pix[:,0]].astype(float);fc=v[f].mean(1)
    brown=(fc[:,1]>.33)&(fc[:,1]+.65*fc[:,2]>.40)&(fc[:,2]>0)&(rgb[:,0]<180)&(rgb[:,1]<153)
    welded,inverse=np.unique(np.round(v,6),axis=0,return_inverse=True)
    labels=components(inverse[f[brown]],len(welded))[inverse[f[:,0]]]
    keys,counts=np.unique(labels[brown],return_counts=True)
    assert sorted(counts[counts>300].tolist())==[391,1104]
    removed=brown&np.isin(labels,keys[counts>300])
    # Vertex-only connectivity lets brown paint touch the disc at a lone corner
    # and mislabels helmet shadows. Require shared-edge connected surfaces.
    ids=np.flatnonzero(removed);wf=inverse[f[ids]]
    es=np.concatenate([wf[:,[0,1]],wf[:,[1,2]],wf[:,[2,0]]]);owners=np.tile(np.arange(len(ids)),3)
    es=np.sort(es,axis=1);order=np.lexsort((es[:,1],es[:,0]))
    same=(es[order[1:]]==es[order[:-1]]).all(1)
    adjacency=np.stack([owners[order[:-1]][same],owners[order[1:]][same]],1)
    flabels=components(adjacency,len(ids));fkeys,fcounts=np.unique(flabels,return_counts=True)
    assert sorted(fcounts[fcounts>300].tolist())==[391,944]
    removed[:]=False;removed[ids[np.isin(flabels,fkeys[fcounts>300])]]=True
    original_edges={tuple(sorted(e))for e in boundary_edges(inverse[f])}
    edges=np.array([e for e in boundary_edges(inverse[f[~removed]]) if tuple(sorted(e))not in original_edges])
    loops=loops_of(edges,welded)
    assert len(loops)==4 and removed.sum()==1335
    return prim,arrays,f,removed,welded,inverse,loops

def build(source,output,normal_finish=True):
    root=Path(__file__).resolve().parents[2]
    assert hashlib.sha256(source.read_bytes()).hexdigest()==BASE_SHA,'Wrong accepted source'
    assert source.resolve()!=output.resolve() and not output.resolve().is_relative_to(root/'assets')
    doc,binary=read_glb(source);doc=copy.deepcopy(doc)
    prim,arrays,f,removed,welded,inverse,loops=select(doc,binary)
    collar=smooth_collar(arrays,f[~removed],inverse,max(loops,key=len))
    v=arrays['POSITION'];representative=np.full(len(welded),-1,int)
    for vertex in np.unique(f[~removed]):representative[inverse[vertex]]=vertex
    additions={k:[]for k in arrays};cap_faces=[];total=len(v);cap_sources=[];crown_reports=[];cap_boundary_ids=[]
    for loop in loops:
        ids=representative[loop];boundary=v[ids]
        if len(loop)>10:
            bulge=.022 if len(loop)==102 else None
            points,crown_normals,tris,donors,stats=crown_patch(boundary,bulge)
            source_donors=ids[donors];crown_reports.append(stats)
            if len(loop)==93 and normal_finish:
                # The unchanged nonplanar underside triangulation carries a
                # shading-only diagonal ridge. A uniform area normal removes
                # that accidental stripe; the source seam still blends below.
                smooth_normal=np.cross(boundary-boundary.mean(0),np.roll(boundary,-1,axis=0)-boundary.mean(0)).sum(0)
                smooth_normal/=np.linalg.norm(smooth_normal);crown_normals[:]=smooth_normal
        else:
            points=boundary;tris,_=triangulate(points);source_donors=ids
            face_n=np.cross(points[tris[:,1]]-points[tris[:,0]],points[tris[:,2]]-points[tris[:,0]])
            crown_normals=np.broadcast_to(face_n.sum(0)/np.linalg.norm(face_n.sum(0)),points.shape).copy()
        for k,a in arrays.items():
            added=a[source_donors].copy()
            if k=='JOINTS_0':added[:]=[11,0,0,0]
            if k=='WEIGHTS_0':added[:]=[1,0,0,0]
            if k in ('JOINTS_1','WEIGHTS_1'):added[:]=0
            if k in ('JOINTS_0','JOINTS_1','WEIGHTS_0','WEIGHTS_1'):added[:len(ids)]=a[ids]
            if k=='POSITION':added=points.copy()
            # Small single atlas footprint from accepted pale gold armor.
            if k=='TEXCOORD_0':added[:]=[.242,.049]
            if k=='NORMAL':
                added=crown_normals.copy()
                distance=np.linalg.norm(points[:,None,:]-boundary[None,:,:],axis=2).min(1)
                mix=np.clip(distance/.009,0,1);mix=mix*mix*(3-2*mix)
                added=added*mix[:,None]+a[source_donors]*(1-mix[:,None])
                added/=np.maximum(np.linalg.norm(added,axis=1,keepdims=True),1e-12)
            additions[k].append(added)
        cap_boundary_ids.extend(range(total,total+len(ids)));cap_faces.append(tris+total);total+=len(points);cap_sources.extend(source_donors.tolist())
    writer=Writer(doc,binary)
    for k,idx in list(prim['attributes'].items()):
        meta=doc['accessors'][idx]
        prim['attributes'][k]=writer.add(np.concatenate([arrays[k]]+additions[k]),meta['type'],meta['componentType'])
    all_faces=np.concatenate([f[~removed]]+cap_faces)
    prim['indices']=writer.add(all_faces.reshape(-1,1),'SCALAR',5125)
    # Smooth 96x12 torus: 0.0038 tube / 0.078 major = 4.9%.
    major,tube=.078,.0038;center=np.array([.043,.442,.086])
    normal=np.array([0.,.92,.392]);normal/=np.linalg.norm(normal)
    axis=np.array([1.,0.,0.]);second=np.cross(normal,axis)
    ring_v=[];ring_n=[];ring_uv=[];ring_f=[]
    for i in range(96):
        theta=2*np.pi*i/96;radial=np.cos(theta)*axis+np.sin(theta)*second
        for j in range(12):
            phi=2*np.pi*j/12;n=np.cos(phi)*radial+np.sin(phi)*normal
            ring_v.append(center+major*radial+tube*n);ring_n.append(n);ring_uv.append([i/96,j/12])
            a=i*12+j;bb=((i+1)%96)*12+j;c=((i+1)%96)*12+(j+1)%12;dd=i*12+(j+1)%12
            ring_f.extend([[a,bb,c],[a,c,dd]])
    nr=len(ring_v);head=next(i for i,j in enumerate(doc['skins'][0]['joints'])if doc['nodes'][j].get('name')=='head')
    attrs={'POSITION':writer.add(ring_v,'VEC3'),'NORMAL':writer.add(ring_n,'VEC3'),'TEXCOORD_0':writer.add(ring_uv,'VEC2')}
    js=np.zeros((nr,4),np.uint16);js[:,0]=head;ws=np.zeros((nr,4),np.float32);ws[:,0]=1
    attrs['JOINTS_0']=writer.add(js,'VEC4',5123);attrs['WEIGHTS_0']=writer.add(ws,'VEC4')
    attrs['JOINTS_1']=writer.add(np.zeros((nr,4)),'VEC4',5123);attrs['WEIGHTS_1']=writer.add(np.zeros((nr,4)),'VEC4')
    attrs['COLOR_0']=writer.add(np.ones((nr,4)),'VEC4')
    mat=len(doc['materials']);doc['materials'].append({'name':'A04_ThinHalo','doubleSided':False,'pbrMetallicRoughness':{'baseColorFactor':[1.,.86,.42,1.],'metallicFactor':.2,'roughnessFactor':.28},'emissiveFactor':[.35,.22,.04]})
    doc['meshes'][0]['primitives'].append({'attributes':attrs,'indices':writer.add(np.asarray(ring_f).reshape(-1,1),'SCALAR',5125),'material':mat})
    output.parent.mkdir(parents=True,exist_ok=True);writer.save(output)
    report={'kind':'Uninstalled A04 CPU/source candidate; GPU/cloth/runtime pending','underside_normal_finish':normal_finish,'source_sha256':BASE_SHA,'candidate_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'crown_helper_sha256':hashlib.sha256(Path(__file__).with_name('ratnik_light_crown_patch.py').read_bytes()).hexdigest(),'removed_face_ids':np.flatnonzero(removed).tolist(),'removed_face_ids_sha256':hashlib.sha256(np.asarray(np.flatnonzero(removed),dtype='<u4').tobytes()).hexdigest(),'removed_triangles':int(removed.sum()),'retained_triangles':int((~removed).sum()),'cap_triangles':sum(len(x)for x in cap_faces),'cap_source_vertex_ids':cap_sources,'cap_boundary_new_vertex_ids':cap_boundary_ids,'cap_loops':len(loops),'crown_reconstruction':crown_reports,'crown_skin':'new crown interiors exactly head joint11 weight1; boundary exact original8weights; all source skin arrays unchanged','ring_triangles':len(ring_f),'ring_vertices':nr,'ring_center':center.tolist(),'ring_normal':normal.tolist(),'major_radius':major,'tube_radius':tube,'ring_head_joint':head,'original_binary_bytes_preserved':len(binary),'original_boundaries_preserved':True,'source_vertices_moved':len(collar['source_vertex_ids']),'collar':collar,'scope':'Only appended buffers/accessors/material, main primitive attribute/index references and additional halo primitive. Original source arrays except exact collar POSITION/NORMAL, CapeGPU, nodes, skeleton/rest/binds, clips, source materials/images retained exactly.'}
    output.with_suffix('.manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items()if not k.endswith('_ids') and k!='collar'},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--diagnostic-underside-normals',action='store_true',help='Reproduce geometry-identical pre-finish d389 normals for the equivalence contract');a=p.parse_args();build(a.source,a.output,not a.diagnostic_underside_normals)
