"""A04 reconstructed crown: exact protected source, bounded collar, closed patch.

No runtime evidence: follow with imported actual-pose/GPU acceptance separately.
"""
import argparse,copy,hashlib,json,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import accessor,read_glb
from remove_grifalon_gale_wind import boundary_edges
from review_levian_gale_wind import normalization_bounds
import audit_20261106 as raw
BASE_SHA='454e8442b83fe7fd618d0bc0338dfc8b51b1daabaa49b4a5237dcb669598f727'
MASK_SHA='78f78b71b6d91f0fa3a190158461c001283e1f23de9e5385755139415fda65eb'


def boundaries(v,f):
    w,inv=np.unique(np.round(v,6),axis=0,return_inverse=True)
    return {tuple(sorted((tuple(w[a]),tuple(w[b]))))for a,b in boundary_edges(inv[f])}


def run(source,candidate,output):
    s,sb=read_glb(source);d,db=read_glb(candidate);m=json.loads(candidate.with_suffix('.manifest.json').read_text())
    assert hashlib.sha256(source.read_bytes()).hexdigest()==BASE_SHA==m['source_sha256']
    sha=hashlib.sha256(candidate.read_bytes()).hexdigest();assert sha==m['candidate_sha256']
    assert db[:len(sb)]==sb
    expected=copy.deepcopy(d)
    for name in ('accessors','bufferViews','materials'):expected[name]=expected[name][:len(s[name])]
    expected['buffers']=copy.deepcopy(s['buffers']);expected['meshes'][0]['primitives']=copy.deepcopy(s['meshes'][0]['primitives'])
    assert expected==s,'Changed protected JSON (includes CapeGPU/nodes/skins/clips/images)'
    sp=s['meshes'][0]['primitives'][0];cp=d['meshes'][0]['primitives'][0];rp=d['meshes'][0]['primitives'][1]
    sa={k:accessor(s,sb,i)for k,i in sp['attributes'].items()};ca={k:accessor(d,db,i)for k,i in cp['attributes'].items()}
    sv=sa['POSITION'];nv=len(sv);removed=np.array(m['removed_face_ids'],dtype='<u4')
    assert hashlib.sha256(removed.tobytes()).hexdigest()==MASK_SHA and len(removed)==1335
    sf=accessor(s,sb,sp['indices']).reshape(-1,3);cf=accessor(d,db,cp['indices']).reshape(-1,3)
    kept=np.ones(len(sf),bool);kept[removed]=False;nr=int(kept.sum());assert nr==114060 and np.array_equal(cf[:nr],sf[kept])
    collar=np.array(m['collar']['source_vertex_ids']);protected=np.ones(nv,bool);protected[collar]=False
    assert len(collar)==315 and len(np.unique(collar))==315
    assert hashlib.sha256(collar.astype('<u4').tobytes()).hexdigest()=='586dc67610957eeb70514e06d966858737737a597e9f8d2cfdd2fae740a5963b','Different source collar whitelist'
    assert m['collar']['geodesic_radius']==.008
    # The immutable source hash and independently asserted exact geometry whitelist
    # bound source changes to this inner helmet seam, preserving horns/body/cape.
    assert np.array_equal(collar,np.flatnonzero(np.any(ca['POSITION'][:nv]!=sv,axis=1)))
    delta=np.linalg.norm(ca['POSITION'][:nv]-sv,axis=1);assert delta.max()<=.0030001
    assert (sv[collar,1]>.32).all() and (sv[collar,1]<.4356).all()
    for key,a in sa.items():
        if key in ('POSITION','NORMAL'):assert ca[key][:nv][protected].tobytes()==a[protected].tobytes(),key
        else:assert ca[key][:nv].tobytes()==a.tobytes(),key
        assert np.isfinite(ca[key]).all(),key
    # Retained collar triangles cannot invert or collapse under the local fairing.
    rf=sf[kept];active=np.isin(rf,collar).any(1);old=sv[rf[active]];new=ca['POSITION'][rf[active]]
    on=np.cross(old[:,1]-old[:,0],old[:,2]-old[:,0]);nn=np.cross(new[:,1]-new[:,0],new[:,2]-new[:,0]);oa=np.linalg.norm(on,axis=1);na=np.linalg.norm(nn,axis=1)
    ratios=na/oa;cos=np.einsum('ij,ij->i',on,nn)/(oa*na)
    assert ratios.min()>.35 and ratios.max()<2.5 and cos.min()>.5
    cap_faces=cf[nr:];assert len(cap_faces)==5403 and (cap_faces>=nv).all()
    donors=np.array(m['cap_source_vertex_ids']);edge_ids=np.array(m['cap_boundary_new_vertex_ids']);edge_local=edge_ids-nv
    assert len(edge_ids)==201
    interiors=np.ones(len(donors),bool);interiors[edge_local]=False
    for key in ('JOINTS_0','JOINTS_1','WEIGHTS_0','WEIGHTS_1'):
        assert ca[key][edge_ids].tobytes()==sa[key][donors[edge_local]].tobytes(),key+' seam'
    assert np.array_equal(ca['POSITION'][edge_ids],ca['POSITION'][donors[edge_local]])
    assert (ca['JOINTS_0'][nv:][interiors]==[11,0,0,0]).all()
    assert (ca['WEIGHTS_0'][nv:][interiors]==[1,0,0,0]).all()
    for key in ('JOINTS_1','WEIGHTS_1'):assert(ca[key][nv:][interiors]==0).all()
    assert boundaries(sv,sf)==boundaries(ca['POSITION'],cf),'Unclosed new crown edge or changed old body/cape edge'
    pts=ca['POSITION'][cap_faces];areas=np.linalg.norm(np.cross(pts[:,1]-pts[:,0],pts[:,2]-pts[:,0]),axis=1)/2
    assert areas.min()>1e-13
    assert np.max(abs(np.linalg.norm(ca['NORMAL'][nv:],axis=1)-1))<1e-5
    rv=accessor(d,db,rp['attributes']['POSITION']);rf=accessor(d,db,rp['indices']).reshape(-1,3)
    assert len(rv)==1152 and len(rf)==2304 and not boundaries(rv,rf)
    normal=np.array(m['ring_normal']);gap=float((rv@normal).min()-(ca['POSITION'][np.unique(cf)]@normal).max());assert gap>.015
    norms={'source':normalization_bounds(raw.read_glb(source)),'candidate':normalization_bounds(raw.read_glb(candidate))}
    for mode in ('all_accessor_positions','referenced_triangle_positions'):
        assert norms['source'][mode]['build_scale']==norms['candidate'][mode]['build_scale']
        assert norms['source'][mode]['build_position']==norms['candidate'][mode]['build_position']
    report={'status':'PASS','kind':'CPU raw-rest source/collar/crown integrity, actual imported poses and GPU acceptance separate','source_sha256':BASE_SHA,'candidate_sha256':sha,'source_binary_prefix_bytes_exact':len(sb),'source_uv_skin_rig_binds_animation_images_CapeGPU_exact':True,'retained_source_face_indices_exact':nr,'source_collar_position_normal_vertices':len(collar),'source_collar_vertex_ids_sha256':hashlib.sha256(collar.astype('<u4').tobytes()).hexdigest(),'source_outside_collar_all_attributes_exact':True,'source_collar_max_displacement':float(delta.max()),'source_collar_changed_triangles':int(active.sum()),'source_collar_min_area_ratio':float(ratios.min()),'source_collar_max_area_ratio':float(ratios.max()),'source_collar_min_normal_cosine':float(cos.min()),'new_crown_triangles':len(cap_faces),'new_crown_vertices':len(donors),'new_crown_min_area':float(areas.min()),'new_crown_boundary_vertices_exact_source_position_and8weights':len(edge_ids),'new_crown_interior_head_weight_one':int(interiors.sum()),'new_unmatched_boundary_edges':0,'ring_raw_rest_plane_clearance':gap,'normalization':norms}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items()if k!='normalization'},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('candidate',type=Path);p.add_argument('output',type=Path);a=p.parse_args();run(a.source,a.candidate,a.output)
