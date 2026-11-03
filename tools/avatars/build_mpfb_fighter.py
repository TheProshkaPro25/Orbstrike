"""Build the game's original anime fighter with MakeHuman hands/rig in an isolated background Blender.
Run from project root; see tools/avatars/README.md. Does not touch creature assets.
"""
import bpy
import sys
import json
import hashlib
from pathlib import Path
from mathutils import Quaternion

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/avatar-source'
SOURCE = next((CACHE / 'mpfb').glob('*/src'))
sys.path.insert(0, str(SOURCE))
# Keep MPFB's data and all Blender preferences inside the build workspace.
original_user_path = bpy.utils.extension_path_user
bpy.utils.extension_path_user = lambda package, *a, **kw: str(CACHE / 'user') if package == 'mpfb' else original_user_path(package, *a, **kw)
bpy.context.preferences.addons.new().module = 'mpfb'
import mpfb
mpfb.register()
from mpfb.services.humanservice import HumanService
from mpfb.services.targetservice import TargetService

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
macro = TargetService.get_default_macro_info_dict()
macro.update(gender=1.0, age=.40, muscle=.30, weight=.38, proportions=.52)
macro['race'] = {'asian': .65, 'caucasian': .35, 'african': 0.0}
human = HumanService.create_human(macro_detail_dict=macro)
human.name = 'FighterBody'
# Only the hands and humanoid rig are retained from the original human.
rig = HumanService.add_builtin_rig(human, 'default_no_toes')
rig.name = 'FighterRig'

used = [{'name':'Hands and humanoid rig','source':'MPFB 2.0.18 base mesh / default_no_toes','license':'CC0-1.0'}]
# No source clothing: torso, limbs, costume and shoes are authored below.
sys.path.insert(0,str(ROOT/'tools/avatars'))
from anime_head import create_anime_head,material
from anime_hair import create_anime_hair
from anime_body import create_anime_body,add_body_morphs
human.data.materials.clear()
human.data.materials.append(material('BodySkin',(.95,.77,.62)))
# Bake macro targets before applying topology masks and the relaxed rest pose.
TargetService.bake_targets(human)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
for obj in meshes:
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        if modifier.type == 'MASK': bpy.ops.object.modifier_apply(modifier=modifier.name)
for side, sign in [('L',1),('R',-1)]:
    bone = rig.pose.bones['upperarm01.'+side]
    basis = bone.bone.matrix_local.to_quaternion()
    bone.rotation_mode = 'QUATERNION'
    bone.rotation_quaternion = basis.inverted() @ Quaternion((0,1,0),sign*.39) @ basis
bpy.context.view_layer.update()
for obj in meshes:
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        if modifier.type == 'ARMATURE': bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
for obj in meshes:
    modifier = obj.modifiers.new('FighterSkinning','ARMATURE')
    modifier.object = rig
    for polygon in obj.data.polygons: polygon.use_smooth = True
# Remove the human body; retain detailed weighted hands underneath the bracers.
import bmesh
bm=bmesh.new();bm.from_mesh(human.data)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not (abs(v.co.x)>.295 and .76<v.co.z<.941 and v.co.y<-.145)],context='VERTS')
bm.to_mesh(human.data);bm.free();human.data.update()
body_parts=create_anime_body(rig)
head,eyes,brows,lashes,mouth=create_anime_head(rig)
hairs=create_anime_hair(human,rig)
meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH']
add_body_morphs([human]+body_parts)
for obj in body_parts:
    for group in obj.vertex_groups:
        assert group.name in rig.data.bones, (obj.name,group.name)
used.append({'name':'Anime head, hair, body and costume','source':'tools/avatars/anime_head.py + anime_hair.py + anime_body.py','author':'Original project geometry'})
# Named roles are a stable material contract for runtime palette controls.
roles = [(human,'Skin'),(head,'SkinFace'),(eyes,'Eyes'),(brows,'Brows'),(lashes,'Lashes'),(mouth,'Mouth')]
roles += [(obj, 'Hair') for obj in hairs]
for obj, role in roles:
    for index, slot in enumerate(obj.material_slots):
        if not slot.material: continue
        material = slot.material.copy()
        slot.material = material
        material.name = role + ('_%d' % index if index else '')
        shader = next((n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'),None)
        if shader:
            if role in ('Skin','SkinFace','Outfit','Shoes'):
                for socket_name in ('Base Color','Normal','Alpha'):
                    for link in list(shader.inputs[socket_name].links): material.node_tree.links.remove(link)
                shader.inputs['Base Color'].default_value = {'Skin':(.80,.53,.35,1),'SkinFace':(.95,.77,.62,1),'Outfit':(.5,.04,.025,1),'Shoes':(.04,.05,.07,1)}[role]
                shader.inputs['Alpha'].default_value=1.0
            shader.inputs['Roughness'].default_value = .72 if role != 'Eyes' else .3
            shader.inputs['Metallic'].default_value = 0
            shader.inputs['Specular IOR Level'].default_value = .3
bpy.context.view_layer.update()
output = ROOT / 'assets/avatars'
output.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
for obj in meshes: obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(output/'fighter_mpfb.glb'),export_format='GLB',use_selection=True,export_animations=False,export_morph=True,export_skins=True,export_yup=True)
# Keep the established material import contract; these parts now have solid geometry.
import struct
path = output/'fighter_mpfb.glb'
raw = path.read_bytes()
length = struct.unpack_from('<I',raw,12)[0]
data = json.loads(raw[20:20+length])
binary = raw[20+length:]
for material in data.get('materials',[]):
    if material.get('name','').startswith(('Hair','Brows','Lashes')):
        material['alphaMode']='MASK'
        material['alphaCutoff']=.35
        material['doubleSided']=True
text = json.dumps(data,separators=(',',':')).encode()
text += b' ' * (-len(text)%4)
path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(text)+len(binary))+struct.pack('<I4s',len(text),b'JSON')+text+binary)
manifest = {'generator':'MPFB 2.0.18','macro':macro,'sources':used,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'mesh_objects':len(meshes),'vertices':sum(len(obj.data.vertices) for obj in meshes),'bones':len(rig.data.bones),'source_urls':['https://github.com/makehumancommunity/mpfb2/tree/v2.0.18'],'source_asset_license':'CC0-1.0 (MakeHuman hands and rig)', 'original_artwork':'Project-authored anime head, hair, body, garments, shoes; see CREDITS.md','style':'anime-fighter-full-redesign'}
(output/'fighter_mpfb.manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('FIGHTER_EXPORT',json.dumps(manifest),flush=True)
bpy.ops.wm.save_as_mainfile(filepath=str(CACHE/'fighter_mpfb.blend'))
