"""Narrow A03 imported-pose BVH and exact original-source-face comparison.

blender -b --factory-startup -P tools/models/review_kolossar_shadow_posed_scope.py -- SOURCE_POSES CANDIDATE_POSES SOURCE_GLB CANDIDATE_GLB MANIFEST REPORT
Only caps/clipped faces are measured against the remaining body and each other.
Source pairs are tested individually in the identical actual exported bone pose.
"""
import hashlib,json,os,sys
from pathlib import Path
import numpy as np
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from inspect_geometry import accessor,read_glb


def read_export(folder):
    doc=json.loads((folder/'poses.json').read_text());meshes=[]
    for meta in doc['meshes']:
        prefix=folder/meta['prefix']
        def read(name,dtype):return np.fromfile(str(prefix)+'_'+name+'.bin',dtype)
        v=read('vertices',np.float32).reshape(-1,3);f=read('indices',np.int32).reshape(-1,3)
        j=read('joints',np.int32).reshape(-1,meta['stride']);w=read('weights',np.float32).reshape(j.shape)
        meshes.append((meta,v,f,j,w))
    return doc,meshes


def skin(mesh,pose,used=None):
    meta,v,f,j,w=mesh
    if used is not None:v,j,w=v[used],j[used],w[used]
    palette=np.asarray(pose['palettes'][meta['mi']]).reshape(-1,3,4);out=np.zeros_like(v)
    for k in range(j.shape[1]):
        matrix=palette[j[:,k]];out+=(np.einsum('nij,nj->ni',matrix[:,:,:3],v)+matrix[:,:,3])*w[:,k,None]
    return out


def check(source_folder,candidate_folder,source_glb,candidate_glb,manifest_path,output):
    manifest=json.loads(manifest_path.read_text());candidate_sha=hashlib.sha256(candidate_glb.read_bytes()).hexdigest()
    assert candidate_sha==manifest['candidate_sha256']
    assert hashlib.sha256(source_glb.read_bytes()).hexdigest()==manifest['source_sha256']
    sd,sm=read_export(source_folder);cd,cm=read_export(candidate_folder)
    assert len(sm)==1 and len(cm)==2 and len(sd['poses'])==len(cd['poses'])==46
    for key in ('height','normalization_scale','normalization_offset'):assert sd[key]==cd[key],key
    assert all(mesh[0]['bones']==sm[0][0]['bones']for mesh in cm)
    gd,gb=read_glb(source_glb);ad,ab=read_glb(candidate_glb)
    # Godot flips winding but must retain every triangle in the same sequence.
    for meshes,doc,binary in [(sm,gd,gb),(cm,ad,ab)]:
        for mesh,prim in zip(meshes,doc['meshes'][0]['primitives']):
            v=accessor(doc,binary,prim['attributes']['POSITION']);f=accessor(doc,binary,prim['indices']).reshape(-1,3)
            assert np.array_equal(v[f[:,[0,2,1]]],mesh[1][mesh[2]]),'Imported face order/geometry changed'
    retained=np.asarray(manifest['retained_source_face_ids']);newids=np.asarray(manifest['new_surface_source_face_ids']);recolored=np.asarray(manifest['recolored_original_face_ids'])
    assert len(retained)==len(cm[0][2]) and len(newids)==len(cm[1][2])==manifest['new_surface_triangles']
    n_main=len(retained);face_source=np.concatenate([retained,newids]);cap=face_source<0
    changed=np.concatenate([np.zeros(n_main,bool),(newids<0)|~np.isin(newids,recolored)])
    assert cap.sum()==manifest['new_cap_triangles'] and (changed&~cap).sum()==manifest['clipped_source_triangles']
    rawv=np.concatenate([mesh[1]for mesh in cm]);faces=np.concatenate([cm[0][2],cm[1][2]+len(cm[0][1])])
    _,uid=np.unique(np.round(rawv,6),axis=0,return_inverse=True)
    _,old_uid=np.unique(np.round(sm[0][1],6),axis=0,return_inverse=True)
    source_faces=sm[0][2];body_indices=np.flatnonzero(~changed);patch_indices=np.flatnonzero(changed)
    rows=[];global_genuine=[];global_inherited=[];adjacent_unresolved=[]
    for sp,cp in zip(sd['poses'],cd['poses']):
        assert (sp['action'],sp['frame'])==(cp['action'],cp['frame'])
        assert sp['palettes']==cp['palettes'],'Actual source/candidate bone matrices differ'
        posed=np.concatenate([skin(mesh,cp)for mesh in cm])
        body=BVHTree.FromPolygons(posed.tolist(),faces[body_indices].tolist(),all_triangles=True,epsilon=0)
        patch=BVHTree.FromPolygons(posed.tolist(),faces[patch_indices].tolist(),all_triangles=True,epsilon=0)
        pairs=[(int(body_indices[a]),int(patch_indices[b]))for b,a in patch.overlap(body)]
        pairs += [(int(patch_indices[a]),int(patch_indices[b]))for a,b in patch.overlap(patch)if a<b]
        pairs=np.asarray(pairs,dtype=int).reshape(-1,2);excluded=0
        if len(pairs):
            adjacent=(uid[faces[pairs[:,0]]][:,:,None]==uid[faces[pairs[:,1]]][:,None,:]).any((1,2));excluded=int(adjacent.sum());pairs=pairs[~adjacent]
        required=np.unique(face_source[pairs]);required=required[required>=0]
        old_used=np.unique(source_faces[required]);old_remap=np.full(len(sm[0][1]),-1,dtype=int);old_remap[old_used]=np.arange(len(old_used))
        old_pos=skin(sm[0],sp,old_used);baseline_cache={};details=[]
        for left,right in pairs:
            a,b=int(face_source[left]),int(face_source[right]);is_cap=bool(cap[left]or cap[right]);old_intersection=False;old_adjacent=False
            if not is_cap and a!=b:
                key=tuple(sorted((a,b)))
                if key not in baseline_cache:
                    old_adjacent=bool((old_uid[source_faces[a]][:,None]==old_uid[source_faces[b]][None,:]).any())
                    triangles=old_pos[old_remap[source_faces[[a,b]]]]
                    ta=BVHTree.FromPolygons(triangles[0].tolist(),[[0,1,2]],all_triangles=True,epsilon=0)
                    tb=BVHTree.FromPolygons(triangles[1].tolist(),[[0,1,2]],all_triangles=True,epsilon=0)
                    baseline_cache[key]=(bool(ta.overlap(tb)),old_adjacent)
                old_intersection,old_adjacent=baseline_cache[key]
            if is_cap:verdict='GENUINELY_NEW_CAP_INTERSECTION'
            elif a==b:verdict='GENUINELY_NEW_SAME_SOURCE_FACE_FOLD'
            elif old_intersection and not old_adjacent:verdict='INHERITED_NONADJACENT_SOURCE_PAIR'
            elif old_intersection and old_adjacent:verdict='SOURCE_ADJACENT_CONTACT_REQUIRES_REVIEW'
            else:verdict='GENUINELY_NEW_CLIPPED_SOURCE_INTERSECTION'
            row={'candidate_face_pair':[int(left),int(right)],'candidate_new_local_face_ids':[int(x-n_main)if x>=n_main else None for x in (left,right)],
                 'source_face_pair':[a,b],'touches_cap':is_cap,'source_pair_intersects_in_same_actual_pose':old_intersection,
                 'source_pair_originally_adjacent':old_adjacent,'verdict':verdict}
            details.append(row)
            if verdict.startswith('GENUINELY'):global_genuine.append({'action':cp['action'],'frame':cp['frame'],**row})
            elif verdict.startswith('SOURCE_ADJACENT'):adjacent_unresolved.append({'action':cp['action'],'frame':cp['frame'],**row})
            else:global_inherited.append({'action':cp['action'],'frame':cp['frame'],**row})
        result={'action':cp['action'],'frame':cp['frame'],'patch_pairs_after_candidate_adjacency_exclusion':len(pairs),
                'candidate_geometric_adjacency_exclusions':excluded,'pairs_touching_new_caps':sum(x['touches_cap']for x in details),
                'inherited_nonadjacent_source_pairs':sum(x['verdict'].startswith('INHERITED')for x in details),
                'source_adjacent_contacts_requiring_review':sum(x['verdict'].startswith('SOURCE_ADJACENT')for x in details),
                'genuinely_new_pairs':sum(x['verdict'].startswith('GENUINELY')for x in details),'details':details}
        rows.append(result);print(cp['action'],cp['frame'],'patchpairs',len(pairs),'caps',result['pairs_touching_new_caps'],'inherited',result['inherited_nonadjacent_source_pairs'],'genuine',result['genuinely_new_pairs'],'oldadjacent',result['source_adjacent_contacts_requiring_review'],flush=True)
    status='PASS_NO_NEW_INTERSECTIONS'if not global_genuine and not adjacent_unresolved else 'FAIL_NEW_OR_UNRESOLVED_INTERSECTIONS'
    report={'status':status,'candidate_sha256':candidate_sha,'source_sha256':manifest['source_sha256'],
            'pose_count':len(rows),'all_actual_bone_palettes_identical':True,'source_candidate_normalization_height_exact':True,
            'imported_triangle_order_verified_against_glb':True,'new_caps':int(cap.sum()),'clipped_source_triangles':int((changed&~cap).sum()),'uv_only_roots':len(recolored),'candidate_export_kind':cd.get('export_kind','ACTUAL_GODOT_EXPORT'),'candidate_actual_Godot_import':not cd.get('export_kind','').startswith('CPU_'),'projection_proof':cd.get('projection_proof'),
            'new_intersection_pairs':len(global_genuine),'inherited_pairs':len(global_inherited),'unresolved_originally_adjacent_pairs':len(adjacent_unresolved),
            'adjacency_rule':'Only candidate pairs sharing an original geometric vertex (rounded6decimals, matching existing audit) are excluded. Inheritance requires the exact mapped source face pair to intersect under the identical actual exported pose and to be nonadjacent in the source. Same-source-face folds and new caps cannot inherit a source collision.',
            'poses':rows,'genuinely_new_pairs':global_genuine,'originally_adjacent_unresolved_pairs':adjacent_unresolved,
            'source_pose_json_sha256':hashlib.sha256((source_folder/'poses.json').read_bytes()).hexdigest(),'candidate_pose_json_sha256':hashlib.sha256((candidate_folder/'poses.json').read_bytes()).hexdigest(),
            'scope':'Only A03 affected patch versus remaining body and patch. No A04 or full baseline BVH repeated. Actual Godot exported source matrices/support; candidate provenance is recorded explicitly. CPU BVH, not GPU art.'}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n');print(status,'new',len(global_genuine),'inherited',len(global_inherited),'unresolved',len(adjacent_unresolved),flush=True)

if __name__=='__main__':
    try:check(*map(Path,sys.argv[sys.argv.index('--')+1:]));code=0
    except Exception:
        import traceback;traceback.print_exc();code=1
    sys.stdout.flush();sys.stderr.flush();os._exit(code)
