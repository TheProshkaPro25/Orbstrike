"""A03 rejected prototype: authored shoulder-local cut, uninstalled only.

A connected neutral material region is restricted to two reviewed shoulder bounds.
This is not a global color deletion. All source vertex streams remain unchanged;
new attachment caps are separate, weight-matched boundary copies. No production write.
"""
import argparse
import copy
import hashlib
import io
import json
from pathlib import Path
import numpy as np
from PIL import Image
from inspect_geometry import accessor, read_glb
from remove_grifalon_gale_wind import components, boundary_edges, loops_of, triangulate
from upgrade_rigs import Writer

BASE_SHA = '6ea6f89a1f2632961e66821d504c57a219952f27e8f0974b4ebc07503ab1462c'


def locate(doc, binary):
    prim = doc['meshes'][0]['primitives'][0]
    arrays = {k: accessor(doc,binary,i) for k,i in prim['attributes'].items()}
    v=arrays['POSITION']; faces=accessor(doc,binary,prim['indices']).reshape(-1,3)
    welded, inverse=np.unique(np.round(v,6),axis=0,return_inverse=True)
    assert len(faces)==149994
    labels=components(inverse[faces],len(welded))[inverse[faces[:,0]]]
    assert len(np.unique(labels))==1, 'Expected fused single source component'
    mat=doc['materials'][prim['material']]
    image=doc['images'][doc['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
    view=doc['bufferViews'][image['bufferView']];start=view.get('byteOffset',0)
    pixels=np.asarray(Image.open(io.BytesIO(binary[start:start+view['byteLength']])).convert('RGB'))/255
    h,w=pixels.shape[:2];uv=arrays['TEXCOORD_0'][faces].mean(1)
    rgb=pixels[np.clip((uv[:,1]*h).astype(int),0,h-1),np.clip((uv[:,0]*w).astype(int),0,w-1)]
    value=rgb.max(1);sat=(value-rgb.min(1))/np.maximum(value,.001)
    q=v[faces].mean(1)
    # Artist-reviewed four-sided masks: shoulder-only neutral smoke. The head,
    # neck, horn roots, breastplate, purple shoulder armor and all lower body
    # are excluded spatially or by their non-neutral material.
    shoulder=((q[:,0]<-.13)|(q[:,0]>.23))&(q[:,1]>.205)
    neutral=shoulder&(sat<.40)&(value>.10)
    labels=components(inverse[faces[neutral]],len(welded))[inverse[faces[:,0]]]
    keys,counts=np.unique(labels[neutral],return_counts=True)
    selected=keys[counts>4000]
    assert sorted(counts[counts>4000].tolist())==[4940,10052]
    removed=neutral&np.isin(labels,selected)
    labels=components(inverse[faces[~removed]],len(welded))[inverse[faces[:,0]]]
    keys,counts=np.unique(labels[~removed],return_counts=True)
    removed |= labels!=keys[np.argmax(counts)]  # enclosed smoke paint flecks only
    assert removed.sum()==15169
    assert not np.any(removed&(q[:,1]<.198))
    assert not np.any(removed&((q[:,0]>=-.125)&(q[:,0]<=.225)))
    return prim,arrays,faces,welded,inverse,removed,rgb,uv


def build(source,output):
    assert source.resolve()!=output.resolve()
    assert 'assets/creatures_hd' not in str(output), 'Candidate path required'
    sha=hashlib.sha256(source.read_bytes()).hexdigest()
    assert sha==BASE_SHA, 'Source differs from reviewed accepted baseline'
    original,binary=read_glb(source);doc=copy.deepcopy(original)
    prim,arrays,faces,welded,inverse,removed,rgb,uv=locate(doc,binary)
    kept=faces[~removed];loops=loops_of(boundary_edges(inverse[kept]),welded)
    representative=np.full(len(welded),-1,dtype=int)
    for vertex in np.unique(kept):representative[inverse[vertex]]=vertex
    additions={k:[] for k in arrays};caps=[];vertex_ids=[];cap_diagnostics=[];total=0
    q=arrays['POSITION'][faces].mean(1);value=rgb.max(1);sat=(value-rgb.min(1))/np.maximum(value,.001)
    dark=~removed&(q[:,1]>.14)&(q[:,1]<.25)&(value>.035)&(value<.20)&(sat>.30)
    for loop in loops:
        ids=representative[loop];points=arrays['POSITION'][ids]
        cap,projection=triangulate(points)
        candidates=np.flatnonzero(dark)
        nearest=candidates[np.argmin(np.linalg.norm(q[candidates]-points.mean(0),axis=1))]
        for key,values in arrays.items():
            copied=values[ids].copy()
            if key=='TEXCOORD_0':copied[:]=uv[nearest]
            if key=='NORMAL':
                # Area-weighted cap normal, with source boundary normals retained
                # only as fallback on a numerically null patch.
                ns=np.cross(points[cap[:,1]]-points[cap[:,0]],points[cap[:,2]]-points[cap[:,0]])
                normals=np.zeros_like(points)
                for corner in range(3):np.add.at(normals,cap[:,corner],ns)
                lengths=np.linalg.norm(normals,axis=1)
                good=lengths>1e-12;copied[good]=normals[good]/lengths[good,None]
            additions[key].append(copied)
        caps.append(cap+total);total+=len(ids);vertex_ids.extend(ids.tolist())
        cap_diagnostics.append({'vertices':len(ids),'triangles':len(cap),'source_uv_face':int(nearest),'sample_rgb':rgb[nearest].tolist()})
    writer=Writer(doc,binary)
    # Existing vertex streams, skin and all clips stay byte-identical. Retaining
    # unused source points also preserves the existing mesh AABB/build scale.
    prim['indices']=writer.add(kept.ravel()[:,None],'SCALAR',5125)
    cap_prim={'attributes':{},'material':prim['material'],'mode':4}
    for key,values in arrays.items():
        meta=doc['accessors'][prim['attributes'][key]]
        cap_prim['attributes'][key]=writer.add(np.concatenate(additions[key]),meta['type'],meta['componentType'])
    cap_faces=np.concatenate(caps);cap_prim['indices']=writer.add(cap_faces.ravel()[:,None],'SCALAR',5125)
    doc['meshes'][0]['primitives'].append(cap_prim)
    output.parent.mkdir(parents=True,exist_ok=True);writer.save(output)
    all_positions=np.concatenate([arrays['POSITION'],np.concatenate(additions['POSITION'])])
    all_faces=np.concatenate([kept,cap_faces+len(arrays['POSITION'])])
    _,iv=np.unique(np.round(all_positions,6),axis=0,return_inverse=True)
    assert len(boundary_edges(iv[all_faces]))==0
    report={'status':'REJECTED_PROTOTYPE','geometry_note':'Planar caps have48 nonadjacent intersections and23 new nonmanifold edges. No install.', 'source_sha256':sha,'candidate_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'source_triangles':len(faces),'removed_smoke_triangles':int(removed.sum()),'retained_source_triangles':len(kept),
            'cap_triangles':len(cap_faces),'cap_vertices':total,'cap_loops':len(loops),'boundary_edges':0,
            'source_vertex_streams_exact':True,'source_nodes_skin_clips_material_images_exact':True,
            'unused_source_positions_retained_for_identical_aabb':True,
            'removed_source_face_ids':np.flatnonzero(removed).tolist(),'cap_vertex_source_ids':vertex_ids,
            'caps':cap_diagnostics,'scope':'CPU raw-rest only; no runtime/GPU/production installation'}
    output.with_suffix('.removal.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items()if not k.endswith('_ids')},indent=2),flush=True)

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args();build(args.source,args.output)
