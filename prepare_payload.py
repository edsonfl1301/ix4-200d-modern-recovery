"""Prepare only generic payload data; never reads a live NAS configuration."""
import argparse, hashlib, json, pathlib, shutil, tarfile, xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).parent
parser=argparse.ArgumentParser()
parser.add_argument('--original',required=True)
parser.add_argument('--runtime',required=True)
parser.add_argument('--shim',required=True)
parser.add_argument('--package-manifest',required=True)
args=parser.parse_args()
with tarfile.open(args.original,'r:gz') as archive:
    config=archive.extractfile('config').read()
assert hashlib.md5(config).hexdigest()=='3f332eae6481860d5407f6a1e1149205', 'Wrong factory config'
factory=ROOT/'factory-config.input'
factory.write_bytes(config)
try:
    import importlib.util
    spec=importlib.util.spec_from_file_location('ext2_read',ROOT/'tools/ext2_read.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    fs=module.Ext2(factory)
    tree=ET.fromstring(fs.content(fs.resolve('/httpd.xml')))
    global_node=tree.find('Customer/Global')
    for directive in global_node.findall('Directive'):
        if directive.get('Listen')=='443':directive.set('Listen','127.0.0.1:4443')
    for host in tree.findall('Customer/VirtualHost'):
        if host.get('realm')=='_default_:443':host.set('realm','127.0.0.1:4443')
    # httpd.conf-cp already has Listen 80; do not duplicate it via XML.
    ET.ElementTree(tree).write(ROOT/'payload/httpd.xml',encoding='utf-8',xml_declaration=True)
    if hasattr(fs.data,'close'):fs.data.close()
    fs.file.close()
finally:
    factory.unlink(missing_ok=True)
for source,name in [(args.runtime,'runtime.tar.gz'),(args.shim,'legacy_socket_compat.so')]:
    destination=ROOT/'payload'/name
    if pathlib.Path(source).resolve()!=destination.resolve():shutil.copyfile(source,destination)
destination=ROOT/'packages-manifest.json'
if pathlib.Path(args.package_manifest).resolve()!=destination.resolve():shutil.copyfile(args.package_manifest,destination)
print('Generic payload prepared; no live passwords, certificates or IP settings used.')
