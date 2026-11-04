"""Package a verified locally built recovery; no download, formatting or flashing."""
import argparse, hashlib, json, pathlib, shutil, zipfile

ROOT=pathlib.Path(__file__).parent
p=argparse.ArgumentParser()
p.add_argument('archive',type=pathlib.Path)
p.add_argument('--report',required=True,type=pathlib.Path)
p.add_argument('--output',required=True,type=pathlib.Path)
a=p.parse_args()
report=json.loads(a.report.read_text(encoding='utf-8'))
release=(ROOT/'payload/RELEASE.txt').read_text().splitlines()[0]
assert report['release']==release,'Verification belongs to a different release'
h=hashlib.sha256()
with a.archive.open('rb') as f:
    for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
assert h.hexdigest()==report['archive_sha256'],'Archive differs from verified input'
assert not a.output.exists(),'Refusing to overwrite an existing ZIP'
a.output.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(a.output,'w',zipfile.ZIP_DEFLATED) as z:
    z.write(a.archive,'USB/emctools/ix4-200d_images/ix4-200d.tgz',compress_type=zipfile.ZIP_STORED)
    z.writestr('USB/emctools/ix4-200d_images/reinstall',b'')
    z.write(a.report,'verification.json')
    for name in ('README.md','VALIDATION.md','LICENSE','THIRD-PARTY.md','packages-manifest.json'):
        z.write(ROOT/name,name)
with zipfile.ZipFile(a.output) as z: assert z.testzip() is None,'ZIP integrity failed'
print('Local USB ZIP created:',a.output)
print('Contains a destructive reinstall marker; use only on expendable test disks.')
