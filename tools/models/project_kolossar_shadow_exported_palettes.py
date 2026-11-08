"""CPU candidate projection into actual Godot-exported source poses.

This does not run/import the new candidate in Godot. The old845daf actual export
calibrates raw-frame, face order, bone-name mapping and exact Godot8weight packing.
python tools/models/project_kolossar_shadow_exported_palettes.py SOURCE_POSES OLD_CANDIDATE_POSES SOURCE_GLB OLD_CANDIDATE_GLB NEW_CANDIDATE_GLB OUTPUT_FOLDER
"""
import copy,hashlib,json,sys
from pathlib import Path
import numpy as np
from inspect_geometry import accessor,read_glb


def quantize(weights):
    total=np.zeros(len(weights),dtype=np.float32)
    for column in range(weights.shape[1]):total+=weights[:,column]
    assert (total>0).all()
    return (np.floor((weights/total[:,None])*65535)/65535).astype(np.float32)


def arrays(doc,binary,primitive,bone_names):
    skin=doc['skins'][0];names=[doc['nodes'][node]['name']for node in skin['joints']]
    assert len(set(names))==len(names) and set(names)==set(bone_names)
    mapping=np.asarray([bone_names.index(name)for name in names],dtype=np.int32)
    attrs=primitive['attributes'];v=accessor(doc,binary,attrs['POSITION'])
    f=accessor(doc,binary,primitive['indices']).reshape(-1,3)[:,[0,2,1]].astype(np.int32)
    j=mapping[np.concatenate([accessor(doc,binary,attrs['JOINTS_0']),accessor(doc,binary,attrs['JOINTS_1'])],axis=1)]
    w=quantize(np.concatenate([accessor(doc,binary,attrs['WEIGHTS_0']),accessor(doc,binary,attrs['WEIGHTS_1'])],axis=1))
    return v,f,j,w


def calibrate(folder,glb):
    exported=json.loads((folder/'poses.json').read_text());d,b=read_glb(glb)
    assert len(exported['meshes'])==len(d['meshes'][0]['primitives'])
    for meta,p in zip(exported['meshes'],d['meshes'][0]['primitives']):
        v,f,j,w=arrays(d,b,p,meta['bones']);prefix=folder/meta['prefix']
        ev=np.fromfile(str(prefix)+'_vertices.bin',np.float32).reshape(-1,3);ef=np.fromfile(str(prefix)+'_indices.bin',np.int32).reshape(-1,3)
        ej=np.fromfile(str(prefix)+'_joints.bin',np.int32).reshape(-1,8);ew=np.fromfile(str(prefix)+'_weights.bin',np.float32).reshape(-1,8)
        assert np.array_equal(v[f],ev[ef]),'Raw/imported source frame or triangle order mismatch'
        assert np.array_equal(j[f],ej[ef]),'Bone-name mapping mismatch'
        assert np.array_equal(w[f],ew[ef]),'Godot8weight packing mismatch'
    return exported,d,b


def project(source_folder,old_candidate_folder,source_glb,old_candidate_glb,new_candidate_glb,output):
    source,sd,sb=calibrate(source_folder,source_glb);old,od,ob=calibrate(old_candidate_folder,old_candidate_glb)
    assert source['poses']==old['poses'],'Calibration source/candidate actual bone poses differ'
    for key in ('height','normalization_scale','normalization_offset'):assert source[key]==old[key]
    nd,nb=read_glb(new_candidate_glb)
    for key in ('nodes','skins','animations'):assert nd[key]==sd[key],'Source rig changed'
    assert accessor(nd,nb,nd['skins'][0]['inverseBindMatrices']).tobytes()==accessor(sd,sb,sd['skins'][0]['inverseBindMatrices']).tobytes()
    bone_names=source['meshes'][0]['bones'];result=copy.deepcopy(source);result['meshes']=[]
    output.mkdir(parents=True,exist_ok=True)
    for index,p in enumerate(nd['meshes'][0]['primitives']):
        v,f,j,w=arrays(nd,nb,p,bone_names);prefix=f'0_{index}'
        for suffix,data in [('vertices',v),('indices',f),('joints',j),('weights',w)]:data.tofile(output/f'{prefix}_{suffix}.bin')
        result['meshes'].append({'bones':bone_names,'mi':0,'name':'Mesh_0','prefix':prefix,'stride':8,'vertices':len(v)})
    result['export_kind']='CPU_GLTF_PROJECTED_TO_ACTUAL_GODOT_SOURCE_PALETTES'
    result['projection_proof']={'candidate_sha256':hashlib.sha256(new_candidate_glb.read_bytes()).hexdigest(),
          'source_glb_sha256':hashlib.sha256(source_glb.read_bytes()).hexdigest(),'calibration_glb_sha256':hashlib.sha256(old_candidate_glb.read_bytes()).hexdigest(),
          'source_actual_pose_json_sha256':hashlib.sha256((source_folder/'poses.json').read_bytes()).hexdigest(),
          'calibration_actual_pose_json_sha256':hashlib.sha256((old_candidate_folder/'poses.json').read_bytes()).hexdigest(),
          'bone_name_mapping_verified':True,'source_bind_nodes_clips_exact':True,'raw_to_imported_frame_and_face_order_exact':True,
          'source_and_old_candidate_quantized_8weights_exact':True,'new_candidate_imported_in_Godot':False,
          'source_authored_frame_assumption':'Uses source height/normalization frame. Final actual candidate import must confirm the guarded source frame remains active.'}
    (output/'poses.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result['projection_proof'],indent=2))
if __name__=='__main__':project(*map(Path,sys.argv[1:7]))
