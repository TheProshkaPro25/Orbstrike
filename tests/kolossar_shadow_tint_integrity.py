"""Strict source-preserving A03 material-only candidate contract.

python tests/kolossar_shadow_tint_integrity.py SOURCE CANDIDATE MANIFEST REPORT
All geometry/UV/skin are identical; no pose/BVH re-run is needed for this partition.
"""
import copy,hashlib,json,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import accessor,read_glb
from upgrade_rigs import Writer
from tint_kolossar_shadow_smoke import BASE_SHA,PALETTES,material_mask


def check(source,candidate,manifest_file,output):
    m=json.loads(manifest_file.read_text());source_sha=hashlib.sha256(source.read_bytes()).hexdigest();candidate_sha=hashlib.sha256(candidate.read_bytes()).hexdigest()
    assert source_sha==BASE_SHA==m['source_sha256'] and candidate_sha==m['candidate_sha256']
    d,b=read_glb(source);a,c=read_glb(candidate);expected=copy.deepcopy(d);old=expected['meshes'][0]['primitives'][0]
    faces=accessor(d,b,old['indices']).reshape(-1,3);mask=material_mask(d,b)
    selected=np.asarray(m['tinted_source_face_ids']);rest=np.asarray(m['unchanged_source_face_ids'])
    assert np.array_equal(selected,np.flatnonzero(mask)) and np.array_equal(rest,np.flatnonzero(~mask))
    assert np.array_equal(np.sort(np.concatenate([selected,rest])),np.arange(len(faces)))
    writer=Writer(expected,b);old['indices']=writer.add(faces[~mask].ravel()[:,None],'SCALAR',5125)
    tinted=copy.deepcopy(old);tinted['indices']=writer.add(faces[mask].ravel()[:,None],'SCALAR',5125);tinted['material']=len(expected['materials']);expected['meshes'][0]['primitives'].append(tinted)
    newmat=copy.deepcopy(expected['materials'][old['material']]);newmat['name']='A03_smoke_'+m['palette'];pbr=newmat.setdefault('pbrMetallicRoughness',{});factor=pbr.get('baseColorFactor',[1,1,1,1]);tint=PALETTES[m['palette']];pbr['baseColorFactor']=[factor[i]*tint[i]for i in range(3)]+[factor[3]];expected['materials'].append(newmat);expected['buffers'][0]['byteLength']=len(writer.binary)
    assert a==expected,'JSON differs beyond exact primitive partition/new index streams/duplicated tint material'
    assert c==bytes(writer.binary),'Binary differs beyond the two appended index streams'
    assert c[:len(b)]==b
    for index in range(len(d['accessors'])):assert accessor(d,b,index).tobytes()==accessor(a,c,index).tobytes(),index
    p0,p1=a['meshes'][0]['primitives'];assert p0['attributes']==p1['attributes']==d['meshes'][0]['primitives'][0]['attributes']
    assert np.array_equal(accessor(a,c,p0['indices']).reshape(-1,3),faces[~mask])
    assert np.array_equal(accessor(a,c,p1['indices']).reshape(-1,3),faces[mask])
    assert len(faces)==149994 and mask.sum()==10443
    result={'status':'PASS_EXACT_GEOMETRY_UV_SKIN_MATERIAL_ONLY_PARTIAL','source_sha256':source_sha,'candidate_sha256':candidate_sha,
            'palette':m['palette'],'tint_rgb':tint,'source_accessor_count_byte_exact':len(d['accessors']),
            'source_binary_prefix_exact':True,'only_appended_binary':'two original-face index streams; no vertex/image/clip data added or modified',
            'strict_complete_json_whitelist_exact':True,'both_primitives_share_all_original_attribute_accessors':True,
            'every_original_triangle_present_exactly_once':True,'total_triangles':len(faces),
            'unchanged_original_material_triangles':int((~mask).sum()),'tinted_effect_material_triangles':int(mask.sum()),
            'original_material_and_all_maps_pbr_alpha_doubleSided_exact':True,'new_material_only_name_and_baseColorFactorRGB_differ':True,
            'positions_normals_uv_joints_8weights_nodes_rest_bind_clips_images_exact':True,
            'all_geometry_bounds_and_pose_deformation_identical_for_identical_bone_matrices':True,
            'new_geometry_intersections_mathematically_impossible':True,'form_repair_claimed':False,
            'scope':'Only10443confirmed pale shoulder-effect faces use a violet duplicate material;139551armor/neck/head/body faces keep original white tint. Source angular effect form and pre-existing source contacts remain.'}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':check(*map(Path,sys.argv[1:5]))
