import argparse
import json
import os
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('stage')
parser.add_argument('--output')
args=parser.parse_args()
data={'stage':args.stage,'build':os.getenv('BUILD_BUILDID','local'),'commit':os.getenv('BUILD_SOURCEVERSION','local'),'branch':os.getenv('BUILD_SOURCEBRANCH','local'),'deployment_requested':os.getenv('DEPLOY_REQUESTED','false')}
print('##[section]VOLT pipeline: '+args.stage)
for key,value in data.items():
    print(f'{key}: {value}')
print('No credentials, environment secrets, Terraform state or plan contents are printed by this summary.')
if args.output:
    path=Path(args.output);path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,indent=2),encoding='utf-8')
