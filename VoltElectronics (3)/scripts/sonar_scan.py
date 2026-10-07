"""Run an actual SonarQube scan, either against a disposable CI server or a supplied server."""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
from urllib.request import Request,urlopen
from urllib.parse import urlencode
from urllib.error import URLError

def run(mode):
    reports=Path('reports/sonarqube'); reports.mkdir(parents=True,exist_ok=True)
    server=os.environ.get('SONAR_HOST_URL','') if mode=='external' else 'http://127.0.0.1:9000'
    token=os.environ.get('SONAR_TOKEN','')
    name='volt-sonarqube-ci'
    def api(path,data=None,basic=None):
        headers={}
        if basic:
            headers['Authorization']='Basic '+base64.b64encode(basic.encode()).decode()
        elif token:
            headers['Authorization']='Bearer '+token
        request=Request(server+path,data=urlencode(data).encode() if data is not None else None,headers=headers)
        with urlopen(request,timeout=30) as response:
            content=response.read()
            return json.loads(content) if content else {}
    try:
        if mode=='ephemeral':
            subprocess.run(['sudo','sysctl','-w','vm.max_map_count=524288'],check=True)
            image=os.environ.get('SONAR_SERVER_IMAGE','sonarqube:community')
            subprocess.run(['docker','run','-d','--name',name,'-p','127.0.0.1:9000:9000',image],check=True)
            for _ in range(180):
                try:
                    if api('/api/system/status').get('status')=='UP':
                        break
                except (URLError,TimeoutError,ValueError,OSError):
                    pass
                time.sleep(3)
            else:
                raise RuntimeError('SonarQube server did not become ready in nine minutes')
            password='V0lt!'+secrets.token_urlsafe(32)
            api('/api/users/change_password',{'login':'admin','previousPassword':'admin','password':password},basic='admin:admin')
            token=api('/api/user_tokens/generate',{'name':'volt-ci-analysis'},basic='admin:'+password)['token']
            print('Disposable CI SonarQube is ready; credentials stay in process memory.')
        elif not server or not token:
            raise RuntimeError('External SonarQube requires SONAR_HOST_URL and secret SONAR_TOKEN')
        environment=os.environ.copy(); environment['SONAR_TOKEN']=token
        environment['SONAR_HOST_URL']=server
        environment['SONAR_USER_HOME']='/tmp/sonar-cache'
        scanner=os.environ.get('SONAR_SCANNER_IMAGE','sonarsource/sonar-scanner-cli:latest')
        for image in ([os.environ.get('SONAR_SERVER_IMAGE','sonarqube:community')] if mode=='ephemeral' else [])+[scanner]:
            subprocess.run(['docker','pull',image],check=True)
            digest=subprocess.check_output(['docker','image','inspect',image,'--format','{{json .RepoDigests}}'],text=True)
            with (reports/'tool-images.txt').open('a') as output:
                output.write(image+' '+digest)
        command=['docker','run','--rm','--network','host','--user',f'{os.getuid()}:{os.getgid()}','-e','SONAR_TOKEN','-e','SONAR_HOST_URL','-e','SONAR_USER_HOME','-v',f'{Path.cwd()}:/usr/src',scanner,'-Dsonar.working.directory=/usr/src/.scannerwork']
        result=subprocess.run(command,env=environment)
        try:
            quality=api('/api/qualitygates/project_status?projectKey=volt-electronics')
            (reports/'quality-gate.json').write_text(json.dumps(quality,indent=2))
            issues=api('/api/issues/search?componentKeys=volt-electronics&ps=500')
            (reports/'issues.json').write_text(json.dumps(issues,indent=2))
            measures=api('/api/measures/component?component=volt-electronics&metricKeys=coverage,ncloc,duplicated_lines_density')
            (reports/'measures.json').write_text(json.dumps(measures,indent=2))
            print('SonarQube quality gate:',quality.get('projectStatus',{}).get('status','unknown'))
        except URLError as error:
            print('Analysis export unavailable:',error.code if hasattr(error,'code') else 'connection error')
        if result.returncode:
            raise RuntimeError('SonarQube scan or quality gate failed; inspect the published reports')
    finally:
        if mode=='ephemeral':
            with (reports/'server.log').open('w') as output:
                subprocess.run(['docker','logs',name],stdout=output,stderr=subprocess.STDOUT)
            subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--mode',choices=['ephemeral','external'],default='ephemeral')
    run(parser.parse_args().mode)
