"""Narrow exact-byte contract for Gale's weights-only tail surface repair."""
import hashlib,json,struct,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import accessor,read_glb
from repair_grifalon_gale_tail import SOURCE_SHA


def stream_ranges(raw,doc,attributes):
    pos=12
    while struct.unpack_from('<I',raw,pos+4)[0]!=0x004e4942:pos+=8+struct.unpack_from('<I',raw,pos)[0]
    offset=pos+8;ranges=[]
    for index in attributes:
        a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']]
        size={5126:4,5123:2}[a['componentType']]*4
        start=offset+view.get('byteOffset',0)+a.get('byteOffset',0)
        for i in range(a['count']):ranges.append((start+i*view.get('byteStride',size),size))
    return ranges


def dense(doc,binary):
    p=doc['meshes'][0]['primitives'][0];a=p['attributes'];j=np.c_[accessor(doc,binary,a['JOINTS_0']),accessor(doc,binary,a['JOINTS_1'])].astype(int);w=np.c_[accessor(doc,binary,a['WEIGHTS_0']),accessor(doc,binary,a['WEIGHTS_1'])]
    result=np.zeros((len(j),len(doc['skins'][0]['joints'])),dtype=float)
    for k in range(8):np.add.at(result,(np.arange(len(j)),j[:,k]),w[:,k])
    return result,j,w


def check(source,candidate,manifest):
    report=json.loads(manifest.read_text());br=source.read_bytes();cr=candidate.read_bytes()
    assert hashlib.sha256(br).hexdigest()==SOURCE_SHA==report['source_sha256']
    assert hashlib.sha256(cr).hexdigest()==report['output_sha256']
    bd,bb=read_glb(source);cd,cb=read_glb(candidate)
    assert bd==cd,'Any GLB document change is outside this weights-only contract'
    attrs=bd['meshes'][0]['primitives'][0]['attributes']
    allowed=np.zeros(len(br),dtype=bool)
    for offset,size in stream_ranges(br,bd,[attrs[n]for n in ['JOINTS_0','JOINTS_1','WEIGHTS_0','WEIGHTS_1']]):allowed[offset:offset+size]=True
    assert len(br)==len(cr)
    assert np.array_equal(np.frombuffer(br,'u1')[~allowed],np.frombuffer(cr,'u1')[~allowed]),'Non-skin binary/header/document changed'
    before,bj,bw=dense(bd,bb);after,cj,cw=dense(cd,cb)
    assert np.isfinite(cw).all() and np.min(cw)>=0
    assert np.max(np.abs(cw.sum(1)-1))<2e-6
    assert np.max(np.count_nonzero(cw,axis=1))<=8
    protected=report['protected_vertex_ids']
    assert np.array_equal(bj[protected],cj[protected]) and np.array_equal(bw[protected],cw[protected]),'Protected real wing/body/leg stream changed'
    names=report['joint_names'];tail=[names.index('tail'+str(k))for k in range(1,5)];right=[names.index(n)for n in ['wing.R','wingtip.R','wingfan.R']]
    other=[i for i in range(len(names))if i not in tail+right]
    assert np.max(np.abs(before[:,other]-after[:,other]))<3e-8,'Unrelated bone masses changed'
    assert np.max(after[:,right]-before[:,right])<3e-8,'New erroneous right wing influence'
    core=np.array(report['wrong_core_vertex_ids']);assert np.max(after[core][:,right])<1e-7
    pos=accessor(bd,bb,attrs['POSITION']);_,inv=np.unique(np.round(pos,6),axis=0,return_inverse=True)
    lo=np.full((inv.max()+1,after.shape[1]),np.inf);hi=np.full_like(lo,-np.inf)
    np.minimum.at(lo,inv,after);np.maximum.at(hi,inv,after)
    seam=float(np.max(hi-lo));assert seam<2e-6,('UV weld weight mismatch',seam)
    changed=np.flatnonzero(np.any(bj!=cj,axis=1)|np.any(bw!=cw,axis=1))
    assert np.array_equal(changed,np.array(report['changed_vertex_ids']))
    p=bd['meshes'][0]['primitives'][0];f=accessor(bd,bb,p['indices']).reshape(-1,3)
    assert len(f)==127686+128
    # A rigid tail matrix must move both original and repaired regions alike.
    # Every tail joint has the same skin matrix after runtime local-rest locks.
    skin=np.tile(np.eye(4),(len(names),1,1));angle=.55;rot=np.array([[np.cos(angle),0,np.sin(angle)],[0,1,0],[-np.sin(angle),0,np.cos(angle)]]);translation=np.array([.03,.01,-.02])
    for i in tail:skin[i,:3,:3]=rot;skin[i,:3,3]=translation
    points=np.c_[pos,np.ones(len(pos))];posed=np.einsum('nijk,nk->nij',skin[cj],points)[:,:,:3];posed=(posed*cw[:,:,None]).sum(1)
    full=core[after[core][:,tail].sum(1)>.99999]
    expected=pos[full]@rot.T+translation
    rigid_error=float(np.max(np.linalg.norm(posed[full]-expected,axis=1)))
    assert rigid_error<2e-6
    movement=np.linalg.norm(posed[full]-pos[full],axis=1)
    result=dict(failures=0,triangles=len(f),wind_caps_preserved=128,vertices=len(pos),changed_vertices=len(changed),protected_vertices=len(protected),non_skin_bytes_exact=True,GLB_document_exact=True,all_geometry_uv_normals_indices_skeleton_binds_clips_images_exact=True,max_normalization_error=float(np.max(np.abs(cw.sum(1)-1))),max_weld_mass_error=seam,wrong_core_vertices=len(core),wrong_core_max_right_wing_mass=float(after[core][:,right].max()),full_rigid_core_vertices=len(full),rigid_tail1_skin_error=rigid_error,core_motion_min_max=[float(movement.min()),float(movement.max())],core_posed_bbox=[posed[full].min(0).tolist(),posed[full].max(0).tolist()],core_rest_bbox=[pos[full].min(0).tolist(),pos[full].max(0).tolist()],scope='Synthetic rigid-tail surface equivalence; source numeric contract, not real runtime GPU check')
    candidate.with_suffix('.integrity.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))

if __name__=='__main__':check(*map(Path,sys.argv[1:4]))
