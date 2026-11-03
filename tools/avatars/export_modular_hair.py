"""Export four CC0 hairstyles from the pinned hiamBoz .blend (background Blender)."""
import bpy
from pathlib import Path
out=str(Path(__file__).resolve().parents[2]/'assets/avatars/itch')+'/'
groups={'bob':['bobback','bobfront','bobleft','bobright'],'short':['hairshortback','hairshortfront','hairshortleft','hairshortright'],'twins':['lowhairband','lowtwinbackleft','lowtwinbackright','lowtwinfront','lowtwinleft','lowtwinright'],'pony':['ponyback','ponyfront','ponyhairband','ponyleft','ponyright']}
for name,names in groups.items():
 for obj in bpy.data.objects: obj.select_set(False)
 for n in names:
  o=bpy.data.objects[n];o.hide_set(False);o.hide_viewport=False;o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=out+'modular_'+name+'.glb',use_selection=True,export_format='GLB',export_animations=False,export_apply=True)
 print('EXPORTED',name,flush=True)
