"""Offline sampling of the user's locally downloaded Kevin Iglesias FREE FBX files.
No vendor animation data is embedded in this script. Outputs stay local/ignored.
"""
from pathlib import Path
import bpy,json,math,os
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'build/kevin-source'
OUT=ROOT/'assets/avatars/motions/kevin_local'
OUT.mkdir(parents=True,exist_ok=True)
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
clips={
 'Boomerang':'throw/**/Human{sex}@ThrowBoomerang01_R.fbx',
 'BallThrow':'throw/**/Human{sex}@ThrowBall01_R.fbx',
 'BoomerangHold':'throw/**/Human{sex}@ThrowBoomerang01_R - Hold.fbx',
 'BallHold':'throw/**/Human{sex}@ThrowBall01_R - Hold.fbx',
 'CastingEnter':'spell/**/Human{sex}@CastingEnter01.fbx',
 'CastingExit':'spell/**/Human{sex}@CastingExit01.fbx',
 'CastingIdle':'spell/**/Human{sex}@CastingIdle01.fbx',
 'CastDirect':'spell/**/Human{sex}@MagicAttackDirect1H01_R.fbx',
 'CastCall':'spell/**/Human{sex}@MagicAttackCall1H01_L.fbx',
 'ObjectGrip':'spell/**/Human@ObjectGripHands01.fbx',
}
def transform(m):
 q=m.to_quaternion().normalized();p=m.to_translation()
 return {'q':[q.x,q.y,q.z,q.w],'p':list(p)}
for sex in ['M','F']:
 result={}
 for name,pattern in clips.items():
  path=next(SOURCE.glob(pattern.format(sex=sex)))
  bpy.ops.wm.read_factory_settings(use_empty=True)
  bpy.ops.import_scene.fbx(filepath=str(path))
  actor=next(o for o in bpy.data.objects if o.type=='ARMATURE')
  scene=bpy.context.scene
  action=actor.animation_data.action
  start,end=action.frame_range
  fps=scene.render.fps/scene.render.fps_base
  duration=(end-start)/fps
  scene.frame_set(math.floor(start),subframe=start-math.floor(start))
  bpy.context.view_layer.update()
  bones=[b.name for b in actor.data.bones]
  root_name='B-root'
  root_rest=C@actor.matrix_world@actor.data.bones[root_name].matrix_local
  root_pose=C@actor.matrix_world@actor.pose.bones[root_name].matrix
  reference=root_pose@root_rest.inverted()
  rest={b.name:transform(reference@C@actor.matrix_world@b.matrix_local) for b in actor.data.bones}
  frames=[]
  count=max(1,math.ceil(duration*30))
  for i in range(count+1):
   t=min(i/30,duration)
   frame=start+t*fps
   scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame))
   frames.append({n:transform(C@actor.matrix_world@actor.pose.bones[n].matrix) for n in bones})
  result[name]={'duration':duration,'rest':rest,'frames':frames,'source':str(path.relative_to(ROOT))}
  print('SAMPLED',sex,name,round(duration,3),len(frames),flush=True)
 (OUT/f'samples_{sex}.json').write_text(json.dumps(result,separators=(',',':')))
print('Sampling finished',flush=True)
# All files are closed; avoid Linux audio backend shutdown in unattended Blender.
os._exit(0)
