"""Compose exact saved GPU PNGs; never substitute baseline for a missing candidate.
python3 tools/models/compose_unirig_unimate_comparison.py BASELINE_DIR CANDIDATE_DIR OUTPUT_PNG
"""
import argparse,json
from pathlib import Path
from PIL import Image,ImageDraw
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('baseline',type=Path);p.add_argument('candidate',type=Path);p.add_argument('output',type=Path)
a=p.parse_args()
base=json.loads((a.baseline/'report.json').read_text());candidate=json.loads((a.candidate/'report.json').read_text())
assert base['source_sha256']!=candidate['source_sha256'],'Identical source/candidate cannot demonstrate a new result'
frames=[n for n in ['native-rest-quarter','native-rest-side','native-idle-33','native-attack-0','native-attack-33','native-attack-67']if(a.baseline/(n+'.png')).exists()and(a.candidate/(n+'.png')).exists()]
assert frames,'No matching actual GPU captures'
width=320;sheet=Image.new('RGB',(width*len(frames),710),'#111821');draw=ImageDraw.Draw(sheet)
for row,(folder,report,label)in enumerate([(a.baseline,base,'OLD SOURCE - native clip, no runtime support'),(a.candidate,candidate,'CANDIDATE - native clip, no gameplay acceptance')]):
 draw.text((8,row*350+7),label+' | '+report['label'],fill='white')
 for column,name in enumerate(frames):
  image=Image.open(folder/(name+'.png')).convert('RGB').resize((width,width));sheet.paste(image,(column*width,row*350+30));draw.text((column*width+6,row*350+332),name,fill='white')
a.output.parent.mkdir(parents=True,exist_ok=True);sheet.save(a.output)
a.output.with_suffix('.json').write_text(json.dumps({'baseline_report':str(a.baseline/'report.json'),'candidate_report':str(a.candidate/'report.json'),'old_source_sha':base['source_sha256'],'candidate_source_sha':candidate['source_sha256'],'matching_captures':frames,'same_camera':base.get('camera')==candidate.get('camera'),'scope':'Native only; source runtime is separately labelled. Missing candidate captures are omitted, never filled with baseline.'},indent=2)+'\n')
print(a.output)
