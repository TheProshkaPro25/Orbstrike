"""Fetch pinned official MPFB sources into build/avatar-source; no global install."""
import hashlib
import json
import zipfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'build/avatar-source'
CACHE.mkdir(parents=True,exist_ok=True)
for source in json.loads(Path(__file__).with_name('sources.json').read_text()):
    path = CACHE/source['archive']
    if not path.exists():
        temp = path.with_suffix('.downloading')
        print('Downloading',source['archive'],flush=True)
        with urllib.request.urlopen(source['url'],timeout=60) as stream,temp.open('wb') as output:
            while chunk := stream.read(1024*1024): output.write(chunk)
        if hashlib.sha256(temp.read_bytes()).hexdigest() != source['sha256']:
            raise RuntimeError('Source changed; verify the new release and its license: '+str(temp))
        temp.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != source['sha256']:
        raise RuntimeError('Archive checksum mismatch: '+str(path))
    with zipfile.ZipFile(path) as archive:
        folder = CACHE/source['extract_to']
        for entry in archive.infolist():
            if not (folder/entry.filename).resolve().is_relative_to(folder.resolve()):
                raise RuntimeError('Unsafe archive path: '+entry.filename)
        archive.extractall(folder)
    print('Verified',source['archive'],flush=True)
