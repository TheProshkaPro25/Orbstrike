"""Compose existing CPU evidence, without rerendering or altering model images."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--a03-status', default='кандидат: проверка поз', choices=['кандидат: проверка поз','установлен','не установлен','частично: исправлен материал'])
parser.add_argument('--a03-after', type=Path, help='Current accepted material-only front image, relative to docs/audits')
parser.add_argument('--a03-before', type=Path, help='Source image from the same renderer/frame as --a03-after')
args = parser.parse_args()
font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
if not Path(font_path).exists(): font_path = '/usr/share/fonts/TTF/DejaVuSans.ttf'
font = ImageFont.truetype(font_path, 22)
small = ImageFont.truetype(font_path, 16)
large = ImageFont.truetype(font_path, 28)
evidence = ROOT / 'docs/audits'
cases = [
    ('Клыкарь Бури', 'установлен', '2026-11-06-model-a01/source-front.png', '2026-11-06-model-a01/candidate-front.png'),
    ('Левиан Бури', 'установлен', '2026-11-06-model-a02/source-front.png', '2026-11-06-model-a02/candidate-front.png'),
    ('Колоссар Тени', args.a03_status, '2026-11-06-model-a03/source-front.png', '2026-11-06-model-a03/final_candidate-front.png'),
    ('Ратник Света — крупный план', 'установлен', '2026-11-06-model-a04/crown-final/source-head-front.png', '2026-11-06-model-a04/crown-final/candidate-head-front.png'),
]
if args.a03_after is not None:
    title,status,before,_=cases[2]
    cases[2]=(title,status,args.a03_before or before,args.a03_after)
elif args.a03_status=='не установлен':
    title,status,before,_=cases[2]
    cases[2]=(title,status,before,before)
width, cell, gap, header, card_height = 1640, 390, 20, 115, 490
sheet = Image.new('RGB',(width,header+card_height*2+gap),(16,23,33))
draw = ImageDraw.Draw(sheet)
draw.text((24,18),'Модели: до и после адресного ремонта',font=large,fill='white')
draw.text((24,62),'CPU raw-rest · одинаковая камера и масштаб внутри каждой пары · это не кадры Godot/GPU',font=small,fill=(183,196,211))
for index,(title,status,before,after) in enumerate(cases):
    x=gap+(index%2)*810
    y=header+(index//2)*card_height
    draw.text((x,y),title,font=font,fill='white')
    draw.text((x,y+32),status,font=small,fill=(142,215,178) if status=='установлен' else (244,192,117))
    for col,path in enumerate([before,after]):
        px=x+col*(cell+10)
        draw.text((px,y+61),'ДО' if col==0 else 'ПОСЛЕ',font=small,fill=(180,195,212))
        picture=Image.open(evidence/path).convert('RGB').resize((cell,cell),Image.Resampling.LANCZOS)
        sheet.paste(picture,(px,y+86))
out=evidence/'2026-11-06-model-repairs-summary.png'
sheet.save(out)
print(out.relative_to(ROOT))
