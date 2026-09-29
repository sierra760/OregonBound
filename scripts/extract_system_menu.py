"""Preserve System7 MDEF0 and MBDF0 for the source-backed Hunt Time popup."""
from pathlib import Path
import argparse,hashlib,json
import macresources
from macresources.greggybits import unpack
SYSTEM_FORK_SHA256='edb31a497602d6141f82d85300d2f4a88c167327531f993b829bfb274cbb9668'

def extract(resource_fork: bytes, output: Path):
    if hashlib.sha256(resource_fork).hexdigest()!=SYSTEM_FORK_SHA256:
        raise ValueError('Expected the verified System7.0 reference resource fork')
    resources={(r.type,r.id):r for r in macresources.parse_file(resource_fork)}
    output.mkdir(parents=True,exist_ok=True)
    entries=[]
    for kind in [b'MDEF',b'MBDF']:
        resource=resources[kind,0];stored=bytes(resource)
        decoded=unpack(stored) if resource.attribs&1 else stored
        stem='system7_'+kind.decode().lower()+'_0'
        (output/(stem+'.bin')).write_bytes(stored)
        (output/(stem+'_unpacked.bin')).write_bytes(decoded)
        entries.append(dict(type=kind.decode(),id=0,attributes=resource.attribs,
            stored_sha256=hashlib.sha256(stored).hexdigest(),unpacked_sha256=hashlib.sha256(decoded).hexdigest(),
            unpacked_length=len(decoded)))
    manifest=dict(source_resource_fork_sha256=SYSTEM_FORK_SHA256,source_hfs_path='System Folder:System',resources=entries)
    (output/'system7_menu_definitions.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('resource_fork',type=Path);p.add_argument('--output',type=Path,default=Path('assets/system_controls'))
    args=p.parse_args();extract(args.resource_fork.read_bytes(),args.output)
