"""Extract original System7 alert icons; explicit verified System disk input."""
from pathlib import Path
import argparse,hashlib,json
import macresources,machfs
from macresources.greggybits import unpack
from PIL import Image

DISK_SHA256='691e76c73a88cd04ced93ec2c84661ca4d900581790e65188ce495f381b005b1'


def extract(resource_fork: bytes, output: Path):
    resources={(r.type,r.id):r for r in macresources.parse_file(resource_fork)}
    output.mkdir(parents=True,exist_ok=True)
    records=[]
    for rid,name in [(0,'stop'),(1,'note'),(2,'caution')]:
        r=resources[b'ICON',rid];stored=bytes(r);bits=unpack(stored) if r.attribs&1 else stored
        if len(bits)!=128:raise ValueError('Expected original32x32 ICON')
        (output/f'system7_alert_icon_{rid}.bin').write_bytes(stored)
        (output/f'system7_alert_icon_{rid}_unpacked.bin').write_bytes(bits)
        image=Image.new('RGBA',(32,32),(255,255,255,255))
        for y in range(32):
            for x in range(32):
                if bits[y*4+x//8]&(0x80>>(x%8)):image.putpixel((x,y),(0,0,0,255))
        filename=f'system7_alert_icon_{rid}.png';image.save(output/filename)
        records.append({'resource_id':rid,'name':name,'width':32,'height':32,'file':filename,
                        'attributes':r.attribs,'stored_sha256':hashlib.sha256(stored).hexdigest(),
                        'unpacked_sha256':hashlib.sha256(bits).hexdigest()})
    manifest={'source_disk_sha256':DISK_SHA256,'source_resource_fork_sha256':hashlib.sha256(resource_fork).hexdigest(),
              'source_hfs_path':'System Folder:System','icons':records}
    (output/'system7_alert_icons.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--disk',type=Path,required=True)
    p.add_argument('--output',type=Path,default=Path('assets/system_controls'));args=p.parse_args()
    data=args.disk.read_bytes()
    if hashlib.sha256(data).hexdigest()!=DISK_SHA256:raise SystemExit('Wrong System7 reference disk')
    volume=machfs.Volume();volume.read(data)
    extract(volume['System Folder']['System'].rsrc,args.output)
