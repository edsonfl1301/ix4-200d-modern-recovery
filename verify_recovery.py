"""Verify final recovery without executing any installer or flashing a device."""
import argparse, hashlib, importlib.util, json, pathlib, tarfile, tempfile, xml.etree.ElementTree as ET
from contextlib import ExitStack

ROOT=pathlib.Path(__file__).parent
spec=importlib.util.spec_from_file_location('ext2_read', ROOT/'tools/ext2_read.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
ORIGINAL={
    'apps':'3c86c20242ab64609b8545f9bbd4520b',
    'config':'3f332eae6481860d5407f6a1e1149205',
    'initrd':'41094fcd536c68bf0c2458cceae3abfa',
    'oem':'72b7dcfa7fc67d6cbbb7fcde40cea9f2',
    'zImage':'a5fefe901e472891794bfcf267e3c167',
}

def digest(path, algorithm):
    h=hashlib.new(algorithm)
    with open(path,'rb') as stream:
        while block:=stream.read(1024*1024): h.update(block)
    return h.hexdigest()

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('archive'); parser.add_argument('--report',required=True);parser.add_argument('--fsck-logs')
    args=parser.parse_args(); report={'release':(ROOT/'payload/RELEASE.txt').read_text().splitlines()[0],'archive':str(pathlib.Path(args.archive).resolve()),'images':{},'checks':[],'physical_restore_tested':False}
    with tempfile.TemporaryDirectory(prefix='ix4-verify-',dir=ROOT) as folder, ExitStack() as resources:
        folder=pathlib.Path(folder)
        with tarfile.open(args.archive,'r:gz') as archive:
            expected=set(ORIGINAL)|{x+'.md5' for x in ORIGINAL}
            members=archive.getmembers()
            assert len(members)==10 and {m.name for m in members}==expected, 'Unexpected tar layout'
            assert all(m.isfile() for m in members), 'Unexpected symlink or special entry'
            for member in members:
                with archive.extractfile(member) as src, (folder/member.name).open('wb') as dst:
                    while block:=src.read(1024*1024): dst.write(block)
        for name, original in ORIGINAL.items():
            actual=digest(folder/name,'md5')
            sidecar=(folder/(name+'.md5')).read_bytes()
            assert sidecar==actual.encode()+b'\n', f'Invalid MD5 sidecar: {name}'
            if name in ('initrd','oem','zImage'): assert actual==original, f'Boot image changed: {name}'
            else: assert actual!=original, f'Expected modified image: {name}'
            report['images'][name]={'md5':actual,'sha256':digest(folder/name,'sha256'),'bytes':(folder/name).stat().st_size,'original_unchanged':actual==original}
        apps=module.Ext2(folder/'apps'); resources.callback(apps.close)
        config=module.Ext2(folder/'config'); resources.callback(config.close)
        for name in ('bootstrap.sh','service.sh','shares.awk','nginx.conf.in','runtime.tar.gz','legacy_socket_compat.so','RELEASE.txt'):
            inode=apps.resolve('/usr/local/iomega-modern/'+name)
            assert apps.content(inode)==(ROOT/'payload'/name).read_bytes(), f'Payload differs: {name}'
            assert apps.u16(apps.inode(inode)+2)==0, 'Non-root owner'
            expected_mode=0o100755 if name.endswith('.sh') else 0o100644
            assert apps.u16(apps.inode(inode))==expected_mode, f'Bad mode: {name}'
        for name in ('rc.local','httpd.xml'):
            assert config.content(config.resolve('/'+name))==(ROOT/'payload'/name).read_bytes(), f'Config differs: {name}'
        assert config.u16(config.inode(config.resolve('/rc.local')))==0o100755
        http=ET.fromstring(config.content(config.resolve('/httpd.xml')))
        apache_base=apps.content(apps.resolve('/usr/local/apache/conf/httpd.conf-cp')).decode('utf-8','replace')
        assert any(line.strip()=='Listen 80' for line in apache_base.splitlines()), 'HTTP backend not enabled in factory template'
        assert not any(x.get('Listen')=='80' for x in http.findall('Customer/Global/Directive')), 'Duplicate HTTP listener'
        http_flags=ET.fromstring(config.content(config.resolve('/sohoFlash.xml')))
        assert http_flags.find('Root') is not None and http_flags.find('Root').get('AllowHTTP')=='1', 'HTTP access disabled by stock flag'
        assert any(x.get('Listen')=='127.0.0.1:4443' for x in http.findall('Customer/Global/Directive')), 'Legacy HTTPS not moved off public 443'
        assert not any(x.get('Listen')=='443' for x in http.findall('Customer/Global/Directive')), 'Legacy listener still occupies 443'
        with tarfile.open(ROOT/'payload/runtime.tar.gz','r:gz') as runtime:
            for item in runtime:
                clean=item.name.removeprefix('./')
                assert not clean.startswith('/') and '..' not in pathlib.PurePosixPath(clean).parts, 'Unsafe runtime member'
                assert not clean.startswith(('etc/','root/','home/')), 'Private/config data in generic runtime'
        report['checks']=['exact ten-file vendor layout','all MD5 sidecars match','initrd/kernel/oem unchanged','embedded payload byte-for-byte verified','root ownership and executable modes','HTTP backend enabled without duplicate listener','legacy HTTPS confined to loopback 4443','generic runtime has no etc/root/home tree']
    report['archive_sha256']=digest(args.archive,'sha256')
    if args.fsck_logs:
        logdir=pathlib.Path(args.fsck_logs)
        statuses={}
        for image in ('apps','config'):
            normalized=[]
            exits=[]
            for stage in ('before','after'):
                lines=(logdir/(image+'-'+stage+'-fsck.txt')).read_text().splitlines()
                normalized.append([line for line in lines if not ('files (' in line and 'non-contiguous' in line and 'blocks' in line)])
                exits.append(int((logdir/(image+'-'+stage+'-fsck.exit')).read_text().strip()))
            assert normalized[0]==normalized[1], 'New filesystem diagnostics: '+image
            assert exits[0]==exits[1] and exits[0] in (0,4), 'Unexpected fsck exit status'
            statuses[image]={'before':exits[0],'after':exits[1],'diagnostics_unchanged':True}
        report['filesystem_checks']=statuses
        report['checks'].append('filesystem diagnostics unchanged from pinned vendor baseline; no repair performed')
    pathlib.Path(args.report).write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))

if __name__=='__main__': main()
