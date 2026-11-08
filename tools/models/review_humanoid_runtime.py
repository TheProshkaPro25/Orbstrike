"""Read actual Godot Skeleton skin matrices into isolated Blender review copies.
No source GLB export. Matrices include BodySupport; cloth here is CPU skin only.
Executed in the connected Blender with REVIEW_STAGE/REVIEW_ID/REVIEW_FRAME set.
"""
import bpy, json
from pathlib import Path
from mathutils import Matrix, Vector
ROOT=Path('/home/loq/Документы/game/sfery_stikhiy')
C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
stage=globals().get('REVIEW_STAGE','after'); identity=globals().get('REVIEW_ID','creature_ratnik_light'); frame=globals().get('REVIEW_FRAME',28)
name='Review_RatnikLight' if identity=='creature_ratnik_light' else 'Review_KolossarLight'
arm=bpy.data.objects[name]; arm.animation_data.action=None
for t in arm.animation_data.nla_tracks:t.mute=True
report=json.loads((ROOT/'build/checks/humanoid-motion'/stage/(identity+'.json')).read_text())
sample=min((s for s in report['samples'] if s['action']=='attack'),key=lambda s:abs(s['frame']-frame))
targets={}
for bone_name,v in sample['bones'].items():
 if bone_name not in arm.data.bones:continue
 pal=Matrix((v[0:4],v[4:8],v[8:12],[0,0,0,1]))
 targets[bone_name]=C@pal@C.inverted()@arm.data.bones[bone_name].matrix_local
for bone_name,target in targets.items():
 bone=arm.data.bones[bone_name]
 arm.pose.bones[bone_name].matrix_basis=(bone.matrix_local.inverted()@bone.parent.matrix_local@targets[bone.parent.name].inverted()@target if bone.parent else bone.matrix_local.inverted()@target)
bpy.context.view_layer.update()
print(identity,stage,'attack',sample['frame'],'phase',sample['phase'])
