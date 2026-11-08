#!/usr/bin/env python3
"""Compose the actual six-element CreatureAnim screenshots without pose edits."""
from pathlib import Path
from PIL import Image, ImageDraw

folder = Path(__file__).resolve().parents[2] / 'build/checks/grifalon-fullset'
elements = ['fire', 'gale', 'stone', 'light', 'shadow', 'tide']
clips = ['idle', 'stance', 'roar', 'attack', 'hit']
sheet = Image.new('RGB', (1600, 2064), (20, 24, 30))
draw = ImageDraw.Draw(sheet)
for row, element in enumerate(elements):
    for col, clip in enumerate(clips):
        corrected = folder / f'{element}-correction' / f'creature_grifalon_{element}-{clip}.png'
        source = corrected if corrected.is_file() else folder / f'creature_grifalon_{element}-{clip}.png'
        image = Image.open(source).convert('RGB')
        image.thumbnail((320, 320))
        sheet.paste(image, (col * 320, row * 344 + 24))
        draw.text((col * 320 + 5, row * 344 + 5), f'{element} / {clip}', fill='white')
sheet.save(folder / 'six-variants-five-clips.jpg', quality=95)
