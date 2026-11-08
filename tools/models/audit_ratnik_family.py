"""Blender Python: reproduce the five-variant distal blade/body audit from runtime exports.
Run via connected Blender execute_blender_code; does not mutate a Blender scene.
"""
from pathlib import Path
script=Path(__file__).with_name('audit_ratnik_slash.py').read_text()
for element in ['fire','gale','stone','shadow','tide']:
 scoped=(script.replace('ratnik_light','ratnik_'+element)
  .replace('build/checks/humanoid-motion','build/checks/ratnik-family')
  .replace('2026-11-08-humanoid-motion','2026-11-08-ratnik-family')
  .replace('blade-body-bvh.json',element+'-blade-body-bvh.json')
  .replace('[12,20,28,36,44,52]','[12,28,44]')
  .replace('six exported runtime attack poses','three exported runtime attack poses'))
 exec(scoped,{})
