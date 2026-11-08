"""Independent protected-stream/geometry contract for the reopened A04 helmet."""
import argparse,copy,hashlib,json,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import read_glb,accessor
from remove_grifalon_gale_wind import boundary_edges
BASE='b209b4bad3ec5e2a4b02104993b7de1adbbdd1b59dba565c7f1e14270fe13df8'
FINAL='d51ab2dc59b810d39e2b7346fab0101256f44f421fdaa8ed4a538eb97cbf5a70'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def boundary(v,f):
 w,inv=np.unique(np.round(v,6),axis=0,return_inverse=True)
 return {tuple(sorted((tuple(w[a]),tuple(w[b]))))for a,b in boundary_edges(inv[f])}
def geometric_rows(v,f):
 return sorted(v[f].astype('<f4').reshape(len(f),9).view('V36').ravel().tolist())
def run(base,candidate,geometry,manifest,output):
 assert sha(base)==BASE and sha(candidate)==FINAL
 s,sb=read_glb(base);d,db=read_glb(candidate);g,gb=read_glb(geometry);m=json.loads(manifest.read_text())
 assert sha(candidate)==m['candidate_sha256']
 assert db[:len(sb)]==sb,'Protected immutable source BIN prefix'
 expected=copy.deepcopy(d)
 for name in ('accessors','bufferViews'):expected[name]=expected[name][:len(s[name])]
 expected['buffers']=copy.deepcopy(s['buffers']);expected['meshes'][0]['primitives']=copy.deepcopy(s['meshes'][0]['primitives'])
 assert expected==s,'Protected JSON: includes ring/CapeGPU/rig/rest/binds/clips/images/materials'
 sp=s['meshes'][0]['primitives'][0];cp=d['meshes'][0]['primitives'][0];gp=g['meshes'][0]['primitives'][0]
 sa={k:accessor(s,sb,i)for k,i in sp['attributes'].items()};ca={k:accessor(d,db,i)for k,i in cp['attributes'].items()}
 nv=m['source_vertices'];assert nv==84900
 for key,old in sa.items():assert ca[key][:nv].tobytes()==old[:nv].tobytes(),key+' source stream changed'
 sf=accessor(s,sb,sp['indices']).reshape(-1,3);cf=accessor(d,db,cp['indices']).reshape(-1,3)
 # Independently identify the high obsolete rim and the small palette seam.
 prior=sf[:114060];high=sa['POSITION'][prior][:,:,1].max(1)>.373;assert high.sum()==696
 kept=prior[~high];fc=sa['POSITION'][kept].mean(1)
 lip=(fc[:,0]>-.016)&(fc[:,0]<.026)&(fc[:,1]>.357)&(fc[:,1]<.371)&(fc[:,2]>.123)&(fc[:,2]<.131);assert lip.sum()==22
 nr=113342;assert np.array_equal(cf[:nr],kept[~lip])
 assert len(cf)-nr==3387 and np.isfinite(ca['POSITION']).all()
 edge=np.array(m['cap_boundary_new_vertex_ids']);donors=np.array(m['cap_source_vertex_ids']);local=edge-nv
 assert np.array_equal(ca['POSITION'][edge],sa['POSITION'][donors[local]])
 for key in ('JOINTS_0','JOINTS_1','WEIGHTS_0','WEIGHTS_1'):
  assert ca[key][edge].tobytes()==sa[key][donors[local]].tobytes(),key+' exact8 seam influences'
 interior=np.ones(len(donors),bool);interior[local]=False
 assert (ca['JOINTS_0'][nv:][interior]==[11,0,0,0]).all()
 assert (ca['WEIGHTS_0'][nv:][interior]==[1,0,0,0]).all()
 for key in ('JOINTS_1','WEIGHTS_1'):assert(ca[key][nv:][interior]==0).all()
 assert boundary(sa['POSITION'],sf)==boundary(ca['POSITION'],cf),'New unmatched external boundary'
 gv=accessor(g,gb,gp['attributes']['POSITION']);gf=accessor(g,gb,gp['indices']).reshape(-1,3)
 assert geometric_rows(gv,gf)==geometric_rows(ca['POSITION'],cf),'Finish must preserve every geometric triangle'
 norms=np.linalg.norm(ca['NORMAL'][nv:],axis=1);assert abs(norms-1).max()<1e-5
 report={'status':'PASS','scope':'Exact protected-stream and local topology/skin contract; three measured forehead contacts are separate from this PASS','source_sha256':BASE,'candidate_sha256':FINAL,'source_BINARY_prefix_exact_bytes':len(sb),'source_vertices_all_attributes_exact':nv,'source_UV_skin_normal_position_streams_exact':True,'rig_rest_binds_clips_materials_images_ring_CapeGPU_exact':True,'source_high_false_rim_triangles_removed':696,'local_palette_seam_triangles_referenced_as_exact_geometry8weights_copies':22,'retained_source_triangles_exact':nr,'replacement_triangles':3387,'replacement_vertices':len(donors),'exact_source_seam_and_palette_vertices':len(edge),'interior_head11_weight1_vertices':int(interior.sum()),'new_unmatched_boundary_edges':0,'geometry_identity_with_raw_BVH_reference':sha(geometry),'finish_all_geometric_triangles_identical':True}
 output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__)
 for key in ('base','candidate','geometry','manifest','output'):p.add_argument(key,type=Path)
 a=p.parse_args();run(a.base,a.candidate,a.geometry,a.manifest,a.output)
