"""Fetch only pinned free itch.io uploads selected by the author. --verify is offline.

No account or payment. Mari was excluded because live checkout requires purchase.
"""
import argparse
import hashlib
import http.cookiejar
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request
import zipfile
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'build/itch-character-source'
SOURCES = json.loads(Path(__file__).with_name('itch_character_sources.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--verify', action='store_true')
args = parser.parse_args()
for source in SOURCES['files']:
    archive = BASE / source['pack'] / source['filename']
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        if args.verify:
            raise FileNotFoundError(archive)
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        opener.addheaders = [('User-Agent', 'Mozilla/5.0')]
        page = source['page']
        html = opener.open(page, timeout=45).read().decode()
        csrf = re.search(r'name="csrf_token" value="([^"]+)"', html).group(1)
        request = urllib.request.Request(page + '/download_url',
            data=urllib.parse.urlencode({'csrf_token': csrf}).encode(), headers={'Referer': page})
        download = json.load(opener.open(request, timeout=45))['url']
        html = opener.open(download, timeout=45).read().decode()
        if source['upload_id'] not in re.findall(r'data-upload_id="(\d+)"', html):
            raise ValueError('Pinned free upload no longer offered: ' + page)
        request = urllib.request.Request(page + '/file/' + source['upload_id'] + '?source=game_download&as_props=1',
            data=b'', headers={'Referer': download})
        url = json.load(opener.open(request, timeout=45))['url']
        data = opener.open(url, timeout=120).read()
        if hashlib.sha256(data).hexdigest() != source['sha256']:
            raise ValueError('Official archive changed: ' + page)
        archive.write_bytes(data)
    blob = archive.read_bytes()
    if hashlib.sha256(blob).hexdigest() != source['sha256']:
        raise ValueError('Source hash mismatch: ' + str(archive))
    print('Verified', source['pack'], source['filename'])
    if args.verify:
        continue
    destination = ROOT / 'assets/avatars/itch'
    destination.mkdir(parents=True, exist_ok=True)
    if source['pack'] == 'kai':
        with zipfile.ZipFile(archive) as files:
            (destination / 'Kai.vrm').write_bytes(files.read('VRoid_Kai/Model/Kai.vrm'))
    elif source['pack'] == 'denim':
        (destination / 'denim').mkdir(exist_ok=True)
        with zipfile.ZipFile(archive) as files:
            for name in files.namelist():
                if name.endswith('.png'):
                    (destination / 'denim' / Path(name).name).write_bytes(files.read(name))
