"""A03 partial material improvement; source geometry/UV/skin remain byte exact.

The source shoulder-effect faces are partitioned into a second primitive sharing
all original attributes and a duplicated original material with a violet factor.
Angular source effect geometry is deliberately retained, not claimed repaired.
"""
import argparse,copy,hashlib,json
from pathlib import Path
import numpy as np
from inspect_geometry import accessor,read_glb
from remove_kolossar_shadow_smoke import BASE_SHA,locate
from remove_grifalon_gale_wind import components
from upgrade_rigs import Writer

PALETTES={'soft_lavender':[.58,.38,.72],'muted_violet':[.38,.22,.52],'smoky_violet':[.24,.14,.34]}


def material_mask(doc,binary):
    p,a,f,welded,inverse,earlier_region,rgb,uv=locate(doc,binary)
    q=a['POSITION'][f].mean(1);value=rgb.max(1);saturation=(value-rgb.min(1))/np.maximum(value,.001)
    # Limit to the two reviewed pale effect lobes. The broad dark roots/pauldron
    # regions from the rejected geometry experiments are expressly excluded.
    region=earlier_region&(value>.24)&(saturation<.30)&(((q[:,0]<-.13)&(q[:,2]>.06))|((q[:,0]>.23)&(q[:,2]<.06)))
    labels=components(inverse[f[region]],len(welded))[inverse[f[:,0]]]
    keys,counts=np.unique(labels[region],return_counts=True);chosen=keys[counts>3000]
    assert sorted(counts[counts>3000].tolist())==[4120,6323]
    selected=region&np.isin(labels,chosen);assert selected.sum()==10443
    return selected


def build(source,output,palette):
    root=Path(__file__).resolve().parents[2];assert source.resolve()!=output.resolve()
    assert not output.resolve().is_relative_to((root/'assets/creatures_hd').resolve())
    sha=hashlib.sha256(source.read_bytes()).hexdigest();assert sha==BASE_SHA
    original,binary=read_glb(source);mask=material_mask(original,binary);doc=copy.deepcopy(original)
    p=doc['meshes'][0]['primitives'][0];faces=accessor(doc,binary,p['indices']).reshape(-1,3)
    old_material=p['material'];material=copy.deepcopy(doc['materials'][old_material]);material['name']='A03_smoke_'+palette
    tint=PALETTES[palette];pbr=material.setdefault('pbrMetallicRoughness',{});factor=pbr.get('baseColorFactor',[1,1,1,1]);pbr['baseColorFactor']=[factor[i]*tint[i]for i in range(3)]+[factor[3]]
    material_id=len(doc['materials']);doc['materials'].append(material)
    writer=Writer(doc,binary);p['indices']=writer.add(faces[~mask].ravel()[:,None],'SCALAR',5125)
    effect=copy.deepcopy(p);effect['indices']=writer.add(faces[mask].ravel()[:,None],'SCALAR',5125);effect['material']=material_id;doc['meshes'][0]['primitives'].append(effect)
    output.parent.mkdir(parents=True,exist_ok=True);writer.save(output)
    report={'status':'PARTIAL_MATERIAL_ONLY_FORM_UNCHANGED','source_sha256':sha,'candidate_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'palette':palette,'tint_rgb':tint,'source_triangles':len(faces),'unchanged_armor_triangles':int((~mask).sum()),'tinted_effect_triangles':int(mask.sum()),
            'tinted_source_face_ids':np.flatnonzero(mask).tolist(),'unchanged_source_face_ids':np.flatnonzero(~mask).tolist(),
            'all_source_attributes_uv_skin_exact':True,'every_source_face_once_exact':True,'form_repair_claimed':False,
            'mask':'two connected pale shoulder-effect lobes6323+4120; dark roots/neck/pauldron and small unrelated pale armor highlights excluded',
            'material_change':'duplicate original material; multiply only new material baseColorFactor RGB, preserve alpha/maps/PBR/doubleSided'}
    output.with_suffix('.tint.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items()if not k.endswith('_ids')},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--palette',choices=PALETTES,required=True);a=p.parse_args();build(a.source,a.output,a.palette)
