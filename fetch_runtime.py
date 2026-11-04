"""Rebuild a generic runtime from the exact official packages in the manifest."""
import argparse, hashlib, io, json, pathlib, tarfile, urllib.request
ROOT=pathlib.Path(__file__).parent
parser=argparse.ArgumentParser();parser.add_argument('--cache',default=str(ROOT/'package-cache'));args=parser.parse_args()
cache=pathlib.Path(args.cache);cache.mkdir(parents=True,exist_ok=True)
records=json.loads((ROOT/'packages-manifest.json').read_text(encoding='utf-8'))
files=[]
for name,record in records.items():
    url=record['feed_url']+record['Filename']
    assert url.startswith('https://downloads.openwrt.org/releases/24.10.4/'), 'Unexpected package origin'
    path=cache/record['Filename']
    if not path.exists(): path.write_bytes(urllib.request.urlopen(url,timeout=60).read())
    expected=record.get('SHA256sum') or record['download_sha256']
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected, 'Package checksum failed: '+name
    if path not in files: files.append(path)
with tarfile.open(ROOT/'payload/runtime.tar.gz','w:gz') as output:
    for path in files:
        with tarfile.open(path,'r:*') as package:
            member=next(m for m in package.getmembers() if m.name.endswith('data.tar.gz'))
            with tarfile.open(fileobj=io.BytesIO(package.extractfile(member).read()),mode='r:gz') as data:
                for entry in data:
                    clean=entry.name.removeprefix('./')
                    assert not clean.startswith('/') and '..' not in pathlib.PurePosixPath(clean).parts
                    if not clean.startswith(('lib/','usr/lib/','usr/bin/','usr/sbin/','bin/')):continue
                    entry.name=clean
                    output.addfile(entry,data.extractfile(entry) if entry.isfile() else None)
print('Generic runtime rebuilt from verified packages.')
