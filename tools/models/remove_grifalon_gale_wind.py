"""Remove the baked wind ribbons of the accepted Gale Grifalon only.

Writes a candidate, never installs it. Genuine retained vertices keep all source
attributes; only ribbon indices are removed, and small attachment holes get caps.
No bone, bind, animation, image or material is rebuilt.
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
from upgrade_rigs import Writer
from compact_glb import compact

BASE_SHA = '221a9ff78f24f9c908b41b29caeff077677b5649cab35906813c5a57ac3e98b1'


def components(faces, count):
    parent = np.arange(count)

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for face in faces:
        first = find(face[0])
        for vertex in face[1:]:
            other = find(vertex)
            if first != other:
                parent[other] = first
    return np.array([find(i) for i in range(count)])


def boundary_edges(faces):
    edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    _, inverse, counts = np.unique(np.sort(edges, axis=1), axis=0, return_inverse=True, return_counts=True)
    return edges[counts[inverse] == 1]


def loops_of(edges, positions):
    remaining = {(int(b), int(a)) for a, b in edges}  # reversed for outward caps
    loops = []
    while remaining:
        start = min(remaining)
        remaining.remove(start)
        walk = [start[0], start[1]]
        while walk[-1] != walk[0]:
            current = walk[-1]
            options = [b for a, b in remaining if a == current]
            if not options:
                raise ValueError('Open boundary walk')
            if len(options) > 1:
                direction = positions[current] - positions[walk[-2]]
                direction /= max(np.linalg.norm(direction), 1e-12)
                options.sort(key=lambda k: np.dot((positions[k]-positions[current]) /
                             max(np.linalg.norm(positions[k]-positions[current]), 1e-12), direction), reverse=True)
            following = options[0]
            remaining.remove((current, following))
            walk.append(following)
        path = []
        for vertex in walk:
            if vertex in path:
                index = path.index(vertex)
                if len(path[index:]) >= 3:
                    loops.append(path[index:])
                path = path[:index+1]
            else:
                path.append(vertex)
    return loops


def cross2(a, b, c):
    x, y = b-a, c-a
    return x[0]*y[1]-x[1]*y[0]


def crossings(points):
    result = 0
    for i in range(len(points)):
        a, b = points[i], points[(i+1) % len(points)]
        for j in range(i+2, len(points)):
            if (j+1) % len(points) == i:
                continue
            c, d = points[j], points[(j+1) % len(points)]
            result += cross2(a,b,c)*cross2(a,b,d) < -1e-16 and cross2(c,d,a)*cross2(c,d,b) < -1e-16
    return result


def project_loop(points):
    centered = points-points.mean(axis=0)
    _, _, basis = np.linalg.svd(centered, full_matrices=False)
    projection = centered @ basis[:2].T
    if crossings(projection) == 0:
        return projection
    choices = []
    for z in np.linspace(-.95, .95, 13):
        for angle in np.linspace(0, np.pi*2, 25)[:-1]:
            normal = np.array([np.cos(angle)*np.sqrt(1-z*z), np.sin(angle)*np.sqrt(1-z*z), z])
            right = np.cross(normal, [0,1,0])
            right /= np.linalg.norm(right)
            up = np.cross(normal, right)
            projection = centered @ np.array([right, up]).T
            area = abs(sum(cross2(np.zeros(2), a, b) for a,b in zip(projection, np.roll(projection,-1,axis=0))))
            if crossings(projection) == 0:
                choices.append((area, projection))
    if not choices:
        raise ValueError('No non-crossing projection for attachment boundary')
    return max(choices, key=lambda item:item[0])[1]


def triangulate(points):
    q = project_loop(points)
    orientation = np.sign(sum(cross2(np.zeros(2), a, b) for a,b in zip(q,np.roll(q,-1,axis=0))))
    indices = list(range(len(q)))
    faces = []
    while len(indices) > 3:
        for middle in range(len(indices)):
            a,b,c = indices[middle-1], indices[middle], indices[(middle+1) % len(indices)]
            if cross2(q[a],q[b],q[c])*orientation <= 1e-12:
                continue
            if any(min(cross2(q[a],q[b],q[p])*orientation,
                       cross2(q[b],q[c],q[p])*orientation,
                       cross2(q[c],q[a],q[p])*orientation) >= -1e-12
                   for p in indices if p not in (a,b,c)):
                continue
            faces.append([a,b,c])
            indices.pop(middle)
            break
        else:
            raise ValueError('Attachment boundary cannot be triangulated safely')
    faces.append(indices)
    return np.array(faces, dtype=np.uint32), q


def build(source, output):
    sha = hashlib.sha256(source.read_bytes()).hexdigest()
    if sha != BASE_SHA:
        raise ValueError('Expected the accepted Gale Grifalon baseline; refusing a different model')
    doc, binary = read_glb(source)
    doc = copy.deepcopy(doc)
    primitive = doc['meshes'][0]['primitives'][0]
    original_arrays = {key:accessor(doc,binary,index) for key,index in primitive['attributes'].items()}
    v = original_arrays['POSITION']
    faces = accessor(doc,binary,primitive['indices']).reshape(-1,3)
    welded, inverse = np.unique(np.round(v,6),axis=0,return_inverse=True)
    labels = components(inverse[faces],len(welded))[inverse[faces[:,0]]]
    keys, counts = np.unique(labels,return_counts=True)
    body_component = keys[np.argmax(counts)]

    material = doc['materials'][primitive['material']]
    texture = doc['textures'][material['pbrMetallicRoughness']['baseColorTexture']['index']]
    image = doc['images'][texture['source']]
    view = doc['bufferViews'][image['bufferView']]
    offset = view.get('byteOffset',0)
    pixels = np.asarray(Image.open(io.BytesIO(binary[offset:offset+view['byteLength']])).convert('RGB')) / 255.0
    h,w = pixels.shape[:2]
    uv = original_arrays['TEXCOORD_0'][faces].mean(axis=1)
    rgb = pixels[np.clip((uv[:,1]*h).astype(int),0,h-1),np.clip((uv[:,0]*w).astype(int),0,w-1)]
    value = rgb.max(axis=1)
    saturation = (value-rgb.min(axis=1))/np.maximum(value,.001)
    white = (value>.40)&(saturation<.35)&(rgb[:,2]>rgb[:,1]*.93)&(rgb[:,2]>rgb[:,0]*.88)
    white_labels = components(inverse[faces[white]],len(welded))[inverse[faces[:,0]]]
    white_keys, white_counts = np.unique(white_labels[white],return_counts=True)
    # Small white paint flecks on real feathers are not wind. Only the six
    # coherent ribbon patches can seed the broader neutral underside region.
    large_white = white_keys[white_counts>500]
    neutral = (value>.055)&(saturation<.55)&(rgb[:,2]>rgb[:,1]*.86)&(rgb[:,2]>rgb[:,0]*.78)
    neutral_labels = components(inverse[faces[neutral]],len(welded))[inverse[faces[:,0]]]
    wind_regions = np.unique(neutral_labels[white & np.isin(white_labels,large_white) & neutral])
    removed = (neutral & np.isin(neutral_labels,wind_regions)) | (labels!=body_component)
    remaining_labels = components(inverse[faces[~removed]],len(welded))[inverse[faces[:,0]]]
    keys, counts = np.unique(remaining_labels[~removed],return_counts=True)
    removed |= remaining_labels != keys[np.argmax(counts)]  # cut ribbon crumbs, not new floating pieces
    kept = faces[~removed]
    # Wind lies above the legs and below the green head crest. These two
    # anatomical regions must retain every original triangle.
    assert not np.any(removed & (v[faces].max(axis=1)[:,1] < -.14))
    assert not np.any(removed & (v[faces].min(axis=1)[:,1] > .36))
    loops = loops_of(boundary_edges(inverse[kept]),welded)
    representative = np.full(len(welded),-1,dtype=int)
    for vertex in np.unique(kept): representative[inverse[vertex]]=vertex
    additions = {key:[] for key in original_arrays}
    caps=[]
    total=len(v)
    centroids=v[faces].mean(axis=1)
    green=(rgb[:,1]>rgb[:,0]*1.35)&(rgb[:,1]>rgb[:,2]*.95)&(value>.10)&~removed
    for loop in loops:
        source_indices=representative[loop]
        points=v[source_indices]
        cap, projection=triangulate(points)
        target=points.mean(axis=0)
        candidates=np.flatnonzero(green)
        nearest=candidates[np.argmin(np.linalg.norm(centroids[candidates]-target,axis=1))]
        # New cap UVs sample a nearby green feather, avoiding interpolation
        # across unrelated atlas islands. Original body UVs remain byte-exact.
        small_uv=uv[nearest]+projection/max(np.ptp(projection,axis=0).max(),1e-8)*.00015
        for key, values in original_arrays.items():
            copied=values[source_indices].copy()
            if key=='TEXCOORD_0':copied=small_uv.astype(values.dtype)
            additions[key].append(copied)
        caps.append(cap+total)
        total+=len(loop)
    all_faces=np.concatenate([kept]+caps)
    arrays={key:np.concatenate([values]+additions[key]) for key,values in original_arrays.items()}
    used=np.unique(all_faces)
    remap=np.full(total,-1,dtype=int);remap[used]=np.arange(len(used))
    all_faces=remap[all_faces]
    writer=Writer(doc,binary)
    for key,index in list(primitive['attributes'].items()):
        meta=doc['accessors'][index]
        primitive['attributes'][key]=writer.add(arrays[key][used],meta['type'],meta['componentType'])
    primitive['indices']=writer.add(all_faces.ravel()[:,None],'SCALAR',5125)
    output.parent.mkdir(parents=True,exist_ok=True)
    doc['asset'].setdefault('extras',{})['sfery_grifalon_gale_wind_removed']=1
    writer.save(output)
    compact(output)
    # A closed surface is required after the ribbon-body attachment is sealed.
    final_positions=arrays['POSITION'][used]
    _, final_inverse=np.unique(np.round(final_positions,6),axis=0,return_inverse=True)
    assert len(boundary_edges(final_inverse[all_faces]))==0
    report={'source_sha256':sha,'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'source_triangles':len(faces),'removed_wind_triangles':int(removed.sum()),
            'retained_original_triangles':len(kept),'cap_triangles':int(sum(len(c)for c in caps)),
            'source_vertices':len(v),'output_vertices':len(used),'attachment_loops':len(loops),
            'boundary_edges':0,'retained_source_vertex_ids':used[used<len(v)].tolist(),
            'retained_source_face_ids':np.flatnonzero(~removed).tolist(),
            'cap_vertex_source_ids':np.concatenate([representative[loop]for loop in loops]).tolist()}
    output.with_suffix('.removal.json').write_text(json.dumps(report,indent=2)+'\n')
    print({key:value for key,value in report.items() if not key.endswith('_ids')})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    build(args.source,args.output)
