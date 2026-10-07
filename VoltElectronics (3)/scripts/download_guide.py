"""Publish navigable Azure DevOps artifact instructions without secrets."""
import os
import sys
from pathlib import Path
base=os.environ.get('SYSTEM_COLLECTIONURI','https://dev.azure.com/edukrondevops/')
project=os.environ.get('SYSTEM_TEAMPROJECT','VoltElectronics')
build=os.environ.get('BUILD_BUILDID','')
url=f'{base}{project}/_build/results?buildId={build}&view=artifacts&type=publishedArtifacts'
text=f'''# VOLT release downloads

[Open published artifacts and choose Download]({url})

| Artifact | Contents |
| --- | --- |
| source-code | Full authored project ZIP including Terraform modules and pipeline |
| unit-test-reports | JUnit results, coverage XML and browsable HTML |
| sonarqube-reports | Quality gate, issues, measures and scanner/server diagnostics |
| trivy-source-reports | Terraform, dependency and secret findings as JSON and SARIF |
| application | Application ZIP, build identity and SHA256 |
| container-image | Exact deployable image TAR, SHA256 and metadata |
| trivy-image-reports | Container findings, SARIF and CycloneDX SBOM |
| hub-sonarqube-reports | Persistent private hub quality gate, issues and measures (deployment runs) |
| deployment-outputs | Public endpoint and resource names when Azure deployment runs |

Only artifacts from stages that ran are present. A failed security gate blocks release.
Terraform plans/state, account tokens, private SSH keys and live SQLite data are excluded.
For SonarQube, ephemeral mode performs real analysis on a fresh isolated server; use
deployment also scans the private hub server through Azure Run Command for durable history.
External CI mode can use a reachable server and a secret sonarToken.
'''
Path(sys.argv[1]).write_text(text,encoding='utf-8')
print(text)
