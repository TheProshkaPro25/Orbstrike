"""Strict A03 local-graft contract, no renderer or production mutation.

python tests/kolossar_shadow_graft_integrity.py SOURCE CANDIDATE MANIFEST BVH_REPORT REPORT
"""
import hashlib,json,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import accessor,read_glb
from remove_grifalon_gale_wind import boundary_edges,components
from remove_kolossar_shadow_smoke import BASE_SHA


def check(source,candidate,manifest_file,bvh_file,output):
    sha=hashlib.sha256(candidate.read_bytes()).hexdigest();m=json.loads(manifest_file.read_text());bvh=json.loads(bvh_file.read_text())
    assert hashlib.sha256(source.read_bytes()).hexdigest()==BASE_SHA==m['source_sha256']
    assert sha==m['candidate_sha256']==bvh['candidate_sha256'] and bvh['accepted_geometry']
    d,b=read_glb(source);a,c=read_glb(candidate);assert c[:len(b)]==b
    for key in d:
        if key not in ('meshes','accessors','bufferViews','buffers'):assert a[key]==d[key],key
    assert a['accessors'][:len(d['accessors'])]==d['accessors'];assert a['bufferViews'][:len(d['bufferViews'])]==d['bufferViews']
    for i in range(len(d['accessors'])):assert accessor(d,b,i).tobytes()==accessor(a,c,i).tobytes(),i
    assert len(a['meshes'])==len(d['meshes'])==1
    assert {k:v for k,v in a['meshes'][0].items()if k!='primitives'}=={k:v for k,v in d['meshes'][0].items()if k!='primitives'}
    p=d['meshes'][0]['primitives'][0];main,new=a['meshes'][0]['primitives'];assert {k:v for k,v in main.items()if k!='indices'}=={k:v for k,v in p.items()if k!='indices'}
    source_a={k:accessor(d,b,i)for k,i in p['attributes'].items()};new_a={k:accessor(a,c,i)for k,i in new['attributes'].items()}
    v=source_a['POSITION'];f=accessor(d,b,p['indices']).reshape(-1,3);kf=accessor(a,c,main['indices']).reshape(-1,3);nf=accessor(a,c,new['indices']).reshape(-1,3);nv=new_a['POSITION']
    retained=np.asarray(m['retained_source_face_ids']);removed=np.asarray(m['removed_source_face_ids']);recolor=np.asarray(m['recolored_original_face_ids']);roi=np.asarray(m['roi_source_face_ids']);newids=np.asarray(m['new_surface_source_face_ids'])
    assert np.array_equal(np.sort(np.concatenate([retained,removed])),np.arange(len(f)))
    assert np.array_equal(kf,f[retained]);assert set(removed)<=set(roi)|set(recolor)
    assert set(np.flatnonzero(~np.isin(np.arange(len(f)),roi)))<=set(retained)|set(recolor)
    assert set(newids[newids>=0])<=set(roi)|set(recolor)
    # Final4020root faces are exact original triangles: UV is their sole change.
    assert np.array_equal(newids[-len(recolor):],recolor)
    root_vertices=nf[-len(recolor):]
    for key,vals in source_a.items():
        if key!='TEXCOORD_0':assert np.array_equal(new_a[key][root_vertices],vals[f[recolor]]),key
    allv=np.concatenate([v,nv]);allf=np.concatenate([kf,nf+len(v)]);used=np.unique(allf);welded,inv=np.unique(np.round(allv,6),axis=0,return_inverse=True)
    assert np.isfinite(allv).all() and np.array_equal(allv.min(0),v.min(0)) and np.array_equal(allv.max(0),v.max(0))
    assert len(boundary_edges(inv[allf]))==0
    labels=components(inv[allf],len(welded));assert len(np.unique(labels[inv[allf]].ravel()))==1
    def topology(points,faces):
        unique,inverse=np.unique(np.round(points,6),axis=0,return_inverse=True)
        edges=np.sort(inverse[np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]])],1);edges,counts=np.unique(edges,axis=0,return_counts=True)
        nm={tuple(unique[e].ravel())for e in edges[counts>2]}
        return nm,int(counts.max())
    old_nm,_=topology(v,f);new_nm,maxval=topology(allv,allf);assert new_nm==old_nm
    areas=np.linalg.norm(np.cross(nv[nf[:,1]]-nv[nf[:,0]],nv[nf[:,2]]-nv[nf[:,0]]),axis=1)*.5;assert (areas>1e-12).all()
    nj=len(d['skins'][0]['joints'])
    def decode(attrs):
        out=np.zeros((len(attrs['POSITION']),nj));row=np.repeat(np.arange(len(out)),4)
        for index in (0,1):np.add.at(out,(row,attrs[f'JOINTS_{index}'].ravel()),attrs[f'WEIGHTS_{index}'].ravel())
        return out
    weights=np.concatenate([decode(source_a),decode(new_a)]);assert np.max(abs(weights[used].sum(1)-1))<2e-6
    low=np.full((len(welded),nj),np.inf);high=np.full((len(welded),nj),-np.inf)
    np.minimum.at(low,inv[used],weights[used]);np.maximum.at(high,inv[used],weights[used])
    seam_groups=np.intersect1d(inv[np.unique(kf)],inv[nf.ravel()+len(v)])
    seam_error=float(np.max(high[seam_groups]-low[seam_groups]));assert seam_error<2e-6
    result={'status':'PASS_CPU_GEOMETRY_AND_PRESERVATION','source_sha256':BASE_SHA,'candidate_sha256':sha,
            'source_accessor_count_byte_exact':len(d['accessors']),'source_binary_prefix_exact':True,
            'nodes_rest_skin_binds_clips_images_materials_extras_exact':True,'outside_whitelist_faces_attributes_exact':True,
            'retained_source_triangles':len(kf),'new_surface_triangles':len(nf),'clipped_source_triangles':m['clipped_source_triangles'],
            'caps':m['new_cap_triangles'],'recolored_root_triangles_geometry_normals_8weights_exact':len(recolor),
            'root_change':'UV only, dark local armor sample; no texture image modified',
            'boundary_edges':0,'active_components':1,'original_nonmanifold_edges':len(old_nm),'new_nonmanifold_edges':0,
            'maximum_welded_edge_face_count':maxval,'new_degenerate_triangles':int((areas<=1e-12).sum()),
            'new_nonadjacent_intersections':bvh['nonadjacent_pairs_touching_caps'],'body_new_seam_max_skin_weight_delta':seam_error,
            'all_accessor_bounds_exact':True,'runtime_import_support_animation_gpu_executed':False,
            'scope':'CPU raw-rest proof only. Animation/support acceptance is a separate required check.'}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':check(*map(Path,sys.argv[1:6]))
