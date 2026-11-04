"""Reproduce pinned VRM evaluation dependencies; --verify never accesses the network."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = json.loads(Path(__file__).with_name('vrm_sources.json').read_text())
parser = argparse.ArgumentParser()
parser.add_argument('--verify',action='store_true')
args = parser.parse_args()

def obtain(path,url,digest):
    if not path.exists():
        if args.verify: raise FileNotFoundError(path)
        path.parent.mkdir(parents=True,exist_ok=True)
        request=urllib.request.Request(url,headers={'User-Agent':'Orbstrike-asset-evaluation'})
        with urllib.request.urlopen(request,timeout=120) as response:
            data=response.read()
        if hashlib.sha256(data).hexdigest()!=digest: raise ValueError('Unexpected source hash: '+url)
        path.write_bytes(data)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=digest: raise ValueError('Changed file: '+str(path))

for source in SOURCES['models']:
    path=ROOT/source['path'];obtain(path,source['url'],source['sha256'])
    print('Verified',source['path'])
plugin=SOURCES['plugin']
archive=ROOT/'build/vrm-source/godot-vrm.zip'
obtain(archive,plugin['url'],plugin['archive_sha256'])
with zipfile.ZipFile(io.BytesIO(archive.read_bytes())) as files:
    for entry in files.infolist():
        relative=Path(*Path(entry.filename).parts[1:])
        if entry.is_dir() or relative.suffix=='.import':continue
        if len(relative.parts)<3 or relative.parts[0]!='addons' or relative.parts[1] not in ['vrm','Godot-MToon-Shader']:continue
        path=(ROOT/relative).resolve()
        if not path.is_relative_to((ROOT/'addons').resolve()):raise ValueError('Unsafe archive path')
        data=files.read(entry)
        if path.exists():
            if path.read_bytes()!=data:raise ValueError('Local addon differs from pinned source: '+str(path))
        else:
            if args.verify:raise FileNotFoundError(path)
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
print('Verified VRM/MToon addon',plugin['commit'])
