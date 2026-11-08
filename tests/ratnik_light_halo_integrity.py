"""A04 exact-byte preservation plus local topology/clearance contract. No GPU."""
import argparse,copy,hashlib,json,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import read_glb,accessor
from remove_grifalon_gale_wind import boundary_edges
from review_levian_gale_wind import normalization_bounds
import audit_20261106 as raw
SOURCE_SHA='454e8442b83fe7fd618d0bc0338dfc8b51b1daabaa49b4a5237dcb669598f727'

def edges(v,f):
    w,inv=np.unique(np.round(v,6),axis=0,return_inverse=True)
    return {tuple(sorted((tuple(w[a]),tuple(w[b]))))for a,b in boundary_edges(inv[f])}

def run(source,candidate,manifest,out):
    m=json.loads(manifest.read_text());s,sb=read_glb(source);d,db=read_glb(candidate)
    assert hashlib.sha256(source.read_bytes()).hexdigest()==SOURCE_SHA==m['source_sha256']
    assert hashlib.sha256(candidate.read_bytes()).hexdigest()==m['candidate_sha256']
    assert db[:len(sb)]==sb,'Original buffer prefix changed'
    assert len(db)>len(sb)
    expected=copy.deepcopy(d)
    expected['accessors']=expected['accessors'][:len(s['accessors'])]
    expected['bufferViews']=expected['bufferViews'][:len(s['bufferViews'])]
    expected['materials']=expected['materials'][:len(s['materials'])]
    expected['buffers']=copy.deepcopy(s['buffers'])
    expected['meshes'][0]['primitives']=copy.deepcopy(s['meshes'][0]['primitives'])
    assert expected==s,'JSON outside appended views/accessors/material and Mesh0 primitives changed'
    sp=s['meshes'][0]['primitives'][0];cp=d['meshes'][0]['primitives'][0];rp=d['meshes'][0]['primitives'][1]
    sa={k:accessor(s,sb,i)for k,i in sp['attributes'].items()};ca={k:accessor(d,db,i)for k,i in cp['attributes'].items()}
    sf=accessor(s,sb,sp['indices']).reshape(-1,3);cf=accessor(d,db,cp['indices']).reshape(-1,3)
    removed=np.array(m['removed_face_ids']);assert len(removed)==1335 and len(np.unique(removed))==1335
    assert hashlib.sha256(np.asarray(removed,dtype='<u4').tobytes()).hexdigest()=='78f78b71b6d91f0fa3a190158461c001283e1f23de9e5385755139415fda65eb','Different semantic removal mask'
    kept=np.ones(len(sf),bool);kept[removed]=False
    assert np.array_equal(cf[:kept.sum()],sf[kept])
    cap_ids=np.array(m['cap_source_vertex_ids']);nv=len(sa['POSITION'])
    for k,arr in sa.items():
        assert ca[k][:nv].tobytes()==arr.tobytes(),k+' original prefix'
        assert len(ca[k])==nv+len(cap_ids)
        if k not in ('TEXCOORD_0','NORMAL'):
            assert ca[k][nv:].tobytes()==arr[cap_ids].tobytes(),k+' cap inherited attributes'
    for k in ('NORMAL','POSITION','TEXCOORD_0','WEIGHTS_0','WEIGHTS_1'):
        assert np.isfinite(ca[k]).all()
    caps=cf[kept.sum():];assert len(caps)==m['cap_triangles'] and (caps>=nv).all()
    area=np.linalg.norm(np.cross(ca['POSITION'][caps[:,1]]-ca['POSITION'][caps[:,0]],ca['POSITION'][caps[:,2]]-ca['POSITION'][caps[:,0]]),axis=1)/2
    assert (area>1e-12).all(),'Degenerate new cap'
    assert edges(sa['POSITION'],sf)==edges(ca['POSITION'],cf),'New unmatched cut edge'
    rv=accessor(d,db,rp['attributes']['POSITION']);rf=accessor(d,db,rp['indices']).reshape(-1,3)
    rn=accessor(d,db,rp['attributes']['NORMAL']);assert len(rv)==1152 and len(rf)==2304
    assert not edges(rv,rf)
    ri=accessor(d,db,rp['attributes']['JOINTS_0']);rw=accessor(d,db,rp['attributes']['WEIGHTS_0'])
    assert (ri[:,0]==11).all() and (rw[:,0]==1).all() and (rw[:,1:]==0).all()
    assert s['nodes'][s['skins'][0]['joints'][11]]['name']=='head'
    normal=np.array(m['ring_normal']);used=ca['POSITION'][np.unique(cf)]
    gap=float((rv@normal).min()-(used@normal).max());assert gap>.015,'Ring not separated from head/body by plane'
    winding=np.einsum('ij,ij->i',np.cross(rv[rf[:,1]]-rv[rf[:,0]],rv[rf[:,2]]-rv[rf[:,0]]),rn[rf].mean(1));assert(winding>0).all()
    inner_radius=m['major_radius']-m['tube_radius'];assert inner_radius>.074
    norms={'source':normalization_bounds(raw.read_glb(source)),'candidate':normalization_bounds(raw.read_glb(candidate))}
    for mode in ('all_accessor_positions','referenced_triangle_positions'):
        assert norms['source'][mode]['build_scale']==norms['candidate'][mode]['build_scale']
        assert norms['source'][mode]['build_position']==norms['candidate'][mode]['build_position']
    result={'status':'PASS','kind':'CPU source integrity; not Godot runtime/GPU/cloth or full motion acceptance','source_sha256':SOURCE_SHA,'candidate_sha256':m['candidate_sha256'],'original_binary_prefix_bytes_exact':len(sb),'original_nodes_skins_binds_animation_material_images_exact':True,'CapeGPU_json_and_buffers_exact':True,'retained_source_triangles_exact':int(kept.sum()),'all_original_attribute_prefixes_exact':True,'cap_triangles':len(caps),'caps_min_area':float(area.min()),'cap_skin_inherited_from_source_boundary':True,'new_unmatched_boundary_edges':0,'ring_triangles':len(rf),'ring_source_rest_plane_clearance':gap,'ring_open_center_radius':inner_radius,'ring_closed_outward_and_head_weight_one':True,'normalization':norms,'limitations':['No Godot import/runtime, actual cloth, animation, support, arena lighting or emitted glow evaluated.','Boundary equality is not an all-surface intersection proof.','Source mask follows baked brown disc paint; adjoining helmet border needs independent six-view artistic review.','Added ring increases raw AABB height by 0.04079461; current CPU build formula gives identical scale/offset, actual Godot import not executed.']}
    out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items()if k!='normalization'},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('candidate',type=Path);p.add_argument('manifest',type=Path);p.add_argument('output',type=Path);a=p.parse_args();run(a.source,a.candidate,a.manifest,a.output)
