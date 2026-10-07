"""Export authored project files; never include databases, credentials or state."""
import argparse
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

def bundle(destination):
    root=Path(__file__).resolve().parents[1]
    allowed_root={'.gitignore','.dockerignore','.coveragerc','Dockerfile','README.md','app.py','catalog.py','requirements.txt','requirements-dev.txt','azure-pipelines.yml','sonar-project.properties'}
    folders={'docs','infra','pipelines','scripts','static','templates','tests','ops'}
    suffixes={'.py','.md','.tf','.yml','.yaml','.txt','.sh','.ps1','.svg','.js','.css','.html','.example','.properties','.hcl'}
    paths=[]
    for path in root.rglob('*'):
        if not path.is_file():
            continue
        relative=path.relative_to(root)
        if relative.parts[0] not in folders and str(relative) not in allowed_root:
            continue
        if any(part in {'.terraform','__pycache__','.git','downloads','.pytest_cache'} for part in relative.parts):
            continue
        if path.name in {'backend.tf','backend.hcl'} or 'tfstate' in path.name or path.suffix=='.tfplan':
            continue
        if path.suffix in suffixes or path.name in allowed_root or path.name=='.terraform.lock.hcl':
            paths.append(path)
    destination=Path(destination)
    destination.parent.mkdir(parents=True,exist_ok=True)
    with ZipFile(destination,'w',ZIP_DEFLATED) as archive:
        for path in sorted(paths):
            archive.write(path,path.relative_to(root).as_posix())
    print(f'Exported {len(paths)} authored files to {destination}')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('destination')
    bundle(parser.parse_args().destination)
