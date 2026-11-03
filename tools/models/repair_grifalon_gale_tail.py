"""Weights-only repair of Gale's lower tail fan, misbound to the right wing.

Accepted input is the wind-removed Gale only. Writes a separate candidate, never
installs it. Geodesic classification runs on welded triangles, not a box cut.
The wrong wingtip.R/wingfan.R dominant surface seeds the tail, while actual wing,
body and leg surfaces protect the transition. Existing tail influences supply
nearby tail1..4 ratios, propagated over the same surface. All non-skin bytes stay
unchanged, including the 128 wind attachment cap triangles.
"""
import argparse, hashlib, heapq, json, struct
from pathlib import Path
import numpy as np
from inspect_geometry import accessor, read_glb

SOURCE_SHA='959044bf764bea0c509c5c438e14ed2c9e2f45d133a693107a292333f6912d03'


def distance(adjacency,seeds,carry=False):
    dist=np.full(len(adjacency),np.inf);owner=np.full(len(adjacency),-1,dtype=int)
    queue=[]
    for i in np.flatnonzero(seeds):dist[i]=0;owner[i]=i;queue.append((0.,int(i)))
    heapq.heapify(queue)
    while queue:
        value,i=heapq.heappop(queue)
        if value>dist[i]:continue
        for nxt,length in adjacency[i]:
            candidate=value+length
            if candidate<dist[nxt]:
                dist[nxt]=candidate;owner[nxt]=owner[i];heapq.heappush(queue,(candidate,nxt))
    return (dist,owner) if carry else dist


def replace_attribute(raw,doc,index,values):
    # Preserve the GLB document, unused buffers and every other binary byte.
    pos=12
    while struct.unpack_from('<I',raw,pos+4)[0]!=0x004e4942:pos+=8+struct.unpack_from('<I',raw,pos)[0]
    binary_start=pos+8;a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']]
    start=binary_start+view.get('byteOffset',0)+a.get('byteOffset',0)
    data=np.ascontiguousarray(values);stride=view.get('byteStride',data.shape[1]*data.dtype.itemsize)
    for i,row in enumerate(data):raw[start+i*stride:start+i*stride+row.nbytes]=row.tobytes()


def build(source,output):
    sha=hashlib.sha256(source.read_bytes()).hexdigest();assert sha==SOURCE_SHA,sha
    doc,binary=read_glb(source);primitive=doc['meshes'][0]['primitives'][0];attrs=primitive['attributes']
    v=accessor(doc,binary,attrs['POSITION']);faces=accessor(doc,binary,primitive['indices']).reshape(-1,3)
    joints=np.c_[accessor(doc,binary,attrs['JOINTS_0']),accessor(doc,binary,attrs['JOINTS_1'])].astype(int)
    weights=np.c_[accessor(doc,binary,attrs['WEIGHTS_0']),accessor(doc,binary,attrs['WEIGHTS_1'])].astype(float)
    names=[doc['nodes'][i]['name']for i in doc['skins'][0]['joints']]
    influences=np.zeros((len(v),len(names)))
    for k in range(8):np.add.at(influences,(np.arange(len(v)),joints[:,k]),weights[:,k])
    # UV copies/cap boundary copies must receive the very same solution.
    welded,inverse=np.unique(np.round(v,6),axis=0,return_inverse=True)
    representative=np.full(len(welded),-1,dtype=int)
    for i,g in enumerate(inverse):
        if representative[g]<0:representative[g]=i
    original=influences[representative];pos=v[representative]
    tailids=np.array([names.index('tail'+str(k))for k in range(1,5)])
    tipids=np.array([names.index(n)for n in ['wingtip.R','wingfan.R']])
    rightids=np.array([names.index(n)for n in ['wing.R','wingtip.R','wingfan.R']])
    tail=original[:,tailids].sum(1);tip=original[:,tipids].sum(1)
    # Both wrong bones' major surfaces are unambiguously the lower tail fan in
    # three orthographic anatomical views. No dominant true wing is in this set.
    wrong_core=(tip>.55)&(pos[:,1]<-.04)&(pos[:,2]<.02)
    tailseed=(tail>.75)|wrong_core
    otherseed=(1-tail-tip)>.70
    # Explicit authored main-wing dominance is also a protected source surface.
    otherseed|=original[:,names.index('wing.R')]>.55
    assert not np.any(tailseed&otherseed)
    edges=np.unique(np.sort(np.concatenate([inverse[faces[:,[0,1]]],inverse[faces[:,[1,2]]],inverse[faces[:,[2,0]]]]),axis=1),axis=0)
    adjacency=[[]for _ in welded]
    lengths=np.linalg.norm(pos[edges[:,0]]-pos[edges[:,1]],axis=1)
    for (a,b),length in zip(edges,lengths):
        if a==b:continue
        adjacency[a].append((int(b),float(length)));adjacency[b].append((int(a),float(length)))
    dt=distance(adjacency,tailseed);do=distance(adjacency,otherseed)
    ratio=do/np.maximum(dt+do,1e-15);ratio[tailseed]=1;ratio[otherseed]=0
    blend=np.clip((ratio-.20)/.60,0,1);blend=blend*blend*(3-2*blend)
    # Original tail neighbors determine the new tail chain distribution.
    _,nearest=distance(adjacency,tail>.75,True)
    distribution=original[nearest][:,tailids].copy();distribution/=distribution.sum(1)[:,None]
    fixed=tail>.75
    for iteration in range(24):
        total=np.zeros_like(distribution);count=np.zeros(len(pos))
        np.add.at(total,edges.ravel(),distribution[edges[:,::-1]].reshape(-1,4))
        np.add.at(count,edges.ravel(),1)
        average=total/np.maximum(count,1)[:,None]
        distribution[~fixed]=.5*distribution[~fixed]+.5*average[~fixed]
    # Keep non-right-wing influences byte-equivalent as real-valued masses.
    repaired=original.copy();unsupported=[]
    for i in np.flatnonzero((blend>0)&(original[:,rightids].sum(1)>1e-9)):
        transfer=original[i,rightids].sum()*blend[i]
        repaired[i,rightids]*=1-blend[i]
        existing=np.flatnonzero(repaired[i,tailids]>0)
        available=8-int(np.count_nonzero(repaired[i]>0))
        target=distribution[i].copy()
        # Never discard an authored non-tail influence to make room. Prefer
        # existing tail entries; add neighboring chain entries in free slots.
        new=[k for k in np.argsort(target)[::-1]if k not in existing and target[k]>1e-8][:max(0,available)]
        permitted=np.r_[existing,new].astype(int)
        if not len(permitted):
            repaired[i]=original[i];unsupported.append(int(i));continue
        target[[k for k in range(4)if k not in permitted]]=0
        target/=target.sum()
        repaired[i,tailids]+=target*transfer
        assert np.count_nonzero(repaired[i]>0)<=8
    # Float32 dense stream is the source of canonical packed entries for every
    # copy in a weld group. Unchanged groups retain their original slot order.
    changed=np.max(np.abs(repaired-original),axis=1)>1e-9
    newj=joints.copy();neww=weights.copy()
    for g in np.flatnonzero(changed):
        ids=np.flatnonzero(repaired[g]>0);ids=ids[np.argsort(-repaired[g,ids],kind='stable')]
        packedj=np.zeros(8,dtype=int);packedw=np.zeros(8)
        packedj[:len(ids)]=ids;packedw[:len(ids)]=repaired[g,ids]
        copies=inverse==g;newj[copies]=packedj;neww[copies]=packedw
    raw=bytearray(source.read_bytes())
    for k in range(2):
        ja=accessor(doc,binary,attrs['JOINTS_'+str(k)]);wa=accessor(doc,binary,attrs['WEIGHTS_'+str(k)])
        replace_attribute(raw,doc,attrs['JOINTS_'+str(k)],newj[:,k*4:k*4+4].astype(ja.dtype))
        replace_attribute(raw,doc,attrs['WEIGHTS_'+str(k)],neww[:,k*4:k*4+4].astype(wa.dtype))
    output.parent.mkdir(parents=True,exist_ok=True);output.write_bytes(raw)
    report=dict(source_sha256=sha,output_sha256=hashlib.sha256(raw).hexdigest(),vertices=len(v),triangles=len(faces),wind_caps=128,wrong_core_welds=int(wrong_core.sum()),tail_seed_welds=int(tailseed.sum()),protected_seed_welds=int(otherseed.sum()),changed_welds=int(changed.sum()),changed_vertices=int(changed[inverse].sum()),unsupported_transition_welds=unsupported,changed_vertex_ids=np.flatnonzero(changed[inverse]).tolist(),wrong_core_vertex_ids=np.flatnonzero(wrong_core[inverse]).tolist(),protected_vertex_ids=np.flatnonzero(otherseed[inverse]).tolist(),transfer_factor=blend[inverse].tolist(),joint_names=names)
    output.with_suffix('.tail-repair.json').write_text(json.dumps(report,indent=2))
    print({k:val for k,val in report.items()if not isinstance(val,list)},flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);a=parser.parse_args();build(a.source,a.output)
