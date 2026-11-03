"""Fetch the pinned CC0 Standard packs from their author's itch.io pages."""
import argparse, hashlib, io, json, urllib.request, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--verify',action='store_true')
args=parser.parse_args()
manifest=json.loads((ROOT/'assets/avatars/motions/sources.json').read_text())
for source in manifest['sources']:
    destination=ROOT/source['path']
    if not destination.exists():
        if args.verify: raise FileNotFoundError(destination)
        request=urllib.request.Request(source['page']+'/file/'+str(source['upload_id'])+'?source=game_download&as_props=1',data=b'',headers={'Referer':source['page'],'User-Agent':'Mozilla/5.0'})
        signed=json.load(urllib.request.urlopen(request,timeout=60))
        archive=urllib.request.urlopen(signed['url'],timeout=120).read()
        if hashlib.sha256(archive).hexdigest()!=source['archive_sha256']: raise ValueError('Archive changed: '+source['page'])
        with zipfile.ZipFile(io.BytesIO(archive)) as z:
            data=z.read(source['member'])
            destination.parent.mkdir(parents=True,exist_ok=True)
            destination.write_bytes(data)
    if hashlib.sha256(destination.read_bytes()).hexdigest()!=source['sha256']: raise ValueError('Source changed: '+str(destination))
    print('Verified',source['path'])
