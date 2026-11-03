"""Separate the generated coil tip from the torso; preserve forefeet and source UVs.
Candidates are saved separately. Source is the preserved post-0.2.8 baseline.
Run with the Hunyuan Python environment (NumPy/SciPy/Pillow).
"""
import sys
sys.path.insert(0,'tools/models')
from inspect_geometry import *
from upgrade_rigs import Writer
from repair_water_beetle import cap_mesh,read_weights
from compact_glb import compact

def repair(id):
 d,b=read_glb('tools/_tmp/repair029/base/'+id+'.glb');writer=Writer(d,b);p,v,f=next(triangles(d,b));n=accessor(d,b,p['attributes']['NORMAL']);uv=accessor(d,b,p['attributes']['TEXCOORD_0']);names=[d['nodes'][j]['name'] for j in d['skins'][0]['joints']];w=read_weights(d,b,p,len(names));influence=w[:,names.index('coil6')]
 original_positions=v.copy()
 remove=(v[:,0]>-.15)&(v[:,0]<-.015)&(v[:,2]>.015)&(v[:,2]<.14)&(v[:,1]<-.16)
 keep=f[remove[f].mean(1)<.5];base=len(keep)
 v,n,uv,w,ff,loops=cap_mesh(v,n,uv,w,keep)
 print('removed',len(f)-len(keep),'loops',loops,'caps',len(ff)-base,flush=True)
 cap_centers=v[ff[base:]].mean(1);tail_caps=ff[base:][cap_centers[:,0]<-.10]
 center=v[np.unique(tail_caps)].mean(0);print('tail cap',center,flush=True)
 def smooth(t):t=np.clip(t,0,1);return t*t*(3-2*t)
 amount=smooth((v[:,0]+.28)/.13)*smooth((influence-.2)/.4)*smooth((v[:,2]+.04)/.06)*(v[:,0]<-.12)
 v[:,1:]=v[:,1:]*(1-.7*amount[:,None])+center[1:]*(.7*amount[:,None])
 v[:,0]-=.075*amount
 protected=(original_positions[:,2]>.24)|(original_positions[:,1]>.1)
 v[protected]=original_positions[protected]
 _,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);normal=np.zeros((uid.max()+1,3));tri=v[ff];face=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0])
 for k in range(3):np.add.at(normal,uid[ff[:,k]],face)
 normal/=np.maximum(np.linalg.norm(normal,axis=1,keepdims=True),1e-12);n=normal[uid]

 attrs={'POSITION':writer.add(v,'VEC3'),'NORMAL':writer.add(n,'VEC3'),'TEXCOORD_0':writer.add(uv,'VEC2')};attrs.update({k:p['attributes'][k] for k in ['JOINTS_0','JOINTS_1','WEIGHTS_0','WEIGHTS_1']})
 import io
 from PIL import Image
 tex=d['materials'][p['material']]['pbrMetallicRoughness']['baseColorTexture']['index'];im=d['images'][d['textures'][tex]['source']];bv=d['bufferViews'][im['bufferView']];pixels=np.array(Image.open(io.BytesIO(b[bv.get('byteOffset',0):bv.get('byteOffset',0)+bv['byteLength']])).convert('RGB'))
 cap_uv=uv[np.unique(ff[base:])];colors=pixels[np.clip((cap_uv[:,1]*pixels.shape[0]).astype(int),0,pixels.shape[0]-1),np.clip((cap_uv[:,0]*pixels.shape[1]).astype(int),0,pixels.shape[1]-1)];cap_color=np.r_[np.median(colors,axis=0)/255,1].tolist()
 d['materials'].append({'name':'sealed tail cut','doubleSided':False,'pbrMetallicRoughness':{'baseColorFactor':cap_color,'roughnessFactor':1,'metallicFactor':0}})
 d['meshes'][0]['primitives']=[{'attributes':attrs.copy(),'indices':writer.add(faces.reshape(-1,1),'SCALAR',5125),'material':mat} for faces,mat in [(ff[:base],p['material']),(ff[base:],len(d['materials'])-1)]]
 d['asset'].setdefault('extras',{})['sfery_tail_clearance']=1
 out=Path('tools/_tmp/repair029/tails')/(id+'.glb');out.parent.mkdir(parents=True,exist_ok=True);writer.save(out);compact(out)

if __name__=='__main__':
 for attr in ['fire','gale','light','shadow','stone','tide']:repair('levian_'+attr)
