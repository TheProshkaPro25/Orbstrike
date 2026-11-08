"""A03 paired CPU raw-rest evidence in a shared camera/frame, never GPU art."""
import argparse,hashlib,json,math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
import audit_20261106 as raw

def review(source,candidate,manifest,output):
 m=json.loads(manifest.read_text());assert hashlib.sha256(candidate.read_bytes()).hexdigest()==m['candidate_sha256']
 before=raw.read_glb(source);after=raw.read_glb(candidate);output.mkdir(parents=True,exist_ok=True);raw.SIZE=960
 angle=.60;elevation=.78
 eye=np.array([math.sin(angle),elevation,math.cos(angle)]);eye/=np.linalg.norm(eye);right=np.cross([0,1,0],eye);right/=np.linalg.norm(right);up=np.cross(eye,right);projection=np.stack([right,-up,eye],axis=1)
 bounds=[]
 for primitives in [before,after]:
  coords=np.concatenate([a[0]for a in primitives])@projection;bounds.append([coords[:,:2].min(0),coords[:,:2].max(0)])
 assert np.array_equal(bounds[0],bounds[1]),'Shared source frame required'
 sheet=Image.new('RGB',(1920,1040),'#111821');draw=ImageDraw.Draw(sheet)
 draw.text((20,16),'A03 | CPU RAW REST - NOT GODOT / GPU / ANIMATION',fill='white')
 draw.text((20,38),'Same source frame, camera, light and render scale. Source body / arms / rig / UV / skin retained exactly.',fill='#b8c4d4')
 for i,(label,primitives)in enumerate([('Before - installed muted material',before),('After - local rounded shoulder anatomy',after)]):
  im=raw.render(primitives,angle,elevation);im.save(output/('source-game-three-quarter.png'if i==0 else 'candidate-game-three-quarter.png'));sheet.paste(im,(i*960,65));draw.text((i*960+20,1016),label,fill='white')
 sheet.save(output/'before-after-game.png')
 report={'kind':'CPU raw-rest comparison, not GPU/runtime/animation','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'candidate_sha256':m['candidate_sha256'],'camera_azimuth':angle,'camera_elevation':elevation,'shared_projected_bounds':np.array(bounds[0]).tolist(),'same_camera_frame_light_scale':True,'image':'before-after-game.png'}
 (output/'visual-evidence.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();review(a.source,a.candidate,a.manifest,a.output)
