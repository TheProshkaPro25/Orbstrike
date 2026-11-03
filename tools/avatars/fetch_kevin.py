"""Install pinned FREE packs locally from their official itch.io pages.

Not CC0: files and derived animations stay ignored. --verify is offline.
No account, purchase or payment; only the author's free Godot/Unreal downloads.
"""
import argparse
import hashlib
import http.cookiejar
import io
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'build/kevin-source'
SOURCES = json.loads(Path(__file__).with_name('kevin_sources.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--verify', action='store_true')
args = parser.parse_args()
BASE.mkdir(parents=True, exist_ok=True)

for source in SOURCES['sources']:
    archive = BASE / (source['name'] + '.zip')
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
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != source['sha256']:
        raise ValueError('Source hash mismatch: ' + str(archive))
    if not args.verify:
        destination = (BASE / source['name']).resolve()
        with zipfile.ZipFile(io.BytesIO(data)) as files:
            for item in files.infolist():
                if not (destination / item.filename).resolve().is_relative_to(destination):
                    raise ValueError('Unsafe ZIP path')
            files.extractall(destination)
    print('Verified', source['name'], source['sha256'])
