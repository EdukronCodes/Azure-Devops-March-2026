"""Package only deployable source, with a checksum and release identity."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo

def build(destination, commit, build_id):
    root=Path(__file__).resolve().parents[1]
    destination=Path(destination)
    destination.mkdir(parents=True,exist_ok=True)
    files=[root/'app.py',root/'catalog.py',root/'requirements.txt']
    for folder in ('static','templates'):
        files.extend(p for p in (root/folder).rglob('*') if p.is_file())
    metadata=json.dumps({'commit':commit,'build_id':build_id},sort_keys=True).encode()
    archive=destination/'app.zip'
    with ZipFile(archive,'w',compression=ZIP_DEFLATED) as bundle:
        for path in sorted(files):
            info=ZipInfo(path.relative_to(root).as_posix(),date_time=(2020,1,1,0,0,0))
            info.compress_type=ZIP_DEFLATED
            info.external_attr=0o100644 << 16
            bundle.writestr(info,path.read_bytes())
        info=ZipInfo('static/build.json',date_time=(2020,1,1,0,0,0))
        info.compress_type=ZIP_DEFLATED
        info.external_attr=0o100644 << 16
        bundle.writestr(info,metadata)
    (destination/'build.json').write_bytes(metadata)
    (destination/'app.zip.sha256').write_text(f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  app.zip\n',encoding='utf-8')
    print(f'Built {archive} for commit {commit}')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('destination')
    parser.add_argument('--commit',required=True)
    parser.add_argument('--build',required=True)
    args=parser.parse_args()
    build(args.destination,args.commit,args.build)
